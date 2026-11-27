-- Testy O25 Wysunięte straże (#342, migracja `*_defense_reach.sql`), uruchamiane przez `supabase test db`
-- (pgTAP). Kryteria: drzewko serwera zna O25 (epoka I, bez wymagań), O25 jest doktryną z poziomami,
-- zamek z epoki I z O25 na poziomie 3 przechodzi walidację badań, poziom 4 w epoce I nie, a gracz nie woła
-- funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

-- Zamek z epoki I (Dwór 3) z technologiami `p_techs` i poziomami `p_levels`.
create function pg_temp.castle(p_techs jsonb, p_levels jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2]]'::jsonb),
    'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 0)),
    'research', jsonb_build_object('done', p_techs, 'levels', p_levels),
    'recruitment', jsonb_build_object('squads', '[]'::jsonb))
$$;

select is(private.tech_tree() -> 'O25', '[0, []]'::jsonb, 'O25 w epoce I bez wymagań');
select ok('O25' = any (private.research_doctrines()), 'O25 drożeje jak doktryny');
select ok('O25' = any (private.research_leveled()), 'O25 ma poziomy');
select ok(private.research_leveled() @> array['A1', 'A2', 'G1', 'G2'], 'dawne doktryny z poziomami zostają');
select is(private.castle_research_problem(pg_temp.castle('["O25"]', '{"O25": 3}')), null,
  'O25 poziom 3 w epoce I przechodzi walidację');
select is(private.castle_research_problem(pg_temp.castle('["O25"]', '{"O25": 4}')), 'bad_research_level',
  'O25 poziom 4 w epoce I odrzucony');
select is(private.tech_level(pg_temp.castle('["O25"]', '{"O25": 2}'), 'O25'), 2, 'poziom O25 z zapisu');

set local role authenticated;
select throws_ok($$select private.research_leveled()$$, '42501', null, 'gracz nie woła funkcji serwera');
reset role;

select * from finish();
rollback;
