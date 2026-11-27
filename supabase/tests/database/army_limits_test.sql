-- Testy limitu armii i utrzymania przy starcie ataku (#249), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `begin_attack` odrzuca armię ponad limit miejsc (Dwór i Koszary) i ponad produkcję żywności
-- (Rybacy, premia G2), liczonych z kopii zamku na serwerze, a odrzucony start niczego nie zapisuje.
-- Klient nie woła funkcji pomocniczych.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(24);

-- S = a1 (20 toporników, bez budynków), K = a2 (20 jeźdźców, Dwór 2), R = a3 (20 jeźdźców, Dwór 2
-- i Rybak 1), T = a4 (50 taranów i 10 toporników, Dwór 6: epoka II, bo taran wymaga A6, #281). Ranking w paśmie 80 000 (bez
-- prawdziwych graczy), bo testy biegną też na projekcie w chmurze, w transakcji, która się cofa.
create temp table limit_ids (id uuid primary key) on commit drop;
insert into limit_ids values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000a2'),
  ('00000000-0000-0000-0000-0000000000a3'), ('00000000-0000-0000-0000-0000000000a4');
insert into auth.users (id) select id from limit_ids;
update public.players set rating = 80000, age = 0 where id in (select id from limit_ids);
-- T w epoce gracza 3: do ataku idzie 6 oddziałów, więc 60 jednostek przekracza limit Dworu 6 (50)
update public.players set age = 3 where id = '00000000-0000-0000-0000-0000000000a4';

-- budynki [id, rodzaj, poziom, x, y, szer., wys.]: Dwór = 5, Rybak = 16, Koszary = 18;
-- oddziały [id, rodzaj, liczba]: topornik 0 (je 1), jeździec 6 (je 2), taran 11 (nie je)
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000000a1', 21, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Szczupły'),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb))),
  ('00000000-0000-0000-0000-0000000000a2', 22, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Głodny'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 2, 30, 30, 4, 4]]'::jsonb),
    'research', jsonb_build_object('done', '["G18", "G19", "A2", "A43", "A7"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 6, 10], [2, 6, 10]]'::jsonb))),
  ('00000000-0000-0000-0000-0000000000a3', 23, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Syty'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 2, 30, 30, 4, 4], [2, 16, 1, 40, 30, 2, 2]]'::jsonb),
    'research', jsonb_build_object('done', '["G18", "G19", "A2", "A43", "A7"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 6, 10], [2, 6, 10]]'::jsonb))),
  ('00000000-0000-0000-0000-0000000000a4', 24, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Oblężniczy'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 6, 30, 30, 4, 4]]'::jsonb),
    'research', jsonb_build_object('done', '["O1", "G1", "G18", "G19", "A2", "A43", "A7", "A1", "A6"]'::jsonb),
    'recruitment', jsonb_build_object('squads',
      '[[1, 11, 10], [2, 11, 10], [3, 11, 10], [4, 11, 10], [5, 11, 10], [6, 0, 10]]'::jsonb)));

-- ---- klient nie woła funkcji pomocniczych ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);
select throws_ok($$select private.army_limit('{}'::jsonb)$$, '42501', null, 'gracz nie woła army_limit');
select throws_ok($$select private.food_production('{}'::jsonb)$$, '42501', null, 'gracz nie woła food_production');
reset role;

set local role service_role;

-- ---- limit miejsc (Recruitment.army_limit) ----
select is(private.army_limit('{}'::jsonb), 10, 'bez Dworu w zapisie: poziom 1, 10 miejsc');
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 3, 0, 0, 4, 4], [2, 18, 2, 0, 0, 3, 3], [3, 18, 3, 0, 0, 3, 3]]}}'),
  40, 'Dwór 3 i Koszary 2 + 3: 30 + 10');
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 0, 0, 0, 4, 4]]}}'), 10, 'Dwór na poziomie 0 liczy się jak 1');
select is(private.army_limit('{"grid": {"buildings": [[1, 5, 9, 0, 0, 4, 4], [2, 18, 99, 0, 0, 3, 3]]}}'),
  102, 'Dwór 9: 50 + 4 × 8, Koszary przycięte do 10 (#262)');
select is(private.army_limit('{"grid": {"buildings": [[1, 18, 5, 0, 0, 3, 3], [1, 18, 5, 0, 0, 3, 3], [0, 18, 5, 0, 0, 3, 3], [-4, 18, 5, 0, 0, 3, 3]]}}'),
  20, 'powtórzone id i id <= 0 się nie liczą');
select is(private.army_limit('{"grid": {"buildings": [[2, 5, 5, 0, 0, 4, 4], [1, 5, 1, 0, 0, 4, 4]]}}'),
  10, 'liczy się Dwór o najniższym id');
select is(private.army_limit('{"grid": {"buildings": [[1, 18, 5], "zły", [2, 18, 2.5, 0, 0, 3, 3]]}}'),
  10, 'krótkie i złe wpisy się nie liczą');
select is(private.army_limit('{"grid": {"buildings": "nie lista"}}'), 10, 'zły typ listy budynków');

-- ---- produkcja żywności (Recruitment.upkeep_limit) ----
select is(private.food_production('{}'::jsonb), 20, 'sam gród: 20 Ży/h');
select is(private.food_production('{"grid": {"buildings": [[1, 16, 1, 0, 0, 2, 2], [2, 16, 3, 0, 0, 2, 2], [3, 16, 0, 0, 0, 2, 2]]}}'),
  140, 'Rybacy 1 i 3: 20 + 40 + 80, plac budowy nic nie daje');
select is(private.food_production('{"grid": {"buildings": [[1, 16, 1, 0, 0, 2, 2], [2, 16, 3, 0, 0, 2, 2]]}, "research": {"done": ["G1", "G2"]}}'),
  161, 'G2: +15 procent, w dół');
select is(private.food_production('{"grid": {"buildings": [[1, 16, 7, 0, 0, 2, 2]]}}'), 220, 'Rybak 7 (epoka II, #262): 20 + 200');
select is(private.food_production('{"research": {"done": "G2"}}'), 20, 'zły typ listy badań');

-- ---- utrzymanie jednostek (UnitTypes.UPKEEP) ----
select is(array[private.unit_upkeep(0), private.unit_upkeep(6), private.unit_upkeep(11), private.unit_upkeep(15)],
  array[1, 2, 0, 2], 'piechota 1, konnica 2, taran 0, Wóz 2');

-- ---- start ataku: limit miejsc ----
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a1', null, 0::smallint, '[[0, 10], [0, 10]]', 1)$$,
  'P0001', 'army_over_limit', '20 toporników przy 10 miejscach odrzucone');
select is((select count(*)::int from public.attacks where attacker_id = '00000000-0000-0000-0000-0000000000a1'),
  0, 'odrzucony start niczego nie zapisuje');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a1', null, 0::smallint, '[[0, 10]]', 1)$$,
  '10 toporników mieści się w limicie');

-- ---- start ataku: utrzymanie ----
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a2', null, 0::smallint, '[[6, 10], [6, 10]]', 1)$$,
  'P0001', 'army_over_upkeep', '20 jeźdźców je 40 przy produkcji 20');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a2', null, 0::smallint, '[[6, 10]]', 1)$$,
  '10 jeźdźców je 20 i się mieści');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a3', null, 0::smallint, '[[6, 10], [6, 10]]', 1)$$,
  'z Rybakiem (60 Ży/h) 20 jeźdźców przechodzi');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a4', null, 0::smallint, '[[11, 10], [11, 10], [11, 10], [11, 10], [11, 10], [0, 10]]', 1)$$,
  'P0001', 'army_over_limit', 'taran nie je, ale zajmuje miejsce');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000a4', null, 0::smallint, '[[11, 10], [11, 10], [11, 10], [11, 10], [11, 10]]', 1)$$,
  '50 taranów: 50 miejsc i 0 Ży/h');

reset role;
select * from finish();
rollback;
