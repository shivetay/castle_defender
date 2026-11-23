-- Testy zniszczonych budynków po ataku (#99), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: zapisuje tylko serwer i tylko dla własnego zakończonego ataku na gracza; lista to gotowe
-- budynki z kopii zamku bez umocnień, nie więcej niż procent zniszczeń; pierwszy zapis wygrywa;
-- obrońca widzi listę swojej obrony, obcy gracz nie.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(18);

-- A atakuje B, O to obcy gracz. Ranking w paśmie 60 000 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa. A = e1, B = e2, O = e3.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000e2'),
  ('00000000-0000-0000-0000-0000000000e3');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 60000, age = 0 where id in (select id from test_ids);

-- Budynki [id, rodzaj, poziom, x, y, szer., wys.]: Dwór 1, Koszary 2, Rybak 3, plac budowy 4 (poziom 0),
-- wał 5 i palisada 6. Do procentu liczą się 1, 2 i 3 (3 budynki).
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4242, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2], [4, 4, 0, 44, 30, 2, 2], [5, 0, 1, 46, 30, 1, 1], [6, 1, 1, 47, 30, 1, 1]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb))
from test_ids t;

set local role service_role;

create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e1',
    '00000000-0000-0000-0000-0000000000e2', null, '[[0, 10]]', 5);
-- #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
update public.attacks set launched_at = now() where id = (select attack_id from started);

select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[1]')$$,
    (select attack_id from started)),
  'P0001', 'attack_not_finished', 'atak w toku: bez listy');

-- 66 procent: najwyżej 2 z 3 budynków
select lives_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000e1', %L, '{"won": false, "percent": 66, "stars": [false, true, false]}', '[0, 0, 0, 0]', '[4]')$$,
    (select attack_id from started)),
  'koniec ataku z 66 procentami');

select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e3', %L, '[1]')$$,
    (select attack_id from started)),
  'P0001', 'attack_not_found', 'obcy gracz nie zapisze listy cudzego ataku');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[1, 2, 3]')$$,
    (select attack_id from started)),
  'P0001', 'destroyed_too_many', '3 z 3 budynków to więcej niż 66 procent');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[5]')$$,
    (select attack_id from started)),
  'P0001', 'bad_destroyed', 'wał się nie liczy');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[4]')$$,
    (select attack_id from started)),
  'P0001', 'bad_destroyed', 'plac budowy się nie liczy');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[99]')$$,
    (select attack_id from started)),
  'P0001', 'bad_destroyed', 'budynku spoza kopii zamku nie ma');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[1, 1]')$$,
    (select attack_id from started)),
  'P0001', 'bad_destroyed', 'powtórzone id');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '[1.5]')$$,
    (select attack_id from started)),
  'P0001', 'bad_destroyed', 'ułamek');
select throws_ok(
  format($$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', %L, '{"a": 1}')$$,
    (select attack_id from started)),
  'P0001', 'bad_destroyed', 'nie lista');
select is((select destroyed from public.attacks where id = (select attack_id from started)), null,
  'odrzucona lista niczego nie zapisuje');

select is(
  public.record_destroyed('00000000-0000-0000-0000-0000000000e1', (select attack_id from started), '[3, 1]'),
  array[3, 1], '2 z 3 budynków przy 66 procentach');
select is(
  public.record_destroyed('00000000-0000-0000-0000-0000000000e1', (select attack_id from started), '[2]'),
  array[3, 1], 'ponowienie zwraca zapisaną listę');
select is((select a.result ->> 'percent' from public.attacks a where a.id = (select attack_id from started)), '66',
  'wynik ataku bez zmian');

reset role;

-- ---- odczyt (RLS) i brak zapisu z klienta ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000e2", "role": "authenticated"}', true);
select is((select destroyed from public.attacks where defender_id = '00000000-0000-0000-0000-0000000000e2'),
  array[3, 1], 'obrońca widzi zniszczone budynki swojej obrony');
select throws_ok(
  $$update public.attacks set destroyed = '{}' where defender_id = '00000000-0000-0000-0000-0000000000e2'$$,
  '42501', null, 'obrońca nie zmieni listy');
select throws_ok(
  $$select public.record_destroyed('00000000-0000-0000-0000-0000000000e1', gen_random_uuid(), '[]')$$,
  '42501', null, 'gracz nie wywoła record_destroyed');
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000e3", "role": "authenticated"}', true);
select is((select count(*)::int from public.attacks where defender_id = '00000000-0000-0000-0000-0000000000e2'),
  0, 'obcy gracz nie widzi cudzej obrony');
reset role;

select * from finish();
rollback;
