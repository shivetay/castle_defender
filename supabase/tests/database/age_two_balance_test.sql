-- Testy balansu epoki II (#262, ADR 0009), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: serwer liczy poziomy 6–10 tymi samymi liczbami co gra (koszt i czas z ciągłej krzywej,
-- umocnienia w połowie czasu, Dwór z tabeli, produkcja, Magazyn, tempo wytwórców, limit armii i siła
-- umocnień do poziomu 10; te same wartości liczą testy gry `tests/test_age_balance.gd`
-- i `tests/test_economy_growth.gd`), epoka I się nie zmienia, a gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(31);

-- ---- koszt budowy (BuildConfig.cost) ----
select is(private.build_cost(3, 5), '{720, 240, 240, 0}'::bigint[], 'Wieża 5 bez zmian: 600 procent');
select is(private.build_cost(3, 6), '{1020, 340, 340, 0}'::bigint[], 'Wieża II.1: 850 procent');
select is(private.build_cost(3, 10), '{3000, 1000, 1000, 0}'::bigint[], 'Wieża II.5: 2500 procent');
select is(private.build_cost(0, 10), '{250, 0, 250, 0}'::bigint[], 'wał II.5: koszt z krzywej');
select is(private.build_cost(5, 6), '{1000, 1000, 1000, 0}'::bigint[], 'przebudowa Dworu na epokę II');
select is(private.build_cost(5, 7), '{1300, 1100, 1100, 0}'::bigint[], 'Dwór II.2');
select is(private.build_cost(5, 10), '{2800, 2300, 2300, 0}'::bigint[], 'Dwór II.5');
select is(private.build_cost(3, 99), '{3000, 1000, 1000, 0}'::bigint[], 'poziom ponad 10 jak 10');

-- ---- czas budowy (BuildConfig.time_ms) ----
select is(private.build_time_ms(3, 5), 5400000::bigint, 'Wieża 5 bez zmian: 90 min');
select is(private.build_time_ms(3, 10), 25200000::bigint, 'Wieża II.5: ×420, 7 h');
select is(private.build_time_ms(0, 5), 450000::bigint, 'wał 5 w epoce I: pełny czas');
select is(private.build_time_ms(0, 6), 325000::bigint, 'wał II.1: połowa krzywej');
select is(private.build_time_ms(2, 7), 2700000::bigint, 'brama II.2: połowa krzywej');
select is(private.build_time_ms(26, 8), 600000::bigint, 'fosa II.3: połowa krzywej');
select is(private.build_time_ms(5, 6), 50400000::bigint, 'przebudowa Dworu: 14 h');
select is(private.build_time_ms(5, 10), 144000000::bigint, 'Dwór II.5: 40 h');

-- ---- premie poziomów 6–10 ----
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 6, 0, 0, 4, 4]]}}'), 58, 'Dwór II.1: 50 + 8');
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 10, 0, 0, 4, 4]]}}'), 90, 'Dwór II.5: 50 + 40');
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 10, 0, 0, 4, 4], [2, 18, 10, 0, 0, 3, 3]]}}'), 110,
  'Koszary II.5: 2 za każdy z 10 poziomów');
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 50, 0, 0, 4, 4]]}}'), 90, 'poziom Dworu przycięty do 10');
select is(private.food_production('{"grid": {"buildings": [[1, 16, 10, 0, 0, 2, 2], [2, 28, 10, 0, 0, 2, 2]]}}'), 770,
  'Rybak i Pole II.5: 20 + 310 + 440');
select is(private.castle_capacity('{"grid": {"buildings": [[1, 25, 6, 0, 0, 2, 2]]}}'), 3500, 'Magazyn II.1: 1000 + 2500');
select is(private.castle_capacity('{"grid": {"buildings": [[1, 25, 10, 0, 0, 2, 2]]}}'), 7000, 'Magazyn II.5: 1000 + 6000');
select is(private.production_max('{}',
    '{"grid": {"buildings": [[1, 5, 10, 30, 30, 4, 4], [3, 4, 10, 10, 10, 2, 2], [4, 30, 10, 20, 10, 2, 2], [5, 6, 10, 10, 20, 2, 2]]}}'),
  '{460, 330, 110, 0}'::bigint[], 'produkcja II.5: Chata drwala 440, Kamieniołom 310, Chata myśliwego 2 × 45');
select is(private.consumption_max('{}', '{"grid": {"buildings": [[1, 5, 10, 30, 30, 4, 4], [6, 17, 10, 10, 20, 3, 3]]}}'),
  '{0, 0, 70, 0}'::bigint[], 'zużycie Stajni II.5: 7 cykli × 10 żywności');
select is((select g.rate from private.goods_plan('{}', '{"grid": {"buildings": [[1, 5, 10, 30, 30, 4, 4], [5, 6, 10, 10, 20, 2, 2]]}}') g
    where g.good = 0), 90::bigint, 'towary II.5: Chata myśliwego 45 cykli × 2 surowe skóry');
select is(private.defense_strength('{"grid": {"buildings": [[4, 3, 10, 31, 28, 2, 2], [5, 1, 12, 30, 30, 1, 1]]}}', null), 95,
  'siła umocnień: Wieża II.5 (73) i palisada przycięta do 10 (22)');

-- ---- gracz nie woła funkcji serwera ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000262a1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select private.build_cost(3, 6)$$, '42501', null, 'gracz nie wywoła build_cost');
select throws_ok($$select private.army_limit('{}')$$, '42501', null, 'gracz nie wywoła army_limit');
select throws_ok($$select private.castle_capacity('{}')$$, '42501', null, 'gracz nie wywoła castle_capacity');
reset role;
set local role anon;
select throws_ok($$select private.build_time_ms(3, 6)$$, '42501', null, 'anon nie wywoła build_time_ms');
reset role;

select * from finish();
rollback;
