-- #427 (ADR 0019): straty armii atakującego po bitwie odejmuje serwer.
--
-- Dotąd poległych odejmował tylko telefon (Recruitment.apply_losses), a zapis zamku pilnował jedynie przyrostu
-- armii, więc spreparowany klient mógł po bitwie zapisać zamek z całym wojskiem. Serwer nie może jednak po prostu
-- odjąć poległych przy kolejnym zapisie: uczciwy telefon już ich odjął i straciłby wojsko dwa razy. Dlatego:
--
-- - `attacks.attacker_squads`: id oddziałów zamku atakującego dla każdego wpisu armii ataku (wyzwalacz przy
--   starcie, z kopii zamku na serwerze, w kolejności Recruitment.battle_ids bez garnizonu). Brak pasującego
--   oddziału to null w tym miejscu.
-- - `attacks.server_losses`: ustawia `launch_attack` (PvP i bot przez begin_bot_attack), gdy `sim_version` ataku
--   jest co najmniej progiem `army_losses_min_sim` z `private.settings` (0 = wyłączone, domyślnie) i tryb weryfikacji
--   tego rodzaju ataku to shadow albo enforce. Odpowiedź oddaje to telefonowi: przy true telefon trzyma poległych
--   jako „czekających na serwer” i wysyła je w zapisie zamku, dopóki serwer ich nie rozliczy. Starsze klienty
--   (bez pola w odpowiedzi) mają niższą wersję i dalej odejmują sami.
-- - `private.castle_army_pending`: polegli (attack_id, oddział, liczba) zapisani przy wejściu skutków ataku
--   (`outcome_applied_at`). Ocaleli z wyniku workera (enforce, porzucony atak), w shadow z wyniku telefonu.
--   Job `failed` w enforce: ocaleli z telefonu, a bez nich (porzucony atak) cały oddział poległ.
-- - Wyzwalacz `castles_army_losses` (przed sprawdzeniem armii): przy zapisie zamku z telefonu (token gracza) odejmuje poległych z tych oddziałów
--   do zera (bez przenoszenia na inne oddziały) i zwraca rozliczenie w `castles.army_applied`
--   ([[attack_id, oddział, odjęci], ...]), które telefon czyta w odpowiedzi na zapis (jak `loot_applied`, #274).
--
-- `launch_attack` i `begin_bot_attack` dostają w odpowiedzi kolumnę `server_losses` (drop i create: zmienia się
-- typ zwracany); ciała skopiowane z `20261128090000_bot_verification.sql`, zmiana tylko przy server_losses.
-- Nowych danych o graczu nie ma: tylko liczby jednostek i id oddziałów z zamku, kasowane z atakiem i kontem.

-- ---- próg wersji ----

alter table private.settings add constraint settings_army_losses_min_sim
  check (key <> 'army_losses_min_sim' or value ~ '^[0-9]{1,6}$');
insert into private.settings (key, value) values ('army_losses_min_sim', '0') on conflict (key) do nothing;

-- Czy straty ataku odejmie serwer: próg wersji włączony, wersja ataku od progu, weryfikacja shadow albo enforce.
create function private.army_losses_on(p_defender uuid, p_sim_version integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.value::integer from private.settings s where s.key = 'army_losses_min_sim'), 0) > 0
    and p_sim_version is not null
    and p_sim_version >= coalesce((select s.value::integer from private.settings s where s.key = 'army_losses_min_sim'), 0)
    and (case when p_defender is not null then private.verification_mode()
      else private.bot_verification_mode() end) in ('shadow', 'enforce');
$$;
comment on function private.army_losses_on(uuid, integer) is
  'Czy straty armii atakującego tego ataku odejmuje serwer (#427, ADR 0019).';
revoke all on function private.army_losses_on(uuid, integer) from public, anon, authenticated;
grant execute on function private.army_losses_on(uuid, integer) to service_role;

-- ---- kolumny ----

alter table public.attacks
  add column attacker_squads integer[],
  add column server_losses boolean not null default false;
comment on column public.attacks.attacker_squads is
  'Id oddziałów zamku atakującego dla wpisów armii ataku (#427); null w miejscu bez pasującego oddziału.';
comment on column public.attacks.server_losses is
  'Straty armii atakującego odejmuje serwer przez castle_army_pending (#427, ADR 0019); ustawia launch_attack.';

alter table public.castles
  add column army_applied jsonb not null default '[]'::jsonb check (jsonb_typeof(army_applied) = 'array');
comment on column public.castles.army_applied is
  'Polegli odjęci przy ostatnim zapisie zamku (#427): [[attack_id, oddział, liczba], ...]. Zmienia tylko wyzwalacz.';

create table private.castle_army_pending (
  attack_id uuid not null references public.attacks (id) on delete cascade,
  player_id uuid not null references public.players (id) on delete cascade,
  squad_id integer not null check (squad_id > 0),
  fallen smallint not null check (fallen between 0 and 10),
  created_at timestamptz not null default now(),
  primary key (attack_id, squad_id)
);
comment on table private.castle_army_pending is
  'Polegli z ataku czekający na najbliższy zapis zamku atakującego (#427, ADR 0019). Tylko wyzwalacze.';
create index castle_army_pending_player_idx on private.castle_army_pending (player_id);
alter table private.castle_army_pending enable row level security;
revoke all on private.castle_army_pending from public, anon, authenticated, service_role;

-- ---- oddziały ataku przy starcie ----

create function private.attacks_attacker_squads()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_own jsonb;
  v_squads jsonb;
  v_garrison bigint[];
  v_used integer[] := '{}';
  v_ids integer[] := '{}';
  v_found integer;
  v_kind bigint;
  e jsonb;
  s jsonb;
begin
  select c.data into v_own from public.castles c where c.player_id = new.attacker_id;
  v_squads := case when jsonb_typeof(v_own -> 'recruitment' -> 'squads') = 'array'
    then v_own -> 'recruitment' -> 'squads' else '[]'::jsonb end;
  -- garnizon Dworu (zadanie GARRISON = 6) nie idzie do ataku, jak w begin_attack
  select coalesce(array_agg(private.json_int(o.value -> 0, 1, 2147483647)), '{}'::bigint[]) into v_garrison
  from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'defense' -> 'orders') = 'array'
        then v_own -> 'defense' -> 'orders' else '[]'::jsonb end) as o
  where case when jsonb_typeof(o.value) <> 'array' then false
      when jsonb_array_length(o.value) < 4 then false
      else private.json_int(o.value -> 1, 0, 100) = 6
        and private.json_int(o.value -> 0, 1, 2147483647) is not null end;
  -- wpis armii i to pierwszy wolny oddział tego rodzaju w kolejności zamku (Recruitment.battle_ids)
  for e in select x.value from jsonb_array_elements(
      case when jsonb_typeof(new.attacker_army) = 'array' then new.attacker_army else '[]'::jsonb end) as x loop
    v_found := null;
    v_kind := case when jsonb_typeof(e) = 'array' then private.json_int(e -> 0, 0, 1000) end;
    for s in select y.value from jsonb_array_elements(v_squads) as y loop
      if jsonb_typeof(s) = 'array' and jsonb_array_length(s) >= 3
          and private.json_int(s -> 0, 1, 2147483647) is not null
          and private.json_int(s -> 1, 0, 1000) is not distinct from v_kind
          and coalesce(private.json_int(s -> 2, 0, 10), 0) > 0
          and private.json_int(s -> 0, 1, 2147483647) <> all (v_garrison)
          and private.json_int(s -> 0, 1, 2147483647)::integer <> all (v_used) then
        v_found := private.json_int(s -> 0, 1, 2147483647)::integer;
        exit;
      end if;
    end loop;
    v_ids := v_ids || v_found;
    if v_found is not null then
      v_used := v_used || v_found;
    end if;
  end loop;
  new.attacker_squads := v_ids;
  new.server_losses := false;
  return new;
end;
$$;
comment on function private.attacks_attacker_squads() is
  'Przy starcie ataku zapisuje id oddziałów zamku atakującego dla wpisów armii (#427, ADR 0019).';
revoke all on function private.attacks_attacker_squads() from public, anon, authenticated, service_role;

create trigger attacks_attacker_squads
  before insert on public.attacks
  for each row execute function private.attacks_attacker_squads();

-- ---- polegli przy wejściu skutków ataku ----

create function private.attacks_army_losses()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_alive jsonb;
  v_count integer;
  v_left integer;
begin
  if new.outcome_applied_at is not null and new.verified_result is not null
      and new.verification in ('verified', 'mismatch') then
    v_alive := new.verified_result -> 'survivors';
  else
    -- shadow (skutki z wyniku telefonu) albo failed w enforce; porzucony atak bez wyniku telefonu: wszyscy polegli
    v_alive := new.claimed_result -> 'survivors';
  end if;
  for i in 0 .. coalesce(jsonb_array_length(new.attacker_army), 0) - 1 loop
    if new.attacker_squads is null or i + 1 > cardinality(new.attacker_squads)
        or new.attacker_squads[i + 1] is null then
      continue;
    end if;
    v_count := coalesce(private.json_int(new.attacker_army -> i -> 1, 0, 10), 0)::integer;
    v_left := case when jsonb_typeof(v_alive) = 'array'
      then least(greatest(coalesce(private.json_int(v_alive -> i, 0, 10), 0), 0), v_count)::integer else 0 end;
    insert into private.castle_army_pending (attack_id, player_id, squad_id, fallen)
    values (new.id, new.attacker_id, new.attacker_squads[i + 1], v_count - v_left)
    on conflict (attack_id, squad_id) do nothing;
  end loop;
  return null;
end;
$$;
comment on function private.attacks_army_losses() is
  'Polegli ataku do castle_army_pending przy wejściu skutków albo po failed w enforce (#427, ADR 0019).';
revoke all on function private.attacks_army_losses() from public, anon, authenticated, service_role;

create trigger attacks_army_losses
  after update of status, outcome_applied_at, verification on public.attacks
  for each row
  when (new.server_losses and (
    (old.outcome_applied_at is null and new.outcome_applied_at is not null)
    or (old.verification is distinct from 'failed' and new.verification = 'failed' and new.outcome_applied_at is null)))
  execute function private.attacks_army_losses();

-- ---- odjęcie przy zapisie zamku ----

create function private.castle_army_losses()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_squads jsonb;
  v_applied jsonb := '[]'::jsonb;
  r record;
  v_count integer;
  v_left integer;
  v_at integer;
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
begin
  -- tylko zapis z telefonu (token gracza, jak bilans surowców #282): rozliczenie wraca w odpowiedzi na ten zapis
  if v_role in ('authenticated', 'anon')
      and jsonb_typeof(new.data -> 'recruitment' -> 'squads') = 'array'
      and exists (select 1 from private.castle_army_pending p where p.player_id = new.player_id) then
    v_squads := new.data -> 'recruitment' -> 'squads';
    for r in
      with gone as (
        delete from private.castle_army_pending p where p.player_id = new.player_id
        returning p.attack_id, p.squad_id, p.fallen, p.created_at
      )
      select * from gone order by created_at, attack_id, squad_id
    loop
      v_at := null;
      for j in 0 .. jsonb_array_length(v_squads) - 1 loop
        if jsonb_typeof(v_squads -> j) = 'array' and jsonb_array_length(v_squads -> j) >= 3
            and private.json_int(v_squads -> j -> 0, 1, 2147483647) = r.squad_id then
          v_at := j;
          exit;
        end if;
      end loop;
      v_left := 0;
      v_count := 0;
      if v_at is not null then
        v_count := coalesce(private.json_int(v_squads -> v_at -> 2, 0, 10), 0)::integer;
        v_left := greatest(v_count - r.fallen, 0);
        v_squads := jsonb_set(v_squads, array[v_at::text, '2'], to_jsonb(v_left));
      end if;
      v_applied := v_applied || jsonb_build_array(jsonb_build_array(r.attack_id::text, r.squad_id, v_count - v_left));
    end loop;
    new.data := jsonb_set(new.data, '{recruitment,squads}', v_squads);
  end if;
  new.army_applied := v_applied;
  return new;
end;
$$;
comment on function private.castle_army_losses() is
  'Przy zapisie zamku odejmuje poległych z castle_army_pending i zwraca rozliczenie w army_applied (#427, ADR 0019).';
revoke all on function private.castle_army_losses() from public, anon, authenticated, service_role;

-- nazwa przed castles_check_army: sprawdzenie armii widzi już oddziały po stratach
create trigger castles_army_losses
  before update of data on public.castles
  for each row execute function private.castle_army_losses();

-- ---- zatwierdzenie planu z server_losses w odpowiedzi ----

drop function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer);
drop function public.launch_attack(uuid, uuid, jsonb, integer, integer);

create function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb, p_general integer,
  p_sim_version integer default null)
returns table (
  castle jsonb,
  defense jsonb,
  plan jsonb,
  techs text[],
  general jsonb,
  ruler_perk smallint,
  server_losses boolean
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_data jsonb;
  v_done jsonb;
begin
  if p_general is not null and (p_general < 0 or p_general > 2) then
    raise exception 'bad_general' using errcode = 'P0001';
  end if;
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'started' or a.started_at < now() - interval '10 minutes' then
    raise exception 'attack_expired' using errcode = 'P0001';
  end if;
  if a.launched_at is null then
    -- #284 §2: wersja symulacji klienta musi mieć pack na workerze (unsupported_version → aktualizacja gry)
    a.sim_version := private.checked_sim_version(p_sim_version);
    a.orders := private.check_plan(p_plan, jsonb_array_length(a.attacker_army));
    select c.data into v_data from public.castles c where c.player_id = p_attacker;
    v_done := v_data -> 'research' -> 'done';
    a.attacker_techs := array(
      select code from unnest(array['A1', 'A2', 'A7']) as code
      where jsonb_typeof(v_done) = 'array' and v_done @> jsonb_build_array(code))
      -- poziomy doktryn ataku od 2 jako „A1:3” (sprawdzone przy zapisie zamku, castle_research_problem)
      || array(
        select code || ':' || private.tech_level(v_data, code) from unnest(array['A1', 'A2']) as code
        where private.tech_level(v_data, code) >= 2);
    a.attacker_general := case when p_general is null then null else private.castle_general(v_data, p_general) end;
    -- perk władcy (#32) z zamku na serwerze, sprawdzony przy zapisie (castles_check_ruler_perk); epokę
    -- sprawdzamy jeszcze raz, bo zamek zapisany przed tą migracją nie przeszedł przez wyzwalacz
    a.attacker_ruler_perk := private.castle_ruler_perk(v_data);
    if a.attacker_ruler_perk in (1, 4) and greatest(
        coalesce((select p.age from public.players p where p.id = p_attacker), 0),
        private.castle_age(v_data)) < 1 then
      a.attacker_ruler_perk := -1;
    end if;
    update public.attacks t set launched_at = now(), orders = a.orders, attacker_techs = a.attacker_techs,
      attacker_general = a.attacker_general, attacker_ruler_perk = a.attacker_ruler_perk,
      sim_version = a.sim_version,
      -- #427 (ADR 0019): straty tego ataku odejmie serwer (telefon dostaje to w odpowiedzi)
      server_losses = private.army_losses_on(a.defender_id, a.sim_version)
    where t.id = a.id;
    a.server_losses := private.army_losses_on(a.defender_id, a.sim_version);
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot, a.orders,
    coalesce(a.attacker_techs, '{}'), a.attacker_general, coalesce(a.attacker_ruler_perk, -1::smallint),
    a.server_losses;
end;
$$;

create function public.begin_bot_attack(p_attacker uuid, p_bot smallint, p_army jsonb, p_battle_seed bigint,
  p_plan jsonb, p_general integer, p_sim_version integer)
returns table (
  attack_id uuid,
  map_seed bigint,
  battle_seed bigint,
  plan jsonb,
  techs text[],
  general jsonb,
  ruler_perk smallint,
  server_losses boolean
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
  v_seed bigint;
  v_battle bigint;
begin
  if p_bot is null then
    raise exception 'bad_target' using errcode = 'P0001';
  end if;
  select b.attack_id, b.map_seed, b.battle_seed into v_id, v_seed, v_battle
  from public.begin_attack(p_attacker, null, p_bot, p_army, p_battle_seed) b;
  return query select v_id, v_seed, v_battle, l.plan, l.techs, l.general, l.ruler_perk, l.server_losses
  from public.launch_attack(p_attacker, v_id, p_plan, p_general, p_sim_version) l;
end;
$$;

comment on function public.launch_attack(uuid, uuid, jsonb, integer, integer) is
  'Zatwierdzenie planu ataku (#28): pełne kopie zamku i obrony obrońcy z chwili startu (przy zamku-bocie puste, #413); zapisuje plan, badania, generała ataku, perk władcy (#29, #31, #32), wersję symulacji dla weryfikacji (#284, unsupported_version bez packa) i czy straty armii odejmie serwer (#427). Tylko dla service_role (Edge Functions launch_attack i start_attack).';
revoke all on function public.launch_attack(uuid, uuid, jsonb, integer, integer) from public, anon, authenticated;
grant execute on function public.launch_attack(uuid, uuid, jsonb, integer, integer) to service_role;
comment on function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer) is
  'Start ataku na zamek-bota z zatwierdzonym planem (#413, ADR 0016): begin_attack i launch_attack w jednej transakcji; zwraca seedy oraz plan, badania, generała, perk i server_losses (#427) z serwera do bitwy i weryfikacji. Tylko dla service_role (Edge Function start_attack).';
revoke all on function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer)
  from public, anon, authenticated;
grant execute on function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer)
  to service_role;
