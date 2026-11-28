-- Testy strat armii odejmowanych przez serwer (#427, ADR 0019), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: próg `army_losses_min_sim` (0 = wyłączone) i tryb weryfikacji decydują o `server_losses`, które oddaje
-- zatwierdzenie planu (PvP i bot); start zapisuje id oddziałów ataku bez garnizonu; po wejściu skutków polegli
-- (shadow: z telefonu, enforce: z workera, failed bez wyniku telefonu: wszyscy) czekają w castle_army_pending,
-- a najbliższy zapis zamku odejmuje ich do zera i zwraca rozliczenie w army_applied raz; oddział, którego nie ma,
-- daje 0; gracz nie czyta kolejki strat i nie ustawia army_applied.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(27);

-- A atakuje, D1–D3 to cele PvP. Ranking w paśmie 64 270 (bez prawdziwych graczy), bo testy biegną też na projekcie
-- w chmurze, w transakcji, która się cofa. Ustawienia i kolejka też wracają po rollbacku.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000427a1'), ('00000000-0000-0000-0000-0000000427d1'),
  ('00000000-0000-0000-0000-0000000427d2'), ('00000000-0000-0000-0000-0000000427d3');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 64270, age = 0 where id in (select id from test_ids);
delete from private.attack_verifications;
update private.settings set value = 'shadow' where key in ('verification_mode', 'bot_verification_mode');
update private.settings set value = '0' where key = 'army_losses_min_sim';

-- trzy oddziały toporników: 3 to garnizon Dworu (zadanie 6), więc atak idzie oddziałami 1 i 2
insert into public.castles (player_id, map_seed, save_version, data)
select t.id, 4270, 8, jsonb_build_object(
  'profile', jsonb_build_object('castle_name', 'Gród'),
  'grid', jsonb_build_object('buildings', '[[1, 5, 3, 30, 30, 2, 2], [2, 18, 3, 36, 30, 2, 2], [9, 18, 2, 50, 50, 2, 2], [3, 16, 1, 40, 30, 2, 2]]'::jsonb),
  'economy', jsonb_build_object('amounts', jsonb_build_array(1000, 1000, 1000, 100)),
  'research', jsonb_build_object('done', '["A1", "A2", "G18", "G19", "A43", "A7"]'::jsonb),
  'recruitment', jsonb_build_object('squads', '[[3, 0, 10], [1, 0, 10], [2, 0, 10]]'::jsonb),
  'defense', jsonb_build_object('orders', '[[3, 6, 30, 30, []]]'::jsonb))
from test_ids t;
-- #421: obrona do ataku ta sama co w zamku
insert into public.defense_layouts (player_id, save_version, data)
select c.player_id, 8, c.data -> 'defense' from public.castles c where c.player_id in (select id from test_ids);

create temp table plan_ok (v jsonb) on commit drop;
insert into plan_ok values ('[{"squad": 1, "manoeuvre": 0, "target": [-1, -1], "waypoints": [], "start": 0, "start_value": 0, "retreat": 0, "flank_left": true}]');
create temp table runs (n int primary key, attack_id uuid, losses boolean) on commit drop;
grant select, insert on runs, plan_ok to service_role;

create function pg_temp.bot(n int, p_bot smallint, sim int) returns boolean language plpgsql as $$
declare
  v uuid;
  l boolean;
begin
  select attack_id, server_losses into v, l from public.begin_bot_attack('00000000-0000-0000-0000-0000000427a1', p_bot,
    '[[0, 10], [0, 10]]', 4270 + n, (select p.v from plan_ok p), null, sim);
  insert into runs values (n, v, l);
  return l;
end;
$$;
create function pg_temp.pvp(n int, d uuid) returns boolean language plpgsql as $$
declare
  v uuid;
  l boolean;
begin
  select attack_id into v from public.begin_attack('00000000-0000-0000-0000-0000000427a1', d, null,
    '[[0, 10], [0, 10]]', 4270 + n);
  select server_losses into l from public.launch_attack('00000000-0000-0000-0000-0000000427a1', v,
    (select p.v from plan_ok p), null, 501);
  insert into runs values (n, v, l);
  return l;
end;
$$;
create function pg_temp.id(k int) returns uuid language sql as $$
  select attack_id from runs where n = k;
$$;
grant execute on function pg_temp.id(int) to service_role;
create function pg_temp.finish(k int, alive text) returns text language sql as $$
  select status from public.end_attack('00000000-0000-0000-0000-0000000427a1', pg_temp.id(k),
    '{"won": false, "percent": 0, "stars": [false, false, false]}', '[0, 0, 0, 0]', alive::jsonb);
$$;
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
  select nullif(pg_temp.v($q$select private.claim_verification('worker-427')$q$), '<null>')::jsonb;
$$;
create function pg_temp.submit(k int, alive jsonb) returns text language sql as $$
  select pg_temp.v(format('select private.submit_verification(%L, %L)', pg_temp.id(k),
    jsonb_build_object('won', false, 'percent', 0, 'stars', '[false, false, false]'::jsonb, 'destroyed_ids', '[]'::jsonb,
      'survivors', alive, 'ticks', 1800, 'checksum', 4270, 'sim_version', 501)));
$$;
create function pg_temp.pending(k int) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_array(squad_id, fallen) order by squad_id), '[]'::jsonb)
  from private.castle_army_pending where attack_id = pg_temp.id(k);
$$;
-- zapis zamku atakującego (te same dane, jak zapis z telefonu bez zmian) i jego oddziały po zapisie
create function pg_temp.save() returns jsonb language plpgsql as $$
declare
  r jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000427a1", "role": "authenticated"}', true);
  update public.castles set data = data where player_id = '00000000-0000-0000-0000-0000000427a1'
  returning army_applied into r;
  perform set_config('request.jwt.claims', '', true);
  return r;
end;
$$;
-- zapis zamku bez tokenu gracza (np. uzupełnienie w migracji) nie rozlicza strat
create function pg_temp.server_save() returns jsonb language sql as $$
  update public.castles set data = data where player_id = '00000000-0000-0000-0000-0000000427a1'
  returning army_applied;
$$;
create function pg_temp.squads() returns jsonb language sql as $$
  select data -> 'recruitment' -> 'squads' from public.castles where player_id = '00000000-0000-0000-0000-0000000427a1';
$$;
create function pg_temp.reset_squads() returns void language sql as $$
  update public.castles set data = jsonb_set(data, '{recruitment,squads}', '[[3, 0, 10], [1, 0, 10], [2, 0, 10]]')
  where player_id = '00000000-0000-0000-0000-0000000427a1';
  update public.attacks set started_at = started_at - interval '11 minutes'
  where attacker_id = '00000000-0000-0000-0000-0000000427a1' and status <> 'started';
$$;

-- ---- próg wyłączony: jak dotąd ----
set local role service_role;
select is(pg_temp.bot(1, 0::smallint, 501), false, 'próg 0: telefon odejmuje straty sam');
reset role;
select is((select attacker_squads from public.attacks where id = pg_temp.id(1)), array[1, 2],
  'oddziały ataku bez garnizonu, w kolejności zamku');
set local role service_role;
select is(pg_temp.finish(1, '[10, 4]'), 'finished', 'wynik przyjęty');
reset role;
select is(pg_temp.pending(1), '[]'::jsonb, 'bez długu strat przy wyłączonym progu');

-- ---- shadow: polegli z wyniku telefonu ----
update private.settings set value = '501' where key = 'army_losses_min_sim';
select pg_temp.reset_squads();
set local role service_role;
select is(pg_temp.bot(2, 0::smallint, 501), true, 'próg 501: straty odejmie serwer');
select is(pg_temp.finish(2, '[10, 4]'), 'finished', 'wynik przyjęty w shadow');
reset role;
select is(pg_temp.pending(2), '[[1, 0], [2, 6]]'::jsonb, 'polegli z wyniku telefonu czekają na zapis');
select is(pg_temp.server_save(), '[]'::jsonb, 'zapis bez tokenu gracza nie rozlicza strat');
select is(pg_temp.save(), jsonb_build_array(jsonb_build_array(pg_temp.id(2)::text, 1, 0),
  jsonb_build_array(pg_temp.id(2)::text, 2, 6)), 'zapis zamku zwraca rozliczenie');
select is(pg_temp.squads(), '[[3, 0, 10], [1, 0, 10], [2, 0, 4]]'::jsonb, 'polegli odjęci z oddziału 2');
select is(pg_temp.save(), '[]'::jsonb, 'kolejny zapis bez rozliczenia');
select is(pg_temp.squads(), '[[3, 0, 10], [1, 0, 10], [2, 0, 4]]'::jsonb, 'straty odjęte raz');

-- ---- enforce: polegli z wyniku workera ----
update private.settings set value = 'enforce' where key = 'bot_verification_mode';
select pg_temp.reset_squads();
set local role service_role;
select is(pg_temp.bot(3, 0::smallint, 501), true, 'enforce: straty odejmie serwer');
select is(pg_temp.finish(3, '[10, 10]'), 'verifying', 'oszust zgłasza, że nikt nie poległ');
reset role;
select is(pg_temp.pending(3), '[]'::jsonb, 'przed wynikiem workera bez długu');
-- tylko ten job w kolejce (shadow też wkłada joby, a kolejność przy tym samym now() jest dowolna)
delete from private.attack_verifications where attack_id <> pg_temp.id(3);
create temp table c3 on commit drop as select pg_temp.claim() as job;
select is(pg_temp.submit(3, '[3, 0]'), 'mismatch', 'worker: inni ocaleli');
select is(pg_temp.pending(3), '[[1, 7], [2, 10]]'::jsonb, 'polegli z wyniku workera');
create temp table s3 on commit drop as select pg_temp.save() as applied;
select is(pg_temp.squads(), '[[3, 0, 10], [1, 0, 3], [2, 0, 0]]'::jsonb, 'garnizon nietknięty, oddziały ataku po stratach');

-- ---- enforce: porzucony atak, job failed: wszyscy polegli ----
select pg_temp.reset_squads();
set local role service_role;
select is(pg_temp.bot(4, 0::smallint, 501), true, 'kolejna wyprawa');
reset role;
update public.attacks set started_at = now() - interval '11 minutes' where id = pg_temp.id(4);
delete from private.attack_verifications;
create temp table c4 on commit drop as select pg_temp.claim() as job;
update private.attack_verifications set attempts = 3, leased_until = now() - interval '1 second'
where attack_id = pg_temp.id(4);
create temp table c4b on commit drop as select pg_temp.claim() as job;
select is(pg_temp.pending(4), '[[1, 10], [2, 10]]'::jsonb, 'failed bez wyniku telefonu: cała armia ataku poległa');

-- ---- oddział, którego już nie ma ----
update public.castles set data = jsonb_set(data, '{recruitment,squads}', '[[3, 0, 10], [2, 0, 10]]')
where player_id = '00000000-0000-0000-0000-0000000427a1';
create temp table s4 on commit drop as select pg_temp.save() as applied;
select is((select army_applied from public.castles where player_id = '00000000-0000-0000-0000-0000000427a1'),
  jsonb_build_array(jsonb_build_array(pg_temp.id(4)::text, 1, 0), jsonb_build_array(pg_temp.id(4)::text, 2, 10)),
  'brak oddziału 1: odjęte 0, bez przenoszenia na inne oddziały');
select is(pg_temp.squads(), '[[3, 0, 10], [2, 0, 0]]'::jsonb, 'oddział 2 do zera, garnizon bez zmian');

-- ---- PvP: tryb i wersja ----
update private.settings set value = 'enforce' where key = 'verification_mode';
select pg_temp.reset_squads();
set local role service_role;
select is(pg_temp.pvp(5, '00000000-0000-0000-0000-0000000427d1'), true, 'PvP w enforce: straty odejmie serwer');
reset role;
update private.settings set value = 'off' where key = 'verification_mode';
select pg_temp.reset_squads();
set local role service_role;
select is(pg_temp.pvp(6, '00000000-0000-0000-0000-0000000427d2'), false, 'PvP w off: telefon odejmuje sam');
reset role;
update private.settings set value = '502' where key = 'army_losses_min_sim';
update private.settings set value = 'shadow' where key = 'verification_mode';
select pg_temp.reset_squads();
set local role service_role;
select is(pg_temp.pvp(7, '00000000-0000-0000-0000-0000000427d3'), false, 'starsza wersja niż próg: telefon odejmuje sam');
reset role;

-- ---- gracz ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000427a1", "role": "authenticated"}', true);
select throws_ok($$select * from private.castle_army_pending$$, '42501', null, 'gracz nie czyta kolejki strat');
select throws_ok($$update public.castles set army_applied = '[]' where player_id = '00000000-0000-0000-0000-0000000427a1'$$,
  '42501', null, 'gracz nie ustawia rozliczenia strat');
reset role;

select * from finish();
rollback;
