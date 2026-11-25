-- Testy weryfikacji ataków PvP na serwerze (#284, #304), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: klient, anon i service_role nie wołają funkcji workera; rola verifier nie czyta tabel; claim nie
-- wydaje tego samego jobu dwa razy; po wygaśnięciu lease job wraca do kolejki; po 3 próbach atak jest
-- `failed`; apply_attack_outcome jest idempotentne; łup, ranking, tarcza i ruiny w trybie enforce liczą się
-- z wyniku workera, nawet gdy klient zgłosił 100 %; cel z atakiem w weryfikacji nie wraca w match_targets
-- i nie da się go zaatakować; tryb shadow daje skutki jak dotąd, a worker tylko porównuje.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(88);

-- A1..A4 atakują D1..D4, A1 jeszcze D5 (uczciwy wynik). Ranking w paśmie 62 000 (bez prawdziwych graczy), bo testy biegną też na projekcie
-- w chmurze, w transakcji, która się cofa. Kolejka i tryb też wracają po rollbacku.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000284a1'), ('00000000-0000-0000-0000-0000000284a2'),
  ('00000000-0000-0000-0000-0000000284a3'), ('00000000-0000-0000-0000-0000000284a4'),
  ('00000000-0000-0000-0000-0000000284d1'), ('00000000-0000-0000-0000-0000000284d2'),
  ('00000000-0000-0000-0000-0000000284d3'), ('00000000-0000-0000-0000-0000000284d4'),
  ('00000000-0000-0000-0000-0000000284d5');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 62000, age = 0 where id in (select id from test_ids);
delete from private.attack_verifications;
update private.settings set value = 'shadow' where key = 'verification_mode';

-- zamek jak w replay_test: 4 budynki do zniszczenia (bez wału i palisady), zapasy 1000/1000/1000/100,
-- dwa oddziały toporników po 10 (unoszą 5 na jednostkę, capacity 100)
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 2840, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'research', jsonb_build_object('done', '["A1", "A2", "G18", "G19", "A43", "A7"]'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[1, 0, 10], [2, 0, 10]]'::jsonb),
  'scout', jsonb_build_object('reports', '[]'::jsonb))
from test_ids t;

create temp table plan_ok (v jsonb) on commit drop;
insert into plan_ok values ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]');
create temp table runs (n int primary key, attack_id uuid) on commit drop;
grant select, insert on runs, plan_ok to service_role;

-- start i zatwierdzenie planu jak Edge Functions start_attack + launch_attack
create function pg_temp.start(n int, p_attacker uuid, p_defender uuid, p_sim integer) returns uuid
language plpgsql as $$
declare
  v uuid;
begin
  select attack_id into v from public.begin_attack(p_attacker, p_defender, null, '[[0, 10], [0, 10]]', 40 + n);
  perform * from public.launch_attack(p_attacker, v, (select p.v from plan_ok p), null, p_sim);
  insert into runs values (n, v);
  return v;
end;
$$;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'ok';
exception when others then
  return sqlerrm;
end;
$$;
grant execute on function pg_temp.err(text) to service_role;
-- zapytanie jako rola verifier (pgTAP zostaje przy właścicielu): wynik jako tekst albo komunikat błędu
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

create function pg_temp.claim(w text) returns text language sql as $$
  select pg_temp.v(format('select private.claim_verification(%L)', w));
$$;
create function pg_temp.submit(k int, res jsonb) returns text language sql as $$
  select pg_temp.v(format('select private.submit_verification(%L, %L)', (select attack_id from runs where n = k), res));
$$;

-- wynik workera jak VerifyJob.verify
create function pg_temp.worker(won boolean, pct int, ids jsonb, alive jsonb) returns jsonb language sql as $$
  select jsonb_build_object('won', won, 'percent', pct, 'stars', jsonb_build_array(pct > 0, pct >= 50, won),
    'destroyed_ids', ids, 'survivors', alive, 'ticks', 1800, 'checksum', 123456789, 'sim_version', 501);
$$;

-- ---- funkcje workera nie są dla klienta ani dla Edge Functions ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000284a1", "role": "authenticated"}', true);
select throws_ok($$select private.claim_verification('w')$$, '42501', null, 'gracz nie wywoła claim_verification');
select throws_ok($$select private.submit_verification(gen_random_uuid(), '{}')$$, '42501', null,
  'gracz nie wywoła submit_verification');
select throws_ok($$select * from private.attack_verifications$$, '42501', null, 'gracz nie czyta kolejki');
reset role;
set local role anon;
select throws_ok($$select private.claim_verification('w')$$, '42501', null, 'anon nie wywoła claim_verification');
select throws_ok($$select private.submit_verification(gen_random_uuid(), '{}')$$, '42501', null,
  'anon nie wywoła submit_verification');
reset role;
set local role service_role;
select throws_ok($$select private.claim_verification('w')$$, '42501', null,
  'service_role nie wywoła claim_verification');
select throws_ok($$select private.submit_verification(gen_random_uuid(), '{}')$$, '42501', null,
  'service_role nie wywoła submit_verification');
select throws_ok($$select private.apply_attack_outcome(gen_random_uuid())$$, '42501', null,
  'service_role nie wywoła apply_attack_outcome');
select throws_ok($$select private.requeue_verification(gen_random_uuid())$$, '42501', null,
  'service_role nie wywoła requeue_verification');
select throws_ok($$select * from private.settings$$, '42501', null, 'service_role nie czyta ustawień');
reset role;

-- ---- rola verifier: tylko dwie funkcje, żadnych tabel ----
select ok(exists (select 1 from pg_roles where rolname = 'verifier'), 'rola verifier istnieje');
select ok(not (select rolsuper or rolbypassrls or rolcreaterole from pg_roles where rolname = 'verifier'),
  'verifier bez superusera, bypassrls i tworzenia ról');
select ok(not pg_has_role('verifier', 'service_role', 'member'), 'verifier nie jest service_role');
select is(array(select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and has_function_privilege('verifier', p.oid, 'execute') order by 1),
  array['claim_verification', 'submit_verification'], 'verifier wywoła tylko claim i submit');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname in ('public', 'private', 'auth') and c.relkind in ('r', 'v', 'm')
      and has_table_privilege('verifier', c.oid, 'select, insert, update, delete')), 0,
  'verifier bez uprawnień do tabel i widoków');
select is(pg_temp.v('select 1 from public.attacks limit 1'), 'permission denied for table attacks', 'verifier nie czyta ataków');
select is(pg_temp.v('select 1 from public.castles limit 1'), 'permission denied for table castles', 'verifier nie czyta zamków');
select is(pg_temp.v('select 1 from public.players limit 1'), 'permission denied for table players', 'verifier nie czyta graczy');
select is(pg_temp.v('select 1 from private.attack_verifications limit 1'), 'permission denied for table attack_verifications',
  'verifier nie czyta kolejki');
select is(pg_temp.v('update private.attack_verifications set attempts = 0 returning 1'),
  'permission denied for table attack_verifications', 'verifier nie zmienia kolejki');
select is(pg_temp.v($$select private.apply_attack_outcome('00000000-0000-0000-0000-000000000000')$$),
  'permission denied for function apply_attack_outcome', 'verifier nie wywoła apply_attack_outcome sam');
select is(pg_temp.v($$select 1 from public.end_attack(gen_random_uuid(), gen_random_uuid(), '{}', '[]', '[]')$$),
  'permission denied for function end_attack', 'verifier nie wywoła end_attack');
select is(pg_temp.v($$select private.claim_verification('worker-1')$$), '<null>', 'pusta kolejka: claim zwraca null');
select is(pg_temp.v($$select private.claim_verification('zły worker; drop')$$), 'bad_worker',
  'identyfikator workera tylko z bezpiecznych znaków');

-- ---- wersja symulacji (launch_attack) ----
set local role service_role;
select is(pg_temp.err($$select pg_temp.start(9, '00000000-0000-0000-0000-0000000284a4',
    '00000000-0000-0000-0000-0000000284d4', 999)$$),
  'unsupported_version', 'wersja bez packa na workerze nie startuje ataku');
select pg_temp.start(1, '00000000-0000-0000-0000-0000000284a1', '00000000-0000-0000-0000-0000000284d1', null);
reset role;
select is((select sim_version from public.attacks where id = (select attack_id from runs where n = 1)), 501,
  'bez wersji od klienta: najnowsza wspierana');

-- ---- tryb shadow: skutki jak dotąd, worker tylko porównuje ----
set local role service_role;
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000284a1',
    (select attack_id from runs where n = 1),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[30, 30, 30, 3]', '[10, 10]')),
  'finished', 'shadow: end_attack kończy atak od razu');
select is(public.record_destroyed('00000000-0000-0000-0000-0000000284a1', (select attack_id from runs where n = 1),
  '[1, 2, 3, 9]'), '{1, 2, 3, 9}', 'shadow: ruiny od razu');
reset role;
select is((select loot from public.attacks where id = (select attack_id from runs where n = 1)), '{30, 30, 30, 3}',
  'shadow: łup z wyniku telefonu');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000284a1'), 1,
  'shadow: ranking od razu');
select is((select verification from public.attacks where id = (select attack_id from runs where n = 1)), 'pending',
  'shadow: atak czeka na porównanie');
select is((select claimed_result -> 'destroyed_ids' from public.attacks where id = (select attack_id from runs where n = 1)),
  '[1, 2, 3, 9]'::jsonb, 'zgłoszone ruiny trafiają do claimed_result');

create temp table job1 on commit drop as select pg_temp.claim('worker-1')::jsonb as j;
select is((select j ->> 'attack_id' from job1), (select attack_id::text from runs where n = 1), 'claim wydaje job');
select ok((select j ? 'castle' and not (j -> 'castle') ? 'scout' and (j ->> 'sim_version')::int = 501
    and j -> 'army' = '[[0, 10], [0, 10]]'::jsonb and j ? 'plan' and j ? 'techs' and j ? 'battle_seed' from job1),
  'job ma kształt attack_replay z sim_version, bez raportów zwiadu');
select is(pg_temp.claim('worker-2'), '<null>', 'drugi worker nie dostaje tego samego jobu');
-- uczciwy wynik telefonu, ale worker policzył inaczej
select is(pg_temp.submit(1, pg_temp.worker(true, 75, '[1, 2, 3]', '[10, 10]')), 'mismatch',
  'shadow: inny wynik → mismatch');
select is(pg_temp.submit(1, pg_temp.worker(true, 75, '[1, 2, 3]', '[10, 10]')), 'not_pending',
  'drugi wynik dla tego samego ataku odrzucony');
select is((select loot from public.attacks where id = (select attack_id from runs where n = 1)), '{30, 30, 30, 3}',
  'shadow: wynik workera nie zmienia łupu');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000284a1'), 1,
  'shadow: wynik workera nie liczy rankingu drugi raz');
select is((select (verified_result ->> 'percent')::int from public.attacks where id = (select attack_id from runs where n = 1)),
  75, 'wynik workera zapisany');
select is((select count(*)::int from private.attack_verifications), 0, 'po wyniku job znika z kolejki');

-- ---- tryb enforce: fałszywe 100 % → łup, ranking, tarcza i ruiny z wyniku workera ----
update private.settings set value = 'enforce' where key = 'verification_mode';
set local role service_role;
select pg_temp.start(2, '00000000-0000-0000-0000-0000000284a2', '00000000-0000-0000-0000-0000000284d2', 501);
select is((select row(status, loot)::text from public.end_attack('00000000-0000-0000-0000-0000000284a2',
    (select attack_id from runs where n = 2),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[30, 30, 30, 3]', '[10, 10]')),
  '(verifying,)', 'enforce: end_attack bez łupu, status verifying');
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000284a2',
    (select attack_id from runs where n = 2),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[30, 30, 30, 3]', '[10, 10]')),
  'verifying', 'enforce: ponowienie dalej verifying');
select is(public.record_destroyed('00000000-0000-0000-0000-0000000284a2', (select attack_id from runs where n = 2),
  '[1, 2, 3, 9]'), '{1, 2, 3, 9}', 'enforce: lista ruin przyjęta do porównania');
-- cel w weryfikacji jest zablokowany
select is(pg_temp.err($$select * from public.begin_attack('00000000-0000-0000-0000-0000000284a3',
    '00000000-0000-0000-0000-0000000284d2', null, '[[0, 10]]', 77)$$), 'target_busy',
  'enforce: celu w weryfikacji nie da się zaatakować');
select ok('00000000-0000-0000-0000-0000000284d2' not in (select player_id from public.match_targets('00000000-0000-0000-0000-0000000284a3')),
  'enforce: cel w weryfikacji nie wraca w match_targets');
reset role;
select ok((select destroyed is null and outcome_applied_at is null from public.attacks where id = (select attack_id from runs where n = 2)),
  'enforce: bez ruin przed weryfikacją');
select is((select count(*)::int from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000284a2'), 0,
  'enforce: bez łupu przed weryfikacją');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000284a2'), 0,
  'enforce: bez rankingu przed weryfikacją');
select is((select count(*)::int from public.shields where player_id = '00000000-0000-0000-0000-0000000284d2'), 0,
  'enforce: bez tarczy przed weryfikacją');

select is(pg_temp.claim('worker-1')::jsonb ->> 'attack_id', (select attack_id::text from runs where n = 2),
  'enforce: worker bierze job');
-- zły kształt: job zostaje, z kodem błędu i wolnym lease
select is(pg_temp.submit(2, pg_temp.worker(true, 100, '[1, 2, 3, 9]', '[10, 10]') || '{"sim_version": 400}'), 'rejected',
  'wynik z inną wersją symulacji odrzucony');
select is((select last_error from private.attack_verifications where attack_id = (select attack_id from runs where n = 2)),
  'bad_result', 'odrzucony wynik: kod błędu bez danych');
select is((select verification from public.attacks where id = (select attack_id from runs where n = 2)), 'pending',
  'odrzucony wynik nie zmienia ataku');
select is(pg_temp.submit(2, pg_temp.worker(false, 25, '[2]', '[3, 0]')), 'lease_expired',
  'bez ważnego lease wynik odrzucony');
select is(pg_temp.claim('worker-2')::jsonb ->> 'attack_id', (select attack_id::text from runs where n = 2),
  'po zwolnieniu lease job wraca do kolejki');
-- prawda: przegrana z 25 %, ocalało 3 toporników
select is(pg_temp.submit(2, pg_temp.worker(false, 25, '[2]', '[3, 0]')), 'mismatch',
  'enforce: fałszywe 100 % → mismatch');
select is((select row(result, loot, destroyed)::text from public.attacks where id = (select attack_id from runs where n = 2)),
  row('{"won": false, "stars": [true, false, false], "percent": 25}'::jsonb, '{0,0,0,0}'::integer[], '{2}'::integer[])::text,
  'enforce: wynik, łup i ruiny z wyniku workera');
select is((select count(*)::int from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000284a2'), 0,
  'enforce: przegrana nie daje łupu mimo zgłoszonego 100 %');
select ok((select attack_games = 1 and attack_rating < 62000 from public.players where id = '00000000-0000-0000-0000-0000000284a2'),
  'enforce: ranking liczy przegraną');
select is((select count(*)::int from public.shields where player_id = '00000000-0000-0000-0000-0000000284d2'), 0,
  'enforce: 25 % nie daje tarczy');
select ok(not private.apply_attack_outcome((select attack_id from runs where n = 2)), 'apply_attack_outcome drugi raz nic nie robi');
select is((select attack_games from public.players where id = '00000000-0000-0000-0000-0000000284a2'), 1,
  'po drugim apply ranking bez zmian');
set local role service_role;
select is((select row(status, loot)::text from public.end_attack('00000000-0000-0000-0000-0000000284a2',
    (select attack_id from runs where n = 2),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[30, 30, 30, 3]', '[10, 10]')),
  '(finished,"{0,0,0,0}")', 'po weryfikacji ponowienie zwraca wynik serwera');
-- match_targets losuje 3 z pasujących: pozostali gracze testu chwilowo pod tarczą, żeby wynik nie był losowy
reset role;
create temp table extra_shields on commit drop as
  select id from test_ids where id not in ('00000000-0000-0000-0000-0000000284d2', '00000000-0000-0000-0000-0000000284a3')
    and id not in (select player_id from public.shields);
insert into public.shields (player_id, until) select id, now() + interval '1 hour' from extra_shields;
set local role service_role;
select ok('00000000-0000-0000-0000-0000000284d2' in (select player_id from public.match_targets('00000000-0000-0000-0000-0000000284a3')),
  'po weryfikacji cel wraca w match_targets');
reset role;
delete from public.shields where player_id in (select id from extra_shields);
set local role service_role;

-- wygrana: łup z capacity ocalałych według workera (4 toporników = 20), tarcza od 30 %
select pg_temp.start(3, '00000000-0000-0000-0000-0000000284a3', '00000000-0000-0000-0000-0000000284d3', null);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000284a3',
    (select attack_id from runs where n = 3),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[30, 30, 30, 3]', '[10, 10]')),
  'verifying', 'enforce: druga bitwa w weryfikacji');
reset role;
-- bez zgłoszonych ruin job czeka (15 s), żeby nie wyprzedzić record_destroyed z finish_attack
select is(pg_temp.claim('worker-1'), '<null>', 'job czeka na ruiny z telefonu');
update private.attack_verifications set not_before = now();
select is(pg_temp.claim('worker-1')::jsonb ->> 'attack_id', (select attack_id::text from runs where n = 3),
  'worker bierze drugi job');
select is(pg_temp.submit(3, pg_temp.worker(true, 100, '[1, 2, 3, 9]', '[4, 0]')), 'mismatch',
  'inni ocaleli → mismatch');
-- zapasy 1000: 100 na surowiec, złoto 10; suma 310 > capacity 20 → 100 × 20 / 310 = 6, 10 × 20 / 310 = 0
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000284a3'),
  '{6, 6, 6, 0}'::bigint[], 'enforce: łup z ocalałych według workera');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000284d3'),
  '{-6, -6, -6, 0}'::bigint[], 'enforce: obrońca traci łup z wyniku workera');
select is((select count(*)::int from public.shields where player_id = '00000000-0000-0000-0000-0000000284d3'), 1,
  'enforce: tarcza z wyniku workera');

-- uczciwy klient: ten sam wynik → verified, łup pełny w capacity (310 > 100 → 100 × 100 / 310 = 32, złoto 3)
set local role service_role;
select pg_temp.start(5, '00000000-0000-0000-0000-0000000284a1', '00000000-0000-0000-0000-0000000284d5', 501);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000284a1',
    (select attack_id from runs where n = 5),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[32, 32, 32, 3]', '[10, 10]')),
  'verifying', 'enforce: uczciwa bitwa w weryfikacji');
select is(public.record_destroyed('00000000-0000-0000-0000-0000000284a1', (select attack_id from runs where n = 5),
  '[9, 3, 2, 1]'), '{9, 3, 2, 1}', 'enforce: zgłoszone ruiny w innej kolejności');
reset role;
select isnt(pg_temp.claim('worker-1'), '<null>', 'worker bierze uczciwy job');
select is(pg_temp.submit(5, pg_temp.worker(true, 100, '[1, 2, 3, 9]', '[10, 10]')), 'verified',
  'zgodny wynik → verified');
select is((select row(loot, destroyed)::text from public.attacks where id = (select attack_id from runs where n = 5)),
  row('{32,32,32,3}'::integer[], '{1,2,3,9}'::integer[])::text, 'verified: łup i ruiny z wyniku serwera');

-- ---- 3 nieudane próby → failed: bez skutków, cel odblokowany ----
set local role service_role;
select pg_temp.start(4, '00000000-0000-0000-0000-0000000284a4', '00000000-0000-0000-0000-0000000284d4', null);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000284a4',
    (select attack_id from runs where n = 4),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[30, 30, 30, 3]', '[10, 10]')),
  'verifying', 'enforce: trzecia bitwa w weryfikacji');
reset role;
update private.attack_verifications set not_before = now();
-- trzy claimy bez wyniku (now() w transakcji stoi, więc lease wygasza się ręcznie)
select isnt(pg_temp.claim('worker-1'), '<null>', 'próba 1');
update private.attack_verifications set leased_until = now() - interval '1 second';
select isnt(pg_temp.claim('worker-1'), '<null>', 'próba 2');
select is((select row(attempts, last_error)::text from private.attack_verifications), '(2,lease_expired)',
  'wygasły lease liczy próbę i zostawia kod błędu');
update private.attack_verifications set leased_until = now() - interval '1 second';
select isnt(pg_temp.claim('worker-1'), '<null>', 'próba 3');
update private.attack_verifications set leased_until = now() - interval '1 second';
select is(pg_temp.claim('worker-1'), '<null>', 'po 3 próbach job nie wraca');
select is((select verification from public.attacks where id = (select attack_id from runs where n = 4)), 'failed',
  'po 3 próbach atak jest failed');
select ok((select loot is null and outcome_applied_at is null from public.attacks where id = (select attack_id from runs where n = 4)),
  'failed: bez łupu i skutków');
select ok((select count(*) = 0 from public.attacks a where a.defender_id = '00000000-0000-0000-0000-0000000284d4'
    and a.verification = 'pending' and a.outcome_applied_at is null), 'failed: cel odblokowany');
select is((select row(queue_length, verified_24h, failed_24h)::text from private.verification_health), '(0,1,1)',
  'verification_health: jeden wiersz z pustą kolejką');
select private.requeue_verification((select attack_id from runs where n = 4));
select is((select row(attempts, last_error)::text from private.attack_verifications), '(0,)',
  'requeue wrzuca job od nowa');

select * from finish();
rollback;
