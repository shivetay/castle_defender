-- #262: balans epoki II (ADR 0009). Serwer powtarza liczby gry dla poziomów 6–10 (epoka II).
--
-- Do tej pory epoka II miała mnożnik kosztu i czasu względem epoki I (AGE_COST_PERCENT = [100, 200],
-- AGE_TIME_MULT = [1, 2]), a premie budynków na poziomach 6–10 zostawały jak na poziomie 5:
-- `private.castle_buildings` obcinał poziom do 5. Teraz (decyzja właścicielki, #262):
-- - koszt i czas budowy to jedna ciągła krzywa przez 10 poziomów narastająco (BuildConfig):
--   COST_PERCENT = [100, 150, 250, 400, 600, 850, 1150, 1500, 1950, 2500] procent kosztu poziomu 1
--   (dzielenie całkowite), TIME_MULT = [1, 3, 10, 30, 90, 130, 180, 240, 320, 420] razy czas poziomu 1;
-- - umocnienia FORT_KINDS = [0, 1, 26, 2] (wał, palisada, fosa, brama) na poziomach epoki II budują się
--   w FORT_AGE_II_TIME_PERCENT = 50 procent czasu z krzywej;
-- - Dwór: MANOR_COST = [[0, 0, 0, 0], [300, 200, 200, 0], [500, 350, 350, 0], [750, 550, 550, 0], [1000, 800, 800, 0], [1000, 1000, 1000, 0], [1300, 1100, 1100, 0], [1700, 1400, 1400, 0], [2200, 1800, 1800, 0], [2800, 2300, 2300, 0]]
--   i MANOR_TIME_S = [0, 600, 3600, 14400, 43200, 50400, 64800, 86400, 108000, 144000];
-- - premie liczą się z poziomu do MAX_TOTAL_LEVEL = 10 (Ages.bonus_level): `private.castle_buildings`
--   przycina poziom do 0..10, a tablice per poziom mają 10 wartości:
--   PRODUCTION = {"4": [0, [60, 90, 120, 160, 200, 240, 280, 330, 380, 440]], "16": [2, [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]], "28": [2, [60, 90, 120, 160, 200, 240, 280, 330, 380, 440]], "30": [1, [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]]},
--   limit utrzymania z żywności FOOD_BASE = 20 plus FISHER_FOOD = [40, 60, 80, 110, 140, 170, 200, 230, 270, 310]
--   i FARM_FOOD = [60, 90, 120, 160, 200, 240, 280, 330, 380, 440],
--   wytwórcy LEVEL_PERCENT = [100, 150, 200, 275, 350, 425, 500, 575, 650, 750] (także żywność Chaty myśliwego,
--   zużycie wejść i górna granica produkcji towarów), Magazyn WAREHOUSE_CAPACITY = [500, 750, 1000, 1500, 2000, 2500, 3000, 3500, 4500, 6000],
--   siła umocnień z wytrzymałości LEVEL_HP_PERCENT = [100, 150, 220, 320, 450, 560, 680, 810, 950, 1100]:
--   FORT_POWER = [3, 4, 6, 9, 13, 16, 20, 24, 28, 33, 2, 3, 4, 6, 9, 11, 13, 16, 19, 22, 4, 6, 8, 12, 18, 22, 27, 32, 38, 44, 23, 25, 29, 34, 40, 46, 52, 58, 65, 73]
--   (RAMPART = 0, PALISADE = 1, GATE = 2, TOWER = 3, po 10 poziomów każdy);
-- - limit armii (Recruitment.army_limit): Dwór ARMY_PER_MANOR_LEVEL = 10 za poziomy 1–5
--   i ARMY_PER_MANOR_LEVEL_AGE_II = 8 za poziomy 6–10 (najwyżej 90), Koszary ARMY_PER_BARRACKS_LEVEL = 2
--   za każdy poziom 1–10.
-- Garnizonu Dworu ani limitu pułapek serwer nie liczy (jak dotąd), a strefa obrony (ADR 0007) się nie zmienia.
-- Badania, rok na pasku i szkolenie (TRAINING_SPEED_PERCENT, `private.train_ms`) bez zmian.
--
-- Zgodność ze starszym klientem: wyższe premie (produkcja, magazyn, limit armii) są dla niego hojniejsze, ale
-- koszty i czasy epoki II rosną (np. przebudowa Dworu 12 h → 14 h, Dwór II.2 600/400/400 → 1300/1100/1100),
-- więc zapis starszego klienta z budową epoki II może dostać economy_too_fast albo build_too_fast. Migrację
-- wgrywa się razem z wydaniem klienta z #262 i podniesieniem `min_code` (docs/PO-WYDANIU.md).
--
-- Każda funkcja to najnowsza wersja z wcześniejszych migracji (perki władcy, doktryny z poziomami) z nowymi
-- tablicami. `create or replace` zostawia uprawnienia; mimo to powtarzamy je jawnie (tylko service_role).
-- Liczby pilnują testy gry (`tests/test_economy_growth.gd`, `tests/test_army_research_goods_sanity.gd`,
-- `tests/test_resource_sanity.gd`, `tests/test_building_sanity.gd`, `tests/test_attack_limits.gd`, `tests/test_strength.gd`)
-- po znacznikach w komentarzach, a pgTAP `supabase/tests/database/age_two_balance_test.sql`.

-- Budynki z zapisu zamku jak po BuildGrid.load_data: pierwszy wpis danego id, poziom 0..10.
create or replace function private.castle_buildings(p_castle jsonb)
returns table (id bigint, kind bigint, level integer)
language sql
immutable
set search_path = ''
as $$
  select distinct on (b.id) b.id, b.kind, least(greatest(b.lvl, 0), 10)::integer
  from (
    select private.json_int(x.e -> 0, 1, 2147483647) as id,
      private.json_int(x.e -> 1, 0, 2147483647) as kind,
      private.json_int(x.e -> 2, -2147483648, 2147483647) as lvl,
      x.ord
    from jsonb_array_elements(
        case when jsonb_typeof(p_castle -> 'grid' -> 'buildings') = 'array'
          then p_castle -> 'grid' -> 'buildings' else '[]'::jsonb end)
      with ordinality as x(e, ord)
    -- case, bo `and` w where nie gwarantuje kolejności, a jsonb_array_length na skalarze rzuca błąd
    where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end
  ) b
  where b.id is not null and b.kind is not null and b.lvl is not null
  order by b.id, b.ord
$$;

-- Limit miejsc w armii (Recruitment.army_limit): Dwór o najniższym id co najmniej poziom 1 (10 za poziomy
-- 1–5, 8 za poziomy 6–10), plus poziomy wszystkich Koszar razy 2.
create or replace function private.army_limit(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce((select 10 * least(greatest(b.level, 1), 5) + 8 * greatest(b.level - 5, 0)
      from private.castle_buildings(p_castle) b where b.kind = 5 order by b.id limit 1), 10)
    + 2 * coalesce((select sum(b.level) from private.castle_buildings(p_castle) b where b.kind = 18), 0)::integer
$$;

-- Limit utrzymania jak w `*_ruler_perk_research.sql`, ze stawkami Rybaka i Pola do poziomu 10.
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
        + case when private.castle_ruler_perk(p_castle) in (3, 4) then 10 else 0 end)
      / 100)::integer
$$;

-- Górna granica produkcji jak w `*_ruler_perk_research.sql`, ze stawkami do poziomu 10.
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
          then 10 else 0 end as percent
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

-- Górna granica zużycia jak w `*_economy_growth.sql`, z tempem wytwórców do poziomu 10.
create or replace function private.consumption_max(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with b as (select * from private.buildings_max(p_old, p_new)),
  rec as (
    select (e ->> 0)::bigint as kind, (e ->> 1)::integer as min_level, (e ->> 2)::bigint as cph, e -> 3 as ins
    from jsonb_array_elements('[[9, 1, 3, {"0": 3, "1": 1}], [9, 1, 3, {"0": 2, "1": 1}], [9, 1, 2, {"0": 2, "1": 2}], [9, 1, 2, {"0": 5, "1": 1}], [11, 1, 2, {"0": 3}], [11, 3, 1, {"0": 4}], [12, 1, 3, {"0": 1}], [8, 1, 2, {"0": 1}], [8, 1, 2, {"0": 2}], [13, 1, 2, {"0": 1}], [14, 1, 3, {"0": 4}], [17, 1, 1, {"2": 10}]]'::jsonb) e
  )
  select array(
    select coalesce((select sum(rec.cph * (array[100, 150, 200, 275, 350, 425, 500, 575, 650, 750])[b.level] / 100 * (rec.ins ->> r::text)::bigint)
        from rec join b on b.kind = rec.kind and b.level >= rec.min_level
        where rec.ins ? r::text), 0)
      + case when r = 2 then greatest(private.upkeep_all(p_old), private.upkeep_all(p_new)) else 0 end
    from generate_series(0, 3) r order by r)::bigint[]
$$;

-- Pojemność drewna, kamienia i żywności z zapisu zamku (Economy.capacities_for), Magazyn do poziomu 10.
create or replace function private.castle_capacity(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (1000 + coalesce((select sum((array[500, 750, 1000, 1500, 2000, 2500, 3000, 3500, 4500, 6000])[b.level])
      from private.castle_buildings(p_castle) b where b.kind = 25 and b.level >= 1), 0))::integer
$$;

-- Koszt poziomu `p_level` (narastająco, 1..10) budynku `p_kind` (BuildConfig.cost), w kolejności EconomyConfig.Res:
--   BUILD_COST = {"0": [10, 0, 10, 0], "1": [20, 0, 5, 0], "2": [60, 20, 20, 0], "3": [120, 40, 40, 0], "4": [80, 0, 30, 0], "6": [60, 0, 20, 0], "7": [80, 20, 20, 0], "8": [100, 20, 30, 0], "9": [80, 20, 20, 0], "10": [60, 0, 20, 0], "11": [100, 0, 30, 0], "12": [80, 10, 20, 0], "13": [90, 0, 30, 0], "14": [60, 40, 10, 0], "15": [30, 0, 20, 0], "16": [70, 0, 10, 0], "17": [100, 20, 40, 0], "18": [100, 20, 40, 0], "19": [140, 30, 40, 0], "20": [120, 10, 40, 0], "21": [150, 60, 40, 0], "22": [120, 20, 40, 10], "24": [100, 40, 30, 0], "25": [100, 40, 0, 0], "26": [5, 0, 15, 0], "27": [60, 40, 40, 0], "28": [60, 0, 20, 0], "29": [40, 30, 10, 0], "30": [100, 0, 30, 0], "31": [100, 20, 30, 0]}
-- razy procent poziomu z krzywej, a Dwór z tabeli.
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
  v_base := '{"0": [10, 0, 10, 0], "1": [20, 0, 5, 0], "2": [60, 20, 20, 0], "3": [120, 40, 40, 0], "4": [80, 0, 30, 0], "6": [60, 0, 20, 0], "7": [80, 20, 20, 0], "8": [100, 20, 30, 0], "9": [80, 20, 20, 0], "10": [60, 0, 20, 0], "11": [100, 0, 30, 0], "12": [80, 10, 20, 0], "13": [90, 0, 30, 0], "14": [60, 40, 10, 0], "15": [30, 0, 20, 0], "16": [70, 0, 10, 0], "17": [100, 20, 40, 0], "18": [100, 20, 40, 0], "19": [140, 30, 40, 0], "20": [120, 10, 40, 0], "21": [150, 60, 40, 0], "22": [120, 20, 40, 10], "24": [100, 40, 30, 0], "25": [100, 40, 0, 0], "26": [5, 0, 15, 0], "27": [60, 40, 40, 0], "28": [60, 0, 20, 0], "29": [40, 30, 10, 0], "30": [100, 0, 30, 0], "31": [100, 20, 30, 0]}'::jsonb
    -> p_kind::text;
  if v_base is null then
    return array[0, 0, 0, 0]::bigint[];
  end if;
  v_percent := (array[100, 150, 250, 400, 600, 850, 1150, 1500, 1950, 2500])[v_lv];
  return array(select (v_base ->> i)::bigint * v_percent / 100 from generate_series(0, 3) i order by i);
end;
$$;

-- Czas budowy poziomu `p_level` (narastająco) w ms jak BuildConfig.time_ms; umocnienia w epoce II o połowę krócej.
create or replace function private.build_time_ms(p_kind bigint, p_level bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_level < 1 or p_level > 10 then 0::bigint
    when p_kind = 5 then (array[0, 600, 3600, 14400, 43200, 50400, 64800, 86400, 108000, 144000])[p_level]::bigint * 1000
    else coalesce((array[5, 10, 30, 60, 45, 0, 40, 50, 60, 50, 40, 60, 50, 60, 45, 30, 40, 60, 60, 75, 70, 90, 70, 0, 60, 45, 5, 60, 40, 30, 50, 50])[p_kind + 1], 0)::bigint
      * (array[1, 3, 10, 30, 90, 130, 180, 240, 320, 420])[p_level]
      * case when p_kind in (0, 1, 26, 2) and p_level > 5 then 50 else 100 end / 100 * 1000
  end
$$;

-- Plan produkcji towarów jak w `*_army_research_goods_sanity.sql`, z tempem wytwórców do poziomu 10.
create or replace function private.goods_plan(p_old jsonb, p_new jsonb)
returns table (good integer, inc bigint, rate bigint, cap bigint)
language sql
immutable
set search_path = ''
as $$
  with b as (
    select x.id, x.kind, max(x.level) as lvl
    from (select * from private.castle_levels(p_old) union all select * from private.castle_levels(p_new)) x
    where x.level >= 1
    group by x.id, x.kind
  ), r as (
    select e.ord, (e.v ->> 0)::bigint as kind, (e.v ->> 1)::bigint as min_level, (e.v ->> 2)::bigint as cph, e.v -> 3 as outs
    from jsonb_array_elements(private.goods_recipes()) with ordinality as e(v, ord)
  ), p as (
    select r.ord, r.outs, sum(r.cph * (array[100, 150, 200, 275, 350, 425, 500, 575, 650, 750])[least(b.lvl, 10)] / 100) as per_hour
    from r join b on b.kind = r.kind and b.lvl >= r.min_level
    group by r.ord, r.outs
  ), g as (
    select o.key::integer as good, sum(p.per_hour * (o.value #>> '{}')::bigint) as rate,
      sum((o.value #>> '{}')::bigint) * 3600000 as cap
    from p cross join lateral jsonb_each(p.outs) o
    where p.per_hour > 0
    group by 1
  )
  select s.g, (private.goods_amounts(p_new))[s.g + 1] - (private.goods_amounts(p_old))[s.g + 1],
    coalesce(g.rate, 0)::bigint, coalesce(g.cap, 0)::bigint
  from generate_series(0, 21) s(g)
  left join g on g.good = s.g
  order by s.g
$$;

-- Siła obrony celu jak w `*_target_strength.sql`, z umocnieniami do poziomu 10.
create or replace function private.defense_strength(p_castle jsonb, p_layout jsonb)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  unit_power constant integer[] := array[11, 8, 7, 11, 5, 0, 15, 11, 16, 8, 25, 50, 5, 6, 4, 0];
  garrison_power constant integer[] := array[12, 9, 7, 13, 6, 0, 16, 12, 18, 9, 27, 56, 5, 7, 5, 0];
  trap_power constant integer[] := array[6, 4, 4, 4, 7];
  fort_power constant integer[] := array[3, 4, 6, 9, 13, 16, 20, 24, 28, 33, 2, 3, 4, 6, 9, 11, 13, 16, 19, 22, 4, 6, 8, 12, 18, 22, 27, 32, 38, 44, 23, 25, 29, 34, 40, 46, 52, 58, 65, 73];
  castle jsonb := case when jsonb_typeof(p_castle) = 'object' then p_castle else '{}'::jsonb end;
  layout jsonb;
  garrison bigint[];
  total bigint := 0;
begin
  -- układ obrony z defense_layouts, a bez wiersza obrona z zapisu zamku (jak w grze)
  layout := case
    when jsonb_typeof(p_layout) = 'object' then p_layout
    when jsonb_typeof(castle -> 'defense') = 'object' then castle -> 'defense'
    else '{}'::jsonb end;

  -- garnizon: ostatni poprawny rozkaz oddziału [id, zadanie, x, y, …] decyduje (DefensePlan.from_dict)
  select coalesce(array_agg(o.id), '{}') into garrison
  from (
    select distinct on (private.json_trunc_int(e.v -> 0)) private.json_trunc_int(e.v -> 0) as id, private.json_trunc_int(e.v -> 1) as task
    from jsonb_array_elements(case when jsonb_typeof(layout -> 'orders') = 'array'
      then layout -> 'orders' else '[]'::jsonb end) with ordinality as e(v, ord)
    where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 4 else false end
      and private.json_trunc_int(e.v -> 0) > 0
      and private.json_trunc_int(e.v -> 1) between 0 and 6
    order by private.json_trunc_int(e.v -> 0), e.ord desc
  ) o
  where o.task = 6;

  -- załoga: oddziały [id, rodzaj, liczba], pierwszy wpis danego id, liczba 0..SQUAD_SIZE (Recruitment.load_data)
  total := total + coalesce((
    select sum(least(greatest(s.n, 0), 10)
      * case when s.id = any (garrison) then garrison_power[s.unit + 1] else unit_power[s.unit + 1] end)
    from (
      select distinct on (private.json_trunc_int(e.v -> 0)) private.json_trunc_int(e.v -> 0) as id,
        private.json_trunc_int(e.v -> 1) as unit, private.json_trunc_int(e.v -> 2) as n
      from jsonb_array_elements(case when jsonb_typeof(castle -> 'recruitment' -> 'squads') = 'array'
        then castle -> 'recruitment' -> 'squads' else '[]'::jsonb end) with ordinality as e(v, ord)
      where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 3 else false end
        and private.json_trunc_int(e.v -> 0) > 0
        and private.json_trunc_int(e.v -> 1) between 0 and 15
        and private.json_trunc_int(e.v -> 2) is not null
      order by private.json_trunc_int(e.v -> 0), e.ord
    ) s
  ), 0);

  -- pułapki [rodzaj, x, y, …]: pierwsza na danej kratce (DefensePlan.from_dict)
  total := total + coalesce((
    select sum(trap_power[t.kind + 1])
    from (
      select distinct on (private.json_trunc_int(e.v -> 1), private.json_trunc_int(e.v -> 2)) private.json_trunc_int(e.v -> 0) as kind
      from jsonb_array_elements(case when jsonb_typeof(layout -> 'traps') = 'array'
        then layout -> 'traps' else '[]'::jsonb end) with ordinality as e(v, ord)
      where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 3 else false end
        and private.json_trunc_int(e.v -> 0) between 0 and 4
        and private.json_trunc_int(e.v -> 1) is not null
        and private.json_trunc_int(e.v -> 2) is not null
      order by private.json_trunc_int(e.v -> 1), private.json_trunc_int(e.v -> 2), e.ord
    ) t
  ), 0);

  -- umocnienia: budynki [id, rodzaj, poziom, x, y, szer., wys.], pierwszy wpis danego id; poziom
  -- powyżej 10 liczy się jak 10 (BattleConfig.building_hp), plac budowy (poziom 0) nie liczy się
  total := total + coalesce((
    select sum(fort_power[b.kind * 10 + least(b.lv, 10)])
    from (
      select distinct on (private.json_trunc_int(e.v -> 0)) private.json_trunc_int(e.v -> 1) as kind,
        private.json_trunc_int(e.v -> 2) as lv
      from jsonb_array_elements(case when jsonb_typeof(castle -> 'grid' -> 'buildings') = 'array'
        then castle -> 'grid' -> 'buildings' else '[]'::jsonb end) with ordinality as e(v, ord)
      where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 7 else false end
        and private.json_trunc_int(e.v -> 0) is not null
      order by private.json_trunc_int(e.v -> 0), e.ord
    ) b
    where b.kind between 0 and 3 and b.lv >= 1
  ), 0);

  return least(total, 2147483647)::integer;
end;
$$;

revoke all on function private.castle_buildings(jsonb) from public, anon, authenticated;
revoke all on function private.army_limit(jsonb) from public, anon, authenticated;
revoke all on function private.food_production(jsonb) from public, anon, authenticated;
revoke all on function private.production_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.consumption_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.castle_capacity(jsonb) from public, anon, authenticated;
revoke all on function private.build_cost(bigint, bigint) from public, anon, authenticated;
revoke all on function private.build_time_ms(bigint, bigint) from public, anon, authenticated;
revoke all on function private.goods_plan(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.defense_strength(jsonb, jsonb) from public, anon, authenticated;
grant execute on function private.castle_buildings(jsonb) to service_role;
grant execute on function private.army_limit(jsonb) to service_role;
grant execute on function private.food_production(jsonb) to service_role;
grant execute on function private.castle_capacity(jsonb) to service_role;
grant execute on function private.defense_strength(jsonb, jsonb) to service_role;
