-- Testy surowców w zapisie zamku (#274, etapy 1 i 2), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: zapis zamku z zapasami ponad pojemność magazynów, złym kształtem `economy` albo złotem bez
-- pokrycia jest odrzucany (HTTP 422, SQLSTATE PT422) bez przycinania; częste zapisy trafiają na rate limit
-- (PT429); łup z przyjętego ataku na gracza serwer przenosi raz, także przy ponowieniu: obrońca traci,
-- atakujący zyskuje, a zmiana wchodzi do zamku przy najbliższym zapisie z telefonu (`loot_applied`);
-- kopia obrońcy do bitwy ma już czekający łup; zamek spoza limitów nie wchodzi do PvP; klient nie czyta
-- łupu czekającego i nie ustawia kolumn serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(37);

create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000274a1'), ('00000000-0000-0000-0000-0000000274b1'),
  ('00000000-0000-0000-0000-0000000274c1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 62740, age = 0 where id in (select id from test_ids);
grant select on test_ids to authenticated;

-- Zamek z zapasami `p_amounts` i Magazynem na poziomie `p_wh` (0: bez Magazynu). Dwór 3 i Koszary 3 + 2 dają
-- 40 miejsc, Rybak 1 karmi 3 oddziały toporników (rodzaj 0).
create function pg_temp.castle(p_amounts jsonb, p_wh int default 0) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 4, 4], [2, 18, 3, 36, 30, 3, 3], [9, 18, 2, 50, 50, 3, 3], [3, 16, 1, 40, 30, 2, 2]]'::jsonb
      || case when p_wh > 0 then jsonb_build_array(jsonb_build_array(4, 25, p_wh, 10, 10, 2, 2)) else '[]'::jsonb end),
    'economy', jsonb_build_object('amounts', p_amounts, 'remainder', '[0, 0, 0, 0]'::jsonb, 'last_update_ms', 0),
    'research', jsonb_build_object('done', '["G21"]'::jsonb),  -- Rybak wymaga G21 (#274, etap 4)
    'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10], [3, 0, 10]]'::jsonb))
$$;
grant execute on function pg_temp.castle(jsonb, int) to authenticated;

-- Zapis zamku jak z telefonu (PATCH) i zmiana z łupu, którą serwer scalił.
create function pg_temp.push(p_player uuid, p_data jsonb) returns integer[] language sql as $$
  update public.castles c set data = p_data where c.player_id = p_player returning c.loot_applied
$$;
grant execute on function pg_temp.push(uuid, jsonb) to authenticated;

-- ---- gracz A zapisuje własny zamek jak telefon ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000274a1", "role": "authenticated"}', true);

select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000274a1', 2741, 12, pg_temp.castle('[1000, 1000, 1000, 175]'))$$,
  'uczciwy zamek: pełny gród i złoto startu z falami PvE');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[1001, 0, 0, 0]') where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'over_capacity', 'drewno ponad pojemność grodu odrzucone');
select lives_ok(
  $$update public.castles set data = pg_temp.castle('[1500, 0, 1500, 0]', 1) where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'Magazyn 1 dodaje 500 pojemności');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[0, 1501, 0, 0]', 1) where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'over_capacity', 'Magazyn 1: najwyżej 1500');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[-1, 0, 0, 0]') where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'bad_economy', 'ujemny zapas odrzucony');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[1.5, 0, 0, 0]') where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'bad_economy', 'ułamek odrzucony');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[0, 0, 0]') where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'bad_economy', 'za mało surowców odrzucone');
select throws_ok(
  $$update public.castles set data = '{"economy": "dużo"}' where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'bad_economy', 'zły kształt economy odrzucony');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[0, 0, 0, 176]') where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'gold_unbacked', 'złoto ponad start i fale PvE odrzucone');
select is((select (data -> 'economy' -> 'amounts')::text from public.castles where player_id = '00000000-0000-0000-0000-0000000274a1'),
  '[1500, 0, 1500, 0]', 'odrzucony zapis niczego nie zmienił');
select lives_ok(
  $$update public.castles set data = '{"profile": {"castle_name": "Gród"}}' where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'zapis bez economy przechodzi');
reset role;
select set_config('request.jwt.claims', '', true);  -- dalej pisze serwer (bez tokenu gracza)

-- złoto z wyprawy na bota przyjętej przez serwer podnosi pokrycie, a rekrutacja generała (50) je zmniejsza
insert into public.attacks (attacker_id, bot_idx, battle_seed, status, result, loot, finished_at)
values ('00000000-0000-0000-0000-0000000274a1', 0, 1, 'finished', '{"won": true, "percent": 100, "stars": [true, true, true]}',
  array[0, 0, 0, 30], now());
select lives_ok(
  $$update public.castles set data = pg_temp.castle('[0, 0, 0, 205]', 1) where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'złoto z bota zapisanego na serwerze ma pokrycie');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[0, 0, 0, 156]', 1)
      || '{"generals": {"roster": [{"kind": 0, "level": 1}], "attack": 0}}'
    where player_id = '00000000-0000-0000-0000-0000000274a1'$$,
  'PT422', 'gold_unbacked', 'złoto wydane na generała nie wraca');

-- ---- rate limit: PUSH_LIMIT = 90 zapisów w 10 minut ----
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000274c1', 2743, 12, pg_temp.castle('[0, 0, 0, 0]'));
do $$
begin
  for i in 1 .. 90 loop
    update public.castles set data = pg_temp.castle(jsonb_build_array(i, 0, 0, 0))
    where player_id = '00000000-0000-0000-0000-0000000274c1';
  end loop;
end;
$$;
select is((select push_count from public.castles where player_id = '00000000-0000-0000-0000-0000000274c1'), 90,
  '90 zapisów w oknie przechodzi');
select throws_ok(
  $$update public.castles set data = pg_temp.castle('[91, 0, 0, 0]') where player_id = '00000000-0000-0000-0000-0000000274c1'$$,
  'PT429', 'castle_rate_limited', '91. zapis w 10 minut odrzucony');
update public.castles set push_window_at = now() - interval '11 minutes'
where player_id = '00000000-0000-0000-0000-0000000274c1';
select lives_ok(
  $$update public.castles set data = pg_temp.castle('[92, 0, 0, 0]') where player_id = '00000000-0000-0000-0000-0000000274c1'$$,
  'po 10 minutach okno zaczyna się od nowa');
select is((select push_count from public.castles where player_id = '00000000-0000-0000-0000-0000000274c1'), 1,
  'nowe okno liczy od 1');

-- ---- łup PvP: A atakuje B ----
update public.castles set data = pg_temp.castle('[1000, 0, 0, 0]', 1) where player_id = '00000000-0000-0000-0000-0000000274a1';
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000274b1', 2742, 12, pg_temp.castle('[1000, 500, 200, 100]'));

create temp table att on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000274a1', '00000000-0000-0000-0000-0000000274b1',
    null, '[[0, 10], [0, 10], [0, 10]]', 7);
select is((select (castle -> 'economy' -> 'amounts')::text from att), '[1000, 500, 200, 100]', 'kopia B do bitwy');
update public.attacks set launched_at = now() where id = (select attack_id from att);
-- limit: 1000 × 50% × 20% = 100 drewna, 50 kamienia, 20 żywności, 10 złota; 30 toporników unosi 150
select is((select loot from public.end_attack('00000000-0000-0000-0000-0000000274a1', (select attack_id from att),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[50, 20, 10, 5]', '[10, 10, 10]')),
  array[50, 20, 10, 5], 'łup przyjęty');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000274a1'),
  array[50, 20, 10, 5]::bigint[], 'atakujący ma łup do scalenia');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000274b1'),
  array[-50, -20, -10, -5]::bigint[], 'obrońca ma stratę do scalenia');
select is((select loot from public.end_attack('00000000-0000-0000-0000-0000000274a1', (select attack_id from att),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[90, 40, 20, 10]', '[10, 10, 10]')),
  array[50, 20, 10, 5], 'ponowienie zwraca pierwszy łup');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000274b1'),
  array[-50, -20, -10, -5]::bigint[], 'ponowienie nie dubluje łupu');
select is((private.castle_with_pending('00000000-0000-0000-0000-0000000274b1',
    (select data from public.castles where player_id = '00000000-0000-0000-0000-0000000274b1')) -> 'economy' -> 'amounts')::text,
  '[950, 480, 190, 95]', 'kopia B do kolejnej bitwy ma już stratę');

-- B zapisuje zamek z telefonu (jeszcze bez straty): serwer odejmuje łup i mówi telefonowi ile
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000274b1", "role": "authenticated"}', true);
select is(pg_temp.push('00000000-0000-0000-0000-0000000274b1', pg_temp.castle('[1000, 500, 200, 100]')),
  array[-50, -20, -10, -5], 'zapis obrońcy zwraca odjęty łup');
select is((select (data -> 'economy' -> 'amounts')::text from public.castles), '[950, 480, 190, 95]',
  'obrońca traci łup w zamku na serwerze');
select is(pg_temp.push('00000000-0000-0000-0000-0000000274b1', pg_temp.castle('[950, 480, 190, 95]')),
  array[0, 0, 0, 0], 'kolejny zapis już bez łupu');
select throws_ok($$select * from public.castle_loot_pending$$, '42501', null, 'gracz nie czyta łupu czekającego');
select throws_ok(
  $$update public.castles set loot_applied = '{0, 0, 0, 999}' where player_id = '00000000-0000-0000-0000-0000000274b1'$$,
  '42501', null, 'gracz nie ustawia loot_applied');
select throws_ok(
  $$update public.castles set push_count = 0 where player_id = '00000000-0000-0000-0000-0000000274b1'$$,
  '42501', null, 'gracz nie zeruje licznika zapisów');
select throws_ok($$select private.castle_capacity('{}')$$, '42501', null, 'gracz nie woła funkcji serwera');
reset role;
select set_config('request.jwt.claims', '', true);  -- dalej pisze serwer (bez tokenu gracza)
select is((select count(*)::int from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000274b1'), 0,
  'scalony łup znika z kolejki');

-- A zapisuje zamek z prawie pełnym Magazynem: łup do pojemności (1500), złoto do pokrycia (175 + 30 + 5)
select is(pg_temp.push('00000000-0000-0000-0000-0000000274a1', pg_temp.castle('[1490, 0, 0, 205]', 1)),
  array[10, 20, 10, 5], 'atakujący dostaje łup w granicach magazynu');
select is((select (data -> 'economy' -> 'amounts')::text from public.castles where player_id = '00000000-0000-0000-0000-0000000274a1'),
  '[1500, 20, 10, 210]', 'zamek atakującego z łupem');

-- strata większa niż zapasy schodzi do zera
select private.add_loot_pending('00000000-0000-0000-0000-0000000274b1', array[-5000, 0, 0, 0]::bigint[]);
select is(pg_temp.push('00000000-0000-0000-0000-0000000274b1', pg_temp.castle('[950, 480, 190, 95]')),
  array[-950, 0, 0, 0], 'strata do zera, nie poniżej');

-- ---- zamek spoza limitów (zapis sprzed migracji) nie wchodzi do PvP ----
alter table public.castles disable trigger castles_resources;
update public.castles set data = pg_temp.castle('[0, 0, 0, 99999]', 1) where player_id = '00000000-0000-0000-0000-0000000274a1';
alter table public.castles enable trigger castles_resources;
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000274a1', null, 0::smallint, '[[0, 10]]', 8)$$,
  'P0001', 'castle_invalid', 'atakujący ze złotem bez pokrycia nie zaczyna ataku');
-- obrońca z takim zapisem nie jest celem (review #278)
alter table public.castles disable trigger castles_resources;
update public.castles set data = pg_temp.castle('[0, 0, 0, 99999]') where player_id = '00000000-0000-0000-0000-0000000274c1';
alter table public.castles enable trigger castles_resources;
select throws_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000274b1', '00000000-0000-0000-0000-0000000274c1',
    null, '[[0, 10]]', 10)$$,
  'P0001', 'target_not_found', 'obrońca ze złotem bez pokrycia nie jest celem');

select * from finish();
rollback;
