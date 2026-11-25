-- Testy poziomów doktryn ataku (migracja `*_attack_doctrine_levels.sql`), uruchamiane przez
-- `supabase test db` (pgTAP). Kryteria: A1 i A2 mają poziomy jak G1 i G2 (walidacja zapisu, koszt),
-- `launch_attack` oddaje poziomy atakującego z jego zamku na serwerze jako „A1:3”, kolumna
-- `attacker_techs` przyjmuje tylko znane wpisy, a gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

create function pg_temp.r(p_research jsonb) returns jsonb language sql as $$
  select jsonb_build_object('research', p_research)
$$;

-- ---- A1 i A2 z poziomami ----
select ok('A1' = any (private.research_leveled()) and 'A2' = any (private.research_leveled()), 'A1 i A2 mają poziomy');
select is(private.castle_research_problem(pg_temp.r('{"done": ["A1"], "levels": {"A1": 3}}')), null, 'A1 poziom 3 w epoce I');
select is(private.castle_research_problem(pg_temp.r('{"done": ["A1"], "levels": {"A1": 4}}')), 'bad_research_level',
  'A1 poziom 4 w epoce I odrzucony');
select is(private.research_spend(pg_temp.r('{"done": ["A1"]}'), pg_temp.r('{"done": ["A1"], "levels": {"A1": 2}}')),
  '{160, 80, 80, 0}'::bigint[], 'poziom 2 A1: krok doktryny ×1,6');

-- ---- launch_attack (wersja Edge Function, z generałem i wersją symulacji) oddaje poziomy z zamku na serwerze ----
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values ('00000000-0000-0000-0000-0000000334a1'), ('00000000-0000-0000-0000-0000000334b1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 61340, age = 0 where id in (select id from test_ids);

insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 3340, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'research', jsonb_build_object('done', '["A1", "A2", "G2"]'::jsonb, 'levels', '{"A1": 3, "A2": 2, "G2": 2}'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
  'scout', jsonb_build_object('reports', '[]'::jsonb))
from test_ids t;

set local role service_role;
create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000334a1',
    '00000000-0000-0000-0000-0000000334b1', null, '[[0, 10], [0, 10]]', 31);
create temp table launched on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000334a1', (select attack_id from started),
    '[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    null::integer, null::integer);
select is((select techs from launched), array['A1', 'A2', 'A1:3', 'A2:2'],
  'techs: zbadane A1 i A2 oraz ich poziomy, bez G2 (nie działa w bitwie)');
select is((select attacker_techs from public.attacks where id = (select attack_id from started)),
  array['A1', 'A2', 'A1:3', 'A2:2'], 'poziomy zapisane w ataku do powtórki i weryfikacji');
reset role;

-- ---- kolumna przyjmuje tylko znane wpisy ----
select throws_ok(format($$update public.attacks set attacker_techs = array['A1', 'A1:9'] where id = %L$$,
    (select attack_id from started)), '23514', null, 'poziom spoza 2..5 odrzucony');
select throws_ok(format($$update public.attacks set attacker_techs = array['G1:2'] where id = %L$$,
    (select attack_id from started)), '23514', null, 'poziom doktryny spoza bitwy odrzucony');
select lives_ok(format($$update public.attacks set attacker_techs = array['A1', 'A2', 'A7', 'A1:5', 'A2:5'] where id = %L$$,
    (select attack_id from started)), 'pełny zestaw: 3 kody i 2 poziomy');

-- ---- uprawnienia ----
grant select on started to authenticated;
set local role authenticated;
select throws_ok($$select private.research_leveled()$$, '42501', null, 'gracz nie woła research_leveled');
select throws_ok(format($$select * from public.launch_attack('00000000-0000-0000-0000-0000000334a1', %L, '[]', null, null)$$,
    (select attack_id from started)), '42501', null, 'gracz nie woła launch_attack');
reset role;

select * from finish();
rollback;
