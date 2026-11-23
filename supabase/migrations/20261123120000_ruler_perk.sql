-- #32: perk władcy (1 miejsce, 6 perków MVP) przy zapisie zamku, w ataku na gracza i w limicie żywności.
--
-- Perk władcy działa na cały zamek (notatka Władca i generałowie), więc wpływa na PvP: Zdobywca na bitwę
-- atakującego, Łupieżca na limit łupu, Gospodarz grodu i Ukochany władca na obronę (kopia zamku),
-- a Gospodarny na produkcję żywności, z której serwer liczy limit utrzymania armii. Klient nie jest
-- zaufany, więc perk w `castles.data -> ruler -> perk` sprawdza serwer przy każdym zapisie zamku:
-- - numery perków (RulerPerks.Perk): CONQUEROR = 0, LOOTER = 1, STEWARD = 2, THRIFTY = 3, BUILDER = 4,
--   BELOVED = 5; brak perka to -1. Liczba spoza 0..5 albo zły typ to brak perka;
-- - epoka (RulerPerks.PERK_AGE = [0, 1, 0, 0, 1, 0]): Łupieżca i Budowniczy dopiero od epoki II, a epoka to
--   wyższa z `players.age` i `private.castle_age` zapisu. Perk z wyższej epoki odpada (-1);
-- - zmiana perka jest darmowa raz na COOLDOWN = 24 godziny według zegara serwera
--   (`castles.ruler_perk_free_at`, chwila ostatniej darmowej zmiany). Kolejna zmiana w tym oknie kosztuje
--   CHANGE_GOLD = 50 złota. Serwer nie zna salda złota, więc jak przy generałach (`general_budget`)
--   sprawdza górną granicę: złoto startowe, nagrody fal PvE i łupy z zakończonych ataków minus rekrutacja
--   i awanse generałów z tego zapisu i wcześniejsze płatne zmiany (`castles.ruler_perk_paid`). Bez
--   pokrycia zmiana jest cofana do poprzedniego perka. Ustawienie braku perka (-1) nie jest zmianą;
-- - płatne zmiany perka zmniejszają też złoto na generałów (`private.checked_generals` od nowa).
-- Obie kolumny zmienia tylko wyzwalacz: gracz ma uprawnienia do zapisu wyłącznie `save_version` i `data`.
-- Wyzwalacz `castles_check_ruler_perk` biegnie po `castles_check_generals` (kolejność nazw), więc widzi
-- już przyciętych generałów.
--
-- Atak na gracza: `launch_attack` bierze perk z zamku atakującego na serwerze, zapisuje go
-- w `attacks.attacker_ruler_perk` i oddaje klientowi (`ruler_perk`), a `attack_replay` oddaje ten sam
-- perk obrońcy w powtórce (#29). `end_attack` przy Łupieżcy podnosi limit łupu z każdego surowca
-- o LOOTER_LOOT_PERCENT = 115 (tylko atak na gracza; capacity ocalałych bez zmian).
-- Limit utrzymania: `private.food_production` dodaje THRIFTY_PRODUCTION_BONUS = 10 punktów procentowych
-- do premii z badań, jak Economy.rates.
-- Liczby pilnuje test gry (`tests/test_ruler_perks.gd`) po znacznikach w komentarzach.

alter table public.castles
  add column ruler_perk_free_at timestamptz,
  add column ruler_perk_paid integer not null default 0 check (ruler_perk_paid >= 0);

comment on column public.castles.ruler_perk_free_at is
  'Chwila ostatniej darmowej zmiany perka władcy (#32), zegar serwera. Zmienia tylko wyzwalacz.';
comment on column public.castles.ruler_perk_paid is
  'Liczba płatnych zmian perka władcy (#32, po 50 złota) do budżetu złota. Zmienia tylko wyzwalacz.';

alter table public.attacks
  add column attacker_ruler_perk smallint check (attacker_ruler_perk between -1 and 5);

comment on column public.attacks.attacker_ruler_perk is
  'Perk władcy atakującego z zamku na serwerze w chwili zatwierdzenia planu (#32). Tylko dla serwera.';

-- Perk władcy z danych zamku: 0..5 albo -1. Bez sprawdzania epoki (to robi wyzwalacz przy zapisie).
create function private.castle_ruler_perk(p_data jsonb)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select coalesce(private.json_int(p_data -> 'ruler' -> 'perk', 0, 5), -1)::smallint
$$;

revoke all on function private.castle_ruler_perk(jsonb) from public, anon, authenticated;
grant execute on function private.castle_ruler_perk(jsonb) to service_role;
-- epokę zamku czyta też `launch_attack` (service_role), nie tylko wyzwalacz
grant execute on function private.castle_age(jsonb) to service_role;

-- Złoto, które gracz mógł jeszcze wydać według serwera: start (50) + fale PvE (125) + łupy z zakończonych
-- ataków, minus generałowie z `p_generals` (już przycięci) i `p_paid` płatnych zmian perka.
create function private.ruler_gold_left(p_player uuid, p_generals jsonb, p_paid integer)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select 50 + 125
    + coalesce((select sum(coalesce(a.loot[4], 0)) from public.attacks a
        where a.attacker_id = p_player and a.status = 'finished'), 0)
    - coalesce((select sum(50
          + case when private.json_int(g -> 'level', 1, 3) >= 2 then 80 else 0 end
          + case when private.json_int(g -> 'level', 1, 3) >= 3 then 150 else 0 end)
        from jsonb_array_elements(case when jsonb_typeof(p_generals -> 'roster') = 'array'
          then p_generals -> 'roster' else '[]'::jsonb end) g), 0)
    - 50 * coalesce(p_paid, 0)
$$;

revoke all on function private.ruler_gold_left(uuid, jsonb, integer) from public, anon, authenticated;

-- Przed zapisem zamku: perk władcy w zakresie gry i epoki, zmiana raz na 24 h za darmo, potem za złoto
-- z pokryciem. SECURITY DEFINER, bo gracz zapisuje jako `authenticated` i nie czyta `players.age`
-- ani wszystkich kolumn `attacks`; dotyczy tylko właściciela zapisywanego zamku (new.player_id).
create function private.check_castle_ruler_perk()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_new smallint := private.castle_ruler_perk(new.data);
  v_old smallint := -1;
  v_free timestamptz;
  v_paid integer := 0;
  v_age smallint;
  v_ruler jsonb;
begin
  if tg_op = 'UPDATE' then
    v_old := private.castle_ruler_perk(old.data);
    v_free := old.ruler_perk_free_at;
    v_paid := old.ruler_perk_paid;
  end if;
  select greatest(p.age, private.castle_age(new.data)) into v_age from public.players p where p.id = new.player_id;
  v_age := coalesce(v_age, private.castle_age(new.data));
  -- PERK_AGE: Łupieżca (1) i Budowniczy (4) od epoki II
  if v_new in (1, 4) and v_age < 1 then
    v_new := -1;
  end if;
  if v_new <> -1 and v_new <> v_old then
    if v_free is null or v_free <= now() - interval '24 hours' then
      new.ruler_perk_free_at := now();
    elsif private.ruler_gold_left(new.player_id, new.data -> 'generals', v_paid) >= 50 then
      new.ruler_perk_paid := v_paid + 1;
    else
      v_new := v_old;
    end if;
  end if;
  -- zawsze zapisujemy perk, który przyjął serwer (także cofnięty albo obcięty)
  if new.data ? 'ruler' or v_new <> -1 then
    v_ruler := case when jsonb_typeof(new.data -> 'ruler') = 'object' then new.data -> 'ruler' else '{}'::jsonb end;
    new.data := jsonb_set(new.data, '{ruler}', v_ruler || jsonb_build_object('perk', v_new));
  end if;
  return new;
end;
$$;

revoke all on function private.check_castle_ruler_perk() from public, anon, authenticated;

create trigger castles_check_ruler_perk
  before insert or update of data on public.castles
  for each row execute function private.check_castle_ruler_perk();

-- Generałowie (#31) z płatnymi zmianami perka władcy w wydanym złocie. Reszta bez zmian.
create or replace function private.checked_generals(p_player uuid, p_generals jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gold bigint;
  v_pvp_gold bigint;
  v_battles bigint;
  v_pvp_battles bigint;
  v_xp_cap bigint;
  v_pvp_xp_cap bigint;
  v_spent bigint := 0;
  v_pvp_spent bigint := 0;
  v_out jsonb := '[]'::jsonb;
  v_seen integer[] := '{}';
  e jsonb;
  v_kind integer;
  v_level integer;
  v_xp bigint;
  v_perk integer;
  v_attack integer;
  v_cost bigint;
begin
  if p_generals is null or jsonb_typeof(p_generals) <> 'object' then
    return jsonb_build_object('roster', '[]'::jsonb, 'attack', -1);
  end if;
  select coalesce(sum(coalesce(a.loot[4], 0)), 0),
    coalesce(sum(coalesce(a.loot[4], 0)) filter (where a.defender_id is not null), 0),
    count(*), count(*) filter (where a.defender_id is not null)
  into v_gold, v_pvp_gold, v_battles, v_pvp_battles
  from public.attacks a
  where a.attacker_id = p_player and a.status = 'finished';
  v_gold := v_gold + 50 + 125;
  -- płatne zmiany perka władcy (#32) zużyły już złoto z tej samej górnej granicy
  v_spent := 50 * coalesce((select c.ruler_perk_paid from public.castles c where c.player_id = p_player), 0);
  v_xp_cap := (v_battles + 5) * 40;
  v_pvp_xp_cap := v_pvp_battles * 40;

  for e in
    select x.v from jsonb_array_elements(case when jsonb_typeof(p_generals -> 'roster') = 'array'
        then p_generals -> 'roster' else '[]'::jsonb end) with ordinality as x(v, ord)
    order by x.ord
  loop
    exit when jsonb_array_length(v_out) >= 3;
    if jsonb_typeof(e) <> 'object' then
      continue;
    end if;
    v_kind := private.json_int(e -> 'kind', 0, 2)::integer;
    if v_kind is null or v_kind = any (v_seen) then
      continue;
    end if;
    -- rekrutacja: bez złota na nią ten i kolejni generałowie odpadają
    exit when v_spent + 50 > v_gold;
    v_cost := 50;
    v_level := coalesce(private.json_int(e -> 'level', 1, 3), 1)::integer;
    -- v_xp_cap i v_pvp_xp_cap to PD jeszcze nieprzydzielone: każdy przyjęty generał je zmniejsza (review #273),
    -- bo PD z jednej bitwy dostaje jeden generał. PD z PvP liczą się w obu pulach.
    -- poziom 2: złoto ogółem i 100 PD z dowolnych bitew
    if v_level >= 2 and (v_spent + v_cost + 80 > v_gold or v_xp_cap < 100) then
      v_level := 1;
    elsif v_level >= 2 then
      v_cost := v_cost + 80;
    end if;
    -- poziom 3: 150 złota z PvP (też w złocie ogółem) i 300 PD z PvP (też w PD ogółem, po poziomie 2)
    if v_level >= 3 and (v_spent + v_cost + 150 > v_gold or v_pvp_spent + 150 > v_pvp_gold
        or v_pvp_xp_cap < 300 or v_xp_cap - 100 < 300) then
      v_level := 2;
    elsif v_level >= 3 then
      v_cost := v_cost + 150;
      v_pvp_spent := v_pvp_spent + 150;
    end if;
    v_xp_cap := v_xp_cap - case when v_level >= 2 then 100 else 0 end - case when v_level >= 3 then 300 else 0 end;
    v_pvp_xp_cap := v_pvp_xp_cap - case when v_level >= 3 then 300 else 0 end;
    -- niewydane PD: na poziomie 1 z dowolnych bitew, wyżej boty już ich nie dają (tylko PvP)
    v_xp := coalesce(private.json_int(e -> 'xp', 0, 300), 0);
    if v_level = 1 then
      v_xp := least(v_xp, v_xp_cap);
    else
      v_xp := least(v_xp, v_pvp_xp_cap, v_xp_cap);
      v_pvp_xp_cap := v_pvp_xp_cap - v_xp;
    end if;
    v_xp_cap := v_xp_cap - v_xp;
    v_perk := case when v_level >= 3 then coalesce(private.json_int(e -> 'perk', 0, 1), -1)::integer else -1 end;
    v_spent := v_spent + v_cost;
    v_seen := v_seen || v_kind;
    v_out := v_out || jsonb_build_array(jsonb_build_object('kind', v_kind, 'level', v_level, 'xp', v_xp,
      'perk', v_perk));
  end loop;

  v_attack := private.json_int(p_generals -> 'attack', 0, 2)::integer;
  if v_attack is null or not (v_attack = any (v_seen)) then
    v_attack := -1;
  end if;
  return jsonb_build_object('roster', v_out, 'attack', v_attack, 'pvp_gold',
    least(coalesce(private.json_int(p_generals -> 'pvp_gold', 0, 10000000), 0), greatest(0, v_pvp_gold - v_pvp_spent)));
end;
$$;

revoke all on function private.checked_generals(uuid, jsonb) from public, anon, authenticated;

-- Zatwierdzenie planu (#28, #29, #31) z perkiem władcy atakującego (#32). Typ wyniku się zmienia, więc
-- funkcja powstaje od nowa; wdrożona Edge Function sprzed #32 woła ją tak samo i nową kolumnę pomija.
drop function public.launch_attack(uuid, uuid, jsonb, integer);

create function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb, p_general integer)
returns table (
  castle jsonb,
  defense jsonb,
  plan jsonb,
  techs text[],
  general jsonb,
  ruler_perk smallint
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
  where t.id = p_attack and t.attacker_id = p_attacker and t.defender_id is not null
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'started' or a.started_at < now() - interval '10 minutes' then
    raise exception 'attack_expired' using errcode = 'P0001';
  end if;
  if a.launched_at is null then
    a.orders := private.check_plan(p_plan, jsonb_array_length(a.attacker_army));
    select c.data into v_data from public.castles c where c.player_id = p_attacker;
    v_done := v_data -> 'research' -> 'done';
    a.attacker_techs := array(
      select code from unnest(array['A1', 'A2', 'A7']) as code
      where jsonb_typeof(v_done) = 'array' and v_done @> jsonb_build_array(code));
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
      attacker_general = a.attacker_general, attacker_ruler_perk = a.attacker_ruler_perk
    where t.id = a.id;
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot, a.orders,
    coalesce(a.attacker_techs, '{}'), a.attacker_general, coalesce(a.attacker_ruler_perk, -1::smallint);
end;
$$;

comment on function public.launch_attack(uuid, uuid, jsonb, integer) is
  'Atak na gracza po zatwierdzeniu planu (#28): pełne kopie zamku i obrony z chwili startu; zapisuje plan, badania, generała ataku i perk władcy z zamku atakującego (#29, #31, #32). Tylko dla service_role (Edge Function launch_attack).';
revoke all on function public.launch_attack(uuid, uuid, jsonb, integer) from public, anon, authenticated;
grant execute on function public.launch_attack(uuid, uuid, jsonb, integer) to service_role;

-- Powtórka obrony (#29) z perkiem władcy atakującego (#32).
drop function public.attack_replay(uuid, uuid);

create function public.attack_replay(p_player uuid, p_attack uuid)
returns table (
  map_seed bigint,
  battle_seed bigint,
  castle jsonb,
  defense jsonb,
  army jsonb,
  plan jsonb,
  techs text[],
  general jsonb,
  ruler_perk smallint,
  result jsonb,
  loot integer[],
  finished_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.defender_id = p_player and t.status = 'finished';
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.attacker_techs is null or a.castle_snapshot is null or a.defense_snapshot is null then
    raise exception 'replay_missing' using errcode = 'P0001';
  end if;
  return query select a.map_seed, a.battle_seed, a.castle_snapshot - 'scout', a.defense_snapshot,
    a.attacker_army, a.orders, a.attacker_techs, a.attacker_general, coalesce(a.attacker_ruler_perk, -1::smallint),
    a.result, a.loot, a.finished_at;
end;
$$;

comment on function public.attack_replay(uuid, uuid) is
  'Dane do powtórki zakończonej obrony (#29): kopie z chwili startu, armia, plan, badania, generał (#31) i perk władcy (#32) atakującego. Tylko obrońca; tylko dla service_role (Edge Function attack_replay).';
revoke all on function public.attack_replay(uuid, uuid) from public, anon, authenticated;
grant execute on function public.attack_replay(uuid, uuid) to service_role;

-- Koniec ataku (#25) z Łupieżcą (#32). Reszta bez zmian względem `*_finish_attack.sql`.
create or replace function public.end_attack(p_attacker uuid, p_attack uuid, p_result jsonb, p_loot jsonb,
  p_survivors jsonb)
returns table (
  status text,
  result jsonb,
  loot integer[],
  shield_until timestamptz
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_won boolean;
  v_percent bigint;
  v_stars jsonb;
  v_loot_pct bigint;
  v_loot integer[] := array[0, 0, 0, 0];
  v_capacity bigint := 0;
  v_sum bigint := 0;
  v_stash bigint;
  v_cap bigint;
  v_squad jsonb;
  v_alive bigint;
  v_count bigint;
  v_shield timestamptz;
  x bigint;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;

  if a.status = 'finished' then
    return query select a.status, a.result, a.loot,
      (select s.until from public.shields s where s.player_id = a.defender_id);
    return;
  end if;
  -- wygasły atak: zapis porzucenia bez wyjątku, żeby się nie cofnął
  if a.status = 'started' and a.started_at < now() - interval '10 minutes' then
    update public.attacks t set status = 'abandoned' where t.id = a.id;
    a.status := 'abandoned';
  end if;
  if a.status <> 'started' then
    return query select a.status, null::jsonb, null::integer[], null::timestamptz;
    return;
  end if;

  -- wynik: dokładnie {won, percent, stars}; STAR_PERCENT = 50
  if p_result is null or jsonb_typeof(p_result) <> 'object'
      or (select count(*) from jsonb_object_keys(p_result)) <> 3
      or jsonb_typeof(p_result -> 'won') is distinct from 'boolean'
      or jsonb_typeof(p_result -> 'stars') is distinct from 'array' then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;
  v_won := (p_result ->> 'won')::boolean;
  v_percent := private.json_int(p_result -> 'percent', 0, 100);
  v_stars := p_result -> 'stars';
  if v_percent is null or jsonb_array_length(v_stars) <> 3
      or jsonb_typeof(v_stars -> 0) <> 'boolean' or jsonb_typeof(v_stars -> 1) <> 'boolean'
      or jsonb_typeof(v_stars -> 2) <> 'boolean'
      or (v_stars ->> 1)::boolean <> (v_percent >= 50)
      or (v_stars ->> 2)::boolean <> v_won then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;

  -- ocaleli: liczba na każdy oddział z armii zapisanej przy starcie
  if p_survivors is null or jsonb_typeof(p_survivors) <> 'array'
      or jsonb_array_length(p_survivors) <> jsonb_array_length(a.attacker_army) then
    raise exception 'bad_survivors' using errcode = 'P0001';
  end if;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    v_squad := a.attacker_army -> i;
    v_count := private.json_int(v_squad -> 1, 0, 10);
    v_alive := private.json_int(p_survivors -> i, 0, coalesce(v_count, 0));
    if v_alive is null then
      raise exception 'bad_survivors' using errcode = 'P0001';
    end if;
    v_capacity := v_capacity + v_alive * private.unit_carry(private.json_int(v_squad -> 0, 0, 1000)::integer);
  end loop;

  -- łup: 4 liczby w kolejności EconomyConfig.Res (drewno, kamień, żywność, złoto)
  if p_loot is null or jsonb_typeof(p_loot) <> 'array' or jsonb_array_length(p_loot) <> 4 then
    raise exception 'bad_loot' using errcode = 'P0001';
  end if;
  -- WIN_LOOT_PERCENT = 50: wygrana liczy łup co najmniej jak przy połowie zniszczeń
  v_loot_pct := case when v_won then greatest(v_percent, 50) else 0 end;
  for i in 0 .. 3 loop
    x := private.json_int(p_loot -> i, 0, 10000000);
    if x is null then
      raise exception 'bad_loot' using errcode = 'P0001';
    end if;
    if a.defender_id is not null then
      v_stash := coalesce(private.json_int(a.castle_snapshot -> 'economy' -> 'amounts' -> i, 0, 10000000), 0);
    elsif i = 3 then
      -- skarbiec zamku-bota (BotRoster): GOLD_BASE = 20, GOLD_STEP = 10
      v_stash := 20 + 10 * a.bot_idx;
    else
      -- STASH_BASE = 1000, STASH_STEP = 500
      v_stash := 1000 + 500 * a.bot_idx;
    end if;
    -- PROTECTED_PERCENT = 50, LOOT_PERCENT = 20; dzielenie całkowite jak BattleResult.compute_loot
    v_cap := v_stash * (100 - 50) / 100 * 20 / 100 * v_loot_pct / 100;
    -- Łupieżca (#32): LOOTER_LOOT_PERCENT = 115 tylko przy ataku na gracza, z perkiem zapisanym przy
    -- zatwierdzeniu planu (attacks.attacker_ruler_perk); dzielenie całkowite jak RulerPerks.pvp_loot
    if a.defender_id is not null and a.attacker_ruler_perk = 1 then
      v_cap := v_cap * 115 / 100;
    end if;
    if x > v_cap then
      raise exception 'loot_too_high' using errcode = 'P0001';
    end if;
    v_loot[i + 1] := x::integer;
    v_sum := v_sum + x;
  end loop;
  if v_sum > v_capacity then
    raise exception 'loot_too_high' using errcode = 'P0001';
  end if;

  update public.attacks t set status = 'finished', result = p_result, loot = v_loot, finished_at = now()
  where t.id = a.id;

  -- SHIELD_PERCENT = 30, SHIELD_HOURS = 8
  if a.defender_id is not null and v_percent >= 30 then
    insert into public.shields as s (player_id, until) values (a.defender_id, now() + interval '8 hours')
    on conflict (player_id) do update set until = greatest(s.until, excluded.until);
  end if;
  if a.defender_id is not null then
    select s.until into v_shield from public.shields s where s.player_id = a.defender_id;
  end if;

  return query select 'finished'::text, p_result, v_loot, v_shield;
end;
$$;

comment on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) is
  'Koniec ataku (#25): wynik i łup w limitach (zapasy obrońcy, capacity ocalałych, Łupieżca #32), tarcza 8 h od 30 procent zniszczeń; ponowienie zwraca zapisany wynik. Tylko dla service_role (Edge Function finish_attack).';
revoke all on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) to service_role;

-- Limit utrzymania (#249, #35) z perkiem Gospodarny (#32): FOOD_BASE = 20, Rybacy FISHER_FOOD = [40, 60, 80, 110, 140],
-- Pola FARM_FOOD = [60, 90, 120, 160, 200], premia G2 = 15 procent i Gospodarny 10 punktów procentowych,
-- zaokrąglone w dół jak Economy.rates. Perk w danych zamku sprawdził już wyzwalacz zapisu.
create or replace function private.food_production(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((20 + coalesce((select sum(case b.kind
          when 16 then (array[40, 60, 80, 110, 140])[b.level]
          when 28 then (array[60, 90, 120, 160, 200])[b.level]
          else 0 end)
        from private.castle_buildings(p_castle) b where b.kind in (16, 28) and b.level >= 1), 0))
      * (100 + case when jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
          and (p_castle -> 'research' -> 'done') @> '["G2"]'::jsonb then 15 else 0 end
        + case when private.castle_ruler_perk(p_castle) = 3 then 10 else 0 end)
      / 100)::integer
$$;

revoke all on function private.food_production(jsonb) from public, anon, authenticated;
grant execute on function private.food_production(jsonb) to service_role;
