-- Testy startu i końca ataku (#25), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: dwóch graczy nie zaatakuje naraz tego samego celu, zawyżony łup jest odrzucany, max łup
-- rośnie z liczbą ocalałych jednostek, tarcza od 30 procent zniszczeń, klient nie wywoła funkcji.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(47);

-- A i X atakują, B i Y bronią się. Ranking w paśmie 60 000 (bez prawdziwych graczy), bo testy
-- biegną też na projekcie w chmurze, w transakcji, która się cofa.
-- A = c1, X = c2, B = d1, Y = d2, S = d3 (tarcza), Z = d4 (epoka 3), N = d5 (zamek bez nazwy)
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000c2'),
  ('00000000-0000-0000-0000-0000000000d1'), ('00000000-0000-0000-0000-0000000000d2'),
  ('00000000-0000-0000-0000-0000000000d3'), ('00000000-0000-0000-0000-0000000000d4'),
  ('00000000-0000-0000-0000-0000000000d5');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 60000, age = 0 where id in (select id from test_ids);
update public.players set age = 3 where id = '00000000-0000-0000-0000-0000000000d4';

-- armia: 3 oddziały toporników (rodzaj 0) po 10 i 1 jeźdźców (rodzaj 6) po 10. Budynki [id, rodzaj,
-- poziom, x, y, szer., wys.]: Dwór 3 i Koszary 3 + 2 dają 40 miejsc, Rybak 1 daje 60 Ży/h (utrzymanie 50, #249).
-- Budynki najwyżej do Dworu (#274). Jeźdźcy mają A7 z wymaganiami, a oddziały są w kształcie z gry (#281). Dziesięć Magazynów 3 (rodzaj 25) mieści 1000 + 10 × 1000 = 11000, a złoto ma pokrycie w złocie startu i fal (#274).
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4242, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 4, 4], [2, 18, 3, 36, 30, 3, 3], [3, 16, 1, 40, 30, 2, 2],
    [4, 25, 3, 10, 10, 2, 2], [5, 25, 3, 13, 10, 2, 2], [6, 25, 3, 16, 10, 2, 2], [7, 25, 3, 19, 10, 2, 2],
    [8, 25, 3, 22, 10, 2, 2], [9, 18, 2, 50, 50, 3, 3], [10, 25, 3, 10, 13, 2, 2], [11, 25, 3, 13, 13, 2, 2],
    [12, 25, 3, 16, 13, 2, 2], [13, 25, 3, 19, 13, 2, 2], [14, 25, 3, 22, 13, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(10000, 4000, 2000, 100)),
  'research', jsonb_build_object('done', '["G18", "G19", "A2", "A43", "A7"]'::jsonb),
  'recruitment', jsonb_build_object('squads',
    '[[1, 0, 10], [2, 0, 10], [3, 0, 10], [4, 6, 10]]'::jsonb))
from test_ids t where t.id <> '00000000-0000-0000-0000-0000000000d5';
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000000d5', 5, 8, '{"profile": {"castle_name": ""}}');
insert into public.defense_layouts (player_id, save_version, data)
  values ('00000000-0000-0000-0000-0000000000d1', 8, '{"traps": [[3, 4, 1]]}');
insert into public.shields (player_id, until)
  values ('00000000-0000-0000-0000-0000000000d3', now() + interval '1 hour');

-- ---- klient nie woła funkcji ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000c1", "role": "authenticated"}', true);
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d1', null, '[[0, 10]]', 1)$$,
  '42501', null, 'gracz nie wywoła begin_attack');
select throws_ok(
  $$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', gen_random_uuid(), '{}', '[]', '[]')$$,
  '42501', null, 'gracz nie wywoła end_attack');
reset role;
set local role anon;
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c1', null, 0::smallint, '[[0, 10]]', 1)$$,
  '42501', null, 'anon nie wywoła begin_attack');
reset role;

-- ---- start ataku (serwer) ----
set local role service_role;

create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000c1',
    '00000000-0000-0000-0000-0000000000d1', null, '[[0, 10], [0, 10], [6, 10]]', 77);
-- #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
update public.attacks set launched_at = now() where id = (select attack_id from started);
select is((select count(*)::int from started), 1, 'A zaczyna atak na B');
select is((select map_seed from started), 4242::bigint, 'seed terenu B');
select is((select battle_seed from started), 77::bigint, 'seed bitwy z Edge Function');
select is((select castle -> 'economy' -> 'amounts' ->> 0 from started), '10000', 'kopia zamku B');
select is((select defense -> 'traps' from started), '[[3, 4, 1]]'::jsonb, 'kopia obrony B');
select is((select status from public.attacks where id = (select attack_id from started)), 'started',
  'atak w toku');

select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d1', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_busy', 'X nie zaatakuje B, gdy atakuje go A');
select throws_ok(
  $$insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot)
    values ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d1', 1, 1, '{}', '{}')$$,
  '23505', null, 'indeks też nie dopuści drugiego ataku w toku na B');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d3', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_shielded', 'cel z tarczą odrzucony');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d4', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_out_of_range', 'cel spoza epoki ±1 odrzucony');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d5', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_not_found', 'zamek bez nazwy nie jest celem');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000c2', null, '[[0, 10]]', 1)$$,
  'P0001', 'self_attack', 'atak na siebie odrzucony');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 3::smallint, '[[6, 10], [6, 10]]', 1)$$,
  'P0001', 'army_not_owned', 'więcej jeźdźców niż w zamku odrzucone');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 3::smallint, '[[0, 11]]', 1)$$,
  'P0001', 'bad_army', 'oddział ponad 10 jednostek odrzucony');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 3::smallint, '[[0, 1], [0, 1], [0, 1], [6, 1]]', 1)$$,
  'P0001', 'bad_army', 'więcej oddziałów niż pozwala epoka I odrzucone');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 3::smallint, '[[0, 2.5]]', 1)$$,
  'P0001', 'bad_army', 'ułamek w armii odrzucony');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 3::smallint, '[[0, 10]]', -1)$$,
  'P0001', 'bad_seed', 'zły seed bitwy odrzucony');

-- Y bez zamku jako atakujący: najpierw zamek (#23)
delete from public.castles where player_id = '00000000-0000-0000-0000-0000000000d2';
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000d2', null, 3::smallint, '[[0, 10]]', 1)$$,
  'P0001', 'attacker_no_castle', 'atak bez zamku na serwerze odrzucony');

-- ---- koniec ataku ----
create temp table ids on commit drop as select attack_id as id from started;

select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c2', %L, '{"won": true, "percent": 60, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10, 10, 10]')$$,
    (select id from ids)),
  'P0001', 'attack_not_found', 'X nie zakończy ataku A');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": true, "percent": 40, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10, 10, 10]')$$,
    (select id from ids)),
  'P0001', 'bad_result', 'gwiazdka połowy zamku przy 40 procentach odrzucona');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": false, "percent": 60, "stars": [true, true, false], "bonus": 1}', '[0, 0, 0, 0]', '[10, 10, 10]')$$,
    (select id from ids)),
  'P0001', 'bad_result', 'nadmiarowe pole w wyniku odrzucone');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": true, "percent": 60, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10, 11, 10]')$$,
    (select id from ids)),
  'P0001', 'bad_survivors', 'więcej ocalałych niż w oddziale odrzucone');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": false, "percent": 60, "stars": [true, true, false]}', '[1, 0, 0, 0]', '[10, 10, 10]')$$,
    (select id from ids)),
  'P0001', 'loot_too_high', 'łup po przegranej odrzucony');
-- zapasy B: 10000 drewna → przy 60 procentach najwyżej 10000 × 50% × 20% × 60% = 600
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": true, "percent": 60, "stars": [true, true, true]}', '[601, 0, 0, 0]', '[10, 10, 10]')$$,
    (select id from ids)),
  'P0001', 'loot_too_high', 'łup ponad niechronione zapasy odrzucony');
-- capacity: 20 toporników × 5 + 10 jeźdźców × 10 = 200; z 5 ocalałymi topornikami tylko 25
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": true, "percent": 60, "stars": [true, true, true]}', '[201, 0, 0, 0]', '[10, 10, 10]')$$,
    (select id from ids)),
  'P0001', 'loot_too_high', 'łup ponad capacity całej armii odrzucony');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": true, "percent": 60, "stars": [true, true, true]}', '[20, 6, 0, 0]', '[5, 0, 0]')$$,
    (select id from ids)),
  'P0001', 'loot_too_high', 'mniej ocalałych daje niższy limit łupu');
select lives_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c1', %L, '{"won": true, "percent": 60, "stars": [true, true, true]}', '[20, 5, 0, 0]', '[5, 0, 0]')$$,
    (select id from ids)),
  'łup w capacity 5 ocalałych przechodzi');
select is((select status from public.attacks where id = (select id from ids)), 'finished', 'atak zakończony');
select is((select loot from public.attacks where id = (select id from ids)), array[20, 5, 0, 0], 'łup zapisany');
select is((select (result ->> 'percent')::int from public.attacks where id = (select id from ids)), 60, 'wynik zapisany');
select ok((select until > now() + interval '7 hours 59 minutes' from public.shields
  where player_id = '00000000-0000-0000-0000-0000000000d1'), 'B dostaje tarczę na 8 godzin');

-- ponowienie: zapisany wynik, nic się nie zmienia
select is(
  (select loot from public.end_attack('00000000-0000-0000-0000-0000000000c1', (select id from ids),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[200, 0, 0, 0]', '[10, 10, 10]')),
  array[20, 5, 0, 0], 'drugi finish zwraca pierwszy łup');
select is((select (result ->> 'percent')::int from public.attacks where id = (select id from ids)), 60,
  'drugi finish nie zmienia wyniku');

-- po końcu ataku cel jest wolny, ale B ma tarczę
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000d1', null, '[[0, 10]]', 1)$$,
  'P0001', 'target_shielded', 'po ataku B jest pod tarczą');

-- zamek-bot 2: skarbiec 2000 drewna → przy wygranej 50 procent najwyżej 100; 30 ocalałych × 5 = 150
create temp table bot on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 2::smallint, '[[0, 10], [0, 10], [0, 10]]', 5);
select is((select map_seed from bot), 2000785702::bigint, 'seed terenu bota');
select is((select castle from bot), null::jsonb, 'bot bez kopii zamku');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000c2', %L, '{"won": true, "percent": 10, "stars": [false, false, true]}', '[101, 0, 0, 0]', '[10, 10, 10]')$$,
    (select attack_id from bot)),
  'P0001', 'loot_too_high', 'łup ponad skarbiec bota odrzucony');
select is(
  (select status from public.end_attack('00000000-0000-0000-0000-0000000000c2', (select attack_id from bot),
    '{"won": true, "percent": 10, "stars": [false, false, true]}', '[100, 50, 0, 0]', '[10, 10, 10]')),
  'finished', 'łup bota w limicie przechodzi');

-- atak poniżej 30 procent nie daje tarczy; wygasły atak zwalnia cel
create temp table y (attack_id uuid, map_seed bigint, battle_seed bigint, castle jsonb, defense jsonb)
  on commit drop;
update public.players set age = 0 where id = '00000000-0000-0000-0000-0000000000d4';
insert into y select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2',
  '00000000-0000-0000-0000-0000000000d4', null, '[[0, 10]]', 9);
update public.attacks set launched_at = now() where id = (select attack_id from y);
select is(
  (select status from public.end_attack('00000000-0000-0000-0000-0000000000c2', (select attack_id from y),
    '{"won": false, "percent": 29, "stars": [true, false, false]}', '[0, 0, 0, 0]', '[0]')),
  'finished', 'przegrana z 29 procentami zapisana');
select is((select count(*)::int from public.shields where player_id = '00000000-0000-0000-0000-0000000000d4'), 0,
  'poniżej 30 procent bez tarczy');

-- wygasły atak: A zaczął atak na Y (d2 ma znowu zamek) 11 minut temu
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000000d2', 8, 8, '{"profile": {"castle_name": "Y"}}');
insert into public.attacks (id, attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot, attacker_army, started_at)
  values ('00000000-0000-0000-0000-00000000aaaa', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000d2',
    8, 1, '{}', '{"economy": {"amounts": [1000, 0, 0, 0]}}', '[[0, 10]]', now() - interval '11 minutes');
select is(
  (select status from public.end_attack('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000aaaa',
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[50, 0, 0, 0]', '[10]')),
  'abandoned', 'wygasły atak nie przyjmuje wyniku');
select is((select status from public.attacks where id = '00000000-0000-0000-0000-00000000aaaa'), 'abandoned',
  'wygasły atak porzucony');
select is((select loot from public.attacks where id = '00000000-0000-0000-0000-00000000aaaa'), null::integer[],
  'porzucony atak bez łupu');

-- limit startów: 10 na 10 minut (X ma już 2 z tego testu)
insert into public.attacks (attacker_id, bot_idx, map_seed, battle_seed, status)
select '00000000-0000-0000-0000-0000000000c2', 0, 1, 1, 'abandoned' from generate_series(1, 8);
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000c2', null, 0::smallint, '[[0, 10]]', 1)$$,
  'P0001', 'rate_limited', '11. start w 10 minut odrzucony');

reset role;
select * from finish();
rollback;
