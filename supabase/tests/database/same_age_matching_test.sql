-- Testy doboru PvP w tej samej epoce (#383, ADR 0010), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `match_targets` nie zwraca gracza z innej epoki, `begin_attack` odrzuca gracza-cel z innej epoki
-- w obie strony (epoka +1 i −1), atak w tej samej epoce startuje, a atak na zamek-bota nie sprawdza epoki.
-- Zwiad (`begin_scout`) sprawdza `scouting_test.sql`.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(10);

-- Ranking w paśmie 75 000 (bez prawdziwych graczy), bo testy biegną też na projekcie w chmurze,
-- w transakcji, która się cofa.
-- A = 38a1 (epoka I, atakuje), B = 38b1 (epoka II, atakuje), P = 38c1 (epoka I, cel), Q = 38d1 (epoka II, cel)
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000038a1'), ('00000000-0000-0000-0000-0000000038b1'),
  ('00000000-0000-0000-0000-0000000038c1'), ('00000000-0000-0000-0000-0000000038d1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 75000, age = 0 where id in (select id from test_ids);

-- zamek jak w attack_flow_test.sql: Dwór 3, Koszary, Rybak, Magazyny i 4 oddziały po 10 (w limitach #249, #274)
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 3838, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 4, 4], [2, 18, 3, 36, 30, 3, 3], [3, 16, 1, 40, 30, 2, 2],
    [4, 25, 3, 10, 10, 2, 2], [5, 25, 3, 13, 10, 2, 2], [6, 25, 3, 16, 10, 2, 2], [7, 25, 3, 19, 10, 2, 2],
    [8, 25, 3, 22, 10, 2, 2], [9, 18, 2, 50, 50, 3, 3], [10, 25, 3, 10, 13, 2, 2], [11, 25, 3, 13, 13, 2, 2],
    [12, 25, 3, 16, 13, 2, 2], [13, 25, 3, 19, 13, 2, 2], [14, 25, 3, 22, 13, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(10000, 4000, 2000, 100)),
  'research', jsonb_build_object('done', '["G18", "G19", "A2", "A43", "A7"]'::jsonb),
  'recruitment', jsonb_build_object('squads',
    '[[1, 0, 10], [2, 0, 10], [3, 0, 10], [4, 6, 10]]'::jsonb))
from test_ids t;
-- epoka gracza tylko rośnie z zapisem zamku (sync_player_age), więc epokę II ustawiamy wprost
update public.players set age = 1
where id in ('00000000-0000-0000-0000-0000000038b1', '00000000-0000-0000-0000-0000000038d1');

set local role service_role;

-- ---- dobór: tylko ta sama epoka ----
select results_eq(
  $$select player_id from public.match_targets('00000000-0000-0000-0000-0000000038a1')
    where player_id::text like '00000000-0000-0000-0000-0000000038%' order by player_id$$,
  $$values ('00000000-0000-0000-0000-0000000038c1'::uuid)$$,
  'epoka I dostaje tylko cel z epoki I');
select results_eq(
  $$select player_id from public.match_targets('00000000-0000-0000-0000-0000000038b1')
    where player_id::text like '00000000-0000-0000-0000-0000000038%' order by player_id$$,
  $$values ('00000000-0000-0000-0000-0000000038d1'::uuid)$$,
  'epoka II dostaje tylko cel z epoki II');
select ok(
  (select coalesce(bool_and(age = 1), true) from public.match_targets('00000000-0000-0000-0000-0000000038b1')),
  'karty gracza epoki II mają tylko epokę II');

-- ---- start ataku: inna epoka odrzucona w obie strony ----
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000038a1',
    '00000000-0000-0000-0000-0000000038d1', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_out_of_range', 'epoka I nie zaatakuje epoki II');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000038b1',
    '00000000-0000-0000-0000-0000000038c1', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_out_of_range', 'epoka II nie zaatakuje epoki I');
select is(
  (select count(*)::int from public.attacks
   where attacker_id in ('00000000-0000-0000-0000-0000000038a1', '00000000-0000-0000-0000-0000000038b1')),
  0, 'odrzucony start nie zapisuje ataku');

-- ---- ta sama epoka i zamek-bot ----
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000038a1',
    '00000000-0000-0000-0000-0000000038c1', null, '[[0, 10]]', 1)$$,
  'epoka I atakuje epokę I');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000038b1',
    '00000000-0000-0000-0000-0000000038d1', null, '[[0, 10]]', 1)$$,
  'epoka II atakuje epokę II');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000038b1', null, 0::smallint, '[[0, 10]]', 1)$$,
  'zamek-bot z epoki I jako zapas dla epoki II (atak na bota nie sprawdza epoki)');

-- ---- uprawnienia bez zmian: tylko serwer ----
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000038a1", "role": "authenticated"}', true);
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000038a1',
    '00000000-0000-0000-0000-0000000038c1', null, '[[0, 10]]', 1)$$,
  '42501', null, 'gracz nie wywoła begin_attack');

select * from finish();
rollback;
