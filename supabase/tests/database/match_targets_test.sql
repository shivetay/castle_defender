-- Testy doboru przeciwnika (#24), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: klient nie wywoła `match_targets` (czyta cudze zamki), serwer dostaje najwyżej 3 graczy
-- bez tarczy, z epoką ±1 i rankingiem ±100, nieatakowanych przez niego w 24 h, bez siebie samego;
-- karta dostaje sam zarys budynków i zaokrąglony szacowany łup.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(25);

-- A atakuje. B, G, I: pasują. C: tarcza. D: epoka 2. E: ranking +200. F: atakowany przez A 2 h temu.
-- H: zamek bez nazwy (bez onboardingu). J: pasuje, ale bez nazwy zamku do drugiej części testu.
-- K: atakował B (cudzy atak nie wyklucza B), sam ma ranking +1000. L: bez zamku.
-- Test dotyka tylko swoich kont, a ich ranking leży w paśmie 50 000, w którym nie ma prawdziwych
-- graczy, więc wynik nie zależy od innych danych w bazie (testy biegną też na projekcie w chmurze,
-- w transakcji, która się cofa).
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-0000000000c1'), ('00000000-0000-0000-0000-0000000000d1'),
  ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000f1'),
  ('00000000-0000-0000-0000-0000000000a2'), ('00000000-0000-0000-0000-0000000000a3'),
  ('00000000-0000-0000-0000-0000000000a4'), ('00000000-0000-0000-0000-0000000000a5'),
  ('00000000-0000-0000-0000-0000000000a6'), ('00000000-0000-0000-0000-0000000000a7');
insert into auth.users (id) select id from test_ids;

-- G = a2, H = a3, I = a4, J = a5, K = a6, L = a7
update public.players set rating = 50000, age = 0 where id in (select id from test_ids);
update public.players set nickname = 'Bolko' where id = '00000000-0000-0000-0000-0000000000b1';
update public.players set rating = 50100 where id = '00000000-0000-0000-0000-0000000000a2';
update public.players set rating = 49900, age = 1 where id = '00000000-0000-0000-0000-0000000000a4';
update public.players set age = 2 where id = '00000000-0000-0000-0000-0000000000d1';
update public.players set rating = 50200 where id = '00000000-0000-0000-0000-0000000000e1';
update public.players set rating = 51000 where id = '00000000-0000-0000-0000-0000000000a6';

insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4242, 8, jsonb_build_object('profile', jsonb_build_object('castle_name', 'Gród', 'ruler', 'kasztelan'))
from test_ids t
where t.id not in ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a5',
  '00000000-0000-0000-0000-0000000000a7', '00000000-0000-0000-0000-0000000000b1');

insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000000b1', 777, 8, '{
    "profile": {"player_name": "Bolko", "castle_name": "Bardzo Długa Nazwa Zamku", "ruler": "kasztelan"},
    "grid": {"next_id": 3, "buildings": [[1, 5, 2, 10, 11, 2, 2], [2, 0, 1, 20, 21, 1, 1], "zły wpis", [9]]},
    "economy": {"amounts": [1000, 555, 0, 99]},
    "defense": {"traps": ["wilczy_dol"]},
    "recruitment": {"army": [1, 2, 3]}
  }'),
  ('00000000-0000-0000-0000-0000000000a3', 1, 8, '{"grid": {}}'),
  ('00000000-0000-0000-0000-0000000000a5', 2, 8, '{"profile": {"castle_name": ""}}');

insert into public.shields (player_id, until) values
  ('00000000-0000-0000-0000-0000000000c1', now() + interval '8 hours'),
  ('00000000-0000-0000-0000-0000000000a4', now() - interval '1 minute');

insert into public.attacks (attacker_id, bot_idx, map_seed, battle_seed, started_at) values
  ('00000000-0000-0000-0000-0000000000a1', 0, 1, 1, now() - interval '1 hour');
insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot, started_at)
values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000f1', 1, 1, '{}', '{}',
    now() - interval '2 hours'),
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-0000000000a2', 1, 1, '{}', '{}',
    now() - interval '25 hours'),
  ('00000000-0000-0000-0000-0000000000a6', '00000000-0000-0000-0000-0000000000b1', 1, 1, '{}', '{}',
    now() - interval '1 hour');

-- ---- klient nie wywoła doboru ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);
select throws_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000a1')$$,
  '42501', null, 'gracz nie wywoła match_targets (nawet dla siebie)');
select throws_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000b1')$$,
  '42501', null, 'gracz nie wywoła match_targets za innego gracza');

reset role;
set local role anon;
select throws_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000a1')$$,
  '42501', null, 'anon nie wywoła match_targets');

-- ---- serwer (Edge Function find_targets) ----
reset role;
set local role service_role;

select results_eq(
  $$select player_id from public.match_targets('00000000-0000-0000-0000-0000000000a1') order by player_id$$,
  $$values ('00000000-0000-0000-0000-0000000000a2'::uuid), ('00000000-0000-0000-0000-0000000000a4'::uuid),
    ('00000000-0000-0000-0000-0000000000b1'::uuid)$$,
  'dobór: B, G (atak sprzed 25 h), I (wygasła tarcza, epoka +1, ranking -100)');
select is_empty(
  $$select 1 from public.match_targets('00000000-0000-0000-0000-0000000000a1')
    where player_id = '00000000-0000-0000-0000-0000000000a1'$$,
  'bez siebie samego');
select is_empty(
  $$select 1 from public.match_targets('00000000-0000-0000-0000-0000000000a1')
    where player_id = '00000000-0000-0000-0000-0000000000c1'$$,
  'bez gracza z aktywną tarczą');
select is_empty(
  $$select 1 from public.match_targets('00000000-0000-0000-0000-0000000000a1')
    where player_id in ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000e1')$$,
  'bez epoki +2 i rankingu +200');
select is_empty(
  $$select 1 from public.match_targets('00000000-0000-0000-0000-0000000000a1')
    where player_id = '00000000-0000-0000-0000-0000000000f1'$$,
  'bez gracza zaatakowanego przez A w ostatnich 24 h');
select is_empty(
  $$select 1 from public.match_targets('00000000-0000-0000-0000-0000000000a1')
    where player_id in ('00000000-0000-0000-0000-0000000000a3', '00000000-0000-0000-0000-0000000000a5',
      '00000000-0000-0000-0000-0000000000a7')$$,
  'bez graczy bez zamku albo bez nazwy zamku');

select results_eq(
  $$select nickname, castle_name, ruler, age, rating, map_seed
    from public.match_targets('00000000-0000-0000-0000-0000000000a1')
    where player_id = '00000000-0000-0000-0000-0000000000b1'$$,
  $$values ('Bolko'::text, 'Bardzo Długa Naz'::text, 'kasztelan'::text, 0::smallint, 50000, 777::bigint)$$,
  'karta: nick, nazwa zamku przycięta do 16 znaków, władca, epoka, ranking, seed terenu');
select is(
  (select footprint from public.match_targets('00000000-0000-0000-0000-0000000000a1')
   where player_id = '00000000-0000-0000-0000-0000000000b1'),
  '[[10, 11, 2, 2], [20, 21, 1, 1]]'::jsonb,
  'zarys: same prostokąty, bez rodzajów i poziomów; złe wpisy pominięte');
select is(
  (select loot from public.match_targets('00000000-0000-0000-0000-0000000000a1')
   where player_id = '00000000-0000-0000-0000-0000000000b1'),
  array[50, 20, 0, 0],
  'szacowany łup: 5 procent zapasów w dół do dziesiątek');
select is(
  (select loot from public.match_targets('00000000-0000-0000-0000-0000000000a1')
   where player_id = '00000000-0000-0000-0000-0000000000a2'),
  array[0, 0, 0, 0],
  'zamek bez ekonomii: łup zerowy, bez błędu');
select is_empty(
  $$select 1 from public.match_targets(null)$$,
  'bez atakującego: pusto');

-- czwarty pasujący gracz: nadal najwyżej 3 cele, wszystkie z pasujących
reset role;
update public.castles set data = '{"profile": {"castle_name": "Jaworzyna"}}'
  where player_id = '00000000-0000-0000-0000-0000000000a5';
set local role service_role;
select is(
  (select count(*)::int from public.match_targets('00000000-0000-0000-0000-0000000000a1')),
  3, 'najwyżej 3 cele');
select ok(
  (select bool_and(player_id in ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-0000000000a4',
     '00000000-0000-0000-0000-0000000000a5', '00000000-0000-0000-0000-0000000000b1'))
   from public.match_targets('00000000-0000-0000-0000-0000000000a1')),
  'wszystkie 3 z pasujących graczy');

-- ---- limit: 20 szukań na 10 minut ----
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000a1", "role": "authenticated"}', true);
select throws_ok(
  $$select * from private.target_searches$$,
  '42501', null, 'gracz nie widzi licznika szukań');

reset role;
select is(
  (select searches from private.target_searches where player_id = '00000000-0000-0000-0000-0000000000a1'),
  12, 'każde wywołanie (poza pustym atakującym) liczy się do limitu');
update private.target_searches set searches = 19 where player_id = '00000000-0000-0000-0000-0000000000a1';
set local role service_role;
select lives_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000a1')$$,
  '20. szukanie w oknie przechodzi');
select throws_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000a1')$$,
  'P0001', 'rate_limited', '21. szukanie w oknie jest odrzucone');
-- licznik nie zależy od wycofania transakcji: po odrzuceniu zostaje 20, a kolejne szukania też
-- są odrzucane (każde w osobnej transakcji, jak w PostgREST: tu po zatwierdzeniu savepointu)
reset role;
select is(
  (select searches from private.target_searches where player_id = '00000000-0000-0000-0000-0000000000a1'),
  20, 'po odrzuceniu licznik zostaje na 20');
set local role service_role;
select throws_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000a1')$$,
  'P0001', 'rate_limited', 'kolejne szukanie w oknie też jest odrzucone');
select throws_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000a1')$$,
  'P0001', 'rate_limited', 'i następne także');
select lives_ok(
  $$select * from public.match_targets('00000000-0000-0000-0000-0000000000b1')$$,
  'limit jest osobny dla każdego gracza');
reset role;
update private.target_searches set window_start = now() - interval '11 minutes'
  where player_id = '00000000-0000-0000-0000-0000000000a1';
set local role service_role;
select is(
  (select count(*)::int from public.match_targets('00000000-0000-0000-0000-0000000000a1')),
  3, 'po 10 minutach okno zaczyna się od nowa');

select * from finish();
rollback;
