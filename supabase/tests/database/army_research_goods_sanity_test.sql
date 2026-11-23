-- Testy badań, wojska i towarów w zapisie zamku (#281), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: lista badań bez wymagań albo z późniejszej epoki, jednostki bez technologii i towary ponad
-- zbrojownię są odrzucane (HTTP 422, SQLSTATE PT422) bez przycinania; gracz nie zapisze technologii, wojska
-- ani towarów szybciej, niż da się je zbadać, wyszkolić albo wyprodukować od poprzedniego zapisu (zlecenia
-- w toku i tolerancja się liczą); uczciwe zapisy, także powrót zwiadu i armia ponad limit po rozbiórce,
-- przechodzą; serwer pisze bez limitu czasu; zamek spoza reguł nie wchodzi do PvP; gracz nie woła funkcji
-- serwera ani nie ustawi kredytów.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(56);

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

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000281a1');
update public.players set rating = 62810, age = 0 where id = '00000000-0000-0000-0000-0000000281a1';

-- Zamek: Dwór 3 i Koszary 1 (limit armii 32), A1, 5 toporników, pusta zbrojownia; `p_extra` nadpisuje części.
create function pg_temp.castle(p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 3, 0, 0, 4, 4], [2, 18, 1, 10, 10, 3, 3]]'::jsonb),
    'economy', jsonb_build_object('amounts', '[0, 0, 0, 0]'::jsonb),
    'research', jsonb_build_object('done', '["A1"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 5]]'::jsonb, 'orders', '[]'::jsonb),
    'goods', jsonb_build_object('amounts', to_jsonb(array_fill(0, array[22])))) || p_extra
$$;
grant execute on function pg_temp.castle(jsonb) to authenticated;

-- Zapasy towarów z `p_first` na pierwszym miejscu (surowe skóry), reszta 0.
create function pg_temp.goods(p_first integer, p_size integer default 22) returns jsonb language sql as $$
  select jsonb_build_object('goods', jsonb_build_object('amounts',
    to_jsonb(array[p_first] || array_fill(0, array[p_size - 1]))))
$$;
grant execute on function pg_temp.goods(integer, integer) to authenticated;

-- Wojsko: 10 toporników w oddziale 1, `p_orders` zleceń szkolenia topornika w Koszarach i opcjonalnie tropiciele.
create function pg_temp.army(p_orders integer, p_trackers jsonb default '[]') returns jsonb language sql as $$
  select jsonb_build_object('recruitment', jsonb_build_object('squads', '[[1, 0, 10]]'::jsonb || p_trackers,
    'orders', coalesce((select jsonb_agg('{"unit": 0, "building_id": 2, "squad_id": 1}'::jsonb)
      from generate_series(1, p_orders)), '[]'::jsonb)))
$$;
grant execute on function pg_temp.army(integer, jsonb) to authenticated;

-- Poprzedni zapis zamku sprzed `p_ago` (zegar serwera): bump_revision ustawia updated_at na teraz.
create function pg_temp.age_castle(p_ago interval) returns void language plpgsql as $$
begin
  alter table public.castles disable trigger castles_bump_revision;
  update public.castles set updated_at = now() - p_ago where player_id = '00000000-0000-0000-0000-0000000281a1';
  alter table public.castles enable trigger castles_bump_revision;
end;
$$;

-- Zapis jak z telefonu (PATCH) albo z serwera (bez tokenu gracza).
create function pg_temp.push(p_extra jsonb default '{}') returns void language sql as $$
  update public.castles set data = pg_temp.castle(p_extra) where player_id = '00000000-0000-0000-0000-0000000281a1'
$$;
grant execute on function pg_temp.push(jsonb) to authenticated;
create function pg_temp.as_a() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000281a1", "role": "authenticated"}', true)
$$;

-- ---- reguły stanu (każdy zapis, także serwera) ----
select is(private.castle_research_problem(pg_temp.castle()), null, 'A1 bez wymagań');
select is(private.castle_research_problem(pg_temp.castle('{"research": {"done": ["A1", "X9"]}}')), 'bad_research',
  'nieznany kod');
select is(private.castle_research_problem(pg_temp.castle('{"research": {"done": ["A1", "A1"]}}')), 'bad_research',
  'powtórzony kod');
select is(private.castle_research_problem(pg_temp.castle('{"research": {"done": "A1"}}')), 'bad_research',
  'zły typ listy');
select is(private.castle_research_problem(pg_temp.castle('{"research": {"done": ["A2", "A7"]}}')), 'research_locked',
  'A7 bez A43');
select is(private.castle_research_problem(pg_temp.castle('{"research": {"done": ["A1", "A6"]}}')), 'research_age',
  'A6 (epoka II) w epoce I');
select is(private.castle_army_problem(pg_temp.castle()), null, 'toporników szkoli się bez badań');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [[1, 0, 11]]}}')), 'bad_army',
  'oddział ponad SQUAD_SIZE');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [[1, 0, 5], [1, 0, 5]]}}')),
  'bad_army', 'powtórzone id oddziału');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [[1, 6, 5]]}}')), 'unit_locked',
  'jeździec bez A7');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [[1, 7, 5]]}}')), 'unit_age',
  'włócznik w epoce I');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [[1, 6, 0]]}}')), null,
  'pusty oddział nie przeszkadza');
select is(private.castle_army_problem(pg_temp.castle('{"scout": {"mission": {"units": [[5, 3]]}}}')), 'unit_locked',
  'tropiciele na zwiadzie bez S1');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [], "orders": [{"unit": 6, "building_id": 2}]}}')),
  'unit_locked', 'jeździec bez A7 w szkoleniu (review #285)');
select is(private.castle_army_problem(pg_temp.castle('{"recruitment": {"squads": [], "orders": [{"unit": "0", "building_id": 2}]}}')),
  'bad_army', 'zlecenie złego kształtu');
select is(private.castle_goods_problem(pg_temp.castle()), null, 'pusta zbrojownia');
select is(private.castle_goods_problem(pg_temp.castle(pg_temp.goods(0, 21))), 'bad_goods', '21 towarów zamiast 22');
select is(private.castle_goods_problem(pg_temp.castle(pg_temp.goods(1001))), 'goods_over_capacity',
  'towar ponad zbrojownię');
select is(private.research_need_ms('{}', '{A1}'), 60000::numeric, 'pierwsza technologia epoki I: 60 s');
select is(private.research_need_ms('{A1}', '{A1,A2,O1}'), 360000::numeric, 'druga i trzecia: 120 s + 240 s');
select is(private.research_need_ms('{}', '{G4}'), 1800000::numeric, 'pierwsza technologia epoki II: 30 min');
select is(private.train_ms(0, 1), 20000::bigint, 'topornik w Koszarach 1: 20 s');
select is(private.train_ms(0, 5), 10000::bigint, 'Koszary 5: dwa razy szybciej');
select is(private.train_ms(0, 9), 10000::bigint, 'poziomy epoki II jak 5');

-- ---- gracz A: czas badań, szkolenia i produkcji ----
set local role authenticated;
select pg_temp.as_a();
select throws_ok($$select private.castle_research_problem('{}')$$, '42501', null, 'gracz nie woła funkcji serwera');
select throws_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000281a1', 2810, 12,
      pg_temp.castle('{"research": {"done": ["A1", "A2", "O1", "G1", "G2", "O2", "G18", "G21", "U1"]}}'))$$,
  'PT422', 'research_too_fast', 'nowe konto nie zbada 9 technologii (8,5 h)');
select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000281a1', 2810, 12, pg_temp.castle())$$,
  'nowe konto: Dwór 3, Koszary 1, A1 i 5 toporników w zapasie gry bez sieci');
select throws_ok($$update public.castles set research_credit_ms = 9999999$$, '42501', null, 'gracz nie ustawi kredytu badań');
select throws_ok($$update public.castles set train_credit_ms = '{"18": 9999999}'$$, '42501', null,
  'gracz nie ustawi kredytu szkolenia');
select throws_ok($$update public.castles set goods_credit = '[9999999]'$$, '42501', null, 'gracz nie ustawi kredytu towarów');

-- badania: jeden badacz
select throws_ok($$select pg_temp.push('{"research": {"done": ["A1", "A2", "O1", "G1"]}}')$$,
  'PT422', 'research_too_fast', 'trzy technologie (14 min) zaraz po zapisie odrzucone');
select lives_ok($$select pg_temp.push('{"research": {"done": ["A1", "A2"]}}')$$, 'A2 (2 min) w tolerancji');
select is((select research_credit_ms from public.castles), -120000::bigint, 'tolerancja schodzi z kredytu');
select lives_ok($$select pg_temp.push('{"research": {"done": ["A1", "A2"], "active": {"code": "O1"}}}')$$,
  'zapis z badaniem O1 w toku');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select pg_temp.as_a();
select lives_ok($$select pg_temp.push('{"research": {"done": ["A1", "A2"], "active": {"code": "O1"}}}')$$,
  'zapis 10 minut później');
select is((select research_credit_ms from public.castles), 240000::bigint,
  'kredyt: najwyżej czas badania w toku (trzecia technologia epoki: 4 min), nie z zapisu');

-- wojsko: Koszary 1 szkolą topornika 20 s
select throws_ok($$select pg_temp.push('{"recruitment": {"squads": [[1, 0, 10], [2, 0, 10], [3, 0, 5]]}}')$$,
  'PT422', 'train_too_fast', '20 nowych toporników (400 s) zaraz po zapisie odrzucone');
select lives_ok($$select pg_temp.push('{"recruitment": {"squads": [[1, 0, 10]]}}')$$, '5 toporników (100 s) w tolerancji');
select throws_ok($$select pg_temp.push('{"recruitment": {"squads": [[1, 0, 10], [2, 2, 1]]}}')$$,
  'PT422', 'unit_no_building', 'łucznik bez Strzelnicy');
select throws_ok($$select pg_temp.push(pg_temp.army(23))$$,
  'PT422', 'army_over_limit', '10 wyszkolonych i 23 w szkoleniu ponad limit 32');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select pg_temp.as_a();
select lives_ok($$select pg_temp.push(pg_temp.army(1))$$, 'zapis ze szkoleniem w toku');
select is((select (train_credit_ms ->> '18')::bigint from public.castles), 20000::bigint,
  'kredyt Koszar: czas pierwszego zlecenia (20 s)');

-- zwiad: wracający tropiciele to nie szkolenie, a armia ponad limit, która nie rośnie, przechodzi
reset role;
select set_config('request.jwt.claims', '', true);
create temp table scouts (v jsonb) on commit drop;
insert into scouts values ('{"grid": {"buildings": [[1, 5, 3, 0, 0, 4, 4], [2, 18, 1, 10, 10, 3, 3], [3, 22, 1, 20, 20, 2, 2]]},
  "research": {"done": ["A1", "A2", "S1"]}}');
grant select on scouts to authenticated;
select pg_temp.push((select v from scouts) || pg_temp.army(22) || '{"scout": {"mission": {"units": [[5, 3]]}}}');
set local role authenticated;
select pg_temp.as_a();
select lives_ok($$select pg_temp.push((select v from scouts) || pg_temp.army(22, '[[2, 5, 3]]'))$$,
  'powrót 3 tropicieli: armia 35 ponad limit 32, ale nie urosła');
select lives_ok($$select pg_temp.push((select v from scouts) || pg_temp.army(22, '[[2, 5, 3]]'))$$,
  'ta sama armia ponad limit przechodzi dalej');

-- towary: Chata myśliwego 1 daje 6 cykli na godzinę po 2 surowe skóry (12 na godzinę)
reset role;
select set_config('request.jwt.claims', '', true);
create temp table hunter (v jsonb) on commit drop;
insert into hunter values ('{"grid": {"buildings": [[1, 5, 3, 0, 0, 4, 4], [2, 18, 1, 10, 10, 3, 3], [3, 22, 1, 20, 20, 2, 2], [4, 6, 1, 30, 30, 2, 2]]},
  "research": {"done": ["A1", "A2", "S1", "G18"]}, "recruitment": {"squads": [[1, 0, 10], [2, 5, 3]]}}');
-- bez zleceń: armia 13 mieści się w limicie
grant select on hunter to authenticated;
select pg_temp.push((select v from hunter));
set local role authenticated;
select pg_temp.as_a();
select throws_ok($$select pg_temp.push((select v from hunter) || pg_temp.goods(2))$$,
  'PT422', 'goods_too_fast', '2 skóry zaraz po zapisie (ponad 5 minut produkcji) odrzucone');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select pg_temp.as_a();
select lives_ok($$select pg_temp.push((select v from hunter) || pg_temp.goods(2))$$, '2 skóry po 10 minutach');
reset role;
select set_config('request.jwt.claims', '', true);
select pg_temp.age_castle(interval '1 hour');
set local role authenticated;
select pg_temp.as_a();
select lives_ok($$select pg_temp.push((select v from hunter) || pg_temp.goods(2))$$, 'godzina bez zmiany zapasu');
select is((select (goods_credit ->> 0)::bigint from public.castles), 7200000::bigint,
  'kredyt towaru: najwyżej jeden cykl (2 skóry × godzina w ms), nie godzina produkcji');
reset role;

-- ---- Chłop tylko w epoce I (UnitTypes.ERA_I_ONLY, review #285) ----
-- Dwór 6 z technologiami przejścia: epoka II; 5 chłopów z epoki I i jeden w szkoleniu
select set_config('request.jwt.claims', '', true);
create temp table age2 (v jsonb) on commit drop;
insert into age2 values ('{"grid": {"buildings": [[1, 5, 6, 0, 0, 4, 4], [2, 18, 1, 10, 10, 3, 3]]},
  "research": {"done": ["A1", "O1", "G1", "G18", "G19", "A2", "A43", "A7"]}}');
grant select on age2 to authenticated;
select pg_temp.push((select v from age2)
  || '{"recruitment": {"squads": [[1, 13, 5]], "orders": [{"unit": 13, "building_id": 2, "squad_id": 1}]}}');
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select pg_temp.as_a();
select lives_ok($$select pg_temp.push((select v from age2) || '{"recruitment": {"squads": [[1, 13, 6]], "orders": []}}')$$,
  'chłop zlecony w epoce I kończy szkolenie w epoce II');
select lives_ok($$select pg_temp.push((select v from age2) || '{"recruitment": {"squads": [[1, 13, 6]], "orders": []}}')$$,
  'chłopi z epoki I zostają w armii');
select throws_ok($$select pg_temp.push((select v from age2) || '{"recruitment": {"squads": [[1, 13, 7]], "orders": []}}')$$,
  'PT422', 'unit_era_passed', 'nowy chłop w epoce II odrzucony');
select throws_ok($$select pg_temp.push((select v from age2)
    || '{"recruitment": {"squads": [[1, 13, 6]], "orders": [{"unit": 13, "building_id": 2, "squad_id": 1}]}}')$$,
  'PT422', 'unit_era_passed', 'zlecenie chłopa w epoce II odrzucone');
select lives_ok($$select pg_temp.push((select v from age2) || '{"recruitment": {"squads": [[1, 13, 6], [2, 0, 2]], "orders": []}}')$$,
  'toporników w epoce II szkoli się dalej');
reset role;

-- ---- serwer pisze bez limitu czasu, ale w regułach stanu ----
select set_config('request.jwt.claims', '', true);
select lives_ok($$select pg_temp.push((select v from hunter)
    || '{"research": {"done": ["A1", "A2", "S1", "G18", "G19", "A43", "A7", "O1", "G1", "G2"]}}')$$,
  'serwer zapisuje badania bez limitu czasu');
select throws_ok($$select pg_temp.push('{"recruitment": {"squads": [[1, 6, 5]]}}')$$,
  'PT422', 'unit_locked', 'serwer też nie zapisze jeźdźca bez A7');

-- ---- zamek spoza reguł (zapis sprzed migracji) nie wchodzi do PvP ----
-- wyzwalacz surowców też sprawdza wojsko (castle_resources_problem), więc oba są wyłączone
alter table public.castles disable trigger castles_check_army;
alter table public.castles disable trigger castles_resources;
select pg_temp.push('{"recruitment": {"squads": [[1, 6, 5]]}}');
alter table public.castles enable trigger castles_resources;
alter table public.castles enable trigger castles_check_army;
set local role service_role;
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000281a1', null, 0::smallint, '[[6, 5]]', 9)$$,
  'P0001', 'castle_invalid', 'jeździec bez A7 nie idzie do PvP');
reset role;

select * from finish();
rollback;
