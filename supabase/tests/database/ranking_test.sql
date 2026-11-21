-- Testy rankingu PvP (#27), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: ranking ataku i obrony są osobne i zmienia je tylko serwer po bitwie PvP; wygrana obrona
-- podnosi ranking obrony; porzucony atak liczy się jak odparty; ponowiony koniec ataku i atak na
-- zamek-bota nic nie zmieniają; tabela pokazuje tylko graczy z tej samej epoki, 20 najlepszych i
-- własny wiersz; klient nie zmieni punktów ani nie wywoła funkcji rankingu.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(45);

-- Gracze testu są w epoce 9 (bez prawdziwych graczy), z rankingiem doboru w paśmie 70 000, bo testy
-- biegną też na projekcie w chmurze, w transakcji, która się cofa.
-- A = e1 i C = e2 atakują, B = f1 i D = f2 bronią się, O = f3 (epoka 8), N = f4 (bez bitew),
-- T01..T22 = 7701..7722 (tłum do limitu 20 wierszy).
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000e2'),
  ('00000000-0000-0000-0000-0000000000f1'), ('00000000-0000-0000-0000-0000000000f2'),
  ('00000000-0000-0000-0000-0000000000f3'), ('00000000-0000-0000-0000-0000000000f4');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 70000, age = 9 where id in (select id from test_ids);
update public.players set nickname = 'Ala' where id = '00000000-0000-0000-0000-0000000000e1';
update public.players set nickname = 'Bolek' where id = '00000000-0000-0000-0000-0000000000f1';

insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4242, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród ' || right(t.id::text, 2), 'ruler', 'mieszko'),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb))
from test_ids t;

-- ---- klient nie zmienia punktów i nie woła funkcji ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000e1", "role": "authenticated"}', true);
select throws_ok(
  $$update public.players set attack_rating = 9999 where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A nie podbije sobie rankingu ataku');
select throws_ok(
  $$update public.players set defense_rating = 9999 where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A nie podbije sobie rankingu obrony');
select throws_ok(
  $$update public.players set attack_games = 99 where id = '00000000-0000-0000-0000-0000000000e1'$$,
  '42501', null, 'A nie dopisze sobie bitew');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  1000, 'A czyta swój ranking ataku');
select is((select count(*)::int from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  0, 'A nie czyta rankingu B z tabeli');
select throws_ok(
  $$select * from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')$$,
  '42501', null, 'gracz nie wywoła pvp_ranking');
reset role;
set local role anon;
select throws_ok(
  $$select * from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')$$,
  '42501', null, 'anon nie wywoła pvp_ranking');
reset role;

-- ---- Elo: K = 32 ----
select is(private.elo_delta(1000, 1000, true), 16, 'równi: wygrana +16');
select is(private.elo_delta(1000, 1000, false), -16, 'równi: przegrana -16');
select is(private.elo_delta(1200, 1000, true), 8, 'faworyt wygrywa: +8');
select is(private.elo_delta(1000, 1200, true), 24, 'słabszy wygrywa: +24');

-- ---- wygrany atak ----
set local role service_role;
create temp table s1 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e1',
    '00000000-0000-0000-0000-0000000000f1', null, '[[0, 10]]', 11);
-- #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
update public.attacks set launched_at = now() where id = (select attack_id from s1);
select is((select defense_games from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  0, 'atak w toku nie zmienia rankingu');
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000e1', (select attack_id from s1),
  '{"won": true, "percent": 20, "stars": [true, false, true]}', '[0, 0, 0, 0]', '[10]')), 'finished', 'A kończy atak na B');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  1016, 'A wygrał: ranking ataku +16');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  1, 'A: jedna bitwa w ataku');
select is((select defense_rating from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  1000, 'ranking obrony A bez zmian');
select is((select defense_rating from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  984, 'B przegrał obronę: ranking obrony -16');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  1000, 'ranking ataku B bez zmian');

-- ponowiony koniec ataku zwraca zapisany wynik i nie liczy bitwy drugi raz
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000e1', (select attack_id from s1),
  '{"won": true, "percent": 20, "stars": [true, false, true]}', '[0, 0, 0, 0]', '[10]')), 'finished', 'ponowienie zwraca zapisany wynik');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  1016, 'ponowienie nie dodaje punktów');
select is((select defense_games from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  1, 'ponowienie nie dodaje bitwy');

-- ---- odparty atak: wygrana obrona podnosi ranking obrony ----
create temp table s2 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e2',
    '00000000-0000-0000-0000-0000000000f1', null, '[[0, 10]]', 12);
-- #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
update public.attacks set launched_at = now() where id = (select attack_id from s2);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000e2', (select attack_id from s2),
  '{"won": false, "percent": 10, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[3]')), 'finished', 'C kończy atak na B');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e2'),
  983, 'C przegrał: ranking ataku -17 (B słabszy w obronie)');
select is((select defense_rating from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  1001, 'B odparł atak: ranking obrony +17');
select is((select defense_games from public.players where id = '00000000-0000-0000-0000-0000000000f1'),
  2, 'B: dwie bitwy w obronie');

-- ---- porzucony atak liczy się jak odparty ----
create temp table s3 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e1',
    '00000000-0000-0000-0000-0000000000f2', null, '[[0, 10]]', 13);
-- #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
update public.attacks set launched_at = now() where id = (select attack_id from s3);
-- A zaczyna atak na zamek-bota: poprzedni atak (na D) jest porzucony
create temp table s4 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e1', null, 0::smallint,
    '[[0, 10]]', 14);
select is((select status from public.attacks where id = (select attack_id from s3)), 'abandoned',
  'atak na D porzucony');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  999, 'A porzucił atak: ranking ataku -17');
select is((select defense_rating from public.players where id = '00000000-0000-0000-0000-0000000000f2'),
  1017, 'D: porzucony atak to odparta obrona, +17');

-- ---- atak na zamek-bota nie zmienia rankingu ----
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000e1', (select attack_id from s4),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished', 'A kończy atak na bota');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  999, 'wygrana z botem nie zmienia rankingu');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000000e1'),
  2, 'bitwa z botem się nie liczy');

-- ---- podłoga 0: nikt nie traci więcej, niż ma, a suma zostaje zerowa ----
-- C (10 punktów ataku) przegrywa z D (0 punktów obrony): Elo dałoby -16, C ma tylko 10
update public.players set defense_rating = 0 where id = '00000000-0000-0000-0000-0000000000f2';
update public.players set attack_rating = 10 where id = '00000000-0000-0000-0000-0000000000e2';
create temp table s5 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e2',
    '00000000-0000-0000-0000-0000000000f2', null, '[[0, 10]]', 15);
-- #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
update public.attacks set launched_at = now() where id = (select attack_id from s5);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000000e2', (select attack_id from s5),
  '{"won": false, "percent": 10, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[3]')), 'finished',
  'C kończy atak na D');
select is((select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000000e2'),
  0, 'C przy 10 punktach ataku spada do 0');
select is((select defense_rating from public.players where id = '00000000-0000-0000-0000-0000000000f2'),
  10, 'D dostaje tylko 10 punktów, które C stracił (suma zero)');
update public.players set defense_rating = 1017 where id = '00000000-0000-0000-0000-0000000000f2';
update public.players set attack_rating = 983 where id = '00000000-0000-0000-0000-0000000000e2';

-- ---- tabela rankingu ----
-- O (epoka 8) ma bitwy i wysoki ranking, N nie ma bitew: obu nie ma w tabeli epoki 9
update public.players set age = 8, attack_games = 5, attack_rating = 5000, defense_games = 5,
  defense_rating = 5000 where id = '00000000-0000-0000-0000-0000000000f3';
reset role;

select results_eq(
  $$select place, nickname, castle_name, ruler, points, is_me
    from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')$$,
  $$values (1, 'Ala', 'Gród e1', 'mieszko', 999, true), (2, 'Gracz', 'Gród e2', 'mieszko', 983, false)$$,
  'ranking ataku: epoka A, tylko gracze z bitwami w ataku, od najlepszego');
select results_eq(
  $$select place, nickname, points, is_me
    from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'defense')$$,
  $$values (1, 'Gracz', 1017, false), (2, 'Bolek', 1001, false)$$,
  'ranking obrony: osobna tabela, A (bez bitew w obronie) poza nią');
select is((select count(*)::int from public.pvp_ranking('00000000-0000-0000-0000-0000000000f3', 'attack')),
  1, 'O w epoce 8 widzi tylko swoją epokę');
select is((select count(*)::int from public.pvp_ranking('00000000-0000-0000-0000-0000000000f4', 'attack')),
  2, 'N bez bitew widzi tabelę bez siebie');
select is((select count(*)::int from public.pvp_ranking(gen_random_uuid(), 'attack')),
  0, 'nieznany gracz: pusta tabela');
select throws_ok(
  $$select * from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'gold')$$,
  'P0001', 'bad_kind', 'zły rodzaj rankingu odrzucony');

-- remis: to samo miejsce
update public.players set attack_rating = 999 where id = '00000000-0000-0000-0000-0000000000e2';
select is((select array_agg(place order by place) from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')),
  array[1, 1], 'remis: to samo miejsce');

-- 22 graczy lepszych od A: tabela ma 20 najlepszych i wiersz A pod nią
insert into auth.users (id)
  select ('00000000-0000-0000-0000-00000000' || (7700 + g)::text)::uuid from generate_series(1, 22) g;
update public.players set age = 9, attack_games = 1, attack_rating = 2000 + g.g
  from generate_series(1, 22) g
  where id = ('00000000-0000-0000-0000-00000000' || (7700 + g.g)::text)::uuid;
insert into public.castles (player_id, map_seed, save_version, data)
  select ('00000000-0000-0000-0000-00000000' || (7700 + g)::text)::uuid, 7, 8,
    '{"profile": {"castle_name": "Tłum"}}'::jsonb
  from generate_series(1, 22) g;
select is((select count(*)::int from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')),
  21, '20 najlepszych i własny wiersz');
select results_eq(
  $$select place, points, is_me from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')
    where is_me or place = 1$$,
  $$values (1, 2022, false), (23, 999, true)$$,
  'na górze najlepszy, A na 23. miejscu pod tabelą');
select is((select max(place) filter (where not is_me) from public.pvp_ranking('00000000-0000-0000-0000-0000000000e1', 'attack')),
  20, 'bez A tabela kończy się na 20. miejscu');
select is((select count(*)::int from public.pvp_ranking('00000000-0000-0000-0000-0000000000e2', 'attack')),
  21, 'C (remis z A) też widzi swój wiersz');

select * from finish();
rollback;
