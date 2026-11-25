-- Testy zapisu obrony (#298), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: właściciel aktualizuje własną obronę (wyzwalacz bump_revision nie czyta pól zamku), licznik
-- zmian rośnie o 1, a obcy gracz nadal nie zmieni cudzej obrony. Seed zamku dalej jest niezmienny.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

-- A = d501 (właściciel obrony), B = d502 (obcy gracz)
insert into auth.users (id) values
  ('00000000-0000-0000-0000-00000000d501'),
  ('00000000-0000-0000-0000-00000000d502');
insert into public.defense_layouts (player_id, save_version, data)
  values ('00000000-0000-0000-0000-00000000d501', 8, '{"traps": []}');

-- ---- gracz A ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d501", "role": "authenticated"}', true);

select lives_ok(
  $$update public.defense_layouts set data = '{"traps": ["wilczy_dol"]}', save_version = 9
    where player_id = '00000000-0000-0000-0000-00000000d501'$$,
  'A zapisuje własną obronę');
select is((select revision from public.defense_layouts where player_id = '00000000-0000-0000-0000-00000000d501'),
  1::bigint, 'licznik zmian obrony rośnie o 1');
select is((select data from public.defense_layouts where player_id = '00000000-0000-0000-0000-00000000d501'),
  '{"traps": ["wilczy_dol"]}'::jsonb, 'serwer ma nowy układ obrony');
select lives_ok(
  $$update public.defense_layouts set save_version = 10
    where player_id = '00000000-0000-0000-0000-00000000d501'$$,
  'A zapisuje obronę drugi raz');
select is((select revision from public.defense_layouts where player_id = '00000000-0000-0000-0000-00000000d501'),
  2::bigint, 'i licznik rośnie dalej');

-- ---- gracz B ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000d502", "role": "authenticated"}', true);
select is_empty(
  $$update public.defense_layouts set data = '{}'
    where player_id = '00000000-0000-0000-0000-00000000d501' returning player_id$$,
  'B nie zmieni obrony A');

-- ---- serwer (rola postgres omija granty): wyzwalacz nadal pilnuje właściciela i seedu ----
reset role;
select throws_ok(
  $$update public.defense_layouts set player_id = '00000000-0000-0000-0000-00000000d502'
    where player_id = '00000000-0000-0000-0000-00000000d501'$$,
  'P0001', 'player_id is immutable', 'właściciela obrony nie da się zmienić');

-- Zamek bez wyzwalaczy INSERT (bilans i budynki mają własne testy). Zmiana samego map_seed uruchamia
-- tylko bump_revision, bo pozostałe wyzwalacze UPDATE patrzą na kolumnę data.
set local session_replication_role = replica;
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-00000000d501', 4242, 8, '{}');
set local session_replication_role = origin;
select throws_ok(
  $$update public.castles set map_seed = 4243 where player_id = '00000000-0000-0000-0000-00000000d501'$$,
  'P0001', 'map_seed is immutable', 'seedu terenu zamku dalej nie da się zmienić');

select * from finish();
rollback;
