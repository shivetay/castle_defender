-- Testy poziomów doktryn (migracja `*_doctrine_levels.sql`), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: poziom z `research.levels` tylko dla zbadanej G1/G2, od 2 do limitu epoki (I: 3), każdy
-- poziom kosztuje krok doktryny i stały czas epoki, premia G1/G2 rośnie o 5 punktów za poziom w produkcji
-- i limicie utrzymania, zły poziom w zapisie jest odrzucony, a gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000330a1');
update public.players set rating = 63300, age = 0 where id = '00000000-0000-0000-0000-0000000330a1';

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
  update public.castles set data = pg_temp.castle(p_amounts, p_extra) where player_id = '00000000-0000-0000-0000-0000000330a1'
$$;
grant execute on function pg_temp.push(jsonb, jsonb) to authenticated;

create function pg_temp.age_castle(p_ago interval) returns void language plpgsql as $$
begin
  alter table public.castles disable trigger castles_bump_revision;
  update public.castles set updated_at = now() - p_ago where player_id = '00000000-0000-0000-0000-0000000330a1';
  alter table public.castles enable trigger castles_bump_revision;
end;
$$;

create function pg_temp.r(p_research jsonb) returns jsonb language sql as $$
  select jsonb_build_object('research', p_research)
$$;

-- ---- poziom w zapisie ----
select is(private.tech_level(pg_temp.r('{"done": []}'), 'G1'), 0, 'niezbadana: poziom 0');
select is(private.tech_level(pg_temp.r('{"done": ["G1"]}'), 'G1'), 1, 'zbadana: poziom 1');
select is(private.tech_level(pg_temp.r('{"done": ["G1"], "levels": {"G1": 3}}'), 'G1'), 3, 'poziom z levels');
select is(private.tech_level(pg_temp.r('{"done": ["A39"], "levels": {"A39": 3}}'), 'A39'), 1,
  'technologia bez poziomów: zawsze 1');
select is(private.doctrine_max_level(0), 3, 'epoka I: 3 poziomy');
select is(private.doctrine_max_level(1), 5, 'epoka II: 5 poziomów');

-- ---- koszt i czas ----
select is(private.research_spend(pg_temp.r('{"done": ["G1"]}'), pg_temp.r('{"done": ["G1"], "levels": {"G1": 2}}')),
  '{160, 80, 80, 0}'::bigint[], 'poziom 2 G1: krok 1 (×1,6)');
select is(private.research_spend(pg_temp.r('{"done": []}'), pg_temp.r('{"done": ["G1"], "levels": {"G1": 3}}')),
  '{516, 258, 258, 0}'::bigint[], 'G1 od zera do poziomu 3: kroki 0, 1 i 2');
select is(private.research_spend(pg_temp.r('{"done": ["G1"], "levels": {"G1": 2}}'), pg_temp.r('{"done": ["G1", "G2"], "levels": {"G1": 2}}')),
  '{256, 128, 128, 0}'::bigint[], 'G2 po dwóch poziomach G1: krok 2');
select is(private.research_spend(pg_temp.r('{"done": ["G1"]}'), pg_temp.r('{"done": ["G1"], "active": {"code": "G1"}}')),
  '{160, 80, 80, 0}'::bigint[], 'poziom w toku jest opłacony przy starcie');
select is(private.research_spend(pg_temp.r('{"done": ["G1"], "active": {"code": "G1"}}'), pg_temp.r('{"done": ["G1"], "levels": {"G1": 2}}')),
  '{0, 0, 0, 0}'::bigint[], 'koniec opłaconego poziomu bez drugiej opłaty');
select is(private.research_spend(pg_temp.r('{"done": ["A39"]}'), pg_temp.r('{"done": ["A39"], "active": {"code": "A39"}}')),
  '{0, 0, 0, 0}'::bigint[], 'zwykła technologia w toku po zbadaniu nie kosztuje drugi raz');
select is(private.research_level_need_ms(pg_temp.r('{"done": ["G1"]}'), pg_temp.r('{"done": ["G1"], "levels": {"G1": 3}}')),
  120000::numeric, 'dwa poziomy G1: 2 × 60 s');
select is(private.research_level_need_ms(pg_temp.r('{"done": []}'), pg_temp.r('{"done": ["G1"], "levels": {"G1": 2}}')),
  60000::numeric, 'nowa G1 z poziomem 2: pierwszy poziom liczy research_need_ms, drugi 60 s');
select is(private.research_head_ms(pg_temp.r('{"done": ["G1"], "active": {"code": "G1"}}')), 60000::bigint,
  'poziom w toku: kredyt czasu 60 s');

-- ---- produkcja i limit utrzymania ----
select is(private.food_production(pg_temp.r('{"done": ["G2"], "levels": {"G2": 3}}')), 25,
  'gród 20 żywności z G2 poziom 3 (+25%)');
select is((private.production_max(pg_temp.castle('[0, 0, 0, 0]', pg_temp.r('{"done": ["G1"]}')),
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.r('{"done": ["G1"], "levels": {"G1": 3}}'))))[1], 104::bigint,
  'drewno 80 na godzinę z G1 poziom 3 (+30%), wyższy poziom z dwóch zapisów');

-- ---- walidacja zapisu ----
select is(private.castle_research_problem(pg_temp.r('{"done": ["G1"], "levels": {"G1": 3}}')), null, 'poziom 3 w epoce I');
select is(private.castle_research_problem(pg_temp.r('{"done": ["G1"], "levels": {"G1": 4}}')), 'bad_research_level',
  'poziom 4 w epoce I odrzucony');
select is(private.castle_research_problem(pg_temp.r('{"done": ["A39"], "levels": {"A39": 2}}')), 'bad_research_level',
  'poziom technologii bez poziomów odrzucony');
select is(private.castle_research_problem(pg_temp.r('{"done": [], "levels": {"G1": 2}}')), 'bad_research_level',
  'poziom niezbadanej doktryny odrzucony');
select is(private.castle_research_problem(pg_temp.r('{"done": ["G1"], "levels": {"G1": 3}, "active": {"code": "G1"}}')),
  'bad_research_level', 'badanie ponad najwyższy poziom epoki odrzucone');

-- ---- zapis zamku ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000330a1", "role": "authenticated"}', true);
select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000330a1', 3301, 12, pg_temp.castle('[60, 150, 100, 50]',
      '{"research": {"done": ["G1"], "levels": {"G1": 2}}}'))$$,
  'nowe konto: G1 poziom 2 po kosztach 100/50/50 i 160/80/80');
reset role;
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select throws_ok($$select pg_temp.push('[60, 150, 100, 50]', '{"research": {"done": ["G1"], "levels": {"G1": 3}}}')$$,
  'PT422', 'economy_too_fast', 'poziom 3 bez kosztu odrzucony');
select throws_ok($$select pg_temp.push('[60, 150, 100, 50]', '{"research": {"done": ["G1"], "levels": {"G1": 4}}}')$$,
  'PT422', 'bad_research_level', 'poziom ponad limit epoki odrzucony');
reset role;
select pg_temp.age_castle(interval '3 hours');
set local role authenticated;
select lives_ok($$select pg_temp.push('[50, 80, 30, 50]', '{"research": {"done": ["G1"], "levels": {"G1": 3}}}')$$,
  'poziom 3 z kosztem 256/128/128 po 3 godzinach produkcji');
reset role;

-- ---- uprawnienia ----
set local role authenticated;
select throws_ok($$select private.tech_level('{}'::jsonb, 'G1')$$, '42501', null, 'gracz nie woła tech_level');
reset role;

select * from finish();
rollback;
