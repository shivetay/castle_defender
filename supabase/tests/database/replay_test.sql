-- Testy powtórki obrony (#29), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `launch_attack` zapisuje plan ataku (sprawdzony: po rozkazie na oddział, liczby w zakresach)
-- i badania atakującego z jego zamku na serwerze, a nie z żądania; ponowienie nie zmienia planu;
-- `attack_replay` oddaje dane zakończonej obrony tylko obrońcy; ataki bez zapisanego planu nie mają
-- powtórki; gracz nie woła funkcji sam i nie czyta badań atakującego.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(29);

-- A atakuje B, O to obcy gracz. Ranking w paśmie 61 000 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000029a1'), ('00000000-0000-0000-0000-0000000029b1'),
  ('00000000-0000-0000-0000-0000000029c1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 61000, age = 0 where id in (select id from test_ids);

insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 2929, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  -- A2 nie jest zbadane; G2 nie działa w bitwie
  'research', jsonb_build_object('done', '["A1", "A7", "G2", "O2"]'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
  'scout', jsonb_build_object('reports', '[]'::jsonb))
from test_ids t;

set local role service_role;
create temp table ok_plan (v jsonb) on commit drop;
insert into ok_plan values ('[
  {"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [[10, 12]], "start": 0, "start_value": 0, "retreat": 30, "flank_left": true},
  {"squad": 2, "manoeuvre": 3, "target": [36, 30], "waypoints": [], "start": 2, "start_value": 1, "retreat": 0, "flank_left": false}
]');

create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000029a1',
    '00000000-0000-0000-0000-0000000029b1', null, '[[0, 10], [0, 10]]', 31);

-- ---- zły plan: odrzucony, a atak zostaje niezatwierdzony ----
create temp table bad_plans (v jsonb, why text) on commit drop;
insert into bad_plans values
  ('{}', 'plan nie jest tablicą'),
  ('[]', 'pusty plan'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true},
    {"squad": 2, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true},
    {"squad": 3, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'więcej rozkazów niż oddziałów'),
  ('[{"squad": 3, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'oddział spoza armii'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true},
    {"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'dwa rozkazy dla jednego oddziału'),
  ('[{"squad": 1, "manoeuvre": 9, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'nieznany manewr'),
  ('[{"squad": 1, "manoeuvre": 0.5, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'ułamek'),
  ('[{"squad": "1", "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'liczba jako tekst'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, 5], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'cel w połowie pusty'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [[1, 1], [2, 2], [3, 3], [4, 4]], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'za dużo punktów trasy'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [[64, 1]], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    'punkt trasy poza mapą'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 101, "flank_left": true}]',
    'odwrót ponad 100 procent'),
  ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true, "loot": 9999}]',
    'nieznany klucz');
select is((select count(*)::int from bad_plans), 13, 'trzynaście złych planów');
create function pg_temp.launch_error(p jsonb) returns text language plpgsql as $$
begin
  perform * from public.launch_attack('00000000-0000-0000-0000-0000000029a1', (select attack_id from started), p);
  return 'ok';
exception when others then
  return sqlerrm;
end;
$$;
select is((select string_agg(why, ', ') from bad_plans where pg_temp.launch_error(v) <> 'bad_plan'), null,
  'każdy zły plan daje bad_plan');
select is((select launched_at from public.attacks where id = (select attack_id from started)), null,
  'zły plan nie zatwierdza ataku');

-- ---- zatwierdzenie: plan z żądania, badania z zamku na serwerze ----
create temp table l1 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000029a1', (select attack_id from started),
    (select v from ok_plan));
select is((select plan from l1), (select v from ok_plan), 'serwer oddaje zapisany plan');
select is((select techs from l1), array['A1', 'A7'], 'badania atakującego działające w bitwie, z jego zamku');
select is((select orders from public.attacks where id = (select attack_id from started)), (select v from ok_plan),
  'plan w attacks.orders');
select isnt((select launched_at from public.attacks where id = (select attack_id from started)), null,
  'atak zatwierdzony');
select ok((select not (castle ? 'scout') from l1), 'zamek obrońcy bez jego zwiadu');

-- ponowienie z innym planem: pierwszy zapis wygrywa
create temp table l2 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000029a1', (select attack_id from started),
    '[{"squad": 1, "manoeuvre": 2, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]');
select is((select plan from l2), (select v from ok_plan), 'ponowienie nie zmienia planu');
-- badania zmienione po zatwierdzeniu nie zmieniają powtórki
reset role;
update public.castles set data = jsonb_set(data, '{research,done}', '["A1", "A2", "A7"]')
where player_id = '00000000-0000-0000-0000-0000000029a1';
set local role service_role;
select is((select techs from public.launch_attack('00000000-0000-0000-0000-0000000029a1',
  (select attack_id from started), (select v from ok_plan))), array['A1', 'A7'], 'ponowienie: te same badania');

-- ---- powtórka: tylko zakończona obrona i tylko dla obrońcy ----
select throws_ok(format($$select * from public.attack_replay('00000000-0000-0000-0000-0000000029b1', %L)$$,
    (select attack_id from started)), 'P0001', 'attack_not_found', 'atak w toku nie ma powtórki');
select lives_ok(format($$select * from public.end_attack('00000000-0000-0000-0000-0000000029a1', %L,
    '{"won": false, "percent": 66, "stars": [false, true, false]}', '[0, 0, 0, 0]', '[4, 0]')$$,
    (select attack_id from started)), 'A kończy atak');

create temp table r1 on commit drop as
  select * from public.attack_replay('00000000-0000-0000-0000-0000000029b1', (select attack_id from started));
select is((select count(*)::int from r1), 1, 'obrońca dostaje powtórkę');
select is((select map_seed from r1), 2929::bigint, 'seed terenu obrońcy');
select is((select battle_seed from r1), 31::bigint, 'seed bitwy');
select is((select army from r1), '[[0, 10], [0, 10]]'::jsonb, 'armia ze startu');
select is((select plan from r1), (select v from ok_plan), 'plan z zatwierdzenia');
select is((select techs from r1), array['A1', 'A7'], 'badania atakującego z zatwierdzenia');
select is((select (result ->> 'percent')::int from r1), 66, 'wynik');
select ok((select castle ? 'grid' and not (castle ? 'scout') from r1), 'kopia zamku z chwili startu, bez zwiadu');
select throws_ok(format($$select * from public.attack_replay('00000000-0000-0000-0000-0000000029a1', %L)$$,
    (select attack_id from started)), 'P0001', 'attack_not_found', 'atakujący nie dostanie kopii obrony');
select throws_ok(format($$select * from public.attack_replay('00000000-0000-0000-0000-0000000029c1', %L)$$,
    (select attack_id from started)), 'P0001', 'attack_not_found', 'obcy gracz nie dostanie powtórki');

-- stara launch_attack (wdrożony klient przed #29) nadal działa
select ok(exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname = 'launch_attack' and p.pronargs = 2), 'stara launch_attack zostaje');
-- atak sprzed #29 (bez zapisanych badań) nie ma powtórki
reset role;
update public.attacks set attacker_techs = null where id = (select attack_id from started);
set local role service_role;
select throws_ok(format($$select * from public.attack_replay('00000000-0000-0000-0000-0000000029b1', %L)$$,
    (select attack_id from started)), 'P0001', 'replay_missing', 'stary atak bez powtórki');

-- ---- gracz nie woła funkcji sam i nie czyta badań atakującego ----
reset role;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000029b1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select * from public.attack_replay('00000000-0000-0000-0000-0000000029b1', gen_random_uuid())$$,
  '42501', null, 'gracz nie wywoła attack_replay');
select throws_ok($$select attacker_techs from public.attacks limit 1$$, '42501', null,
  'gracz nie czyta badań atakującego');
select throws_ok($$select private.check_plan('[]', 1)$$, '42501', null, 'gracz nie woła check_plan');
select throws_ok($$select * from public.launch_attack('00000000-0000-0000-0000-0000000029b1', gen_random_uuid())$$,
  '42501', null, 'gracz nie woła też starej launch_attack');
select is((select jsonb_array_length(orders) from public.attacks where defender_id = '00000000-0000-0000-0000-0000000029b1'),
  2, 'obrońca widzi plan ataku na siebie');

select * from finish();
rollback;
