-- Testy rankingu PvE (#242), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: punkty PvE zmienia tylko serwer po wygranym ataku na zamek-bota (10 + 5 × numer bota),
-- ten sam bot daje punkty najwyżej raz na dobę, przegrana, porzucony atak i ponowiony koniec ataku nic
-- nie zmieniają, ranking PvP zostaje bez zmian; tabela pokazuje tylko graczy z tej samej epoki
-- z co najmniej jedną punktowaną wygraną, 20 najlepszych i własny wiersz; boty nie są w tabeli;
-- klient nie zmieni punktów, nie przeczyta licznika i nie wywoła funkcji rankingu.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(37);

-- Gracze testu są w epoce 9 (bez prawdziwych graczy), bo testy biegną też na projekcie w chmurze,
-- w transakcji, która się cofa. A = d1 i B = d2 atakują boty, C = d3 (epoka 8), N = d4 (bez wygranych),
-- T01..T22 = 7801..7822 (tłum do limitu 20 wierszy).
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d2'),
  ('00000000-0000-0000-0000-0000000000d3'), ('00000000-0000-0000-0000-0000000000d4');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 70000, age = 9 where id in (select id from test_ids);
update public.players set age = 8 where id = '00000000-0000-0000-0000-0000000000d3';
update public.players set nickname = 'Ala' where id = '00000000-0000-0000-0000-0000000000d1';
update public.players set nickname = 'Bolek' where id = '00000000-0000-0000-0000-0000000000d2';

insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4242, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród ' || right(t.id::text, 2), 'ruler', 'mieszko'),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb))
from test_ids t;

-- ---- klient nie zmienia punktów, nie czyta licznika i nie woła funkcji ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000d1", "role": "authenticated"}', true);
select throws_ok(
  $$update public.players set pve_points = 9999 where id = '00000000-0000-0000-0000-0000000000d1'$$,
  '42501', null, 'A nie podbije sobie punktów PvE');
select throws_ok(
  $$update public.players set pve_wins = 99 where id = '00000000-0000-0000-0000-0000000000d1'$$,
  '42501', null, 'A nie dopisze sobie wygranych PvE');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  0, 'A czyta swoje punkty PvE');
select throws_ok(
  $$select * from private.pve_awards$$,
  '42501', null, 'gracz nie czyta licznika punktów PvE');
select throws_ok(
  $$select * from public.pve_ranking('00000000-0000-0000-0000-0000000000d1')$$,
  '42501', null, 'gracz nie wywoła pve_ranking');
reset role;
set local role anon;
select throws_ok(
  $$select * from public.pve_ranking('00000000-0000-0000-0000-0000000000d1')$$,
  '42501', null, 'anon nie wywoła pve_ranking');
reset role;

-- ---- punkty za bota: PVE_BASE = 10, PVE_STEP = 5 ----
select is(private.pve_points(0::smallint), 10, 'pierwszy bot: 10 punktów');
select is(private.pve_points(19::smallint), 105, 'ostatni bot: 105 punktów');

-- ---- wygrana z botem ----
set local role service_role;
create temp table s1 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d1', null, 3::smallint, '[[0, 10]]', 21);
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  0, 'atak w toku nie daje punktów');
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d1', (select attack_id from s1),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'A kończy atak na bota 3');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  25, 'A wygrał z botem 3: +25');
select is((select pve_wins from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  1, 'A: jedna punktowana wygrana');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  1000, 'ranking ataku PvP bez zmian');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  0, 'bitwa z botem nie liczy się do PvP');

-- ponowiony koniec ataku zwraca zapisany wynik i nie liczy punktów drugi raz
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d1', (select attack_id from s1),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'ponowienie zwraca zapisany wynik');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  25, 'ponowienie nie dodaje punktów');

-- ---- ten sam bot w ciągu doby: bez punktów ----
create temp table s2 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d1', null, 3::smallint, '[[0, 10]]', 22);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d1', (select attack_id from s2),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'A znowu wygrywa z botem 3');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  25, 'ten sam bot w ciągu doby nie daje punktów');
select is((select pve_wins from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  1, 'nie liczy się jako punktowana wygrana');

-- ---- przegrana i porzucony atak: bez punktów ----
create temp table s3 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d1', null, 5::smallint, '[[0, 10]]', 23);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d1', (select attack_id from s3),
  '{"won": false, "percent": 10, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[3]')), 'finished',
  'A przegrywa z botem 5');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  25, 'przegrana nie zmienia punktów');
create temp table s4 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d1', null, 6::smallint, '[[0, 10]]', 24);
-- nowy start porzuca atak na bota 6
create temp table s5 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d1', null, 7::smallint, '[[0, 10]]', 25);
select is((select status from public.attacks where id = (select attack_id from s4)), 'abandoned',
  'atak na bota 6 porzucony');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  25, 'porzucony atak nie zmienia punktów');

-- ---- inny bot daje punkty od razu, a ten sam znowu po dobie ----
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d1', (select attack_id from s5),
  '{"won": true, "percent": 60, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'A wygrywa z botem 7');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  70, 'bot 7: +45');
reset role;
update private.pve_awards set awarded_at = now() - interval '25 hours'
where player_id = '00000000-0000-0000-0000-0000000000d1' and bot_idx = 3;
set local role service_role;
create temp table s6 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d1', null, 3::smallint, '[[0, 10]]', 26);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d1', (select attack_id from s6),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'A wygrywa z botem 3 po dobie');
select is((select pve_points from public.players where id = '00000000-0000-0000-0000-0000000000d1'),
  95, 'po dobie bot 3 znowu daje +25');

-- B wygrywa z pierwszym botem
create temp table s7 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000d2', null, 0::smallint, '[[0, 10]]', 27);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000d2', (select attack_id from s7),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'B wygrywa z botem 0');
reset role;

-- ---- tabela rankingu ----
-- C (epoka 8) ma wysokie punkty, N nie ma wygranych: obu nie ma w tabeli epoki 9
update public.players set pve_points = 5000, pve_wins = 5 where id = '00000000-0000-0000-0000-0000000000d3';
select results_eq(
  $$select place, nickname, castle_name, ruler, points, is_me
    from public.pve_ranking('00000000-0000-0000-0000-0000000000d1')$$,
  $$values (1, 'Ala', 'Gród d1', 'mieszko', 95, true), (2, 'Bolek', 'Gród d2', 'mieszko', 10, false)$$,
  'ranking PvE: epoka A, tylko gracze z wygranymi, od najlepszego, bez botów');
select is((select count(*)::int from public.pve_ranking('00000000-0000-0000-0000-0000000000d3')),
  1, 'C w epoce 8 widzi tylko swoją epokę');
select is((select count(*)::int from public.pve_ranking('00000000-0000-0000-0000-0000000000d4')),
  2, 'N bez wygranych widzi tabelę bez siebie');
select is((select count(*)::int from public.pve_ranking(gen_random_uuid())),
  0, 'nieznany gracz: pusta tabela');
select is((select count(*)::int from public.pve_ranking(null)),
  0, 'brak gracza: pusta tabela');

-- remis: to samo miejsce
update public.players set pve_points = 95 where id = '00000000-0000-0000-0000-0000000000d2';
select is((select array_agg(place order by place) from public.pve_ranking('00000000-0000-0000-0000-0000000000d1')),
  array[1, 1], 'remis: to samo miejsce');

-- 22 graczy lepszych od A: tabela ma 20 najlepszych i wiersz A pod nią
insert into auth.users (id)
  select ('00000000-0000-0000-0000-00000000' || (7800 + g)::text)::uuid from generate_series(1, 22) g;
update public.players set age = 9, pve_wins = 1, pve_points = 2000 + g.g
  from generate_series(1, 22) g
  where id = ('00000000-0000-0000-0000-00000000' || (7800 + g.g)::text)::uuid;
insert into public.castles (player_id, map_seed, save_version, data)
  select ('00000000-0000-0000-0000-00000000' || (7800 + g)::text)::uuid, 7, 8,
    '{"profile": {"castle_name": "Tłum"}}'::jsonb
  from generate_series(1, 22) g;
select is((select count(*)::int from public.pve_ranking('00000000-0000-0000-0000-0000000000d1')),
  21, '20 najlepszych i własny wiersz');
select results_eq(
  $$select place, points, is_me from public.pve_ranking('00000000-0000-0000-0000-0000000000d1')
    where is_me or place = 1$$,
  $$values (1, 2022, false), (23, 95, true)$$,
  'pierwsze miejsce i własny wiersz pod 20 najlepszymi');

-- ---- usunięcie konta kasuje licznik punktów ----
delete from auth.users where id = '00000000-0000-0000-0000-0000000000d1';
select is((select count(*)::int from private.pve_awards where player_id = '00000000-0000-0000-0000-0000000000d1'),
  0, 'licznik PvE znika z kontem');

select * from finish();
rollback;
