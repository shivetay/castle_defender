-- Testy garnizonu Dworu przy starcie ataku (#81), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `begin_attack` nie liczy do wojska atakującego oddziałów, które w kopii zamku na serwerze
-- mają zadanie obrony Garnizon Dworu (GARRISON = 6); złe wpisy zadań nie robią garnizonu; odrzucony
-- start niczego nie zapisuje.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(7);

-- G = b1: Dwór 2 (20 miejsc), oddziały 1 i 2 po 10 toporników (topornik 0, je 1; produkcja 20 Ży/h),
-- oddział 1 w garnizonie. Z = b2: to samo, ale zadania obrony z błędami (zły typ, krótki wpis,
-- zadanie spoza listy, id jako tekst), więc bez garnizonu. B = b3: zapis bez zadań obrony.
-- Ranking w paśmie 80 000 (bez prawdziwych graczy), bo testy biegną też na projekcie w chmurze,
-- w transakcji, która się cofa.
create temp table garrison_ids (id uuid primary key) on commit drop;
insert into garrison_ids values
  ('00000000-0000-0000-0000-0000000000b1'), ('00000000-0000-0000-0000-0000000000b2'),
  ('00000000-0000-0000-0000-0000000000b3');
insert into auth.users (id) select id from garrison_ids;
update public.players set rating = 80000, age = 0 where id in (select id from garrison_ids);

-- „Zły zapis” to zamek sprzed #421 (dziś wyzwalacz castles_check_defense go odrzuca): begin_attack dalej
-- liczy złe wpisy jako brak garnizonu
alter table public.castles disable trigger castles_check_defense;
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000000b1', 31, 12, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Strzeżony'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 2, 30, 30, 4, 4]]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
    'defense', jsonb_build_object('orders', '[[1, 6, -1, -1, []], [2, 0, 30, 30, []]]'::jsonb))),
  ('00000000-0000-0000-0000-0000000000b2', 32, 12, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Zły zapis'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 2, 30, 30, 4, 4]]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
    'defense', jsonb_build_object('orders', '["zły", [1, 6], [2, 6.5, 0, 0, []], ["1", 6, 0, 0, []]]'::jsonb))),
  ('00000000-0000-0000-0000-0000000000b3', 33, 12, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Bez obrony'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 2, 30, 30, 4, 4]]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb)));
alter table public.castles enable trigger castles_check_defense;

set local role service_role;

-- ---- garnizon nie idzie do ataku ----
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000b1', null, 0::smallint, '[[0, 10], [0, 10]]', 1)$$,
  'P0001', 'army_not_owned', 'oddział z garnizonu nie idzie do ataku');
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000b1', null, 0::smallint, '[[0, 10], [0, 1]]', 1)$$,
  'P0001', 'army_not_owned', 'nawet jedna jednostka z garnizonu');
select is((select count(*)::int from public.attacks where attacker_id = '00000000-0000-0000-0000-0000000000b1'),
  0, 'odrzucony start niczego nie zapisuje');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000b1', null, 0::smallint, '[[0, 10]]', 1)$$,
  'oddział spoza garnizonu idzie do ataku');
select is((select attacker_army from public.attacks where attacker_id = '00000000-0000-0000-0000-0000000000b1'),
  '[[0, 10]]'::jsonb, 'zapisana armia bez garnizonu');

-- ---- złe wpisy zadań nie robią garnizonu ----
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000b2', null, 0::smallint, '[[0, 10], [0, 10]]', 1)$$,
  'złe wpisy zadań: cała armia idzie');

-- ---- bez zadań obrony jak dotąd ----
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000b3', null, 0::smallint, '[[0, 10], [0, 10]]', 1)$$,
  'zapis bez obrony: cała armia idzie');

reset role;
select * from finish();
rollback;
