-- Testy stałego kosztu technologii (migracja `*_research_fixed_cost.sql`), uruchamiane przez
-- `supabase test db` (pgTAP). Kryteria: zwykła technologia kosztuje stały koszt epoki, doktryny
-- (A1, A2, G1, G2) drożeją ×1,6 z każdą wcześniejszą doktryną tej samej epoki, badanie w toku też się
-- liczy, uczciwy zapis z kilkoma zwykłymi technologiami przechodzi, zaniżony koszt doktryn nie,
-- a gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000320a1');
update public.players set rating = 63200, age = 0 where id = '00000000-0000-0000-0000-0000000320a1';

-- Zamek jak w economy_growth_test: Dwór 1, donżon, Chata drwala 1 i Koszary 1, zapasy `p_amounts`.
create function pg_temp.castle(p_amounts jsonb, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings',
      '[[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2], [3, 4, 1, 10, 10, 2, 2], [4, 18, 1, 50, 50, 3, 3]]'::jsonb),
    'economy', jsonb_build_object('amounts', p_amounts),
    'research', jsonb_build_object('done', '[]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[]'::jsonb, 'orders', '[]'::jsonb)) || p_extra
$$;
grant execute on function pg_temp.castle(jsonb, jsonb) to authenticated;

create function pg_temp.push(p_amounts jsonb, p_extra jsonb default '{}') returns void language sql as $$
  update public.castles set data = pg_temp.castle(p_amounts, p_extra) where player_id = '00000000-0000-0000-0000-0000000320a1'
$$;
grant execute on function pg_temp.push(jsonb, jsonb) to authenticated;

create function pg_temp.age_castle(p_ago interval) returns void language plpgsql as $$
begin
  alter table public.castles disable trigger castles_bump_revision;
  update public.castles set updated_at = now() - p_ago where player_id = '00000000-0000-0000-0000-0000000320a1';
  alter table public.castles enable trigger castles_bump_revision;
end;
$$;

create function pg_temp.r(p_research jsonb) returns jsonb language sql as $$
  select jsonb_build_object('research', p_research)
$$;

-- ---- wzór kosztu ----
select is(private.research_spend(pg_temp.r('{"done": []}'), pg_temp.r('{"done": ["A39", "G18", "G21"]}')),
  '{300, 150, 150, 0}'::bigint[], 'trzy zwykłe technologie epoki I: 3 × koszt bazowy');
select is(private.research_spend(pg_temp.r('{"done": []}'), pg_temp.r('{"done": ["A1", "A2"]}')),
  '{260, 130, 130, 0}'::bigint[], 'dwie doktryny: baza i ×1,6');
select is(private.research_spend(pg_temp.r('{"done": ["A39", "G18", "A1"]}'), pg_temp.r('{"done": ["A39", "G18", "A1", "A2", "G19"]}')),
  '{260, 130, 130, 0}'::bigint[], 'druga doktryna po jednej starej (×1,6) i zwykła technologia po bazie');
select is(private.research_spend(pg_temp.r('{"done": ["A1"]}'), pg_temp.r('{"done": ["A1"], "active": {"code": "G2"}}')),
  '{160, 80, 80, 0}'::bigint[], 'doktryna w toku kosztuje krok po zbadanych doktrynach');
select is(private.research_spend(pg_temp.r('{"done": ["A39", "A1", "G18", "A2", "G1", "G19", "G2"]}'),
    pg_temp.r('{"done": ["A39", "A1", "G18", "A2", "G1", "G19", "G2"]}')),
  '{0, 0, 0, 0}'::bigint[], 'bez nowych technologii bez wydatku');
select is(private.research_spend(pg_temp.r('{"done": []}'), pg_temp.r('{"done": ["A39", "A1", "G18", "A2", "G1", "G19", "G2"]}')),
  '{1225, 612, 612, 0}'::bigint[], 'jak w teście gry: 3 zwykłe i 4 doktryny (kroki 0..3)');
select is(private.research_spend(pg_temp.r('{"done": ["A1", "A2", "G1", "G2"]}'), pg_temp.r('{"done": ["A1", "A2", "G1", "G2", "A39"]}')),
  '{100, 50, 50, 0}'::bigint[], 'zwykła technologia po wszystkich doktrynach: nadal baza');

-- ---- zapis zamku ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000320a1", "role": "authenticated"}', true);
select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000320a1', 3201, 12, pg_temp.castle('[320, 280, 230, 50]'))$$,
  'nowe konto');
reset role;
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select lives_ok($$select pg_temp.push('[120, 180, 130, 50]', '{"research": {"done": ["A1", "A39"]}}')$$,
  'doktryna i zwykła technologia po 100/50/50 każda przechodzą (wcześniej serwer liczył drugą ×1,6)');
reset role;
-- 3 godziny produkcji: 240 drewna, 60 kamienia i 60 żywności (A2 ×1,6 to 160/80/80, po bazie byłoby 100/50/50)
select pg_temp.age_castle(interval '3 hours');
set local role authenticated;
select throws_ok($$select pg_temp.push('[240, 175, 125, 50]', '{"research": {"done": ["A1", "A39", "A2"]}}')$$,
  'PT422', 'economy_too_fast', 'druga doktryna po koszcie bazowym odrzucona (to krok ×1,6)');
select lives_ok($$select pg_temp.push('[150, 120, 80, 50]', '{"research": {"done": ["A1", "A39", "A2"]}}')$$,
  'druga doktryna z kosztem ×1,6 przechodzi');
reset role;

-- ---- uprawnienia ----
set local role authenticated;
select throws_ok($$select private.research_doctrines()$$, '42501', null, 'gracz nie woła research_doctrines');
reset role;

select * from finish();
rollback;
