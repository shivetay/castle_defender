-- Testy perka władcy z technologii (#308, ADR 0002; wcześniej wybór z listy, #32), uruchamiane przez
-- `supabase test db` (pgTAP). Kryteria: serwer liczy stan perka z badań w zapisie zamku (jedna linia,
-- poziom 2 tylko z poziomem 1 i od epoki II, dwie linie = brak perka) i ignoruje perk wpisany przez klienta
-- w `ruler`; nie ma już okna 24 h ani płatnych zmian; gracz nie ustawia kolumn serwera i nie czyta perka
-- atakującego; `launch_attack` bierze perk z zamku atakującego na serwerze, `attack_replay` oddaje ten sam,
-- a `end_attack` przy Łupieżcy przyjmuje łup do 115% zwykłego limitu tylko przy ataku na gracza;
-- Gospodarny na obu poziomach podnosi limit żywności.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(28);

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

-- A atakuje B, O to obcy gracz. Ranking w paśmie 63 300 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000032a1'), ('00000000-0000-0000-0000-0000000032b1'),
  ('00000000-0000-0000-0000-0000000032c1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 63300, age = 0 where id in (select id from test_ids);

-- Zamek z technologiami `p_techs` (poza G21 dla Rybaka) i wpisem władcy `p_ruler`; z `p_age2` Dwór
-- poziomu 6 i technologie przejścia I → II (epoka II zamku, private.castle_age).
create function pg_temp.castle(p_techs jsonb, p_age2 boolean default false, p_ruler jsonb default '{}')
returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', jsonb_build_array(
      jsonb_build_array(1, 5, case when p_age2 then 6 else 3 end, 30, 30, 2, 2),
      '[2, 18, 3, 36, 30, 2, 2]'::jsonb, '[9, 18, 2, 50, 50, 2, 2]'::jsonb, '[3, 16, 1, 40, 30, 2, 2]'::jsonb)),
    'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 0)),
    -- G21: Rybak wymaga badania (BuildConfig.REQUIRED_TECH, #274)
    'research', jsonb_build_object('done', '["G21"]'::jsonb
      || case when p_age2 then '["G18", "G19", "A2", "A43", "A7", "O1", "G1"]'::jsonb else '[]'::jsonb end
      || p_techs),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
    'ruler', p_ruler)
$$;

-- ---- stan perka z badań (RulerPerks.from_done) ----
select is(private.castle_ruler_perk(pg_temp.castle('[]')), -1::smallint, 'bez technologii perka: brak');
select is(private.castle_ruler_perk(pg_temp.castle('[]', false, '{"perk": 3}')), -1::smallint,
  'perk wpisany przez klienta w ruler się nie liczy');
select is(private.castle_ruler_perk(pg_temp.castle('["A60"]')), 0::smallint, 'A60: Zdobywca');
select is(private.castle_ruler_perk(pg_temp.castle('["O23"]')), 2::smallint, 'O23: Gospodarz grodu');
select is(private.castle_ruler_perk(pg_temp.castle('["G25"]')), 3::smallint, 'G25: Gospodarny');
select is(private.castle_ruler_perk(pg_temp.castle('["U14"]')), 5::smallint, 'U14: Ukochany władca');
select is(private.castle_ruler_perk(pg_temp.castle('["A60", "A61"]', true)), 1::smallint, 'A61 w epoce II: Łupieżca');
select is(private.castle_ruler_perk(pg_temp.castle('["O23", "O24"]', true)), 6::smallint, 'O24: Gospodarz grodu II');
select is(private.castle_ruler_perk(pg_temp.castle('["G25", "G26"]', true)), 4::smallint, 'G26: Budowniczy');
select is(private.castle_ruler_perk(pg_temp.castle('["U14", "U15"]', true)), 7::smallint, 'U15: Ukochany władca II');
select is(private.castle_ruler_perk(pg_temp.castle('["A60", "A61"]')), 0::smallint,
  'poziom 2 w zamku z epoki I nie działa, zostaje poziom 1');
select is(private.castle_ruler_perk(pg_temp.castle('["A61"]', true)), -1::smallint, 'poziom 2 bez poziomu 1: brak');
select is(private.castle_ruler_perk(pg_temp.castle('["A60", "G25"]')), -1::smallint, 'dwie linie: brak perka');
select is(private.castle_ruler_perk('{"research": {"done": "A60"}}'), -1::smallint, 'zły kształt badań: brak');

-- ---- drzewko serwera zna technologie perków ----
select is(private.tech_tree() -> 'A61', '[1, ["A60"]]'::jsonb, 'A61 w epoce II wymaga A60');
select is(private.castle_research_problem(pg_temp.castle('["A60", "O23", "G25", "U14"]')), null,
  'technologie perków przechodzą walidację badań');

-- ---- Gospodarny w limicie żywności ----
-- gród 20 + Rybak poziomu 1 (40) = 60; z Gospodarnym 66
select is(private.food_production(pg_temp.castle('["G25"]')), 66, 'Gospodarny: +10% żywności');
select is(private.food_production(pg_temp.castle('["G25", "G26"]', true)), 66, 'Budowniczy z Gospodarnym: +10%');
select is(private.food_production(pg_temp.castle('["A60"]')), 60, 'inny perk: bez premii');

-- ---- gracz nie ustawia kolumn serwera ----
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000032c1', 3232, 12, pg_temp.castle('["G25"]'));
select hasnt_column('public', 'castles', 'ruler_perk_free_at', 'bez okna 24 h');
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000032c1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$update public.castles set ruler_perk_paid = 0
  where player_id = '00000000-0000-0000-0000-0000000032c1'$$, '42501', null, 'gracz nie zeruje płatnych zmian');
select throws_ok($$select attacker_ruler_perk from public.attacks limit 1$$, '42501', null,
  'gracz nie czyta perka atakującego');
select throws_ok($$select private.castle_ruler_perk('{}')$$, '42501', null, 'gracz nie woła funkcji serwera');
reset role;

-- ---- atak na gracza: perk z zamku atakującego na serwerze, Łupieżca w limicie łupu ----
-- A w epoce II z Łupieżcą (A60 i A61), B bez perka. Zamki wstawiamy bez wyzwalaczy zapisu, bo zamek
-- z epoki II w jednym zapisie nie przeszedłby sprawdzania czasu budowy; ten test sprawdza odczyt perka.
set local session_replication_role = replica;
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000032a1', 3232, 12, pg_temp.castle('["A60", "A61"]', true)),
  ('00000000-0000-0000-0000-0000000032b1', 3232, 12, pg_temp.castle('[]'));
set local session_replication_role = origin;
-- #383: atak tylko w tej samej epoce, więc B też jest w epoce II
update public.players set age = 1 where id in ('00000000-0000-0000-0000-0000000032a1',
  '00000000-0000-0000-0000-0000000032b1');

set local role service_role;
create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000032a1',
    '00000000-0000-0000-0000-0000000032b1', null, '[[0, 10], [0, 10]]', 32);
create temp table l1 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000032a1', (select attack_id from started),
    '[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    null);
select is((select ruler_perk from l1), 1::smallint, 'launch_attack oddaje perk atakującego z badań na serwerze');
-- zmiana badań po zatwierdzeniu nie zmienia ataku
reset role;
set local session_replication_role = replica;
update public.castles set data = pg_temp.castle('["A60"]', true) where player_id = '00000000-0000-0000-0000-0000000032a1';
set local session_replication_role = origin;
set local role service_role;
select is((select ruler_perk from public.launch_attack('00000000-0000-0000-0000-0000000032a1',
  (select attack_id from started), '[]', null)), 1::smallint, 'ponowienie: ten sam perk');

-- zwykły limit drewna przy 60%: 1000 * 50 / 100 * 20 / 100 * 60 / 100 = 60, z Łupieżcą 69
select throws_ok(format($$select * from public.end_attack('00000000-0000-0000-0000-0000000032a1', %L,
    '{"won": true, "percent": 60, "stars": [false, true, true]}', '[70, 0, 0, 0]', '[10, 10]')$$,
    (select attack_id from started)), 'P0001', 'loot_too_high', 'ponad 115% limitu: odrzucone');
select lives_ok(format($$select * from public.end_attack('00000000-0000-0000-0000-0000000032a1', %L,
    '{"won": true, "percent": 60, "stars": [false, true, true]}', '[69, 0, 0, 0]', '[10, 10]')$$,
    (select attack_id from started)), 'Łupieżca: 115% limitu przyjęte');
select is((select ruler_perk from public.attack_replay('00000000-0000-0000-0000-0000000032b1',
  (select attack_id from started))), 1::smallint, 'powtórka u obrońcy z tym samym perkiem');

select * from finish();
rollback;
