-- #413 (ADR 0016): worker weryfikacji liczy też ataki na zamki-boty.
--
-- Dotąd wygraną z botem, łup (#282), punkty PvE (#242) i postęp kampanii (`players.bots_beaten`, #386) dawał
-- wynik z telefonu. Atak na bota nie miał na serwerze planu, badań, generała, perku ani `sim_version`, więc
-- worker nie miał z czego policzyć bitwy.
--
-- - `public.begin_bot_attack`: start ataku na bota razem z zatwierdzeniem planu w jednej transakcji
--   (`begin_attack` + `launch_attack`). Edge Function `start_attack` woła ją, gdy żądanie niesie plan; odpowiedź
--   oddaje seed bitwy, plan, badania, generała i perk z serwera (BotBattle.from_start w grze).
-- - `public.launch_attack` przyjmuje też atak na bota (zamek-bot nie ma ukrytej obrony, kopie są puste).
-- - `private.settings.bot_verification_mode` (`off` / `shadow` / `enforce`, domyślnie `shadow`), niezależny
--   od `verification_mode` dla PvP. Powrót: update private.settings set value = 'shadow' where key = 'bot_verification_mode';
--   Przed `enforce` właścicielka podnosi `min_code` (ADR 0006), a klient musi znać status `verifying` (#417).
-- - `end_attack`: atak na bota z `sim_version` idzie do kolejki (od razu, bez czekania na ruiny). W `enforce`
--   bez łupu, punktów PvE i postępu kampanii do wyniku workera; bez `sim_version` (stary klient) nic nie daje.
-- - `apply_attack_outcome` i `attack_loot`: łup z zamku-bota z wyniku workera (skarbiec z `bot_idx`, powtórka
--   zdobytego zamku 50 %, bez Łupieżcy), bez tarczy i ruin.
-- - Wyzwalacze punktów PvE i kampanii działają przy wejściu skutków (`outcome_applied_at`), a nie przy samej
--   zmianie statusu, i pomijają `verification = 'failed'`. W `off` i `shadow` oba wchodzą jak dotąd w end_attack.
-- - `claim_verification`: najpierw PvP, potem boty (FIFO w grupie); job niesie `bot_idx`.
-- - `checked_verified_result`: przy bocie bez sprawdzania zniszczonych budynków względem kopii zamku (jej nie ma).
--
-- Ciała funkcji są skopiowane z `20261125211238_attack_verification.sql` (launch_attack z
-- `20261126065756_attack_doctrine_levels.sql`); zmieniają się tylko miejsca opisane wyżej. Sygnatury
-- i uprawnienia bez zmian. Nowych danych o graczu nie ma.

-- ---- przełącznik ----

alter table private.settings add constraint settings_bot_verification_mode
  check (key <> 'bot_verification_mode' or value in ('off', 'shadow', 'enforce'));
insert into private.settings (key, value) values ('bot_verification_mode', 'shadow') on conflict (key) do nothing;

create function private.bot_verification_mode()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select s.value from private.settings s where s.key = 'bot_verification_mode'), 'off');
$$;
comment on function private.bot_verification_mode() is 'Tryb weryfikacji ataków na zamki-boty: off, shadow albo enforce (#413, ADR 0016).';
revoke all on function private.bot_verification_mode() from public, anon, authenticated;
grant execute on function private.bot_verification_mode() to service_role;

-- ---- zatwierdzenie planu także dla zamka-bota ----

create or replace function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb, p_general integer,
  p_sim_version integer default null)
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
      sim_version = a.sim_version
    where t.id = a.id;
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot, a.orders,
    coalesce(a.attacker_techs, '{}'), a.attacker_general, coalesce(a.attacker_ruler_perk, -1::smallint);
end;
$$;

-- Start ataku na zamek-bota z planem (#413): begin_attack i launch_attack w jednej transakcji, więc odrzucony
-- plan albo wersja bez packa nie zostawia ataku w toku. Tylko dla service_role (Edge Function start_attack).
create function public.begin_bot_attack(p_attacker uuid, p_bot smallint, p_army jsonb, p_battle_seed bigint,
  p_plan jsonb, p_general integer, p_sim_version integer)
returns table (
  attack_id uuid,
  map_seed bigint,
  battle_seed bigint,
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
  v_id uuid;
  v_seed bigint;
  v_battle bigint;
begin
  if p_bot is null then
    raise exception 'bad_target' using errcode = 'P0001';
  end if;
  select b.attack_id, b.map_seed, b.battle_seed into v_id, v_seed, v_battle
  from public.begin_attack(p_attacker, null, p_bot, p_army, p_battle_seed) b;
  return query select v_id, v_seed, v_battle, l.plan, l.techs, l.general, l.ruler_perk
  from public.launch_attack(p_attacker, v_id, p_plan, p_general, p_sim_version) l;
end;
$$;

comment on function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer) is
  'Start ataku na zamek-bota z zatwierdzonym planem (#413, ADR 0016): begin_attack i launch_attack w jednej transakcji; zwraca seedy oraz plan, badania, generała i perk z serwera do bitwy i weryfikacji. Tylko dla service_role (Edge Function start_attack).';
revoke all on function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer)
  from public, anon, authenticated;
grant execute on function public.begin_bot_attack(uuid, smallint, jsonb, bigint, jsonb, integer, integer)
  to service_role;

-- ---- koniec ataku: tryb dla botów ----

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
  v_mode text := 'off';
  x bigint;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;

  if a.status = 'finished' then
    -- #284: atak w weryfikacji (enforce) nie ma jeszcze skutków ani łupu
    return query select case when a.outcome_applied_at is null then 'verifying'::text else a.status end,
      a.result, a.loot,
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

  -- #284, #413: atak na gracza i na zamek-bota idzie do weryfikacji na serwerze (worker z tym samym GDScript). Wynik telefonu zostaje
  -- w claimed_result tylko do porównania.
  if a.defender_id is not null then
    v_mode := private.verification_mode();
  else
    -- #413 (ADR 0016): atak na zamek-bota ma własny przełącznik
    v_mode := private.bot_verification_mode();
  end if;
  if v_mode = 'enforce' and a.defender_id is null and a.sim_version is null then
    -- bez planu zatwierdzonego na serwerze (stary klient) worker nie policzy bitwy: wynik bez łupu, punktów
    -- PvE i postępu kampanii (wyzwalacze pomijają verification = 'failed')
    update public.attacks t set status = 'finished', result = p_result, loot = array[0, 0, 0, 0],
      finished_at = now(), outcome_applied_at = now(), verification = 'failed', verified_at = now(),
      claimed_result = jsonb_build_object('won', v_won, 'percent', v_percent, 'stars', v_stars,
        'loot', to_jsonb(v_loot), 'survivors', p_survivors)
    where t.id = a.id;
    return query select 'finished'::text, p_result, array[0, 0, 0, 0]::integer[], null::timestamptz;
    return;
  end if;
  if v_mode = 'enforce' then
    -- bez łupu, rankingu, tarczy i ruin: wszystko policzy apply_attack_outcome z wyniku workera. Cel zostaje
    -- zablokowany (begin_attack, match_targets), więc nikt nie złupi tych samych zapasów drugi raz.
    update public.attacks t set status = 'finished', result = p_result, loot = null, finished_at = now(),
      claimed_result = jsonb_build_object('won', v_won, 'percent', v_percent, 'stars', v_stars,
        'loot', to_jsonb(v_loot), 'survivors', p_survivors),
      verification = 'pending'
    where t.id = a.id;
    perform private.enqueue_verification(a.id);
    if a.defender_id is null then
      perform private.verification_ready(a.id);  -- zamek-bot nie ma ruin, job od razu (#413)
    end if;
    return query select 'verifying'::text, p_result, null::integer[],
      (select s.until from public.shields s where s.player_id = a.defender_id);
    return;
  end if;

  update public.attacks t set status = 'finished', result = p_result, loot = v_loot, finished_at = now(),
    outcome_applied_at = now(),
    claimed_result = case when v_mode = 'shadow' then jsonb_build_object('won', v_won, 'percent', v_percent,
      'stars', v_stars, 'loot', to_jsonb(v_loot), 'survivors', p_survivors) end,
    verification = case when v_mode = 'shadow' and a.sim_version is not null then 'pending' end
  where t.id = a.id;
  -- tryb shadow: skutki już weszły z wyniku telefonu, worker tylko porówna (attacks.verification)
  if v_mode = 'shadow' and a.sim_version is not null then
    perform private.enqueue_verification(a.id);
    if a.defender_id is null then
      perform private.verification_ready(a.id);
    end if;
  end if;

  -- #274: łup przenosi serwer w tej samej transakcji: atakujący zyskuje, a obrońca-gracz traci. Od #282 także
  -- łup z zamku-bota (bez obrońcy). Zmiana czeka w castle_loot_pending i wchodzi do `castles.data` przy
  -- najbliższym zapisie zamku każdego z nich (wyzwalacz castles_resources, po bilansie surowców). Ponowienie
  -- wraca wyżej (status 'finished'), więc łup liczy się raz.
  if v_sum > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
  end if;
  if a.defender_id is not null and v_sum > 0 then
    perform private.add_loot_pending(a.defender_id,
      array[-v_loot[1], -v_loot[2], -v_loot[3], -v_loot[4]]::bigint[]);
  end if;

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

-- ---- łup i skutki z wyniku workera ----

create or replace function private.attack_loot(a public.attacks, p_won boolean, p_percent bigint, p_survivors jsonb)
returns integer[]
language plpgsql
stable
set search_path = ''
as $$
declare
  v_loot bigint[] := array[0, 0, 0, 0];
  v_pct bigint := case when p_won then greatest(p_percent, 50) else 0 end;
  v_capacity bigint := 0;
  v_total bigint := 0;
  v_stash bigint;
  v_squad jsonb;
  v_alive bigint;
  -- REPEAT_PERCENT = 50: zamek-bot zdobyty już wcześniej (BattleResult.compute_loot, BotRoster.is_beaten)
  v_repeat boolean := a.defender_id is null
    and coalesce((select p.bots_beaten from public.players p where p.id = a.attacker_id), 0) > a.bot_idx;
begin
  for i in 0 .. 3 loop
    if a.defender_id is not null then
      v_stash := coalesce(private.json_int(a.castle_snapshot -> 'economy' -> 'amounts' -> i, 0, 10000000), 0);
    elsif i = 3 then
      -- skarbiec zamku-bota (BattleResult.stash): GOLD_BASE = 20, GOLD_STEP = 10
      v_stash := 20 + 10 * a.bot_idx;
    else
      -- STASH_BASE = 1000, STASH_STEP = 500
      v_stash := 1000 + 500 * a.bot_idx;
    end if;
    v_loot[i + 1] := v_stash * (100 - 50) / 100 * 20 / 100 * v_pct / 100;
    if v_repeat then
      v_loot[i + 1] := v_loot[i + 1] * 50 / 100;
    end if;
    -- Łupieżca (#32) tylko przy ataku na gracza
    if a.defender_id is not null and a.attacker_ruler_perk = 1 then
      v_loot[i + 1] := v_loot[i + 1] * 115 / 100;
    end if;
    v_total := v_total + v_loot[i + 1];
  end loop;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    v_squad := a.attacker_army -> i;
    v_alive := least(greatest(coalesce(private.json_int(p_survivors -> i, 0, 2147483647), 0), 0),
      coalesce(private.json_int(v_squad -> 1, 0, 10), 0));
    v_capacity := v_capacity + v_alive * private.unit_carry(private.json_int(v_squad -> 0, 0, 1000)::integer);
  end loop;
  if v_total > v_capacity then
    for i in 1 .. 4 loop
      v_loot[i] := v_loot[i] * v_capacity / v_total;
    end loop;
  end if;
  return v_loot::integer[];
end;
$$;

create or replace function private.apply_attack_outcome(p_attack uuid)
returns boolean
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  a public.attacks%rowtype;
  v jsonb;
  v_loot integer[];
  v_percent bigint;
begin
  select * into a from public.attacks t where t.id = p_attack for update;
  if not found or a.outcome_applied_at is not null or a.verified_result is null
      or a.verification not in ('verified', 'mismatch') or a.status <> 'finished' then
    return false;
  end if;
  v := a.verified_result;
  v_percent := (v ->> 'percent')::bigint;
  -- łup przed zmianą ataku: wyzwalacz kampanii (#413) podbija bots_beaten dopiero po niej, a powtórka
  -- zdobytego zamku-bota daje mniej łupu
  v_loot := private.attack_loot(a, (v ->> 'won')::boolean, v_percent, v -> 'survivors');

  update public.attacks t set
    result = jsonb_build_object('won', v -> 'won', 'percent', v -> 'percent', 'stars', v -> 'stars'),
    loot = v_loot,
    -- ruiny ma tylko obrońca-gracz; zamek-bot powstaje z seeda (#99)
    destroyed = case when a.defender_id is null then t.destroyed
      else array(select (x.value #>> '{}')::integer from jsonb_array_elements(v -> 'destroyed_ids') as x) end,
    outcome_applied_at = now()
  where t.id = a.id;

  if v_loot[1] + v_loot[2] + v_loot[3] + v_loot[4] > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
    if a.defender_id is not null then
      perform private.add_loot_pending(a.defender_id,
        array[-v_loot[1], -v_loot[2], -v_loot[3], -v_loot[4]]::bigint[]);
    end if;
  end if;
  if a.defender_id is not null and v_percent >= 30 then
    insert into public.shields as s (player_id, until) values (a.defender_id, now() + interval '8 hours')
    on conflict (player_id) do update set until = greatest(s.until, excluded.until);
  end if;
  return true;
end;
$$;

create or replace function private.checked_verified_result(a public.attacks, p_result jsonb)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_won boolean;
  v_percent bigint;
  v_stars jsonb;
  v_ids integer[] := '{}';
  v_alive jsonb := '[]'::jsonb;
  v_total bigint;
  v_ticks bigint;
  v_checksum bigint;
  v_sim bigint;
  x bigint;
  e jsonb;
begin
  if p_result is null or jsonb_typeof(p_result) <> 'object'
      or jsonb_typeof(p_result -> 'won') is distinct from 'boolean'
      or jsonb_typeof(p_result -> 'stars') is distinct from 'array'
      or jsonb_typeof(p_result -> 'destroyed_ids') is distinct from 'array'
      or jsonb_typeof(p_result -> 'survivors') is distinct from 'array' then
    return null;
  end if;
  v_won := (p_result ->> 'won')::boolean;
  v_percent := private.json_int(p_result -> 'percent', 0, 100);
  v_stars := p_result -> 'stars';
  v_ticks := private.json_int(p_result -> 'ticks', 0, 2147483647);
  v_checksum := private.json_int(p_result -> 'checksum', -9223372036854775808, 9223372036854775807);
  v_sim := private.json_int(p_result -> 'sim_version', 1, 2147483647);
  -- STAR_PERCENT = 50: druga gwiazdka od połowy zniszczeń, trzecia za wygraną
  if v_percent is null or v_ticks is null or v_checksum is null or v_sim is null
      or v_sim is distinct from a.sim_version::bigint
      or jsonb_array_length(v_stars) <> 3
      or jsonb_typeof(v_stars -> 0) <> 'boolean' or jsonb_typeof(v_stars -> 1) <> 'boolean'
      or jsonb_typeof(v_stars -> 2) <> 'boolean'
      or (v_stars ->> 1)::boolean <> (v_percent >= 50)
      or (v_stars ->> 2)::boolean <> v_won then
    return null;
  end if;

  -- zniszczone budynki: gotowe budynki z kopii zamku bez wału i palisady (jak record_destroyed), bez powtórzeń
  if jsonb_array_length(p_result -> 'destroyed_ids') > 200 then
    return null;
  end if;
  for e in select y.value from jsonb_array_elements(p_result -> 'destroyed_ids') as y loop
    x := private.json_int(e, 1, 2147483647);
    if x is null or x::integer = any (v_ids) then
      return null;
    end if;
    v_ids := v_ids || x::integer;
  end loop;
  -- #413: zamek-bot nie ma kopii zamku w bazie; budynki z BotRoster zna tylko worker
  if a.defender_id is not null then
    if exists (
      select 1 from unnest(v_ids) as d(id)
      where not exists (
        select 1 from private.castle_buildings(a.castle_snapshot) b
        where b.id = d.id and b.level >= 1 and b.kind not in (0, 1))) then
      return null;
    end if;
    select count(*) into v_total from private.castle_buildings(a.castle_snapshot) b
    where b.level >= 1 and b.kind not in (0, 1);
    if cardinality(v_ids) > 0 and cardinality(v_ids)::bigint * 100 / greatest(v_total, 1) > v_percent then
      return null;
    end if;
  end if;

  -- ocaleli: liczba na każdy oddział armii z chwili startu
  if jsonb_array_length(p_result -> 'survivors') <> jsonb_array_length(a.attacker_army) then
    return null;
  end if;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    x := private.json_int(p_result -> 'survivors' -> i, 0,
      coalesce(private.json_int(a.attacker_army -> i -> 1, 0, 10), 0));
    if x is null then
      return null;
    end if;
    v_alive := v_alive || to_jsonb(x);
  end loop;

  return jsonb_build_object('won', v_won, 'percent', v_percent, 'stars', v_stars,
    'destroyed_ids', to_jsonb(array(select i from unnest(v_ids) as i order by i)),
    'survivors', v_alive, 'ticks', v_ticks, 'checksum', v_checksum, 'sim_version', v_sim);
end;
$$;

-- ---- kolejka ----

create or replace function private.claim_verification(p_worker text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  q private.attack_verifications%rowtype;
  a public.attacks%rowtype;
begin
  if p_worker is null or p_worker !~ '^[A-Za-z0-9_.-]{1,64}$' then
    raise exception 'bad_worker' using errcode = 'P0001';
  end if;

  with dead as (
    select v.attack_id from private.attack_verifications v
    where v.attempts >= 3 and v.leased_until <= now()
    for update skip locked
  ), gone as (
    delete from private.attack_verifications v using dead where v.attack_id = dead.attack_id
    returning v.attack_id
  )
  update public.attacks t set verification = 'failed', verified_at = now()
  from gone where t.id = gone.attack_id and t.verification = 'pending';

  -- #413 (ADR 0016): najpierw PvP (w enforce atak blokuje cel), potem zamki-boty; w każdej grupie FIFO
  select v.* into q from private.attack_verifications v
  join public.attacks t on t.id = v.attack_id
  where v.attempts < 3 and (v.leased_until is null or v.leased_until <= now()) and v.not_before <= now()
  order by (t.defender_id is null), v.created_at, v.attack_id
  limit 1
  for update of v skip locked;
  if not found then
    return null;
  end if;

  update private.attack_verifications v set
    attempts = v.attempts + 1,
    leased_until = now() + interval '5 minutes',
    leased_by = p_worker,
    -- poprzedni lease wygasł bez wyniku (timeout, crash albo błąd Godota po stronie workera)
    last_error = case when v.attempts > 0 then 'lease_expired' else v.last_error end
  where v.attack_id = q.attack_id;

  select * into a from public.attacks t where t.id = q.attack_id;
  return jsonb_build_object(
    'attack_id', a.id, 'id', a.id, 'sim_version', a.sim_version, 'bot_idx', a.bot_idx,
    'map_seed', a.map_seed, 'battle_seed', a.battle_seed,
    'castle', coalesce(a.castle_snapshot - 'scout', '{}'::jsonb), 'defense', coalesce(a.defense_snapshot, '{}'::jsonb),
    'army', a.attacker_army, 'plan', a.orders, 'techs', to_jsonb(coalesce(a.attacker_techs, '{}')),
    'general', a.attacker_general, 'ruler_perk', coalesce(a.attacker_ruler_perk, -1::smallint));
end;
$$;

create or replace function private.requeue_verification(p_attack uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
begin
  update public.attacks t set verification = 'pending', verified_result = null, verified_at = null
  where t.id = p_attack and t.status = 'finished'
    and t.verification in ('failed', 'pending');
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  insert into private.attack_verifications (attack_id) values (p_attack)
  on conflict (attack_id) do update set attempts = 0, leased_until = null, leased_by = null, last_error = null,
    not_before = now();
  update private.attack_verifications v set not_before = now() where v.attack_id = p_attack;
end;
$$;

-- ---- punkty PvE i kampania przy wejściu skutków ----

-- W enforce wynik z telefonu nie daje punktów ani postępu: wchodzą razem ze skutkami z wyniku workera.
-- W off i shadow end_attack ustawia status i outcome_applied_at jednym update, więc działa to jak dotąd.
drop trigger attacks_pve_points on public.attacks;
create trigger attacks_pve_points
  after update of status, outcome_applied_at on public.attacks
  for each row
  when (new.bot_idx is not null and new.status = 'finished'
    and old.outcome_applied_at is null and new.outcome_applied_at is not null
    and new.result -> 'won' = 'true'::jsonb and new.verification is distinct from 'failed')
  execute function private.apply_pve_points();

drop trigger attacks_bots_beaten on public.attacks;
create trigger attacks_bots_beaten
  after update of status, outcome_applied_at on public.attacks
  for each row
  when (new.bot_idx is not null and new.status = 'finished'
    and old.outcome_applied_at is null and new.outcome_applied_at is not null
    and new.result -> 'won' = 'true'::jsonb and new.verification is distinct from 'failed')
  execute function private.advance_bots_beaten();


comment on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) is
  'Koniec ataku (#25): wynik i łup w limitach (zapasy obrońcy albo skarbiec zamku-bota, capacity ocalałych, Łupieżca #32). Atak na gracza (verification_mode) i na zamek-bota z sim_version (bot_verification_mode, #413) idzie do weryfikacji (#284): w trybie shadow skutki od razu i porównanie przez worker, w enforce status verifying bez łupu, rankingu, tarczy, ruin, punktów PvE i postępu kampanii, które da wynik workera. Łup przez castle_loot_pending (#274, #282); ponowienie zwraca zapisany wynik. Tylko dla service_role (Edge Function finish_attack).';
comment on function private.apply_attack_outcome(uuid) is
  'Skutki ataku z wyniku workera (#284, #413): łup, ranking, tarcza i ruiny (gracz) albo łup, punkty PvE i postęp kampanii (zamek-bot) tylko z verified_result; idempotentna.';
comment on function private.claim_verification(text) is
  'Worker weryfikacji (#284, #413): bierze jeden job z kolejki, najpierw PvP, potem zamki-boty (SKIP LOCKED, lease 5 min, max 3 próby). Tylko dla roli verifier.';
comment on function public.launch_attack(uuid, uuid, jsonb, integer, integer) is
  'Zatwierdzenie planu ataku (#28): pełne kopie zamku i obrony obrońcy z chwili startu (przy zamku-bocie puste, #413); zapisuje plan, badania, generała ataku, perk władcy (#29, #31, #32) i wersję symulacji dla weryfikacji (#284, unsupported_version bez packa). Tylko dla service_role (Edge Functions launch_attack i start_attack).';
