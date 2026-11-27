-- Testy Młyna (#388, ADR 0010, migracja `*_mill.sql`), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: Młyn (rodzaj 32) kosztuje i buduje się od poziomu 6 z krzywej gry, wymaga G5, daje premię
-- 4/8/12/16/20% całej żywności (jeden Młyn, najwyższy poziom) w limicie utrzymania i górnej granicy
-- produkcji, a serwer nie liczy poziomów 1–5, których w grze nie ma. Te same liczby liczy `tests/test_mill.gd`.
-- Gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(20);

-- ---- drzewko i technologia ----
select is(private.tech_tree() -> 'G5', '[1, ["G2"]]'::jsonb, 'G5 Młyn wodny: epoka II, wymaga G2');
select ok(private.locked_new_building('{}', '{"grid": {"buildings": [[7, 32, 6, 0, 0, 2, 2]]}, "research": {"done": ["G2"]}}'),
  'nowy Młyn bez G5 odrzucony');
select ok(not private.locked_new_building('{}',
    '{"grid": {"buildings": [[7, 32, 6, 0, 0, 2, 2]]}, "research": {"done": ["G2", "G5"]}}'), 'z G5 przechodzi');

-- ---- koszt i czas od poziomu 6 ----
select is(private.build_cost(32, 6), '{1020, 510, 170, 0}'::bigint[], 'Młyn II.1: 850 procent kosztu poziomu 1');
select is(private.build_cost(32, 10), '{3000, 1500, 500, 0}'::bigint[], 'Młyn II.5: 2500 procent');
select is(private.build_time_ms(32, 6), 6500000::bigint, 'Młyn II.1: 50 s × 130');
select is((select count(*) from private.build_paid('{"grid": {"buildings": [[7, 32, 6, 0, 0, 2, 2]]}}') p where p.kind = 32),
  1::bigint, 'opłacony tylko poziom 6, bez poziomów 1–5');
select is((select min(p.level) from private.build_paid('{"grid": {"buildings": [[7, 32, 8, 0, 0, 2, 2]]}}') p),
  6::bigint, 'Młyn II.3: opłacone poziomy od 6');
select is(private.build_need_ms('{}', '{"grid": {"buildings": [[7, 32, 6, 0, 0, 2, 2]]}}'), 6500000::bigint,
  'nowy Młyn: czas samego poziomu 6');
select is(private.build_need_ms('{"grid": {"buildings": [[7, 32, 6, 0, 0, 2, 2]]}}',
    '{"grid": {"buildings": [[7, 32, 7, 0, 0, 2, 2]]}}'), 9000000::bigint, 'ulepszenie II.1 → II.2: 50 s × 180');
select is(private.build_need_ms('{}', '{"grid": {"buildings": [[7, 16, 1, 0, 0, 2, 2]]}}'), 40000::bigint,
  'Rybak dalej od poziomu 1');

-- ---- poziomy 1–5 Młyna nie istnieją ----
select is(private.castle_buildings_problem('{"grid": {"buildings": [[1, 5, 6, 0, 0, 4, 4], [7, 32, 3, 0, 0, 2, 2]]},
    "research": {"done": ["O1", "G1", "A7"]}}'), 'bad_building', 'Młyn na poziomie 3 odrzucony');
select is(private.castle_buildings_problem('{"grid": {"buildings": [[1, 5, 6, 0, 0, 4, 4], [7, 32, 6, 0, 0, 2, 2]]},
    "research": {"done": ["O1", "G1", "A7"]}}'), null::text, 'Młyn II.1 przy Dworze II.1 przechodzi');
select is(private.castle_buildings_problem('{"grid": {"buildings": [[1, 5, 6, 0, 0, 4, 4], [7, 32, 0, 0, 0, 2, 2]]},
    "research": {"done": ["O1", "G1", "A7"]}}'), null::text, 'plac budowy Młyna (poziom 0) przechodzi');

-- ---- premia do żywności ----
select is(private.food_production('{"grid": {"buildings": [[1, 16, 10, 0, 0, 2, 2], [7, 32, 6, 0, 0, 2, 2]]}}'), 343,
  'Rybak II.5 z Młynem II.1: 330 × 104 procent');
select is(private.food_production('{"grid": {"buildings": [[1, 16, 10, 0, 0, 2, 2], [7, 32, 10, 0, 0, 2, 2]]}}'), 396,
  'z Młynem II.5: 330 × 120 procent');
select is(private.food_production(
    '{"grid": {"buildings": [[1, 16, 10, 0, 0, 2, 2], [7, 32, 10, 0, 0, 2, 2], [8, 32, 10, 0, 0, 2, 2]]}}'), 396,
  'drugi Młyn się nie sumuje');
select is(private.production_max('{}', '{"grid": {"buildings": [[1, 16, 10, 0, 0, 2, 2], [7, 32, 10, 0, 0, 2, 2]]}}'),
  '{20, 20, 396, 0}'::bigint[], 'górna granica produkcji z premią Młyna tylko dla żywności');
select is(private.mill_food_percent(5), 0, 'poziom poniżej epoki II nic nie daje');

-- ---- uprawnienia ----
set local role authenticated;
select throws_ok($$select private.mill_food_percent(6)$$, '42501', null, 'gracz nie woła mill_food_percent');
reset role;

select * from finish();
rollback;
