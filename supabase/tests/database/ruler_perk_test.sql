-- Testy perka władcy (#32), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: przy zapisie zamku serwer zostawia tylko znany perk z epoki zamku; zmiana jest darmowa raz
-- na 24 h (zegar serwera), a kolejna kosztuje 50 złota z pokryciem w tym, co gracz mógł zdobyć (jak
-- generałowie); płatne zmiany zmniejszają złoto na generałów; gracz nie ustawia kolumn serwera;
-- `launch_attack` bierze perk z zamku atakującego na serwerze, `attack_replay` oddaje ten sam, a
-- `end_attack` przy Łupieżcy przyjmuje łup do 115% zwykłego limitu tylko przy ataku na gracza;
-- Gospodarny podnosi limit żywności.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(29);

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

-- Zamek z perkiem `p_ruler` (bez generałów, chyba że podane): ten sam układ dla A, B i O.
create function pg_temp.castle(p_ruler jsonb, p_generals jsonb default null) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
    'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 0)),
    -- G21: Rybak wymaga badania (BuildConfig.REQUIRED_TECH, #274)
    'research', jsonb_build_object('done', '["G21"]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
    'ruler', p_ruler)
    || case when p_generals is null then '{}'::jsonb else jsonb_build_object('generals', p_generals) end
$$;

-- Zapis zamku O jak z telefonu (upsert) i perk, który przyjął serwer.
create function pg_temp.save_o(p_ruler jsonb, p_generals jsonb default null) returns int language sql as $$
  insert into public.castles as c (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000032c1', 3232, 12, pg_temp.castle(p_ruler, p_generals))
  on conflict (player_id) do update set data = excluded.data
  returning (c.data -> 'ruler' ->> 'perk')::int
$$;

-- ---- zakres i epoka ----
select is(pg_temp.save_o('{"perk": 9, "free_ms": 5}'), -1, 'nieznany perk odpada');
select is((select data -> 'ruler' -> 'free_ms' from public.castles where player_id = '00000000-0000-0000-0000-0000000032c1'),
  '5'::jsonb, 'reszta wpisu władcy zostaje');
select is(pg_temp.save_o('{"perk": 1}'), -1, 'Łupieżca (od epoki II) w epoce I odpada');
select is(pg_temp.save_o('{"perk": 4}'), -1, 'Budowniczy (od epoki II) w epoce I odpada');
select is((select ruler_perk_free_at from public.castles where player_id = '00000000-0000-0000-0000-0000000032c1'),
  null, 'odrzucony perk nie zużywa darmowej zmiany');

-- ---- 24 h i złoto ----
select is(pg_temp.save_o('{"perk": 0}'), 0, 'pierwszy wybór: Zdobywca, darmowo');
select isnt((select ruler_perk_free_at from public.castles where player_id = '00000000-0000-0000-0000-0000000032c1'),
  null, 'serwer zapamiętał chwilę darmowej zmiany');
select is(pg_temp.save_o('{"perk": 0}'), 0, 'zapis bez zmiany perka nic nie kosztuje');
select is(pg_temp.save_o('{"perk": 2}'), 2, 'druga zmiana w 24 h: za złoto (175 zł startu i fal starcza)');
select is((select ruler_perk_paid from public.castles where player_id = '00000000-0000-0000-0000-0000000032c1'),
  1, 'jedna płatna zmiana');
select is(pg_temp.save_o('{"perk": 5}'), 5, 'trzecia zmiana: 175 - 50 - 50 wciąż starcza');
-- generał poziomu 2 (130 zł) + 2 płatne zmiany (100 zł) = 230 > 175: generał spada do poziomu 1 (50 zł),
-- a na kolejną płatną zmianę (175 - 50 - 100 = 25) już brak złota
select is(pg_temp.save_o('{"perk": 3}', '{"roster": [{"kind": 0, "level": 2, "xp": 0}]}'), 5,
  'bez pokrycia w złocie zmiana cofnięta do poprzedniego perka');
select is((select (data -> 'generals' -> 'roster' -> 0 ->> 'level')::int from public.castles
  where player_id = '00000000-0000-0000-0000-0000000032c1'), 1, 'płatne zmiany perka zmniejszyły złoto na generałów');
select is(pg_temp.save_o('{"perk": -1}'), -1, 'brak perka zawsze wolno ustawić');
-- po 24 h znowu darmowo
update public.castles set ruler_perk_free_at = now() - interval '25 hours'
where player_id = '00000000-0000-0000-0000-0000000032c1';
select is(pg_temp.save_o('{"perk": 3}', '{"roster": [{"kind": 0, "level": 1, "xp": 0}]}'), 3,
  'po 24 h zmiana znowu darmowa');
select is((select ruler_perk_paid from public.castles where player_id = '00000000-0000-0000-0000-0000000032c1'),
  2, 'darmowa zmiana nie zwiększa płatnych');

-- ---- Gospodarny w limicie żywności ----
-- gród 20 + Rybak poziomu 1 (40) = 60; z Gospodarnym 66
select is(private.food_production(pg_temp.castle('{"perk": 3}')), 66, 'Gospodarny: +10% żywności');
select is(private.food_production(pg_temp.castle('{"perk": 0}')), 60, 'inny perk: bez premii');

-- ---- gracz nie ustawia kolumn serwera ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000032c1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$update public.castles set ruler_perk_free_at = null
  where player_id = '00000000-0000-0000-0000-0000000032c1'$$, '42501', null, 'gracz nie zeruje okna 24 h');
select throws_ok($$update public.castles set ruler_perk_paid = 0
  where player_id = '00000000-0000-0000-0000-0000000032c1'$$, '42501', null, 'gracz nie zeruje płatnych zmian');
select throws_ok($$select attacker_ruler_perk from public.attacks limit 1$$, '42501', null,
  'gracz nie czyta perka atakującego');
reset role;

-- ---- atak na gracza: perk z zamku atakującego na serwerze, Łupieżca w limicie łupu ----
-- A w epoce II (players.age) z Łupieżcą, B bez perka
update public.players set age = 1 where id = '00000000-0000-0000-0000-0000000032a1';
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000032a1', 3232, 12, pg_temp.castle('{"perk": 1}')),
  ('00000000-0000-0000-0000-0000000032b1', 3232, 12, pg_temp.castle('{}'));
select is((select (data -> 'ruler' ->> 'perk')::int from public.castles where player_id = '00000000-0000-0000-0000-0000000032a1'),
  1, 'Łupieżca w epoce II zostaje');

set local role service_role;
create temp table started on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000032a1',
    '00000000-0000-0000-0000-0000000032b1', null, '[[0, 10], [0, 10]]', 32);
create temp table l1 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000032a1', (select attack_id from started),
    '[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
    null);
select is((select ruler_perk from l1), 1::smallint, 'launch_attack oddaje perk atakującego z serwera');
-- zmiana perka po zatwierdzeniu nie zmienia ataku
reset role;
update public.castles set data = pg_temp.castle('{"perk": 0}') where player_id = '00000000-0000-0000-0000-0000000032a1';
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

-- zamek sprzed migracji (bez wyzwalacza) z Łupieżcą w epoce I: launch_attack go nie przyjmuje
reset role;
alter table public.castles disable trigger castles_check_ruler_perk;
update public.castles set data = pg_temp.castle('{"perk": 1}') where player_id = '00000000-0000-0000-0000-0000000032c1';
alter table public.castles enable trigger castles_check_ruler_perk;
update public.shields set until = now() - interval '1 second' where player_id = '00000000-0000-0000-0000-0000000032b1';
set local role service_role;
create temp table started2 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000032c1',
    '00000000-0000-0000-0000-0000000032b1', null, '[[0, 10]]', 33);
select is((select ruler_perk from public.launch_attack('00000000-0000-0000-0000-0000000032c1',
  (select attack_id from started2),
  '[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]',
  null)), -1::smallint, 'stary zapis: perk z wyższej epoki nie wchodzi do ataku');

-- ---- gracz nie woła funkcji serwera ----
reset role;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000032a1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select private.ruler_gold_left('00000000-0000-0000-0000-0000000032a1', '{}', 0)$$, '42501', null,
  'gracz nie liczy budżetu sam');

select * from finish();
rollback;
