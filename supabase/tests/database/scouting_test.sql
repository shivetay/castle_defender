-- Testy zwiadu na gracza i ukrycia obrony w planie (#28), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: klient nie woła funkcji zwiadu ani nie czyta misji; begin_scout wymaga Chaty tropicieli,
-- S1 i zwiadowców z zamku na serwerze i naraz jednej misji; wynik i odsłonięte dane widać dopiero po
-- końcu misji; odsłonięte jest tylko to, co leży w obszarze; plan ataku dostaje zarys, donżon
-- i odsłonięte, a pełną obronę dopiero launch_attack; wyniku bez launch_attack serwer nie przyjmie.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(49);

-- A = 5c01 (zwiadowca: Chata tropicieli 22, S1, 3 Tropicieli 5 i 4 Zwiadowców 14), B = 5c02 (cel),
-- C = 5c03 (bez Chaty), D = 5c04 (Chata bez S1), E = 5c05 (Chata i S1 bez zwiadowców),
-- F = 5c06 (cel z Wieżą sygnałową 31), G = 5c07 (epoka 3, poza zasięgiem), H = 5c08 (obcy gracz).
-- Ranking w paśmie 90 000, bo testy biegną też na projekcie w chmurze w transakcji, która się cofa.
create temp table scout_ids (id uuid primary key) on commit drop;
insert into scout_ids values
  ('00000000-0000-0000-0000-000000005c01'), ('00000000-0000-0000-0000-000000005c02'),
  ('00000000-0000-0000-0000-000000005c03'), ('00000000-0000-0000-0000-000000005c04'),
  ('00000000-0000-0000-0000-000000005c05'), ('00000000-0000-0000-0000-000000005c06'),
  ('00000000-0000-0000-0000-000000005c07'), ('00000000-0000-0000-0000-000000005c08');
insert into auth.users (id) select id from scout_ids;
update public.players set rating = 90000, age = 0 where id in (select id from scout_ids);
update public.players set age = 3 where id = '00000000-0000-0000-0000-000000005c07';

-- budynki [id, rodzaj, poziom, x, y, szer., wys.]; oddziały [id, rodzaj, liczba]
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-000000005c01', 31, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Zwiad'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 1, 30, 30, 2, 2], [2, 22, 1, 34, 30, 2, 2]]'::jsonb),
    'research', jsonb_build_object('done', '["S1"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 5, 3], [2, 14, 4], [3, 0, 10]]'::jsonb))),
  -- cel: donżon 21 na 10..11, chata 4 na 20..21, mur 1 na 15,15; zwiad stanu `scout` obrońcy
  ('00000000-0000-0000-0000-000000005c02', 32, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Cel'),
    'grid', jsonb_build_object('buildings', '[[1, 21, 1, 10, 10, 2, 2], [2, 4, 3, 20, 20, 2, 2], [3, 1, 1, 15, 15, 1, 1]]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 2, 5], [2, 0, 5]]'::jsonb),
    'economy', jsonb_build_object('amounts', '[100, 0, 0, 0]'::jsonb),
    'scout', jsonb_build_object('reports', '[{"key": "gracz:tajne"}]'::jsonb))),
  ('00000000-0000-0000-0000-000000005c03', 33, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Bez chaty'),
    'research', jsonb_build_object('done', '["S1"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 5, 3]]'::jsonb))),
  ('00000000-0000-0000-0000-000000005c04', 34, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Bez S1'),
    'grid', jsonb_build_object('buildings', '[[2, 22, 1, 34, 30, 2, 2]]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 5, 3]]'::jsonb))),
  ('00000000-0000-0000-0000-000000005c05', 35, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Bez zwiadu'),
    'grid', jsonb_build_object('buildings', '[[2, 22, 1, 34, 30, 2, 2]]'::jsonb),
    'research', jsonb_build_object('done', '["S1"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10]]'::jsonb))),
  ('00000000-0000-0000-0000-000000005c06', 36, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Czujny'),
    'grid', jsonb_build_object('buildings', '[[1, 21, 1, 10, 10, 2, 2], [2, 31, 1, 14, 10, 2, 2]]'::jsonb))),
  ('00000000-0000-0000-0000-000000005c07', 37, 10, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Daleki'),
    'grid', jsonb_build_object('buildings', '[[1, 21, 1, 10, 10, 2, 2]]'::jsonb)));
-- obrona B: oddział 1 (łucznicy, klasa 2) trzyma 11,11; oddział 2 patroluje 21,19 → 30,30; pułapki
insert into public.defense_layouts (player_id, save_version, data) values
  ('00000000-0000-0000-0000-000000005c02', 10, '{"orders": [[1, 0, 11, 11, []], [2, 1, 21, 19, [[30, 30]]]],
    "traps": [[0, 12, 12, 0], [1, 25, 25, 0]], "tower_priority": 0}');

-- ---- klient nie woła funkcji zwiadu i nie czyta misji ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-000000005c01", "role": "authenticated"}', true);
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c02', 0::smallint, 0)$$, '42501', null, 'gracz nie wywoła begin_scout');
select throws_ok($$select * from public.scout_reports('00000000-0000-0000-0000-000000005c01')$$,
  '42501', null, 'gracz nie wywoła scout_reports');
select throws_ok($$select * from public.attack_preview('00000000-0000-0000-0000-000000005c01', gen_random_uuid())$$,
  '42501', null, 'gracz nie wywoła attack_preview');
select throws_ok($$select * from public.launch_attack('00000000-0000-0000-0000-000000005c01', gen_random_uuid())$$,
  '42501', null, 'gracz nie wywoła launch_attack');
select throws_ok($$select * from private.scout_missions$$, '42501', null, 'gracz nie czyta misji zwiadu');
select throws_ok($$select private.scout_intel('{}', '{}', array[0, 0, 1, 1])$$, '42501', null,
  'gracz nie woła scout_intel');
select throws_ok($$select launched_at from public.attacks limit 1$$, '42501', null,
  'gracz nie czyta launched_at');
set local role anon;
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c02', 0::smallint, 0)$$, '42501', null, 'anon nie wywoła begin_scout');

-- ---- warunki wysłania zwiadu (serwer) ----
set local role service_role;
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c03',
  '00000000-0000-0000-0000-000000005c02', 0::smallint, 0)$$, 'P0001', 'no_building', 'bez Chaty tropicieli');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c04',
  '00000000-0000-0000-0000-000000005c02', 0::smallint, 0)$$, 'P0001', 'no_tech', 'bez S1');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c05',
  '00000000-0000-0000-0000-000000005c02', 0::smallint, 0)$$, 'P0001', 'no_scouts', 'bez zwiadowców w budynku');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c01', 0::smallint, 0)$$, 'P0001', 'self_scout', 'nie na siebie');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c02', 3::smallint, 0)$$, 'P0001', 'bad_duration', 'zła długość');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c02', 0::smallint, -1)$$, 'P0001', 'bad_seed', 'zły seed');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c07', 0::smallint, 0)$$, 'P0001', 'target_out_of_range', 'cel poza epoką ±1');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c08', 0::smallint, 0)$$, 'P0001', 'target_not_found', 'cel bez zamku');

-- ---- misja: seed 0 to rzut 0, czyli sukces ----
create temp table m1 on commit drop as
  select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
    '00000000-0000-0000-0000-000000005c02', 1::smallint, 0);
select is((select trackers from m1), 3::smallint, 'najpierw Tropiciele');
select is((select scouts from m1), 2::smallint, 'razem najwyżej 5 zwiadowców');
select ok((select ends_at from m1) = now() + interval '10 minutes', 'średni zwiad: 10 minut');
select throws_ok($$select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
  '00000000-0000-0000-0000-000000005c06', 0::smallint, 0)$$, 'P0001', 'scout_busy', 'naraz jedna misja');
select is((select finished from public.scout_reports('00000000-0000-0000-0000-000000005c01')), false,
  'misja w drodze');
select is((select outcome from public.scout_reports('00000000-0000-0000-0000-000000005c01')), null::smallint,
  'przed końcem bez wyniku');
select is((select intel from public.scout_reports('00000000-0000-0000-0000-000000005c01')), null::jsonb,
  'przed końcem bez danych');
select is((select count(*)::int from public.scout_reports('00000000-0000-0000-0000-000000005c08')), 0,
  'obcy gracz nie widzi cudzej misji');

-- koniec misji: czas przesunięty wstecz
reset role;
update private.scout_missions set started_at = now() - interval '11 minutes', ends_at = now() - interval '1 minute'
  where attacker_id = '00000000-0000-0000-0000-000000005c01';
set local role service_role;
create temp table r1 on commit drop as select * from public.scout_reports('00000000-0000-0000-0000-000000005c01');
select is((select outcome from r1), 0::smallint, 'rzut 0: sukces');
select is((select returned from r1), 5::smallint, 'sukces: wracają wszyscy');
-- średni zwiad 35 + 4 × 5 za zwiadowców = 55
select is((select percent from r1), 55::smallint, 'procent zamku z długości i liczby zwiadowców');
select is((select castle_name from r1), 'Cel', 'nazwa zamku celu');
select ok((select (intel -> 'region' ->> 0)::int >= 10 and (intel -> 'region' ->> 1)::int >= 10
    and (intel -> 'region' ->> 0)::int + (intel -> 'region' ->> 2)::int <= 22
    and (intel -> 'region' ->> 1)::int + (intel -> 'region' ->> 3)::int <= 22 from r1),
  'obszar w zabudowie celu');
select ok((select (intel -> 'region' ->> 2)::int * (intel -> 'region' ->> 3)::int < 144 from r1),
  'nawet sukces odsłania tylko część zamku');

-- ---- co odsłania obszar (scout_intel z jawnym obszarem 10..13 × 10..13) ----
create temp table i1 on commit drop as select private.scout_intel(
  (select data from public.castles where player_id = '00000000-0000-0000-0000-000000005c02'),
  (select data from public.defense_layouts where player_id = '00000000-0000-0000-0000-000000005c02'),
  array[10, 10, 4, 4]) as v;
select is((select v -> 'buildings' from i1), '[[10, 10, 2, 2, 21, 1]]'::jsonb, 'tylko budynki w obszarze');
select is((select v -> 'squads' from i1), '[[2, 11, 11]]'::jsonb, 'oddział z miejscem w obszarze, z klasą');
select is((select v -> 'traps' from i1), '[[0, 12, 12]]'::jsonb, 'tylko pułapki w obszarze');
select is((select v -> 'patrols' from i1), '[]'::jsonb, 'patrol poza obszarem ukryty');
select is((select private.scout_intel(
    (select data from public.castles where player_id = '00000000-0000-0000-0000-000000005c02'),
    (select data from public.defense_layouts where player_id = '00000000-0000-0000-0000-000000005c02'),
    array[29, 29, 3, 3]) -> 'patrols'), '[[[21, 19], [30, 30]]]'::jsonb, 'patrol z punktem w obszarze: cała trasa');
select is(private.scout_intel('{}', '{}', null), '{}'::jsonb, 'bez obszaru nic');
select is(private.scout_region('{"grid": {"buildings": [[1, 4, 1, 10, 10, 20, 10]]}}', 20, 12345),
  private.scout_region('{"grid": {"buildings": [[1, 4, 1, 10, 10, 20, 10]]}}', 20, 12345), 'ten sam seed: ten sam obszar');

-- ---- Wieża sygnałowa celu: rzut 50 przy sukcesie 40 to wynik częściowy ----
reset role;
delete from private.scout_missions where attacker_id = '00000000-0000-0000-0000-000000005c01';
set local role service_role;
create temp table m2 on commit drop as
  select * from public.begin_scout('00000000-0000-0000-0000-000000005c01',
    '00000000-0000-0000-0000-000000005c06', 0::smallint, 50);
reset role;
select is((select outcome from private.scout_missions where id = (select mission_id from m2)), 1::smallint,
  'Wieża sygnałowa wykrywa: częściowy');
select is((select returned from private.scout_missions where id = (select mission_id from m2)), 3::smallint,
  'częściowy: wraca połowa w górę');
delete from private.scout_missions where attacker_id = '00000000-0000-0000-0000-000000005c01';

-- ---- plan ataku: zarys, donżon i odsłonięte; pełna obrona dopiero po zatwierdzeniu ----
insert into private.scout_missions (attacker_id, defender_id, duration, trackers, scouts, started_at, ends_at,
  outcome, percent, returned, intel)
  values ('00000000-0000-0000-0000-000000005c01', '00000000-0000-0000-0000-000000005c02', 0, 1, 0,
    now() - interval '5 minutes', now() - interval '3 minutes', 0, 20, 1, (select v from i1));
set local role service_role;
create temp table a1 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-000000005c01',
    '00000000-0000-0000-0000-000000005c02', null, '[[0, 10]]', 7);
create temp table p1 on commit drop as
  select * from public.attack_preview('00000000-0000-0000-0000-000000005c01', (select attack_id from a1));
select is((select jsonb_array_length(footprint) from p1), 3, 'zarys wszystkich budynków');
select is((select keep from p1), array[10, 10, 2, 2], 'donżon: cel ataku');
select is((select intel -> 'traps' from p1), '[[0, 12, 12]]'::jsonb, 'odsłonięte z ostatniego zwiadu');
select is((select count(*)::int from public.attack_preview('00000000-0000-0000-0000-000000005c08',
  (select attack_id from a1))), 0, 'obcy gracz nie podejrzy cudzego ataku');
select throws_ok(format($$select * from public.end_attack('00000000-0000-0000-0000-000000005c01', %L,
    '{"won": false, "percent": 0, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[10]')$$,
    (select attack_id from a1)), 'P0001', 'not_launched', 'bez zatwierdzenia planu brak wyniku');
select throws_ok(format($$select * from public.launch_attack('00000000-0000-0000-0000-000000005c08', %L)$$,
    (select attack_id from a1)), 'P0001', 'attack_not_found', 'obcy gracz nie dostanie cudzej obrony');
create temp table l1 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-000000005c01', (select attack_id from a1));
select is((select defense -> 'traps' from l1), '[[0, 12, 12, 0], [1, 25, 25, 0]]'::jsonb,
  'po zatwierdzeniu pełna obrona');
select ok((select not (castle ? 'scout') and castle ? 'grid' from l1), 'zamek bez zwiadu obrońcy');
select is((select status from public.end_attack('00000000-0000-0000-0000-000000005c01', (select attack_id from a1),
    '{"won": false, "percent": 0, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'po zatwierdzeniu wynik przyjęty');

-- ---- konto celu znika razem z misjami o nim ----
reset role;
delete from auth.users where id = '00000000-0000-0000-0000-000000005c02';
select is((select count(*)::int from private.scout_missions where defender_id = '00000000-0000-0000-0000-000000005c02'),
  0, 'misje znikają z kontem celu');

select * from finish();
rollback;
