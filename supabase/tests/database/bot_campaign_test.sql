-- Testy kampanii zamków-botów na serwerze (#386, ADR 0015), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: nowy gracz atakuje tylko bota 0, `begin_attack` odrzuca zamek powyżej `players.bots_beaten`
-- kodem `bot_locked`, wygrana z kolejnym botem podbija licznik o 1, a przegrana, wygrana ze zdobytym już
-- botem i ponowiony koniec ataku nic nie zmieniają; licznik kończy się na 40; klient nie zmieni swojego
-- ani cudzego postępu.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(22);

-- Gracze testu są w epoce 9 (bez prawdziwych graczy), bo testy biegną też na projekcie w chmurze,
-- w transakcji, która się cofa. A = 386a1 gra kampanię, B = 386b1 to obcy gracz.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000386a1'), ('00000000-0000-0000-0000-0000000386b1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 70000, age = 9 where id in (select id from test_ids);

insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4242, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród ' || right(t.id::text, 2), 'ruler', 'mieszko'),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb))
from test_ids t;

-- błąd begin_attack jako tekst (pusty, gdy start przeszedł)
create function pg_temp.start_err(p_player uuid, p_bot smallint) returns text language plpgsql as $$
begin
  perform * from public.begin_attack(p_player, null, p_bot, '[[0, 10]]', 386);
  return '';
exception when others then
  return sqlerrm;
end;
$$;

-- start i koniec ataku na bota z wynikiem `p_won`; zwraca status z end_attack
create function pg_temp.fight(p_player uuid, p_bot smallint, p_won boolean) returns text language plpgsql as $$
declare
  v_id uuid;
begin
  select attack_id into v_id from public.begin_attack(p_player, null, p_bot, '[[0, 10]]', 386);
  return (select status from public.end_attack(p_player, v_id,
    case when p_won then '{"won": true, "percent": 100, "stars": [true, true, true]}'::jsonb
      else '{"won": false, "percent": 10, "stars": [false, false, false]}'::jsonb end,
    '[0, 0, 0, 0]', '[10]'));
end;
$$;

-- ---- klient nie zmienia postępu ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000386a1", "role": "authenticated"}', true);
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386a1'),
  0::smallint, 'nowy gracz: zero zdobytych zamków, czyta swój postęp');
select throws_ok(
  $$update public.players set bots_beaten = 40 where id = '00000000-0000-0000-0000-0000000386a1'$$,
  '42501', null, 'A nie odblokuje sobie zamków');
select throws_ok(
  $$update public.players set bots_beaten = 0 where id = '00000000-0000-0000-0000-0000000386b1'$$,
  '42501', null, 'A nie zmieni postępu B');
select is((select count(*)::int from public.players where id = '00000000-0000-0000-0000-0000000386b1'),
  0, 'A nie widzi wiersza B');
reset role;
set local role anon;
select throws_ok(
  $$update public.players set bots_beaten = 40$$,
  '42501', null, 'anon nie zmieni postępu');
reset role;

set local role service_role;

-- ---- nowy gracz: tylko bot 0 ----
select is(pg_temp.start_err('00000000-0000-0000-0000-0000000386a1', 1::smallint), 'bot_locked',
  'nowy gracz nie atakuje bota 1');
select is(pg_temp.start_err('00000000-0000-0000-0000-0000000386a1', 39::smallint), 'bot_locked',
  'nowy gracz nie atakuje bota 39');
select is((select count(*)::int from public.attacks where attacker_id = '00000000-0000-0000-0000-0000000386a1'),
  0, 'odmowa nie zapisuje ataku');
select is(pg_temp.start_err('00000000-0000-0000-0000-0000000386a1', 0::smallint), '',
  'nowy gracz atakuje bota 0');

-- ---- przegrana nie odblokowuje ----
select is(pg_temp.fight('00000000-0000-0000-0000-0000000386a1', 0::smallint, false), 'finished',
  'A przegrywa z botem 0');
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386a1'),
  0::smallint, 'przegrana nie odblokowuje');

-- ---- wygrana z kolejnym botem: +1 ----
select is(pg_temp.fight('00000000-0000-0000-0000-0000000386a1', 0::smallint, true), 'finished',
  'A wygrywa z botem 0');
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386a1'),
  1::smallint, 'wygrana z botem 0 odblokowuje bota 1');
select is(pg_temp.start_err('00000000-0000-0000-0000-0000000386a1', 2::smallint), 'bot_locked',
  'bot 2 dalej zablokowany');

-- ---- wygrana ze zdobytym już botem nic nie zmienia ----
select is(pg_temp.fight('00000000-0000-0000-0000-0000000386a1', 0::smallint, true), 'finished',
  'A znowu wygrywa z botem 0');
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386a1'),
  1::smallint, 'zdobyty bot nie podbija licznika');

-- ---- ponowiony koniec ataku nie liczy się drugi raz ----
create temp table s1 on commit drop as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000386a1', null, 1::smallint, '[[0, 10]]', 386);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000386a1', (select attack_id from s1),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'A wygrywa z botem 1');
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000386a1', (select attack_id from s1),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10]')), 'finished',
  'ponowienie zwraca zapisany wynik');
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386a1'),
  2::smallint, 'ponowienie nie podbija licznika drugi raz');
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386b1'),
  0::smallint, 'postęp B bez zmian');

-- ---- koniec kampanii: najwyżej 40 ----
reset role;
update public.players set bots_beaten = 39 where id = '00000000-0000-0000-0000-0000000386a1';
-- limit 10 startów na 10 minut: starsze ataki testu nie liczą się do limitu
update public.attacks set started_at = now() - interval '1 hour'
where attacker_id = '00000000-0000-0000-0000-0000000386a1';
set local role service_role;
select is(pg_temp.fight('00000000-0000-0000-0000-0000000386a1', 39::smallint, true), 'finished',
  'A wygrywa z ostatnim botem');
select is((select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000386a1'),
  40::smallint, 'wszystkie 40 zamków zdobyte');
reset role;

select * from finish();
rollback;
