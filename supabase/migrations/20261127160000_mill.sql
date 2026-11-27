-- #388: Młyn (G5 Młyn wodny), pierwszy budynek epoki II spoza MVP (#102, ADR 0010).
--
-- Młyn (MILL = 32) stoi przy rzece, wymaga G5 (epoka II, wymaga G2) i stawia się od razu na poziomie
-- START_LEVEL = 6 (poziom 1 epoki II, BuildConfig.start_level), ulepsza do 10. Daje premię do całej produkcji
-- żywności MILL_FOOD_PERCENT = [4, 8, 12, 16, 20] punktów procentowych na poziomach 6–10; liczy się jeden Młyn
-- (najwyższy poziom). Serwer musi to znać w kilku miejscach:
-- - drzewko `private.tech_tree` jak w `*_defense_reach.sql`, z G5:
--   TECH_TREE = {"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "A60": [0, []], "A61": [1, ["A60"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "O25": [0, []], "O23": [0, []], "O24": [1, ["O23"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [0, ["G1"]], "G5": [1, ["G2"]], "G6": [1, ["G4"]], "G25": [0, []], "G26": [1, ["G25"]], "U1": [0, []], "U14": [0, []], "U15": [1, ["U14"]], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}
-- - koszt poziomu 1 (`private.build_cost`, krzywa jak w `*_age_two_balance.sql`):
--   BUILD_COST = {"0": [10, 0, 10, 0], "1": [20, 0, 5, 0], "2": [60, 20, 20, 0], "3": [120, 40, 40, 0], "4": [80, 0, 30, 0], "6": [60, 0, 20, 0], "7": [80, 20, 20, 0], "8": [100, 20, 30, 0], "9": [80, 20, 20, 0], "10": [60, 0, 20, 0], "11": [100, 0, 30, 0], "12": [80, 10, 20, 0], "13": [90, 0, 30, 0], "14": [60, 40, 10, 0], "15": [30, 0, 20, 0], "16": [70, 0, 10, 0], "17": [100, 20, 40, 0], "18": [100, 20, 40, 0], "19": [140, 30, 40, 0], "20": [120, 10, 40, 0], "21": [150, 60, 40, 0], "22": [120, 20, 40, 10], "24": [100, 40, 30, 0], "25": [100, 40, 0, 0], "26": [5, 0, 15, 0], "27": [60, 40, 40, 0], "28": [60, 0, 20, 0], "29": [40, 30, 10, 0], "30": [100, 0, 30, 0], "31": [100, 20, 30, 0], "32": [120, 60, 20, 0]}
-- - czas poziomu 1 (`private.build_time_ms`): BASE_TIME_S = [5, 10, 30, 60, 45, 0, 40, 50, 60, 50, 40, 60, 50, 60, 45, 30, 40, 60, 60, 75, 70, 90, 70, 0, 60, 45, 5, 60, 40, 30, 50, 50, 50]
-- - wymagana technologia nowego budynku (`private.locked_new_building`):
--   REQUIRED_TECH = {"6": "G18", "7": "G19", "8": "A38", "9": "A39", "10": "A40", "11": "A41", "12": "A42", "13": "A43", "14": "G24", "15": "G20", "16": "G21", "19": "A45", "20": "A44", "22": "S1", "24": "O2", "27": "O1", "30": "G4", "31": "S2", "32": "G5"}
-- - poziomy opłacone i budowane (`private.build_paid`, `private.build_need_ms`) zaczynają się dla Młyna od
--   START_LEVEL, bo w grze nie ma poziomów 1–5 Młyna (bez tego serwer liczyłby koszt i czas poziomów 1–6);
-- - zapis z Młynem na poziomie 1–5 jest odrzucany (`private.castle_buildings_problem`, kod `bad_building`):
--   takich poziomów w grze nie ma, a serwer nie liczy za nie kosztu ani czasu, więc byłyby darmowym budynkiem
--   z wytrzymałością w bitwie;
-- - limit utrzymania (`private.food_production`) i górna granica produkcji (`private.production_max`) z premią Młyna.
-- Ruina Młyna (#99) daje w grze 75% premii; serwer liczy premię pełną, jak pełną produkcję ruin
-- (górna granica, bez nowej furtki). Nowych danych o graczu nie ma.
--
-- Każda funkcja to najnowsza wersja z wcześniejszych migracji z nowymi tablicami. `create or replace` zostawia
-- uprawnienia; mimo to powtarzamy je jawnie (tylko service_role tam, gdzie było). Liczby pilnują testy gry
-- (`tests/test_mill.gd`, `tests/test_army_research_goods_sanity.gd`, `tests/test_building_sanity.gd`,
-- `tests/test_economy_growth.gd`, `tests/test_attack_limits.gd`) po znacznikach w komentarzach,
-- a pgTAP `supabase/tests/database/mill_test.sql`.

create or replace function private.tech_tree()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "A60": [0, []], "A61": [1, ["A60"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "O25": [0, []], "O23": [0, []], "O24": [1, ["O23"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [0, ["G1"]], "G5": [1, ["G2"]], "G6": [1, ["G4"]], "G25": [0, []], "G26": [1, ["G25"]], "U1": [0, []], "U14": [0, []], "U15": [1, ["U14"]], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}'::jsonb
$$;

-- Koszt poziomu `p_level` (narastająco, 1..10) budynku `p_kind` (BuildConfig.cost) jak w `*_age_two_balance.sql`, z Młynem.
create or replace function private.build_cost(p_kind bigint, p_level bigint)
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_lv integer := least(greatest(p_level, 1), 10)::integer;
  v_base jsonb;
  v_percent bigint;
begin
  if p_kind = 5 then
    return array(select (e #>> '{}')::bigint from jsonb_array_elements(
      ('[[0, 0, 0, 0], [300, 200, 200, 0], [500, 350, 350, 0], [750, 550, 550, 0], [1000, 800, 800, 0], [1000, 1000, 1000, 0], [1300, 1100, 1100, 0], [1700, 1400, 1400, 0], [2200, 1800, 1800, 0], [2800, 2300, 2300, 0]]'::jsonb
        -> (v_lv - 1))) e);
  end if;
  v_base := '{"0": [10, 0, 10, 0], "1": [20, 0, 5, 0], "2": [60, 20, 20, 0], "3": [120, 40, 40, 0], "4": [80, 0, 30, 0], "6": [60, 0, 20, 0], "7": [80, 20, 20, 0], "8": [100, 20, 30, 0], "9": [80, 20, 20, 0], "10": [60, 0, 20, 0], "11": [100, 0, 30, 0], "12": [80, 10, 20, 0], "13": [90, 0, 30, 0], "14": [60, 40, 10, 0], "15": [30, 0, 20, 0], "16": [70, 0, 10, 0], "17": [100, 20, 40, 0], "18": [100, 20, 40, 0], "19": [140, 30, 40, 0], "20": [120, 10, 40, 0], "21": [150, 60, 40, 0], "22": [120, 20, 40, 10], "24": [100, 40, 30, 0], "25": [100, 40, 0, 0], "26": [5, 0, 15, 0], "27": [60, 40, 40, 0], "28": [60, 0, 20, 0], "29": [40, 30, 10, 0], "30": [100, 0, 30, 0], "31": [100, 20, 30, 0], "32": [120, 60, 20, 0]}'::jsonb
    -> p_kind::text;
  if v_base is null then
    return array[0, 0, 0, 0]::bigint[];
  end if;
  v_percent := (array[100, 150, 250, 400, 600, 850, 1150, 1500, 1950, 2500])[v_lv];
  return array(select (v_base ->> i)::bigint * v_percent / 100 from generate_series(0, 3) i order by i);
end;
$$;

-- Czas budowy poziomu `p_level` (narastająco) w ms jak BuildConfig.time_ms, z Młynem.
create or replace function private.build_time_ms(p_kind bigint, p_level bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_level < 1 or p_level > 10 then 0::bigint
    when p_kind = 5 then (array[0, 600, 3600, 14400, 43200, 50400, 64800, 86400, 108000, 144000])[p_level]::bigint * 1000
    else coalesce((array[5, 10, 30, 60, 45, 0, 40, 50, 60, 50, 40, 60, 50, 60, 45, 30, 40, 60, 60, 75, 70, 90, 70, 0, 60, 45, 5, 60, 40, 30, 50, 50, 50])[p_kind + 1], 0)::bigint
      * case when p_kind in (0, 1, 26, 2) and p_level > 5
          then 90 + ((array[1, 3, 10, 30, 90, 130, 180, 240, 320, 420])[p_level] - 90) * 50 / 100
          else (array[1, 3, 10, 30, 90, 130, 180, 240, 320, 420])[p_level] end * 1000
  end
$$;

-- Czy w `p_new` stoi nowy budynek bez technologii z BuildConfig.REQUIRED_TECH (jak w `*_building_sanity.sql`, z Młynem).
create or replace function private.locked_new_building(p_old jsonb, p_new jsonb)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select exists (
    select 1
    from private.castle_levels(p_new) n
    cross join lateral (select ('{"6": "G18", "7": "G19", "8": "A38", "9": "A39", "10": "A40", "11": "A41", "12": "A42", "13": "A43", "14": "G24", "15": "G20", "16": "G21", "19": "A45", "20": "A44", "22": "S1", "24": "O2", "27": "O1", "30": "G4", "31": "S2", "32": "G5"}'::jsonb ->> n.kind::text) as tech) r
    where r.tech is not null
      and not exists (select 1 from private.castle_levels(p_old) o where o.id = n.id and o.kind = n.kind)
      -- coalesce: zapis bez `research` to brak technologii (null nie może przepuścić budynku)
      and not coalesce(jsonb_typeof(p_new -> 'research' -> 'done') = 'array'
        and (p_new -> 'research' -> 'done') @> jsonb_build_array(r.tech), false))
$$;

-- Czas budowy (ms) poziomów, które przybyły w `p_new` względem `p_old`; Młyn od START_LEVEL.
create or replace function private.build_need_ms(p_old jsonb, p_new jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(private.build_time_ms(n.kind, l)), 0)::bigint
  from private.castle_levels(p_new) n
  left join private.castle_levels(p_old) o on o.id = n.id and o.kind = n.kind
  cross join lateral generate_series(greatest(greatest(coalesce(o.level, 0), 0) + 1,
    case when n.kind = 32 then 6 else 1 end), least(n.level, 10)) as l
$$;

-- Poziomy opłacone w zapisie (jak w `*_economy_growth.sql`): Młyn od START_LEVEL, reszta od poziomu 1.
create or replace function private.build_paid(p_castle jsonb)
returns table (id bigint, kind bigint, level bigint, queued boolean)
language sql
immutable
set search_path = ''
as $$
  select b.id, b.kind, l::bigint, false
  from private.castle_levels(p_castle) b
  cross join lateral generate_series(case when b.kind = 32 then 6 else 1 end, least(greatest(b.level, 0), 10)) as l
  union
  select b.id, b.kind, q.level, true
  from (
    select private.json_int(o -> 'building_id', 1, 2147483647) as id, private.json_int(o -> 'level', 1, 10) as level
    from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'queue' -> 'orders') = 'array'
        then p_castle -> 'queue' -> 'orders' else '[]'::jsonb end) o
    where jsonb_typeof(o) = 'object'
  ) q
  join private.castle_levels(p_castle) b on b.id = q.id
  where q.level is not null
$$;

-- Premia Młyna do żywności w punktach procentowych z najwyższego Młyna w zbiorze budynków (0 poniżej poziomu 6).
create or replace function private.mill_food_percent(p_level integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce((select (array[4, 8, 12, 16, 20])[least(m.level - 5, 5)]
    from (select p_level as level) m where m.level >= 6), 0)
$$;

-- Limit utrzymania (żywność na godzinę) jak w `*_age_two_balance.sql`, z premią Młyna.
create or replace function private.food_production(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((20 + coalesce((select sum(case b.kind
          when 16 then (array[40, 60, 80, 110, 140, 170, 200, 230, 270, 310])[b.level]
          when 28 then (array[60, 90, 120, 160, 200, 240, 280, 330, 380, 440])[b.level]
          else 0 end)
        from private.castle_buildings(p_castle) b where b.kind in (16, 28) and b.level >= 1), 0))
      * (100 + case when private.tech_level(p_castle, 'G2') >= 1
          then 15 + 5 * (private.tech_level(p_castle, 'G2') - 1) else 0 end
        + case when private.castle_ruler_perk(p_castle) in (3, 4) then 10 else 0 end
        + private.mill_food_percent((select max(b.level) from private.castle_buildings(p_castle) b where b.kind = 32)))
      / 100)::integer
$$;

-- Górna granica produkcji jak w `*_age_two_balance.sql`, z premią Młyna do żywności.
create or replace function private.production_max(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with b as (select * from private.buildings_max(p_old, p_new)),
  raw as (
    select r, (array[20, 20, 20, 0])[r + 1] + coalesce((select sum((p.v -> 1 ->> (b.level - 1))::bigint)
        from b join jsonb_each('{"4": [0, [60, 90, 120, 160, 200, 240, 280, 330, 380, 440]], "16": [2, [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]], "28": [2, [60, 90, 120, 160, 200, 240, 280, 330, 380, 440]], "30": [1, [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]]}'::jsonb) p(k, v)
          on p.k = b.kind::text and (p.v ->> 0)::integer = r), 0) as amount
    from generate_series(0, 3) r
  ), bonus as (
    select r, coalesce((select sum((t.v ->> 1)::integer
          + 5 * (greatest(private.tech_level(p_old, t.k), private.tech_level(p_new, t.k)) - 1))
        from jsonb_each('{"G1": [0, 20], "G2": [2, 15]}'::jsonb) t(k, v)
        where (t.v ->> 0)::integer = r
          and greatest(private.tech_level(p_old, t.k), private.tech_level(p_new, t.k)) >= 1), 0)
      + case when private.castle_ruler_perk(p_old) in (3, 4) or private.castle_ruler_perk(p_new) in (3, 4)
          then 10 else 0 end
      + case when r = 2 then private.mill_food_percent((select max(b.level) from b where b.kind = 32)) else 0 end as percent
    from generate_series(0, 3) r
  )
  select array(
    select raw.amount * (100 + bonus.percent) / 100
      -- HUNTER_FOOD = 2 na cykl, 6 cykli na godzinę na poziomie 1 razy LEVEL_PERCENT = [100, 150, 200, 275, 350, 425, 500, 575, 650, 750]
      + case when raw.r = 2 then coalesce((select sum(2 * (6 * (array[100, 150, 200, 275, 350, 425, 500, 575, 650, 750])[b.level] / 100))
          from b where b.kind = 6), 0) else 0 end
    from raw join bonus on bonus.r = raw.r
    order by raw.r)::bigint[]
$$;

-- Kod problemu z poziomami budynków w zapisie albo null (jak w `*_building_sanity.sql`), z Młynem tylko od START_LEVEL.
create or replace function private.castle_buildings_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_manor_id bigint;
  v_manor bigint;
begin
  if exists (select 1 from private.castle_levels(p_castle) b where b.level < 0 or b.level > 10) then
    return 'bad_building';
  end if;
  if exists (select 1 from private.castle_levels(p_castle) b where b.kind = 32 and b.level between 1 and 5) then
    return 'bad_building';
  end if;
  select b.id, greatest(b.level, 1) into v_manor_id, v_manor
  from private.castle_levels(p_castle) b where b.kind = 5 order by b.id limit 1;
  v_manor := coalesce(v_manor, 1);
  if exists (select 1 from private.castle_levels(p_castle) b
      where b.id is distinct from v_manor_id
        and b.level > case when b.kind in (21, 23) then 1 else v_manor end) then
    return 'building_over_manor';
  end if;
  if v_manor >= 6 and not (jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
      and (p_castle -> 'research' -> 'done') @> '["O1", "G1", "A7"]'::jsonb) then
    return 'age_locked';
  end if;
  return null;
end;
$$;

revoke all on function private.tech_tree() from public, anon, authenticated;
revoke all on function private.build_cost(bigint, bigint) from public, anon, authenticated;
revoke all on function private.build_time_ms(bigint, bigint) from public, anon, authenticated;
revoke all on function private.locked_new_building(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.build_need_ms(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.build_paid(jsonb) from public, anon, authenticated;
revoke all on function private.mill_food_percent(integer) from public, anon, authenticated;
revoke all on function private.food_production(jsonb) from public, anon, authenticated;
revoke all on function private.production_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.castle_buildings_problem(jsonb) from public, anon, authenticated;
grant execute on function private.castle_buildings_problem(jsonb) to service_role;
grant execute on function private.food_production(jsonb) to service_role;
-- food_production woła ją jako service_role (np. begin_attack), więc service_role musi mieć EXECUTE
grant execute on function private.mill_food_percent(integer) to service_role;
grant execute on function private.tech_tree() to service_role;
