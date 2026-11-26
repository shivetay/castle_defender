-- Testy siły celu PvP (#293, ADR 0004), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `private.defense_strength` liczy siłę obrony z kopii zamku i układu obrony na serwerze tym
-- samym wzorem co gra (przykładowy zamek liczy też `tests/test_strength.gd`), a karta celu
-- (`match_targets`) i historia obron (`defense_history`) dostają tylko dolną granicę przedziału.
-- Gracz nie woła funkcji siły ani nie czyta cudzego zamku i układu obrony.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(19);

-- ---- wzór siły i przedziały ----
select is(private.defense_strength(
  '{"grid": {"buildings": [[1,5,1,32,32,2,2],[2,21,1,34,31,2,2],[4,3,3,31,28,2,2],[5,2,1,31,34,3,1],[6,0,0,33,28,1,1],[7,0,5,34,28,1,1],[8,4,2,34,34,2,2]]},
    "recruitment": {"squads": [[1,0,10],[2,3,7],[3,1,4],[4,5,3],[1,2,10],[5,99,3],[6,10,15]]}}',
  '{"orders": [[3,6,40,40,[]],[1,0,30,30,[]],[2,6,0,0,[]],[2,0,1,1,[]]], "traps": [[0,10,10,0],[4,11,10,0],[3,10,10,0],[9,12,12,0]]}'),
  532, 'siła przykładowego zamku jak w grze');
select is(private.strength_range_low(532), 500, 'przedział przykładowego zamku');
select is(private.defense_strength(null, null), 0, 'pusty zamek');
select is(private.defense_strength('{"grid": 5, "recruitment": {"squads": "x"}}', '[]'), 0, 'zły kształt danych');
select is(private.defense_strength('{"defense": {"traps": [[4, 1, 1]]}}', null), 7,
  'bez układu obrony liczy się obrona z zapisu zamku');
select is(private.defense_strength('{"recruitment": {"squads": [[1.7, 0, 3.9], [2, 0, "5"], [2e20, 0, 1]]}}', '{}'),
  33, 'liczby jak int() w grze, złe wpisy odpadają');
select is(array(select private.strength_range_low(v) from unnest(array[-5, 0, 49, 50, 499, 500, 1999, 2000, 2499, 2500, 200000]) v),
  array[0, 0, 0, 50, 450, 500, 1900, 2000, 2000, 2500, 99500], 'stałe granice przedziałów');

-- ---- karta celu i historia obron ----
-- A atakuje, B to cel z obroną. Ranking w paśmie 63 293 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values ('00000000-0000-0000-0000-0000000293a1'), ('00000000-0000-0000-0000-0000000293b1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 63293, age = 0 where id in (select id from test_ids);
update public.players set nickname = 'Bolko' where id = '00000000-0000-0000-0000-0000000293b1';

-- zamki bez zgodnego bilansu i budowy: wyzwalacze kontroli zapisu i rankingu (ich własne testy) są
-- wyłączone do końca tej transakcji, która się cofa (także na projekcie, gdzie `session_replication_role`
-- jest niedostępne)
alter table public.castles disable trigger user;
alter table public.attacks disable trigger user;
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000293a1', 4242, 8, '{"profile": {"castle_name": "Gród A"}}'),
  ('00000000-0000-0000-0000-0000000293b1', 4243, 8, '{"profile": {"castle_name": "Gród B"},
    "recruitment": {"squads": [[1, 10, 10]]}, "grid": {"buildings": [[1, 3, 3, 1, 1, 2, 2]]}}');
insert into public.defense_layouts (player_id, save_version, data) values
  ('00000000-0000-0000-0000-0000000293b1', 8, '{"traps": [[4, 1, 1]]}');
insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot,
  status, result, loot, finished_at)
values ('00000000-0000-0000-0000-0000000293b1', '00000000-0000-0000-0000-0000000293a1', 1, 1, '{}', '{}',
  'finished', '{"won": true, "percent": 50, "stars": [true, false, false]}', array[0, 0, 0, 0], now());

set local role service_role;
-- B: 10 kopijników w obronie (250), wieża na 3. poziomie (29) i smoła (7) = 286
create temp table m on commit drop as select * from public.match_targets('00000000-0000-0000-0000-0000000293a1');
select is((select strength from m where player_id = '00000000-0000-0000-0000-0000000293b1'), 250,
  'karta celu: dolna granica przedziału siły obrony');
select ok(not exists (select 1 from m where strength <> private.strength_range_low(strength)),
  'karta celu: tylko granice przedziałów');
select is((select defense from public.defense_history('00000000-0000-0000-0000-0000000293a1') limit 1), 250,
  'historia obron: przedział siły obrony zamku napastnika');
select is((select nickname from public.defense_history('00000000-0000-0000-0000-0000000293a1') limit 1), 'Bolko',
  'historia obron: nick bez zmian');
reset role;
-- napastnik bez zamku (usunięte konto): „?”
delete from public.castles where player_id = '00000000-0000-0000-0000-0000000293b1';
set local role service_role;
select is((select defense from public.defense_history('00000000-0000-0000-0000-0000000293a1') limit 1), null::integer,
  'historia obron: bez zamku napastnika brak siły');
reset role;

-- ---- gracz nie liczy siły sam i nie czyta cudzej obrony ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000293a1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select private.defense_strength('{}', '{}')$$, '42501', null, 'gracz nie wywoła defense_strength');
select throws_ok($$select private.strength_range_low(1)$$, '42501', null, 'gracz nie wywoła strength_range_low');
select throws_ok($$select * from public.match_targets('00000000-0000-0000-0000-0000000293a1')$$, '42501', null,
  'gracz nie wywoła match_targets');
select throws_ok($$select * from public.defense_history('00000000-0000-0000-0000-0000000293a1')$$, '42501', null,
  'gracz nie wywoła defense_history');
select is((select count(*)::int from public.defense_layouts where player_id = '00000000-0000-0000-0000-0000000293b1'), 0,
  'gracz nie czyta cudzego układu obrony');
reset role;
set local role anon;
select throws_ok($$select private.defense_strength('{}', '{}')$$, '42501', null, 'anon nie wywoła defense_strength');
select throws_ok($$select * from public.match_targets('00000000-0000-0000-0000-0000000293a1')$$, '42501', null,
  'anon nie wywoła match_targets');

select * from finish();
rollback;
