-- Testy G4 Kamieniarstwo w epoce I (#315, migracja `*_quarry_age_one.sql`), uruchamiane przez
-- `supabase test db` (pgTAP). Kryteria: drzewko serwera ma G4 w epoce I z wymaganiem G1, zamek z epoki I
-- z G1 i G4 przechodzi walidację badań, G4 bez G1 nie, G6 (epoka II) w zamku z epoki I nadal nie,
-- a gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(6);

-- Zamek z epoki I (Dwór 3) z technologiami `p_techs`.
create function pg_temp.castle(p_techs jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2]]'::jsonb),
    'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 0)),
    'research', jsonb_build_object('done', p_techs),
    'recruitment', jsonb_build_object('squads', '[]'::jsonb))
$$;

select is(private.tech_tree() -> 'G4', '[0, ["G1"]]'::jsonb, 'G4 w epoce I wymaga G1');
select is(private.tech_tree() -> 'G6', '[1, ["G4"]]'::jsonb, 'G6 zostaje w epoce II');
select is(private.castle_research_problem(pg_temp.castle('["G1", "G4"]')), null,
  'zamek z epoki I z G1 i G4 przechodzi walidację badań');
select isnt(private.castle_research_problem(pg_temp.castle('["G4"]')), null, 'G4 bez G1 odrzucone');
select isnt(private.castle_research_problem(pg_temp.castle('["G1", "G4", "G6"]')), null,
  'G6 z epoki II w zamku z epoki I odrzucone');

set local role authenticated;
select throws_ok($$select private.tech_tree()$$, '42501', null, 'gracz nie woła funkcji serwera');
reset role;

select * from finish();
rollback;
