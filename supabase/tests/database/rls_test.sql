-- Testy RLS i uprawnień (#21), uruchamiane przez `supabase test db` (pgTAP).
-- Kryterium: obcy gracz nie zmieni cudzego zamku ani nie zobaczy cudzych danych, a klient nie
-- zapisze ataków, tarcz, rankingu ani seedu terenu.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(52);

-- Trzech graczy: A, B, C (konta Auth tworzą wiersze w players przez wyzwalacz).
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000000a'),
  ('00000000-0000-0000-0000-00000000000b'),
  ('00000000-0000-0000-0000-00000000000c');

-- liczy tylko konta testu: testy biegną też na projekcie w chmurze, gdzie są prawdziwi gracze
select is((select count(*)::int from public.players where id in ('00000000-0000-0000-0000-00000000000a',
  '00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c')), 3,
  'konto Auth tworzy wiersz gracza');

select ok(
  (select bool_and(c.relrowsecurity) from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r'),
  'RLS włączone na każdej tabeli w public');

-- Zamek B i atak A na B zakłada serwer (rola postgres w teście).
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-00000000000b', 4242, 8, '{"grid": "b"}');
insert into public.defense_layouts (player_id, save_version, data)
  values ('00000000-0000-0000-0000-00000000000b', 8, '{"traps": []}');
insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot)
  values ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 4242, 7,
    '{"traps": ["wilczy_dol"]}', '{"grid": "b"}');
insert into public.attacks (attacker_id, bot_idx, map_seed, battle_seed)
  values ('00000000-0000-0000-0000-00000000000a', 3, 786423411, 8);
insert into public.shields (player_id, until) values ('00000000-0000-0000-0000-00000000000b', now() + interval '8 hours');

-- ---- gracz A ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000a", "role": "authenticated"}', true);

select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-00000000000a', 1337, 8, '{"grid": "a"}')$$,
  'A zakłada własny zamek');
select throws_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-00000000000c', 1, 8, '{}')$$,
  '42501', null, 'A nie założy zamku za C');
select is((select count(*)::int from public.castles), 1, 'A widzi tylko swój zamek');
select is((select player_id from public.castles), '00000000-0000-0000-0000-00000000000a'::uuid, 'i to jest jego zamek');

-- cudzy zamek: aktualizacja nie trafia w żaden wiersz
select is_empty(
  $$update public.castles set data = '{"grid": "zniszczony"}'
    where player_id = '00000000-0000-0000-0000-00000000000b' returning player_id$$,
  'A nie zmieni zamku B');
select lives_ok(
  $$update public.castles set data = '{"grid": "a2"}', save_version = 8
    where player_id = '00000000-0000-0000-0000-00000000000a'$$,
  'A zapisuje własny zamek');
select is((select revision from public.castles), 1::bigint, 'zapis podbija licznik zmian');
select throws_ok(
  $$update public.castles set map_seed = 99 where player_id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501', null, 'A nie zmieni seedu terenu');
select throws_ok(
  $$update public.castles set revision = 100 where player_id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501', null, 'A nie ustawi licznika zmian');
select throws_ok(
  $$delete from public.castles where player_id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501', null, 'A nie usunie zamku (nowa gra z tym samym seedem)');

-- obrona
select is_empty($$select 1 from public.defense_layouts$$, 'A nie widzi obrony B');
select is_empty(
  $$update public.defense_layouts set data = '{}'
    where player_id = '00000000-0000-0000-0000-00000000000b' returning player_id$$,
  'A nie zmieni obrony B');
select lives_ok(
  $$insert into public.defense_layouts (player_id, save_version, data)
    values ('00000000-0000-0000-0000-00000000000a', 8, '{"traps": []}')$$,
  'A zakłada własną obronę');

-- konto: ranking i epoka tylko z serwera
select is((select count(*)::int from public.players), 1, 'A widzi tylko swoje konto');
select lives_ok(
  $$update public.players set nickname = 'Wojewoda' where id = '00000000-0000-0000-0000-00000000000a'$$,
  'A zmienia swój nick');
select throws_ok(
  $$update public.players set rating = 9999 where id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501', null, 'A nie podbije sobie rankingu');
select throws_ok(
  $$update public.players set age = 5 where id = '00000000-0000-0000-0000-00000000000a'$$,
  '42501', null, 'A nie zmieni sobie epoki');
select is_empty(
  $$update public.players set nickname = 'Zdrajca' where id = '00000000-0000-0000-0000-00000000000b' returning id$$,
  'A nie zmieni nicku B');

-- ataki, tarcze, nagrody: tylko odczyt własnych
select is((select count(*)::int from public.attacks), 2, 'A widzi swoje ataki (na B i na bota)');
select is((select map_seed from public.attacks where defender_id is not null), 4242::bigint,
  'A czyta map_seed terenu obrońcy (#166)');
select is((select battle_seed from public.attacks where defender_id is not null), 7::bigint,
  'battle_seed osobny od map_seed');
select throws_ok(
  $$insert into public.attacks (attacker_id, bot_idx, battle_seed)
    values ('00000000-0000-0000-0000-00000000000a', 0, 1)$$,
  '42501', null, 'A nie zapisze ataku sam (tylko serwer)');
select throws_ok(
  $$update public.attacks set status = 'finished'$$,
  '42501', null, 'A nie zmieni wyniku ataku');
select is_empty($$select 1 from public.shields$$, 'A nie widzi tarczy B');
select throws_ok(
  $$insert into public.shields (player_id, until) values ('00000000-0000-0000-0000-00000000000a', now())$$,
  '42501', null, 'A nie da sobie tarczy');
select throws_ok(
  $$insert into public.ad_rewards (player_id, reward) values ('00000000-0000-0000-0000-00000000000a', 'zloto')$$,
  '42501', null, 'A nie da sobie nagrody za reklamę');

-- kopie z chwili startu ataku czyta tylko serwer (pułapki obrońcy, jego pełny zamek)
select throws_ok($$select defense_snapshot from public.attacks$$, '42501', null,
  'A nie podejrzy obrony B (z pułapkami) z kopii ataku');
select throws_ok($$select castle_snapshot from public.attacks$$, '42501', null,
  'A nie podejrzy zamku B z kopii ataku');

-- lista zamków-botów tylko do odczytu
select throws_ok($$insert into public.bot_castles (idx, name, map_seed, age) values (0, 'x', 1, 0)$$,
  '42501', null, 'A nie doda zamku-bota');
select throws_ok($$update public.bot_castles set map_seed = 1$$, '42501', null, 'A nie zmieni seedu zamku-bota');
select throws_ok($$delete from public.bot_castles$$, '42501', null, 'A nie usunie zamków-botów');

-- ---- gracz B: widzi atak na siebie, nie widzi ataku A na bota ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000b", "role": "authenticated"}', true);
select is((select count(*)::int from public.attacks), 1, 'B widzi tylko atak na siebie');
select is((select data from public.castles), '{"grid": "b"}'::jsonb, 'zamek B nietknięty');

-- ---- gracz C: nic cudzego ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000000c", "role": "authenticated"}', true);
select is_empty($$select 1 from public.attacks$$, 'C nie widzi cudzych ataków');
select is_empty($$select 1 from public.castles$$, 'C nie widzi cudzych zamków');

-- ---- niezalogowany (anon) ----
reset role;
set local role anon;
select is((select count(*)::int from public.bot_castles), 20, 'lista 20 zamków-botów jest publiczna');
select throws_ok($$select 1 from public.castles$$, '42501', null, 'anon nie czyta zamków');
select throws_ok($$select 1 from public.players$$, '42501', null, 'anon nie czyta graczy');
select throws_ok($$select 1 from public.defense_layouts$$, '42501', null, 'anon nie czyta obron');
select throws_ok($$select 1 from public.attacks$$, '42501', null, 'anon nie czyta ataków');
select throws_ok($$select 1 from public.shields$$, '42501', null, 'anon nie czyta tarcz');
select throws_ok($$select 1 from public.ad_rewards$$, '42501', null, 'anon nie czyta nagród');
select throws_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-00000000000c', 1, 8, '{}')$$,
  '42501', null, 'anon nie założy zamku');
select throws_ok($$insert into public.players (id) values ('00000000-0000-0000-0000-00000000000c')$$,
  '42501', null, 'anon nie założy gracza');
select throws_ok($$update public.bot_castles set name = 'x'$$, '42501', null, 'anon nie zmieni zamków-botów');
select throws_ok($$delete from public.bot_castles$$, '42501', null, 'anon nie usunie zamków-botów');

-- ---- serwer (Edge Functions, service_role): zapisuje ataki, tarcze i nagrody ----
reset role;
set local role service_role;
select lives_ok(
  $$insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot, attacker_army, status)
    values ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000b', 4242, 9,
      '{"traps": []}', '{"grid": "b"}', '[["topornik", 5]]', 'abandoned')$$,
  'serwer zapisuje atak z kopią obrony i zamku');
select throws_ok(
  $$insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed)
    values ('00000000-0000-0000-0000-00000000000c', '00000000-0000-0000-0000-00000000000b', 4242, 10)$$,
  '23514', null, 'atak na gracza bez kopii obrony jest odrzucony');
select lives_ok(
  $$insert into public.shields (player_id, until) values ('00000000-0000-0000-0000-00000000000c', now() + interval '8 hours')$$,
  'serwer daje tarczę');
select lives_ok(
  $$insert into public.ad_rewards (player_id, reward) values ('00000000-0000-0000-0000-00000000000c', 'zloto')$$,
  'serwer zapisuje nagrodę za reklamę');

reset role;
select * from finish();
rollback;
