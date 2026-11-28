-- Testy porzuconego ataku rozstrzyganego przez serwer (#425, ADR 0018), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: porzucony atak z zatwierdzonym planem (bot po begin_bot_attack, PvP po launch_attack) w shadow i enforce
-- trafia do kolejki od razu gotowy, a wynik workera zamyka go jako finished ze skutkami (łup, kampania, punkty PvE,
-- ranking), także gdy telefon nic nie wysłał; w off i bez planu porzucenie jest jak dotąd (PvP: przegrana od razu);
-- ranking porzuconego ataku w kolejce czeka na worker, a po `failed` liczy się jako przegrana raz; claim_verification
-- sam porzuca wygasłe ataki; obrońca porzuconego ataku w kolejce jest zablokowany; spóźniony wynik z telefonu niczego
-- nie zmienia.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(37);

-- A atakuje, D1–D3 to cele PvP. Ranking w paśmie 64 250 (bez prawdziwych graczy), bo testy biegną też na projekcie
-- w chmurze, w transakcji, która się cofa. Kolejka i tryby też wracają po rollbacku.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000425a1'), ('00000000-0000-0000-0000-0000000425d1'),
  ('00000000-0000-0000-0000-0000000425d2'), ('00000000-0000-0000-0000-0000000425d3');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 64250, age = 0 where id in (select id from test_ids);
delete from private.attack_verifications;
update private.settings set value = 'shadow' where key = 'verification_mode';
update private.settings set value = 'shadow' where key = 'bot_verification_mode';

-- zamek jak w bot_verification_test: dwa oddziały toporników po 10 (unoszą 5 na jednostkę), badania A1 i A7
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4250, 8, jsonb_build_object(
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
  select attack_id into v from public.begin_bot_attack('00000000-0000-0000-0000-0000000425a1', p_bot,
    '[[0, 10], [0, 10]]', 4250 + n, (select p.v from plan_ok p), null, 501);
  insert into runs values (n, v);
  return v;
end;
$$;
-- start ataku na gracza; z planem (launch) albo bez
create function pg_temp.pvp(n int, d uuid, launch boolean) returns uuid language plpgsql as $$
declare
  v uuid;
begin
  select attack_id into v from public.begin_attack('00000000-0000-0000-0000-0000000425a1', d, null,
    '[[0, 10], [0, 10]]', 4250 + n);
  if launch then
    perform 1 from public.launch_attack('00000000-0000-0000-0000-0000000425a1', v, (select p.v from plan_ok p), null, 501);
  end if;
  insert into runs values (n, v);
  return v;
end;
$$;
create function pg_temp.id(k int) returns uuid language sql as $$
  select attack_id from runs where n = k;
$$;
grant execute on function pg_temp.id(int) to service_role;
create function pg_temp.err(q text) returns text language plpgsql as $$
begin
  execute q;
  return 'ok';
exception when others then
  return sqlerrm;
end;
$$;
grant execute on function pg_temp.err(text) to service_role;
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
  select nullif(pg_temp.v($q$select private.claim_verification('worker-425')$q$), '<null>')::jsonb;
$$;
create function pg_temp.submit(k int, res jsonb) returns text language sql as $$
  select pg_temp.v(format('select private.submit_verification(%L, %L)', pg_temp.id(k), res));
$$;
-- wynik workera jak VerifyJob.verify; przy graczu zniszczone budynki muszą być z kopii zamku (id 3)
create function pg_temp.worker(won boolean, pct int, alive jsonb, ids jsonb) returns jsonb language sql as $$
  select jsonb_build_object('won', won, 'percent', pct, 'stars', jsonb_build_array(pct > 0, pct >= 50, won),
    'destroyed_ids', ids, 'survivors', alive, 'ticks', 1800, 'checksum', 4250, 'sim_version', 501);
$$;
create function pg_temp.beaten() returns smallint language sql as $$
  select bots_beaten from public.players where id = '00000000-0000-0000-0000-0000000425a1';
$$;
create function pg_temp.pve() returns integer language sql as $$
  select pve_points from public.players where id = '00000000-0000-0000-0000-0000000425a1';
$$;
create function pg_temp.rating() returns integer language sql as $$
  select attack_rating from public.players where id = '00000000-0000-0000-0000-0000000425a1';
$$;
create function pg_temp.games() returns integer language sql as $$
  select attack_games from public.players where id = '00000000-0000-0000-0000-0000000425a1';
$$;
create function pg_temp.queued(k int) returns boolean language sql as $$
  select exists (select 1 from private.attack_verifications v where v.attack_id = pg_temp.id(k) and v.not_before <= now());
$$;
-- starty z przeszłości: limit 10 startów na 10 minut nie blokuje kolejnych kroków testu
create function pg_temp.age_all() returns void language sql as $$
  update public.attacks set started_at = started_at - interval '11 minutes'
  where attacker_id = '00000000-0000-0000-0000-0000000425a1' and status <> 'started';
$$;

-- ---- bot w shadow: porzucenie po poznaniu seeda ----
set local role service_role;
select ok(pg_temp.bot(1, 0::smallint) is not null, 'start wyprawy z planem');
select ok(pg_temp.bot(2, 0::smallint) is not null, 'drugi start bez wysłania wyniku pierwszego');
reset role;
select is((select status from public.attacks where id = pg_temp.id(1)), 'abandoned', 'nowy start porzuca poprzedni');
select is((select verification from public.attacks where id = pg_temp.id(1)), 'pending',
  'porzucona wyprawa z planem czeka na worker');
select ok(pg_temp.queued(1), 'job porzuconej wyprawy gotowy od razu');
select is(pg_temp.beaten(), 0::smallint, 'przed wynikiem workera bez postępu kampanii');

-- spóźniony wynik z telefonu nie zmienia porzuconego ataku
set local role service_role;
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000425a1', pg_temp.id(1),
  '{"won": true, "percent": 100, "stars": [true, true, true]}', '[0, 0, 0, 0]', '[10, 10]')), 'abandoned',
  'spóźniony wynik z telefonu odrzucony');
reset role;

-- ostatni atak w toku (2) też się porzuca, ale kolejka bierze najpierw starszy
update private.attack_verifications set created_at = now() - interval '1 minute' where attack_id = pg_temp.id(1);
select is((pg_temp.claim() ->> 'attack_id')::uuid, pg_temp.id(1), 'worker bierze porzuconą wyprawę');
select is(pg_temp.submit(1, pg_temp.worker(true, 60, '[10, 5]', '[3]')), 'verified',
  'bez wyniku z telefonu zgodny wynik workera to verified');
select is((select status from public.attacks where id = pg_temp.id(1)), 'finished', 'wynik workera zamyka atak');
select is((select result -> 'won' from public.attacks where id = pg_temp.id(1)), 'true'::jsonb,
  'wynik ataku z workera');
-- skarbiec bota 0: 1000 / 1000 / 1000 / 20 → 60, 60, 60, 1 przy 60 %; capacity 15 × 5 = 75 z 181 → 24, 24, 24, 0
select is((select loot from public.attacks where id = pg_temp.id(1)), array[24, 24, 24, 0],
  'łup z wyniku workera dla porzuconej wyprawy');
select is(pg_temp.beaten(), 1::smallint, 'wygrana według workera odblokowuje kolejnego bota');
select is(pg_temp.pve(), 10, 'punkty PvE z wyniku workera (10 + 5 × 0)');
select ok((select claimed_result is null and finished_at is not null and outcome_applied_at is not null
  from public.attacks where id = pg_temp.id(1)), 'rozstrzygnięty przez serwer: bez wyniku z telefonu');

-- ---- claim_verification sam porzuca wygasłe ataki ----
update public.attacks set started_at = now() - interval '11 minutes' where id = pg_temp.id(2);
create temp table c2 on commit drop as select pg_temp.claim() as job;
select is(((select job from c2) ->> 'attack_id')::uuid, pg_temp.id(2), 'wygasła wyprawa trafia do kolejki z claim');
select is(pg_temp.submit(2, pg_temp.worker(false, 20, '[0, 3]', '[]')), 'verified', 'przegrana według workera');
select is(pg_temp.beaten(), 1::smallint, 'przegrana porzuconej wyprawy nie odblokowuje');
select is((select loot from public.attacks where id = pg_temp.id(2)), array[0, 0, 0, 0], 'przegrana bez łupu');

-- ---- bot w off i bez planu: jak dotąd ----
update private.settings set value = 'off' where key = 'bot_verification_mode';
select pg_temp.age_all();
set local role service_role;
select ok(pg_temp.bot(3, 0::smallint) is not null, 'wyprawa w trybie off');
select ok((select attack_id from public.begin_attack('00000000-0000-0000-0000-0000000425a1', null, 0::smallint,
  '[[0, 10], [0, 10]]', 4254)) is not null, 'kolejny start');
reset role;
select ok((select status = 'abandoned' and verification is null from public.attacks where id = pg_temp.id(3)),
  'off: porzucenie bez weryfikacji');
update private.settings set value = 'shadow' where key = 'bot_verification_mode';
set local role service_role;
insert into runs select 4, id from public.attacks
where attacker_id = '00000000-0000-0000-0000-0000000425a1' and status = 'started';
select ok(pg_temp.bot(5, 0::smallint) is not null, 'start po starcie bez planu');
reset role;
select ok((select status = 'abandoned' and verification is null from public.attacks where id = pg_temp.id(4)),
  'start bez planu (stary klient): porzucenie bez weryfikacji');
-- porzucenie 5 (kolejny test) czyści kolejkę z jego jobu
delete from private.attack_verifications;
update public.attacks set status = 'abandoned', verification = null where id = pg_temp.id(5);

-- ---- PvP bez planu: przegrana od razu ----
select pg_temp.age_all();
create temp table r0 on commit drop as select pg_temp.rating() as r, pg_temp.games() as g;
set local role service_role;
select ok(pg_temp.pvp(6, '00000000-0000-0000-0000-0000000425d1', false) is not null, 'atak PvP bez zatwierdzenia planu');
reset role;
update public.attacks set started_at = now() - interval '11 minutes' where id = pg_temp.id(6);
create temp table c6 on commit drop as select pg_temp.claim() as job;
select ok((select status = 'abandoned' and verification is null from public.attacks where id = pg_temp.id(6)),
  'PvP bez planu: porzucenie bez weryfikacji');
select is(pg_temp.games(), (select g from r0) + 1, 'PvP bez planu: ranking od razu jak przegrana');

-- ---- PvP z planem: ranking z wyniku workera ----
create temp table r1 on commit drop as select pg_temp.rating() as r, pg_temp.games() as g;
set local role service_role;
select ok(pg_temp.pvp(7, '00000000-0000-0000-0000-0000000425d2', true) is not null, 'atak PvP z planem');
reset role;
update public.attacks set started_at = now() - interval '11 minutes' where id = pg_temp.id(7);
create temp table c7 on commit drop as select pg_temp.claim() as job;
select is(((select job from c7) ->> 'attack_id')::uuid, pg_temp.id(7), 'porzucony atak PvP w kolejce');
select is(pg_temp.games(), (select g from r1), 'ranking czeka na wynik workera');
set local role service_role;
select alike(pg_temp.err($$select * from public.begin_attack('00000000-0000-0000-0000-0000000425d3',
  '00000000-0000-0000-0000-0000000425d2', null, '[[0, 10]]', 4299)$$), '%target_busy%',
  'obrońca porzuconego ataku w kolejce zablokowany');
reset role;
select is(pg_temp.submit(7, pg_temp.worker(true, 100, '[10, 10]', '[3]')), 'verified', 'wygrana według workera');
select ok(pg_temp.games() = (select g from r1) + 1 and pg_temp.rating() > (select r from r1),
  'ranking raz, z wygranej według workera');
select ok(exists (select 1 from public.shields s
  where s.player_id = '00000000-0000-0000-0000-0000000425d2' and s.until > now()),
  'obrońca dostaje tarczę z wyniku workera');

-- ---- PvP z planem: worker nie policzył (failed) ----
select pg_temp.age_all();
create temp table r2 on commit drop as select pg_temp.rating() as r, pg_temp.games() as g;
set local role service_role;
select ok(pg_temp.pvp(8, '00000000-0000-0000-0000-0000000425d3', true) is not null, 'kolejny atak PvP z planem');
reset role;
update public.attacks set started_at = now() - interval '11 minutes' where id = pg_temp.id(8);
create temp table c8 on commit drop as select pg_temp.claim() as job;
update private.attack_verifications set attempts = 3, leased_until = now() - interval '1 second'
where attack_id = pg_temp.id(8);
create temp table c8b on commit drop as select pg_temp.claim() as job;
select is(pg_temp.games(), (select g from r2) + 1, 'failed: porzucony atak raz jako przegrana');
select throws_ok(format('select private.requeue_verification(%L)', pg_temp.id(8)), 'P0001', 'attack_not_found',
  'requeue nie zdubluje rankingu porzuconego ataku na gracza');

select * from finish();
rollback;
