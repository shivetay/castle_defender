-- Testy epoki gracza z zamku (#34), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `private.castle_age` daje epokę II tylko przy Dworze 6+ i zbadanych O1, G1, A7;
-- zapis zamku podnosi `players.age` właściciela (nigdy nie obniża), obcy gracz nie zmieni cudzej
-- epoki, a klient nie ustawi epoki sam ani nie zawoła funkcji pomocniczych.
-- Testy biegną też na projekcie w chmurze, w transakcji, która się cofa: liczą tylko swoje konta.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(22);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000a9e01'),
  ('00000000-0000-0000-0000-0000000a9e02');

-- ---- klient nie woła funkcji pomocniczych ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000a9e01", "role": "authenticated"}', true);
select throws_ok($$select private.castle_age('{}'::jsonb)$$, '42501', null, 'gracz nie woła castle_age');
select throws_ok($$select private.sync_player_age()$$, '42501', null, 'gracz nie woła sync_player_age');
reset role;

-- ---- epoka z zapisu zamku ----
select is(private.castle_age('{}'::jsonb), 0::smallint, 'pusty zapis: epoka I');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, 5, 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1", "A7"]}}'),
  0::smallint, 'Dwór 5 z technologiami: jeszcze epoka I');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}}'),
  0::smallint, 'Dwór 6 bez badań: epoka I');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1"]}}'),
  0::smallint, 'Dwór 6 bez A7: epoka I');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}, "research": {"done": ["G1", "A7", "O2"]}}'),
  0::smallint, 'Dwór 6 bez O1: epoka I');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}, "research": {"done": ["A1", "A7", "G1", "O1"]}}'),
  1::smallint, 'Dwór 6 i O1, G1, A7: epoka II');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, 99, 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1", "A7"]}}'),
  1::smallint, 'poziom ponad 10 przycięty, najwyżej epoka II');
select is(private.castle_age('{"grid": {"buildings": [[2, 5, 6, 30, 30, 2, 2], [1, 5, 3, 40, 40, 2, 2]]}, "research": {"done": ["O1", "G1", "A7"]}}'),
  0::smallint, 'liczy się Dwór o najniższym id');
select is(private.castle_age('{"grid": {"buildings": [[1, 4, 9, 30, 30, 2, 2], [2, 5, 5, 0, 0, 2, 2]]}, "research": {"done": ["O1", "G1", "A7"]}}'),
  0::smallint, 'inny budynek na poziomie epoki II nie zmienia epoki');
select is(private.castle_age('{"grid": {"buildings": [[1, 5, "6", 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1", "A7"]}}'),
  0::smallint, 'poziom jako napis odrzucony');
select is(private.castle_age('{"grid": {"buildings": "x"}, "research": {"done": "O1 G1 A7"}}'),
  0::smallint, 'zły kształt zapisu: epoka I');

-- ---- zapis zamku przez gracza ----
-- konto sprzed doby (zabudowa i badania z czasu gry, #274, #281), a przebudowa Dworu na 6 jest w kolejce przy zapisie
update public.players set created_at = now() - interval '1 day' where id = '00000000-0000-0000-0000-0000000a9e01';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000a9e01", "role": "authenticated"}', true);
select lives_ok($$insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000a9e01', 77, 8,
   '{"grid": {"buildings": [[1, 5, 5, 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1", "G18", "G19", "A2", "A43", "A7"]},
     "queue": {"orders": [{"building_id": 1, "level": 6}]}}')$$,
  'gracz zakłada swój zamek');
select is((select age from public.players where id = '00000000-0000-0000-0000-0000000a9e01'), 0::smallint,
  'Dwór 5: epoka I');
select lives_ok($$update public.castles set data =
  '{"grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1", "G18", "G19", "A2", "A43", "A7"]}}'
  where player_id = '00000000-0000-0000-0000-0000000a9e01'$$, 'gracz zapisuje zamek po przebudowie Dworu');
select is((select age from public.players where id = '00000000-0000-0000-0000-0000000a9e01'), 1::smallint,
  'zapis zamku podnosi epokę do II');
select lives_ok($$update public.castles set data = '{"grid": {"buildings": [[1, 5, 2, 30, 30, 2, 2]]}}'
  where player_id = '00000000-0000-0000-0000-0000000a9e01'$$, 'zapis z niższym Dworem przechodzi');
select is((select age from public.players where id = '00000000-0000-0000-0000-0000000a9e01'), 1::smallint,
  'epoka nie spada (zmodyfikowany zapis nie przeniesie do słabszych)');
select throws_ok($$update public.players set age = 0 where id = '00000000-0000-0000-0000-0000000a9e01'$$,
  '42501', null, 'gracz nie zmieni epoki sam');
reset role;

-- ---- obcy gracz nie zmieni cudzego zamku ani epoki ----
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000a9e02', 78, 8, '{"grid": {"buildings": [[1, 5, 1, 30, 30, 2, 2]]}}');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000a9e01", "role": "authenticated"}', true);
select is_empty($$update public.castles set data =
  '{"grid": {"buildings": [[1, 5, 6, 30, 30, 2, 2]]}, "research": {"done": ["O1", "G1", "G18", "G19", "A2", "A43", "A7"]}}'
  where player_id = '00000000-0000-0000-0000-0000000a9e02' returning player_id$$, 'cudzy zamek: 0 wierszy');
reset role;
select is((select age from public.players where id = '00000000-0000-0000-0000-0000000a9e02'), 0::smallint,
  'cudza epoka bez zmian');

select * from finish();
rollback;
