-- Testy weryfikacji ataków na zamki-boty (#413, ADR 0016), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: start z planem zapisuje plan, badania i wersję symulacji w jednej transakcji (zły plan albo wersja
-- bez packa nie zostawia ataku); klient i anon nie wołają begin_bot_attack; tryb `bot_verification_mode`
-- jest osobny od PvP; w shadow skutki wchodzą od razu, a job jest gotowy bez czekania na ruiny; kolejka daje
-- najpierw PvP; w enforce wygrana z telefonu nie daje łupu, punktów PvE ani postępu kampanii, a dają je
-- dopiero wynik workera (mismatch: wynik workera); łup z wyniku workera liczy skarbiec bota, powtórkę i capacity;
-- atak bez zatwierdzonego planu w enforce nic nie daje.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(41);

-- A = 413a1 atakuje boty, D1 i D2 to cele PvP. Ranking w paśmie 63 000 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa. Kolejka i tryby też wracają po rollbacku.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000413a1'), ('00000000-0000-0000-0000-0000000413d1'),
  ('00000000-0000-0000-0000-0000000413d2');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 63000, age = 0 where id in (select id from test_ids);
delete from private.attack_verifications;
update private.settings set value = 'shadow' where key = 'verification_mode';

-- zamek jak w attack_verification_test: dwa oddziały toporników po 10 (unoszą 5 na jednostkę), badania A1 i A7
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4130, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'research', jsonb_build_object('done', '["A1", "A2", "G18", "G19", "A43", "A7"]'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb))
from test_ids t;

create temp table plan_ok (v jsonb) on commit drop;
insert into plan_ok values ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]');
create temp table runs (n int primary key, attack_id uuid) on commit drop;
grant select, insert on runs, plan_ok to service_role;

-- start ataku na bota z planem jak Edge Function start_attack (#413)
create function pg_temp.bot(n int, p_bot smallint) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  select attack_id into v from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', p_bot,
    '[[0, 10], [0, 10]]', 4130 + n, (select p.v from plan_ok p), null, 501);
  insert into runs values (n, v);
  return v;
end;
$$;
-- koniec ataku z wynikiem z telefonu (wygrana 100 %, wszyscy ocaleli); zwraca status z end_attack
create function pg_temp.finish(n int) returns text language sql as $$
  select status from public.end_attack('00000000-0000-0000-0000-0000000413a1', (select attack_id from runs where runs.n = finish.n),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10, 10]');
$$;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'ok';
exception when others then
  return sqlerrm;
end;
$$;
grant execute on function pg_temp.err(text) to service_role, authenticated, anon;
-- zapytanie jako rola verifier: wynik jako tekst albo komunikat błędu
create function pg_temp.v(q text) returns text language plpgsql as $$
declare
  r text;
begin
  set local role verifier;
  execute q into r;
  reset role;
  return coalesce(r, '<null>');
exception when others then
  return sqlerrm;
end;
$$;
create function pg_temp.claim() returns jsonb language sql as $$
  select pg_temp.v($q$select private.claim_verification('worker-413')$q$)::jsonb;
$$;
create function pg_temp.submit(k int, res jsonb) returns text language sql as $$
  select pg_temp.v(format('select private.submit_verification(%L, %L)', (select attack_id from runs where n = k), res));
$$;
-- wynik workera jak VerifyJob.verify (zniszczone budynki bota zna tylko worker)
create function pg_temp.worker(won boolean, pct int, alive jsonb) returns jsonb language sql as $$
  select jsonb_build_object('won', won, 'percent', pct, 'stars', jsonb_build_array(pct > 0, pct >= 50, won),
    'destroyed_ids', '[3, 7, 12]'::jsonb, 'survivors', alive, 'ticks', 1800, 'checksum', 4130, 'sim_version', 501);
$$;
create function pg_temp.beaten() returns smallint language sql as $$
  select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000413a1';
$$;
create function pg_temp.pve() returns integer language sql as $$
  select pve_points from public.players where id = '00000000-0000-0000-0000-0000000413a1';
$$;

-- ---- przełącznik ----
select is((select value from private.settings where key = 'bot_verification_mode'), 'shadow',
  'weryfikacja botów domyślnie w trybie shadow');
select throws_ok($$update private.settings set value = 'zawsze' where key = 'bot_verification_mode'$$,
  '23514', null, 'tryb botów tylko off, shadow albo enforce');

-- ---- begin_bot_attack tylko dla Edge Function ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000413a1", "role": "authenticated"}', true);
select alike(pg_temp.err($$select * from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', 0::smallint,
  '[[0, 10]]', 1, '[]', null, 501)$$), 'permission denied%', 'gracz nie wywoła begin_bot_attack');
reset role;
set local role anon;
select alike(pg_temp.err($$select * from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', 0::smallint,
  '[[0, 10]]', 1, '[]', null, 501)$$), 'permission denied%', 'anon nie wywoła begin_bot_attack');
reset role;

-- ---- start z planem: jedna transakcja ----
set local role service_role;
select alike(pg_temp.err($$select * from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', 0::smallint,
  '[[0, 10], [0, 10]]', 1, '[{"squad": 9}]', null, 501)$$), '%bad_plan%', 'zły plan odrzucony');
select alike(pg_temp.err($$select * from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', 0::smallint,
  '[[0, 10], [0, 10]]', 1, (select v from plan_ok), null, 999)$$), '%unsupported_version%', 'wersja bez packa odrzucona');
select alike(pg_temp.err($$select * from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', 1::smallint,
  '[[0, 10], [0, 10]]', 1, (select v from plan_ok), null, 501)$$), '%bot_locked%', 'kampania dalej pilnowana');
select is((select count(*)::int from public.attacks where attacker_id = '00000000-0000-0000-0000-0000000413a1'), 0,
  'odrzucony start nie zostawia ataku');

create temp table s1 on commit drop as
  select * from public.begin_bot_attack('00000000-0000-0000-0000-0000000413a1', 0::smallint, '[[0, 10], [0, 10]]',
    4131, (select v from plan_ok), null, 501);
insert into runs select 1, attack_id from s1;
select is((select battle_seed from s1), 4131::bigint, 'odpowiedź niesie seed bitwy');
select is((select plan from s1), (select v from plan_ok), 'odpowiedź niesie plan zapisany na serwerze');
select ok((select techs @> array['A1', 'A7'] from s1), 'badania atakującego z zamku na serwerze');
select is((select ruler_perk from s1), (-1)::smallint, 'perk władcy z zamku na serwerze');
reset role;
select is((select sim_version from public.attacks where id = (select attack_id from s1)), 501,
  'atak na bota ma wersję symulacji');
select ok((select launched_at is not null and orders is not null from public.attacks
  where id = (select attack_id from s1)), 'plan zatwierdzony przy starcie');

-- ---- shadow: skutki od razu, job gotowy bez czekania na ruiny ----
set local role service_role;
select is(pg_temp.finish(1), 'finished', 'shadow: wynik przyjęty od razu');
reset role;
select is((select verification from public.attacks where id = (select attack_id from s1)), 'pending',
  'shadow: atak na bota czeka na worker');
select ok((select not_before <= now() from private.attack_verifications where attack_id = (select attack_id from s1)),
  'job z botem gotowy od razu');
select is(pg_temp.beaten(), 1::smallint, 'shadow: kampania jak dotąd z wyniku telefonu');
select is(pg_temp.pve(), 10, 'shadow: punkty PvE jak dotąd (10 + 5 × 0)');

-- ---- kolejka: najpierw PvP ----
set local role service_role;
create temp table p1 on commit drop as
  select attack_id from public.begin_attack('00000000-0000-0000-0000-0000000413a1', '00000000-0000-0000-0000-0000000413d1',
    null, '[[0, 10], [0, 10]]', 4190);
select is((select count(*)::int from public.launch_attack('00000000-0000-0000-0000-0000000413a1', (select attack_id from p1),
  (select v from plan_ok), null, 501)), 1, 'atak PvP zatwierdzony');
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000413a1', (select attack_id from p1),
  '{"won": false, "percent": 0, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[10, 10]')), 'finished',
  'atak PvP w shadow');
reset role;
-- job z botem starszy niż PvP, a PvP już bez czekania na ruiny
update private.attack_verifications set created_at = now() - interval '1 minute' where attack_id = (select attack_id from s1);
update private.attack_verifications set not_before = now() where attack_id = (select attack_id from p1);
select is((pg_temp.claim() ->> 'attack_id')::uuid, (select attack_id from p1), 'kolejka daje najpierw PvP');
create temp table j1 on commit drop as select pg_temp.claim() as job;
select is(((select job from j1) ->> 'attack_id')::uuid, (select attack_id from s1), 'potem atak na bota');
select is(((select job from j1) ->> 'bot_idx')::int, 0, 'job niesie numer zamku-bota');
select is((select job -> 'plan' from j1), (select v from plan_ok), 'job niesie zapisany plan');
select is(pg_temp.submit(1, pg_temp.worker(true, 100, '[10, 10]')), 'verified',
  'zgodny wynik bota: verified (budynki bota bez kopii w bazie)');

-- ---- enforce: wygrana z telefonu nic nie daje ----
update private.settings set value = 'enforce' where key = 'bot_verification_mode';
set local role service_role;
create temp table b2 on commit drop as select pg_temp.bot(2, 1::smallint);
select is(pg_temp.finish(2), 'verifying', 'enforce: wynik czeka na worker');
reset role;
select is(pg_temp.beaten(), 1::smallint, 'enforce: wygrana z telefonu nie odblokowuje');
select is(pg_temp.pve(), 10, 'enforce: wygrana z telefonu nie daje punktów PvE');
select is((select loot from public.attacks where id = (select attack_id from runs where n = 2)), null::integer[],
  'enforce: bez łupu przed wynikiem workera');
create temp table c2 on commit drop as select pg_temp.claim() as job;
select is(pg_temp.submit(2, pg_temp.worker(false, 20, '[0, 3]')), 'mismatch', 'oszust: przegrana według workera');
select is(pg_temp.beaten(), 1::smallint, 'mismatch: postęp z wyniku workera');

-- ---- enforce: uczciwa wygrana z wyniku workera ----
set local role service_role;
create temp table b3 on commit drop as select pg_temp.bot(3, 1::smallint), pg_temp.finish(3);
reset role;
create temp table c3 on commit drop as select pg_temp.claim() as job;
select is(pg_temp.submit(3, pg_temp.worker(true, 60, '[10, 5]')), 'mismatch', 'inny procent niż na telefonie: mismatch');
-- skarbiec bota 1: 1500 / 1500 / 1500 / 30 → 90, 90, 90, 1 przy 60 %; capacity 15 × 5 = 75 → 24, 24, 24, 0
select is((select loot from public.attacks where id = (select attack_id from runs where n = 3)), array[24, 24, 24, 0],
  'łup z wyniku workera: skarbiec bota i capacity ocalałych');
select is(pg_temp.beaten(), 2::smallint, 'wygrana według workera odblokowuje bota 2');
select is(pg_temp.pve(), 25, 'punkty PvE z wyniku workera (10 + 5 × 1)');
select is((select private.apply_attack_outcome((select attack_id from runs where n = 3))), false,
  'skutki ataku na bota wchodzą raz');

-- ---- enforce: powtórka zdobytego zamku i atak bez planu ----
update public.attacks set started_at = now() - interval '1 hour'
where attacker_id = '00000000-0000-0000-0000-0000000413a1';
set local role service_role;
create temp table b4 on commit drop as select pg_temp.bot(4, 0::smallint), pg_temp.finish(4);
reset role;
create temp table c4 on commit drop as select pg_temp.claim() as job;
create temp table r4 on commit drop as select pg_temp.submit(4, pg_temp.worker(true, 60, '[10, 5]')) as r;
-- skarbiec bota 0: 60, 60, 60, 1 przy 60 %, powtórka 30, 30, 30, 0; capacity 75 → 25, 25, 25, 0
select is((select loot from public.attacks where id = (select attack_id from runs where n = 4)), array[25, 25, 25, 0],
  'powtórka zdobytego zamku: połowa łupu');
set local role service_role;
create temp table s5 on commit drop as
  select attack_id from public.begin_attack('00000000-0000-0000-0000-0000000413a1', null, 2::smallint, '[[0, 10], [0, 10]]', 4135);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000413a1', (select attack_id from s5),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10, 10]')), 'finished',
  'stary klient bez planu w enforce: wynik przyjęty');
reset role;
select is(pg_temp.beaten(), 2::smallint, 'bez planu na serwerze wygrana nie odblokowuje');

-- ---- PvP nie zależy od trybu botów ----
set local role service_role;
create temp table p2 on commit drop as
  select attack_id from public.begin_attack('00000000-0000-0000-0000-0000000413a1', '00000000-0000-0000-0000-0000000413d2',
    null, '[[0, 10], [0, 10]]', 4191);
create temp table l2 on commit drop as
  select * from public.launch_attack('00000000-0000-0000-0000-0000000413a1', (select attack_id from p2), (select v from plan_ok), null, 501);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000413a1', (select attack_id from p2),
  '{"won": false, "percent": 0, "stars": [false, false, false]}', '[0, 0, 0, 0]', '[10, 10]')), 'finished',
  'PvP dalej w shadow przy enforce dla botów');
reset role;

select * from finish();
rollback;
