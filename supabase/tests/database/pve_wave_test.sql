-- Testy fal PvE na serwerze (#288), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: nagroda fali tylko za falę, którą zna serwer (start i wygrana w `pve_wave`), raz na falę;
-- skok `pve.cleared` w zapisie bez wyniku fali nie daje nagrody; fala poniżej postępu serwera nie startuje;
-- za szybka wygrana i wynik po terminie nie dają nagrody; ponowienie zwraca zapisany wynik; limit startów;
-- gracz nie czyta ani nie pisze przebiegów fal i nie woła funkcji fal; fale znikają z kontem.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(33);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000288a1'), ('00000000-0000-0000-0000-0000000288b1');

-- Zamek: Dwór 1, donżon, Chata drwala 1 i Koszary 1, zapasy `p_amounts`, licznik fal `p_cleared`.
create function pg_temp.castle(p_amounts jsonb, p_cleared integer default 0) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings',
      '[[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2], [3, 4, 1, 10, 10, 2, 2], [4, 18, 1, 50, 50, 3, 3]]'::jsonb),
    'economy', jsonb_build_object('amounts', p_amounts),
    'research', jsonb_build_object('done', '[]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 13, 4]]'::jsonb, 'orders', '[]'::jsonb),
    'pve', jsonb_build_object('cleared', p_cleared))
$$;
grant execute on function pg_temp.castle(jsonb, integer) to authenticated;

-- Zapis jak z telefonu (PATCH) gracza A.
create function pg_temp.push(p_amounts jsonb, p_cleared integer) returns void language sql as $$
  update public.castles set data = pg_temp.castle(p_amounts, p_cleared)
  where player_id = '00000000-0000-0000-0000-0000000288a1'
$$;
grant execute on function pg_temp.push(jsonb, integer) to authenticated;

create function pg_temp.as_a() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000288a1", "role": "authenticated"}', true)
$$;

create function pg_temp.amounts() returns jsonb language sql as $$
  select data -> 'economy' -> 'amounts' from public.castles where player_id = '00000000-0000-0000-0000-0000000288a1'
$$;
grant execute on function pg_temp.amounts() to authenticated;

-- Start fali jako Edge Function i cofnięcie startu o `p_ago` (wygrana wymaga 5 sekund bitwy).
create function pg_temp.begin(p_wave integer, p_ago interval default interval '1 minute') returns uuid language plpgsql as $$
declare
  v_id uuid;
begin
  select run_id into v_id from public.begin_wave('00000000-0000-0000-0000-0000000288a1', p_wave);
  update public.pve_wave_runs set started_at = now() - p_ago where id = v_id;
  return v_id;
end;
$$;

create function pg_temp.finish(p_run uuid, p_won boolean) returns text language sql as $$
  select status from public.end_wave('00000000-0000-0000-0000-0000000288a1', p_run, p_won)
$$;

-- ---- nagrody i postęp ----
select is(private.pve_wave_reward(0), '{100, 50, 100, 10}'::integer[], 'nagroda pierwszej fali');
select is(private.pve_wave_reward(4), '{500, 300, 500, 50}'::integer[], 'nagroda ostatniej fali');
select is(private.pve_progress('00000000-0000-0000-0000-0000000288a1'), 0, 'nowy gracz: postęp 0');

-- ---- pierwszy zapis zamku ----
select pg_temp.as_a();
set local role authenticated;
insert into public.castles (player_id, map_seed, save_version, data)
values ('00000000-0000-0000-0000-0000000288a1', 1, 12, pg_temp.castle('[480, 300, 280, 50]'));
select throws_ok($$select pg_temp.push('[700, 400, 500, 175]', 5)$$, 'PT422', 'economy_too_fast',
  'skok pve.cleared z 0 do 5 bez wyniku fali nie daje nagrody (#288)');
select throws_ok($$select pg_temp.push('[580, 350, 380, 60]', 1)$$, 'PT422', 'economy_too_fast',
  'nagroda pierwszej fali z samego licznika odrzucona');
select lives_ok($$select pg_temp.push('[480, 300, 280, 50]', 5)$$, 'sam licznik fal przechodzi bez nagrody');
reset role;
select is(private.pve_progress('00000000-0000-0000-0000-0000000288a1'), 0, 'licznik z zapisu nie zmienia postępu serwera');

-- ---- gracz nie dotyka przebiegów fal ----
select pg_temp.as_a();
set local role authenticated;
select throws_ok($$select * from public.pve_wave_runs$$, '42501', null, 'gracz nie czyta przebiegów fal');
select throws_ok($$insert into public.pve_wave_runs (player_id, wave, status, reward, finished_at)
    values ('00000000-0000-0000-0000-0000000288a1', 4, 'won', '{500, 300, 500, 50}', now())$$,
  '42501', null, 'gracz nie wpisze wygranej fali');
select throws_ok($$select * from public.begin_wave('00000000-0000-0000-0000-0000000288a1', 0)$$,
  '42501', null, 'gracz nie woła begin_wave');
select throws_ok($$select * from public.end_wave('00000000-0000-0000-0000-0000000288a1', gen_random_uuid(), true)$$,
  '42501', null, 'gracz nie woła end_wave');
reset role;
set local role anon;
select throws_ok($$select * from public.pve_wave_runs$$, '42501', null, 'anon nie czyta przebiegów fal');
reset role;

-- ---- fala przez serwer ----
select set_config('request.jwt.claims', '', true);
set local role service_role;
create temp table runs (name text primary key, id uuid);
insert into runs values ('w0', pg_temp.begin(0));
select is(pg_temp.finish((select id from runs where name = 'w0'), true), 'won', 'wygrana pierwsza fala przyjęta');
select is((select reward from public.end_wave('00000000-0000-0000-0000-0000000288a1', (select id from runs where name = 'w0'), true)),
  '{100, 50, 100, 10}'::integer[], 'ponowienie zwraca zapisaną nagrodę');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000288a1'),
  '{100, 50, 100, 10}'::bigint[], 'nagroda czeka na zapis zamku raz, mimo ponowienia');
select is(private.pve_progress('00000000-0000-0000-0000-0000000288a1'), 1, 'postęp serwera po wygranej fali');
select throws_ok($$select pg_temp.begin(0)$$, 'P0001', 'wave_done', 'nagrodzona fala nie startuje drugi raz');
reset role;

select pg_temp.as_a();
set local role authenticated;
select lives_ok($$select pg_temp.push('[480, 300, 280, 50]', 1)$$, 'zapis po fali bez nagrody z telefonu');
select is(pg_temp.amounts(), '[580, 350, 380, 60]'::jsonb, 'nagrodę dopisał serwer po bilansie');
select is((select loot_applied from public.castles where player_id = '00000000-0000-0000-0000-0000000288a1'),
  '{100, 50, 100, 10}'::integer[], 'telefon dostaje nagrodę w loot_applied');
reset role;

select set_config('request.jwt.claims', '', true);
set local role service_role;
-- przegrana: bez nagrody i bez postępu
insert into runs values ('w1_lost', pg_temp.begin(1));
select is(pg_temp.finish((select id from runs where name = 'w1_lost'), false), 'lost', 'przegrana fala przyjęta');
select is(private.pve_progress('00000000-0000-0000-0000-0000000288a1'), 1, 'przegrana nie zmienia postępu');
-- za szybka wygrana: WAVE_MIN_S = 5
insert into runs values ('w1_fast', pg_temp.begin(1, interval '1 second'));
select throws_ok($$select pg_temp.finish((select id from runs where name = 'w1_fast'), true)$$,
  'P0001', 'wave_too_fast', 'wygrana w sekundę odrzucona');
-- nowy start porzuca poprzednią niezakończoną falę
insert into runs values ('w2', pg_temp.begin(2));
select is((select status from public.pve_wave_runs where id = (select id from runs where name = 'w1_fast')), 'abandoned',
  'nowy start porzuca poprzednią falę');
select is(pg_temp.finish((select id from runs where name = 'w1_fast'), true), 'abandoned', 'porzucona fala nie daje nagrody');
-- po terminie: WAVE_DEADLINE_S = 600
update public.pve_wave_runs set started_at = now() - interval '11 minutes' where id = (select id from runs where name = 'w2');
select is(pg_temp.finish((select id from runs where name = 'w2'), true), 'abandoned', 'wynik po 10 minutach odrzucony');
-- fala pominięta (wygrana bez sieci): kolejna startuje od wyższego numeru, pominiętej serwer już nie nagrodzi
insert into runs values ('w3', pg_temp.begin(3));
select is(pg_temp.finish((select id from runs where name = 'w3'), true), 'won', 'fala 4 po pominiętych');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000288a1'),
  '{300, 200, 300, 30}'::bigint[], 'nagroda tylko za falę 4');
select throws_ok($$select pg_temp.begin(2)$$, 'P0001', 'wave_done', 'pominięta fala nie startuje po wyższej');
select throws_ok($$select * from public.begin_wave('00000000-0000-0000-0000-0000000288a1', 5)$$,
  'P0001', 'bad_wave', 'fali spoza gry nie ma');
-- cudza fala
select throws_ok($$select * from public.end_wave('00000000-0000-0000-0000-0000000288b1', (select id from runs where name = 'w3'), true)$$,
  'P0001', 'wave_not_found', 'gracz nie kończy cudzej fali');
-- limit startów: 10 na 10 minut (w oknie już 4: fala po terminie ma start sprzed 11 minut)
select pg_temp.begin(4) from generate_series(1, 6);
select throws_ok($$select pg_temp.begin(4)$$, 'P0001', 'rate_limited', 'jedenasty start w 10 minut odrzucony');
reset role;

-- ---- konto ----
delete from auth.users where id = '00000000-0000-0000-0000-0000000288a1';
select is((select count(*)::integer from public.pve_wave_runs where player_id = '00000000-0000-0000-0000-0000000288a1'), 0,
  'fale znikają z kontem');

select * from finish();
rollback;
