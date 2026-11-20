-- Testy Wozu łupowego (#235), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: Wóz w ataku podnosi max łup walidowany w `end_attack`, brak Wozu nie blokuje ataku
-- (tylko niższy limit), a Wozu, którego zamek nie ma, nie da się wziąć do ataku.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(9);

-- W = e1 (ma 2 wozy), V = e2 (bez wozów). Ranking w paśmie 70 000 (bez prawdziwych graczy), bo testy
-- biegną też na projekcie w chmurze, w transakcji, która się cofa.
create temp table wagon_ids (id uuid primary key) on commit drop;
insert into wagon_ids values
  ('00000000-0000-0000-0000-0000000000e1'), ('00000000-0000-0000-0000-0000000000e2');
insert into auth.users (id) select id from wagon_ids;
update public.players set rating = 70000, age = 0 where id in (select id from wagon_ids);

-- oddziały [id, rodzaj, liczba]: toporniki (0) po 10, Wóz to rodzaj 15
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000000e1', 11, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Tabor'),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 15, 2]]'::jsonb)));
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000000e2', 12, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Pieszo'),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10]]'::jsonb)));

set local role service_role;

-- tabela capacity i liczba rodzajów (UnitTypes.CARRY, UnitTypes.count())
select is(private.unit_count(), 16, '16 rodzajów jednostek');
select is(private.unit_carry(15), 50, 'Wóz unosi 50');
select is(private.unit_carry(0), 5, 'piechota dalej 5');

-- Wozu nie ma w zamku V: atak z wozem odrzucony, bez wozu przechodzi
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000e2', null, 0::smallint, '[[0, 10], [15, 1]]', 1)$$,
  'P0001', 'army_not_owned', 'Wozu spoza zamku nie da się wziąć do ataku');
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000e2', null, 0::smallint, '[[0, 10]]', 1)$$,
  'brak Wozu nie blokuje ataku');

-- W atakuje zamek-bota 0 (skarbiec 1000 drewna, kamienia, żywności): po wygranej ze 100 procentami
-- najwyżej 100 każdego. Capacity: 10 toporników × 5 + 2 wozy × 50 = 150, bez wozów 50.
create temp table w on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000000e1', null, 0::smallint,
    '[[0, 10], [15, 2]]', 3);
select is((select count(*)::int from w), 1, 'W zaczyna atak z wozami');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000e1', %L, '{"won": true, "percent": 100, "stars": [true, true, true]}', '[100, 50, 0, 0]', '[10, 0]')$$,
    (select attack_id from w)),
  'P0001', 'loot_too_high', 'bez ocalałych wozów limit 50');
select throws_ok(
  format($$select * from public.end_attack('00000000-0000-0000-0000-0000000000e1', %L, '{"won": true, "percent": 100, "stars": [true, true, true]}', '[100, 51, 0, 0]', '[10, 2]')$$,
    (select attack_id from w)),
  'P0001', 'loot_too_high', 'łup ponad capacity z wozami odrzucony');
select is(
  (select loot from public.end_attack('00000000-0000-0000-0000-0000000000e1', (select attack_id from w),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[100, 50, 0, 0]', '[10, 2]')),
  array[100, 50, 0, 0], 'ocalałe wozy podnoszą limit do 150');

reset role;
select * from finish();
rollback;
