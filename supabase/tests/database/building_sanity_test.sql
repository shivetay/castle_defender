-- Testy zabudowy w zapisie zamku (#274, etap 4), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: budynek wyżej niż Dwór, poziom spoza gry i Dwór epoki II bez technologii przejścia są
-- odrzucane (HTTP 422, SQLSTATE PT422) bez przycinania; gracz nie zapisze zabudowy szybciej, niż
-- zbudowałby ją jeden budowniczy od poprzedniego zapisu (zlecenie w toku i tolerancja się liczą);
-- uczciwe zapisy, także niższa zabudowa po nowej grze, przechodzą; serwer pisze bez limitu czasu;
-- zamek spoza reguł nie wchodzi do PvP; gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(23);

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
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10]]'::jsonb)) || p_extra
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
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000274d1", "role": "authenticated"}', true);

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
  $$update public.castles set data = pg_temp.castle('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]')
    where player_id = '00000000-0000-0000-0000-0000000274d1'$$,
  'PT422', 'build_too_fast', 'Dwór 2 (10 min) zaraz po poprzednim zapisie odrzucony');
select is((select data -> 'grid' -> 'buildings' -> 0 ->> 2 from public.castles), '1', 'odrzucony zapis niczego nie zmienił');
reset role;
select set_config('request.jwt.claims', '', true);  -- serwer przestawia czas poprzedniego zapisu
-- przy poprzednim zapisie Dwór 2 był w toku: jego czas się liczy, choć od zapisu nic nie minęło
update public.castles set data = data || '{"queue": {"orders": [{"building_id": 1, "level": 2}]}}'
where player_id = '00000000-0000-0000-0000-0000000274d1';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000274d1", "role": "authenticated"}', true);
select lives_ok(
  $$update public.castles set data = pg_temp.castle('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [3, 3, 1, 12, 9, 2, 2]]')
    where player_id = '00000000-0000-0000-0000-0000000274d1'$$,
  'zlecenie w toku przy poprzednim zapisie kończy się zaraz po nim');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.age_castle('00000000-0000-0000-0000-0000000274d1', interval '20 minutes');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000274d1", "role": "authenticated"}', true);
-- nowa Wieża 2 to 60 + 180 s, a Chata drwala 2 na id 3 (inny rodzaj nie dziedziczy poziomu Wieży) 45 + 135 s
select lives_ok(
  $$update public.castles set data = pg_temp.castle('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [4, 3, 2, 12, 9, 2, 2],
      [3, 4, 2, 15, 9, 2, 2]]')
    where player_id = '00000000-0000-0000-0000-0000000274d1'$$,
  '20 minut wystarcza na Wieżę 2 i Chatę drwala 2');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[[1, 5, 2, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2], [4, 3, 2, 12, 9, 2, 2],
      [3, 4, 2, 15, 9, 2, 2], [6, 3, 2, 18, 9, 2, 2], [7, 3, 2, 21, 9, 2, 2], [8, 3, 2, 24, 9, 2, 2]]')
    where player_id = '00000000-0000-0000-0000-0000000274d1'$$,
  'PT422', 'build_too_fast', 'trzy nowe Wieże 2 (12 min) zaraz po zapisie odrzucone');
select lives_ok(
  $$update public.castles set data = pg_temp.castle('[[1, 5, 1, 0, 0, 4, 4], [2, 21, 1, 9, 9, 2, 2]]')
    where player_id = '00000000-0000-0000-0000-0000000274d1'$$,
  'niższa zabudowa (nowa gra) przechodzi');
select throws_ok($$select private.build_need_ms('{}', '{}')$$, '42501', null, 'gracz nie woła funkcji serwera');
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
