-- Testy generała ataku (#31), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `launch_attack` z generałem bierze jego poziom i perk z zamku atakującego na serwerze,
-- a nie z żądania; zły rodzaj odrzuca; generał, którego atakujący nie ma, nie wchodzi do bitwy; ponowienie
-- nie zmienia generała; powtórka u obrońcy oddaje tego samego generała; gracz nie czyta kolumny
-- `attacker_general` i nie woła funkcji sam.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(17);

-- A atakuje B, O to obcy gracz. Ranking w paśmie 63 100 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000031a1'), ('00000000-0000-0000-0000-0000000031b1'),
  ('00000000-0000-0000-0000-0000000031c1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 63100, age = 0 where id in (select id from test_ids);

-- Pokrycie generałów (#31, `general_budget`): 10 zakończonych ataków A na gracza sprzed dwóch dni z łupem 200 złota
-- (2000 złota z PvP, 400 PD z PvP), więc wyzwalacz zapisu zamku zostawia Łowczego na poziomie 3 i Wodza.
-- Atak na gracza ma kopie zamku i obrony (attacks_player_target_snapshots), więc wstawiamy puste.
insert into public.attacks (attacker_id, defender_id, battle_seed, status, result, loot, started_at, finished_at,
  castle_snapshot, defense_snapshot)
select '00000000-0000-0000-0000-0000000031a1', '00000000-0000-0000-0000-0000000031c1', g, 'finished',
  '{"won": true, "percent": 60, "stars": [false, true, true]}', array[0, 0, 0, 200],
  now() - interval '2 days', now() - interval '2 days', '{}', '{}'
from generate_series(1, 10) g;

-- Łowczy (1) na poziomie 3 z Szybkim marszem; Wódz (0) z poziomem spoza MVP i perkiem poniżej poziomu 3
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 3131, 11, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 5, 36, 30, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'research', jsonb_build_object('done', '["A1"]'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
  'generals', jsonb_build_object('roster',
    '[{"kind": 1, "level": 3, "xp": 300, "perk": 0}, {"kind": 0, "level": 9, "perk": 1}, {"kind": 1, "level": 1}]'::jsonb,
    'attack', 1))
from test_ids t;

select is(private.castle_general((select data from public.castles where player_id = '00000000-0000-0000-0000-0000000031a1'), 1),
  '{"kind": 1, "level": 3, "perk": 0}'::jsonb, 'Łowczy z pierwszego wpisu, z perkiem');
select is(private.castle_general((select data from public.castles where player_id = '00000000-0000-0000-0000-0000000031a1'), 0),
  '{"kind": 0, "level": 1, "perk": -1}'::jsonb, 'poziom spoza MVP: 1, bez perka');
select is(private.castle_general((select data from public.castles where player_id = '00000000-0000-0000-0000-0000000031a1'), 2),
  null, 'generała, którego nie ma, nie ma w bitwie');
select is(private.castle_general('{"generals": {"roster": "x"}}', 1), null, 'zła lista generałów');
select is(private.castle_general('{"generals": {"roster": [{"kind": 1, "level": 3, "perk": 2}]}}', 1),
  '{"kind": 1, "level": 3, "perk": -1}'::jsonb, 'nieznany perk odpada');

set local role service_role;
create temp table ok_plan (v jsonb) on commit drop;
insert into ok_plan values ('[
  {"squad": 1, "manoeuvre": 3, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}
]');

create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000031a1',
    '00000000-0000-0000-0000-0000000031b1', null, '[[0, 10], [0, 10]]', 41);

-- ---- zły rodzaj generała: odrzucony, atak zostaje niezatwierdzony ----
select throws_ok(format($$select * from public.launch_attack('00000000-0000-0000-0000-0000000031a1', %L, %L, 3)$$,
    (select attack_id from started), (select v from ok_plan)), 'P0001', 'bad_general', 'rodzaj spoza gry');
select throws_ok(format($$select * from public.launch_attack('00000000-0000-0000-0000-0000000031a1', %L, %L, -1)$$,
    (select attack_id from started), (select v from ok_plan)), 'P0001', 'bad_general', 'ujemny rodzaj');
select is((select launched_at from public.attacks where id = (select attack_id from started)), null,
  'zły generał nie zatwierdza ataku');

-- ---- zatwierdzenie: generał z zamku na serwerze ----
create temp table l1 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000031a1', (select attack_id from started),
    (select v from ok_plan), 1);
select is((select general from l1), '{"kind": 1, "level": 3, "perk": 0}'::jsonb, 'generał z zamku atakującego');
select is((select attacker_general from public.attacks where id = (select attack_id from started)),
  '{"kind": 1, "level": 3, "perk": 0}'::jsonb, 'generał w attacks.attacker_general');
-- ponowienie z innym generałem i po zmianie zamku: pierwszy zapis wygrywa
reset role;
update public.castles set data = jsonb_set(data, '{generals,roster,0,perk}', '1')
where player_id = '00000000-0000-0000-0000-0000000031a1';
set local role service_role;
select is((select general from public.launch_attack('00000000-0000-0000-0000-0000000031a1',
  (select attack_id from started), (select v from ok_plan), 0)), '{"kind": 1, "level": 3, "perk": 0}'::jsonb,
  'ponowienie nie zmienia generała');

-- ---- powtórka u obrońcy z tym samym generałem ----
select lives_ok(format($$select * from public.end_attack('00000000-0000-0000-0000-0000000031a1', %L,
    '{"won": false, "percent": 10, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[5, 0]')$$,
    (select attack_id from started)), 'A kończy atak');
select is((select general from public.attack_replay('00000000-0000-0000-0000-0000000031b1', (select attack_id from started))),
  '{"kind": 1, "level": 3, "perk": 0}'::jsonb, 'powtórka z generałem ataku');

-- ---- bez generała: null ----
create temp table started2 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000031a1',
    '00000000-0000-0000-0000-0000000031c1', null, '[[0, 10], [0, 10]]', 42);
select is((select general from public.launch_attack('00000000-0000-0000-0000-0000000031a1',
  (select attack_id from started2), (select v from ok_plan), null)), null, 'atak bez generała');

-- ---- gracz nie woła funkcji sam i nie czyta generała ataku ----
reset role;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000031b1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select attacker_general from public.attacks limit 1$$, '42501', null,
  'gracz nie czyta generała ataku');
select throws_ok($$select private.castle_general('{}', 1)$$, '42501', null, 'gracz nie woła castle_general');
select throws_ok($$select * from public.launch_attack('00000000-0000-0000-0000-0000000031b1', gen_random_uuid(), '[]', 1)$$,
  '42501', null, 'gracz nie woła launch_attack z generałem');

select * from finish();
rollback;
