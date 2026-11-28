-- Testy sanity układu obrony (#421, ADR 0020), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: obrona w zamku ma kształt jak DefensePlan.to_dict (zadania tylko oddziałów z armii, kratki na mapie,
-- pułapki z technologią i epoką, w limicie Dworu); `defense_layouts` gracza tylko równe obronie z zamku; obcy gracz
-- nie pisze cudzego układu; start ataku z układem innym niż w zamku kończy się `defense_invalid`.
-- Na projekcie w chmurze uruchamiaj w transakcji, która się cofa (koniec pliku: rollback).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(36);

-- A = 421a (obrońca), B = 421b (obcy gracz i atakujący)
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values ('00000000-0000-0000-0000-00000000421a'), ('00000000-0000-0000-0000-00000000421b');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 4210, age = 0 where id in (select id from test_ids);

-- Dwór 3 (limit 6 pułapek), Koszary, Chata łowcy; G18 (Wilczy dół) i O2 (Kolczatka) zbadane, A42 nie
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4210, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'research', jsonb_build_object('done', '["A1", "A2", "G18", "G19", "A43", "A7", "O2"]'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10], [3, 0, 0]]'::jsonb),
  'defense', '{"orders": [[1, 0, 31, 33, []], [2, 1, 28, 28, [[34, 34], [28, 34]]], [3, 3, -1, -1, []]],
    "traps": [[0, 25, 25, 0], [1, 26, 25, 1]], "tower_priority": 2, "commander": 1}'::jsonb)
from test_ids t;
insert into public.defense_layouts (player_id, save_version, data)
select c.player_id, 8, c.data -> 'defense' from public.castles c where c.player_id in (select id from test_ids);

create function pg_temp.with_defense(d jsonb) returns text language plpgsql as $$
begin
  update public.castles set data = jsonb_set(data, '{defense}', d) where player_id = '00000000-0000-0000-0000-00000000421a';
  return 'ok';
end;
$$;

-- ---- obrona w zamku: kształt (wyzwalacz castles_check_defense, każdy zapis) ----
select is(private.defense_problem((select data from public.castles where player_id = '00000000-0000-0000-0000-00000000421a')),
  null, 'zadania, patrol, przy donżonie, pułapki, priorytet i komendant przechodzą');
select is(private.defense_problem('{"recruitment": {"squads": []}}'), null, 'zamek bez obrony (nowa gra) przechodzi');
select is(private.defense_problem('{"defense": {}}'), null, 'pusta obrona przechodzi');
select lives_ok($$select pg_temp.with_defense('{"orders": [[1, 7, 30, 31]], "traps": [[0, 0, 0]]}')$$,
  'wpisy bez trasy i bez znacznika odkrycia (stare zapisy) przechodzą');
select throws_ok($$select pg_temp.with_defense('[]')$$, 'PT422', 'bad_defense', 'obrona, która nie jest obiektem');
select throws_ok($$select pg_temp.with_defense('{"orders": [[9, 0, 30, 30, []]]}')$$, 'PT422', 'bad_defense',
  'zadanie oddziału, którego nie ma w armii');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 0, 30, 30, []], [1, 1, 31, 31, []]]}')$$, 'PT422',
  'bad_defense', 'dwa zadania jednego oddziału');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 8, 30, 30, []]]}')$$, 'PT422', 'bad_defense',
  'zadanie spoza listy (TASKS = 8)');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 0, 64, 30, []]]}')$$, 'PT422', 'bad_defense',
  'miejsce poza mapą 64×64');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 0, -1, 30, []]]}')$$, 'PT422', 'bad_defense',
  'pół NO_POST');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 0, 30.5, 30, []]]}')$$, 'PT422', 'bad_defense',
  'kratka, która nie jest liczbą całkowitą');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 1, 30, 30, [[31, 31], [32, 32], [33, 33]]]]}')$$,
  'PT422', 'bad_defense', 'patrol z trzema punktami trasy poza startem');
select throws_ok($$select pg_temp.with_defense('{"orders": [[1, 1, 30, 30, [[-1, -1]]]]}')$$, 'PT422', 'bad_defense',
  'punkt trasy poza mapą');
select throws_ok($$select pg_temp.with_defense('{"traps": [[3, 25, 25, 0]]}')$$, 'PT422', 'bad_defense',
  'Płonące strzały bez A42');
select throws_ok($$select pg_temp.with_defense('{"traps": [[5, 25, 25, 0]]}')$$, 'PT422', 'bad_defense',
  'rodzaj pułapki spoza listy');
select throws_ok($$select pg_temp.with_defense('{"traps": [[0, 25, 25, 0], [1, 25, 25, 0]]}')$$, 'PT422', 'bad_defense',
  'dwie pułapki na jednej kratce');
select throws_ok($$select pg_temp.with_defense('{"traps": [[0, 25, 25, 2]]}')$$, 'PT422', 'bad_defense',
  'znacznik odkrycia spoza 0/1');
select lives_ok($$select pg_temp.with_defense('{"traps": [[0, 20, 20], [0, 21, 20], [0, 22, 20], [0, 23, 20],
  [0, 24, 20], [0, 25, 20]]}')$$, 'sześć pułapek przy Dworze 3');
select throws_ok($$select pg_temp.with_defense('{"traps": [[0, 20, 20], [0, 21, 20], [0, 22, 20], [0, 23, 20],
  [0, 24, 20], [0, 25, 20], [0, 26, 20]]}')$$, 'PT422', 'bad_defense', 'siódma pułapka ponad limit Dworu 3');
select throws_ok($$select pg_temp.with_defense('{"tower_priority": 4}')$$, 'PT422', 'bad_defense',
  'priorytet wież spoza listy');
select throws_ok($$select pg_temp.with_defense('{"commander": 3}')$$, 'PT422', 'bad_defense',
  'komendant spoza listy generałów');
-- Wrząca smoła (G24) wymaga epoki II: technologia sama nie wystarczy
select is(private.defense_problem('{"research": {"done": ["G24"]}, "defense": {"traps": [[4, 25, 25]]}}'),
  'bad_defense', 'Wrząca smoła w epoce I');
select is(private.defense_problem('{"research": {"done": ["G24", "O1", "G1", "A7"]},
  "grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}, "defense": {"traps": [[4, 25, 25]]}}'),
  null, 'Wrząca smoła w epoce II');

-- jednorazowe sprzątanie: zostają poprawne wpisy, pierwsze wystąpienie
select is(private.defense_trimmed('{"recruitment": {"squads": [[1, 0, 10]]}, "research": {"done": ["G18"]},
    "defense": {"orders": [[1, 0, 30, 30, []], [1, 1, 31, 31, []], [9, 0, 30, 30, []]],
      "traps": [[0, 25, 25, 0], [3, 26, 26, 0], [0, 25, 25, 1], [0, 27, 27, 0], [0, 28, 28, 0]],
      "tower_priority": 9, "commander": 1}}'),
  '{"orders": [[1, 0, 30, 30, []]], "traps": [[0, 25, 25, 0], [0, 27, 27, 0]], "tower_priority": 0, "commander": 1}'::jsonb,
  'przycięta obrona: zadanie oddziału z armii, pułapki z technologią do limitu Dworu 1');

-- przywrócenie obrony do części z graczem
update public.castles c set data = jsonb_set(c.data, '{defense}', d.data)
from public.defense_layouts d where d.player_id = c.player_id and c.player_id = '00000000-0000-0000-0000-00000000421a';

-- ---- defense_layouts: gracz zapisuje tylko obronę z zamku ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000421a", "role": "authenticated"}', true);
select set_config('request.headers', '{"x-client-version": "999999"}', true);
select lives_ok(
  $$update public.defense_layouts set save_version = 9, data = (select c.data -> 'defense' from public.castles c
    where c.player_id = '00000000-0000-0000-0000-00000000421a') where player_id = '00000000-0000-0000-0000-00000000421a'$$,
  'A zapisuje obronę równą obronie z zamku');
select throws_ok(
  $$update public.defense_layouts set data = '{"traps": [[0, 25, 25, 0], [1, 26, 25, 1], [0, 30, 30, 0]]}'
    where player_id = '00000000-0000-0000-0000-00000000421a'$$,
  'PT422', 'defense_mismatch', 'A nie dopisze pułapki, której nie ma w zamku');
select throws_ok(
  $$update public.defense_layouts set data = '{}' where player_id = '00000000-0000-0000-0000-00000000421a'$$,
  'PT422', 'defense_mismatch', 'A nie zdejmie obrony bez zapisu zamku');
reset role;
delete from public.defense_layouts where player_id = '00000000-0000-0000-0000-00000000421a';
set local role authenticated;
select throws_ok(
  $$insert into public.defense_layouts (player_id, save_version, data)
    values ('00000000-0000-0000-0000-00000000421a', 8, '{"orders": [[1, 0, 31, 33, []]]}')$$,
  'PT422', 'defense_mismatch', 'A nie założy obrony innej niż w zamku');
select lives_ok(
  $$insert into public.defense_layouts (player_id, save_version, data)
    select '00000000-0000-0000-0000-00000000421a', 8, c.data -> 'defense' from public.castles c
    where c.player_id = '00000000-0000-0000-0000-00000000421a'$$,
  'A zakłada obronę równą obronie z zamku');

-- obcy gracz
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000421b", "role": "authenticated"}', true);
select is_empty(
  $$update public.defense_layouts set data = (select c.data -> 'defense' from public.castles c
    where c.player_id = '00000000-0000-0000-0000-00000000421b')
    where player_id = '00000000-0000-0000-0000-00000000421a' returning player_id$$,
  'B nie zmieni obrony A');
select throws_ok(
  $$insert into public.defense_layouts (player_id, save_version, data)
    values ('00000000-0000-0000-0000-00000000421a', 8, '{}')$$,
  '42501', null, 'B nie założy obrony za A (RLS, bez porównania z cudzym zamkiem)');
-- układ równy obronie zamku A: ten sam błąd, więc odmowa nie zdradza obrony A
select throws_ok(
  $$insert into public.defense_layouts (player_id, save_version, data)
    values ('00000000-0000-0000-0000-00000000421a', 8, '{"orders": [[1, 0, 31, 33, []], [2, 1, 28, 28, [[34, 34], [28, 34]]],
      [3, 3, -1, -1, []]], "traps": [[0, 25, 25, 0], [1, 26, 25, 1]], "tower_priority": 2, "commander": 1}')$$,
  '42501', null, 'B nie założy obrony za A');
reset role;

-- gracz bez zamku nie ma obrony
insert into auth.users (id) values ('00000000-0000-0000-0000-00000000421c');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000421c", "role": "authenticated"}', true);
select throws_ok(
  $$insert into public.defense_layouts (player_id, save_version, data)
    values ('00000000-0000-0000-0000-00000000421c', 8, '{}')$$,
  'PT422', 'defense_mismatch', 'bez zamku nie ma obrony');
reset role;

-- ---- start ataku: kopia obrony = obrona z zamku ----
select set_config('request.jwt.claims', '', true);
-- układ rozjechany z zamkiem (zapis sprzed migracji albo zapis obrony, który nie doszedł)
update public.defense_layouts set data = '{"traps": []}' where player_id = '00000000-0000-0000-0000-00000000421a';
set local role service_role;
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-00000000421b', '00000000-0000-0000-0000-00000000421a',
    null, '[[0, 10]]', 421)$$,
  'P0001', 'defense_invalid', 'układ inny niż w zamku nie idzie do ataku');
reset role;
update public.defense_layouts d set data = c.data -> 'defense'
from public.castles c where c.player_id = d.player_id and d.player_id = '00000000-0000-0000-0000-00000000421a';
set local role service_role;
create temp table a1 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-00000000421b', '00000000-0000-0000-0000-00000000421a',
    null, '[[0, 10]]', 421);
reset role;
select is((select defense from a1), (select data -> 'defense' from public.castles
  where player_id = '00000000-0000-0000-0000-00000000421a'), 'atak dostaje obronę z zamku');
select is((select defense_snapshot from public.attacks where id = (select attack_id from a1)),
  (select defense from a1), 'kopia obrony w ataku');

select * from finish();
rollback;
