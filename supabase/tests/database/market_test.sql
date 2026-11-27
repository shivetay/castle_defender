-- Testy Targu (#408, migracja `*_market.sql`), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: Targ (rodzaj 33) jest najwyżej jeden, tylko na poziomie 1, nic nie kosztuje i buduje się od razu;
-- gracz nie przeniesie ani nie usunie Targu z zapisu (market_moved), chyba że zaczyna od nowa (same budynki startu);
-- serwer pisze bez tej reguły. Te same rodzaje pilnuje `tests/test_market.gd`.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000408a1');

-- Zamek: Dwór 1, donżon, Chata drwala 1, Koszary 1 i Targ w prostokącie `p_market` ([x, y] albo null: bez Targu);
-- `p_start`: same budynki startu (nowa gra), bez Chaty i Koszar.
create function pg_temp.castle(p_market jsonb, p_start boolean default false) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings',
      '[[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2]]'::jsonb
      || case when p_start then '[]'::jsonb else '[[3, 4, 1, 10, 10, 2, 2], [4, 18, 1, 50, 50, 3, 3]]'::jsonb end
      || case when p_market is null then '[]'::jsonb
        else jsonb_build_array(jsonb_build_array(5, 33, 1, p_market -> 0, p_market -> 1, 4, 4)) end),
    'economy', jsonb_build_object('amounts', '[480, 300, 280, 50]'::jsonb),
    'research', jsonb_build_object('done', '[]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 13, 4]]'::jsonb, 'orders', '[]'::jsonb))
$$;
grant execute on function pg_temp.castle(jsonb, boolean) to authenticated, service_role;

create function pg_temp.push(p_data jsonb) returns void language sql as $$
  update public.castles set data = p_data where player_id = '00000000-0000-0000-0000-0000000408a1'
$$;
grant execute on function pg_temp.push(jsonb) to authenticated, service_role;

create function pg_temp.as_a() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000408a1", "role": "authenticated"}', true)
$$;

-- ---- reguły zapisu ----
select is(private.castle_buildings_problem(pg_temp.castle('[20, 20]')), null::text, 'jeden Targ na poziomie 1 przechodzi');
select is(private.castle_buildings_problem(jsonb_set(pg_temp.castle('[20, 20]'), '{grid,buildings,4,2}', '2')),
  'bad_building', 'Targ na poziomie 2 odrzucony (bez poziomów)');
select is(private.castle_buildings_problem(jsonb_set(pg_temp.castle('[20, 20]'), '{grid,buildings,4,2}', '0')),
  'bad_building', 'plac budowy Targu odrzucony (Targ stoi od startu)');
select is(private.castle_buildings_problem(jsonb_set(pg_temp.castle('[20, 20]'), '{grid,buildings}',
    (pg_temp.castle('[20, 20]') -> 'grid' -> 'buildings') || '[[6, 33, 1, 0, 0, 4, 4]]'::jsonb)),
  'bad_building', 'drugi Targ odrzucony');
select is(private.build_time_ms(33, 1), 0::bigint, 'Targ buduje się od razu');
select is(private.build_cost(33, 1), '{0, 0, 0, 0}'::bigint[], 'Targ nic nie kosztuje');
select ok(not private.locked_new_building('{}', pg_temp.castle('[20, 20]')), 'Targ nie wymaga technologii');

-- ---- gracz nie przenosi Targu ----
select pg_temp.as_a();
set local role authenticated;
insert into public.castles (player_id, map_seed, save_version, data)
values ('00000000-0000-0000-0000-0000000408a1', 1, 12, pg_temp.castle('[20, 20]'));
select lives_ok($$select pg_temp.push(pg_temp.castle('[20, 20]'))$$, 'Targ w tym samym miejscu przechodzi');
select throws_ok($$select pg_temp.push(pg_temp.castle('[24, 20]'))$$, 'PT422', 'market_moved',
  'przeniesiony Targ odrzucony');
select throws_ok($$select pg_temp.push(pg_temp.castle(null))$$, 'PT422', 'market_moved',
  'zapis bez Targu odrzucony (Targu nie da się rozebrać)');
select lives_ok($$select pg_temp.push(pg_temp.castle('[24, 20]', true))$$,
  'nowa gra (same budynki startu) stawia Targ od nowa');
select is((select data -> 'grid' -> 'buildings' -> 2 from public.castles
    where player_id = '00000000-0000-0000-0000-0000000408a1'), '[5, 33, 1, 24, 20, 4, 4]'::jsonb,
  'Targ nowej gry w zapisie');
reset role;

-- ---- serwer pisze stan zaufany ----
select set_config('request.jwt.claims', '', true);
select lives_ok($$select pg_temp.push(pg_temp.castle('[0, 0]'))$$, 'zapis serwera bez reguły Targu');

select * from finish();
rollback;
