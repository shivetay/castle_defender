-- Testy zabudowy w zapisie zamku (#274, etap 4), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: budynek wyżej niż Dwór, poziom spoza gry i Dwór epoki II bez technologii przejścia są
-- odrzucane (HTTP 422, SQLSTATE PT422) bez przycinania; gracz nie zapisze zabudowy szybciej, niż
-- zbudowałby ją jeden budowniczy od poprzedniego zapisu (zlecenie w toku i tolerancja się liczą);
-- uczciwe zapisy, także niższa zabudowa po nowej grze, przechodzą; serwer pisze bez limitu czasu;
-- zamek spoza reguł nie wchodzi do PvP; gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(30);

-- #282: bilans surowców ma własny test (`economy_growth_test.sql`). Zamki w tym teście nie mają zgodnego
-- bilansu, więc każdy zapis zamku dostaje kredyt bez limitu (przed wstawieniem i po każdym zapisie).
create function pg_temp.economy_free() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and tg_when = 'BEFORE' then
    new.economy_credit := '{1000000000, 1000000000, 1000000000, 1000000000}';
    return new;
  end if;
  perform set_config('session_replication_role', 'replica', true);
  update public.castles set economy_credit = '{1000000000, 1000000000, 1000000000, 1000000000}',
    hide_credit = '{1000000000, 1000000000, 1000000000, 1000000000}' where player_id = new.player_id;
  perform set_config('session_replication_role', 'origin', true);
  return null;
end;
$$;
create trigger castles_economy_free before insert on public.castles
  for each row execute function pg_temp.economy_free();
create trigger castles_economy_free_after after insert or update of data on public.castles
  for each row execute function pg_temp.economy_free();

create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values ('00000000-0000-0000-0000-0000000274d1'), ('00000000-0000-0000-0000-0000000274e1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 62750, age = 0 where id in (select id from test_ids);

-- Zamek z budynkami `p_buildings` ([id, rodzaj, poziom, x, y, szer., wys.]) i opcjonalnie kolejką i badaniami.
create function pg_temp.castle(p_buildings jsonb, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', p_buildings),
    'economy', jsonb_build_object('amounts', '[0, 0, 0, 0]'::jsonb),
    -- toporników szkolą Koszary (#281): zamek gracza bez Koszar nie ma wojska
    'recruitment', jsonb_build_object('squads', '[]'::jsonb)) || p_extra
$$;
grant execute on function pg_temp.castle(jsonb, jsonb) to authenticated;

-- Poprzedni zapis zamku `p_player` sprzed `p_ago` (zegar serwera): bump_revision ustawia updated_at na teraz.
create function pg_temp.age_castle(p_player uuid, p_ago interval) returns void language plpgsql as $$
begin
  alter table public.castles disable trigger castles_bump_revision;
  update public.castles set updated_at = now() - p_ago where player_id = p_player;
  alter table public.castles enable trigger castles_bump_revision;
end;
$$;

-- ---- reguły poziomów (każdy zapis, także serwera) ----
select is(private.build_time_ms(3, 1), 60000::bigint, 'Wieża 1: 60 s');
select is(private.build_time_ms(3, 5), 5400000::bigint, 'Wieża 5: 90 min');
select is(private.build_time_ms(3, 6), 120000::bigint, 'Wieża 6 (epoka II, poziom 1): ×2');
select is(private.build_time_ms(5, 5), 43200000::bigint, 'Dwór 5: 12 h');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 3, 0, 0, 4, 4], [2, 3, 3, 9, 9, 2, 2]]')), null,
  'Wieża na poziomie Dworu');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 3, 0, 0, 4, 4], [2, 18, 4, 9, 9, 3, 3]]')),
  'building_over_manor', 'Koszary wyżej niż Dwór');
select is(private.castle_buildings_problem(pg_temp.castle('[[2, 3, 2, 9, 9, 2, 2]]')), 'building_over_manor',
  'bez Dworu liczy się poziom 1');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 3, 0, 0, 4, 4], [2, 21, 2, 9, 9, 2, 2]]')),
  'building_over_manor', 'donżon nie ma poziomów');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 3, 0, 0, 4, 4], [5, 5, 9, 9, 9, 4, 4]]')),
  'building_over_manor', 'drugi Dwór nie podnosi pierwszego');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 11, 0, 0, 4, 4]]')), 'bad_building',
  'poziom spoza gry');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 6, 0, 0, 4, 4]]', '{"research": {"done": ["O1", "G1"]}}')),
  'age_locked', 'epoka II bez A7');
select is(private.castle_buildings_problem(pg_temp.castle('[[1, 5, 6, 0, 0, 4, 4], [2, 3, 6, 9, 9, 2, 2]]',
    '{"research": {"done": ["O1", "G1", "A7"]}}')), null, 'epoka II z technologiami przejścia');
select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000274e1', 2750, 12, pg_temp.castle('[[1, 5, 5, 0, 0, 4, 4]]'))$$,
  'serwer zakłada zamek bez limitu czasu');

-- ---- gracz D: czas jednego budowniczego ----
-- Zapis jak z telefonu (PATCH): budynki `p_b` i opcjonalnie kolejka/badania w `p_extra`.
create function pg_temp.push(p_b jsonb, p_extra jsonb default '{}') returns void language sql as $$
  update public.castles set data = pg_temp.castle(p_b, p_extra) where player_id = '00000000-0000-0000-0000-0000000274d1'
$$;
grant execute on function pg_temp.push(jsonb, jsonb) to authenticated;
-- Gracz D z tokenem (limit czasu działa tylko dla zapisów gracza).
create function pg_temp.as_d() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000274d1", "role": "authenticated"}', true)
$$;

set local role authenticated;
select pg_temp.as_d();

select throws_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000274d1', 2751, 12, pg_temp.castle('[[1, 5, 5, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2]]'))$$,
  'PT422', 'build_too_fast', 'nowe konto nie założy Dworu 5 (17 h budowy)');
select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000274d1', 2751, 12,
      pg_temp.castle('[[1, 5, 1, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]'))$$,
  'nowe konto: Dwór i donżon za darmo, Wieża 1 w zapasie gry bez sieci');
select throws_ok(
  $$select pg_temp.push('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]')$$,
  'PT422', 'build_too_fast', 'Dwór 2 (10 min) zaraz po poprzednim zapisie odrzucony');
select is((select data -> 'grid' -> 'buildings' -> 0 ->> 2 from public.castles), '1', 'odrzucony zapis niczego nie zmienił');
-- review #279: zlecenie wpisane do zapisu nie daje czasu samo z siebie
select lives_ok(
  $$select pg_temp.push('[[1, 5, 1, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]',
    '{"queue": {"orders": [{"building_id": 1, "level": 2}]}}')$$,
  'zapis ze zleceniem Dworu 2 przechodzi');
select throws_ok(
  $$select pg_temp.push('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]')$$,
  'PT422', 'build_too_fast', 'fikcyjne zlecenie nie skraca budowy');
reset role;
select set_config('request.jwt.claims', '', true);  -- serwer przestawia czas poprzedniego zapisu
select pg_temp.age_castle('00000000-0000-0000-0000-0000000274d1', interval '20 minutes');
set local role authenticated;
select pg_temp.as_d();
-- 20 minut pracy nad Dworem 2 przed zapisem: kredyt najwyżej czas tego zlecenia (10 min)
select lives_ok(
  $$select pg_temp.push('[[1, 5, 1, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]',
    '{"queue": {"orders": [{"building_id": 1, "level": 2}]}}')$$,
  'zapis w trakcie budowy Dworu 2');
select is((select build_credit_ms from public.castles), 600000::bigint, 'kredyt: czas zlecenia w toku');
select lives_ok(
  $$select pg_temp.push('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]')$$,
  'Dwór 2 kończy się zaraz po zapisie: praca sprzed zapisu z kredytu');
-- tolerancja 5 minut jest łączna, nie na każdy zapis: Wieża 1 to 54 s, piąta mieści się, szósta już nie
do $$
begin
  perform pg_temp.push(('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]'
    || (select string_agg(format(', [%s, 3, 1, %s, 20, 2, 2]', 10 + i, 2 * i), '') from generate_series(1, n) i)
    || ']')::jsonb) from generate_series(1, 5) n;
end;
$$;
select is((select build_credit_ms from public.castles), (-5 * 54000)::bigint, 'pięć Wież na kredyt z tolerancji');
select throws_ok(
  $$select pg_temp.push(('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]'
    || (select string_agg(format(', [%s, 3, 1, %s, 20, 2, 2]', 10 + i, 2 * i), '') from generate_series(1, 6) i)
    || ']')::jsonb)$$,
  'PT422', 'build_too_fast', 'szósta Wieża ponad łączną tolerancję odrzucona');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.age_castle('00000000-0000-0000-0000-0000000274d1', interval '20 minutes');
set local role authenticated;
select pg_temp.as_d();
-- nowy Rybak (rodzaj 16) wymaga G21 (BuildConfig.REQUIRED_TECH); id i rodzaj z poprzedniego zapisu już nie
select throws_ok(
  $$select pg_temp.push('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2], [30, 16, 0, 30, 30, 2, 2]]')$$,
  'PT422', 'building_locked', 'nowy Rybak bez G21 odrzucony');
select lives_ok(
  $$select pg_temp.push('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2], [30, 16, 1, 30, 30, 2, 2]]',
    '{"research": {"done": ["G21"]}}')$$,
  'Rybak z G21 przechodzi');
select lives_ok(
  $$select pg_temp.push('[[1, 5, 1, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2]]')$$,
  'niższa zabudowa (nowa gra) przechodzi');
select throws_ok($$select private.build_need_ms('{}', '{}')$$, '42501', null, 'gracz nie woła funkcji serwera');
select throws_ok($$update public.castles set build_credit_ms = 999999999$$, '42501', null, 'gracz nie ustawia kredytu');
reset role;
select set_config('request.jwt.claims', '', true);

-- ---- zamek spoza reguł (zapis sprzed migracji) nie wchodzi do PvP ----
-- wyzwalacz surowców też sprawdza poziomy (castle_resources_problem), więc oba są wyłączone
alter table public.castles disable trigger castles_check_buildings;
alter table public.castles disable trigger castles_resources;
update public.castles set data = pg_temp.castle('[[1, 5, 1, 0, 0, 4, 4], [2, 18, 5, 9, 9, 3, 3]]')
where player_id = '00000000-0000-0000-0000-0000000274d1';
alter table public.castles enable trigger castles_resources;
alter table public.castles enable trigger castles_check_buildings;
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000274d1', null, 0::smallint, '[[0, 10]]', 9)$$,
  'P0001', 'castle_invalid', 'Koszary wyżej niż Dwór nie podnoszą limitu armii w PvP');

select * from finish();
rollback;
