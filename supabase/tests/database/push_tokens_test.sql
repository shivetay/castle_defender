-- Testy tokenów push (#30, ADR 0012), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: klient (authenticated, anon) nie czyta ani nie zapisuje push_tokens i nie woła funkcji pusha;
-- serwer zapisuje token tylko dla gracza z JWT, przenosi token urządzenia na nowe konto, trzyma najwyżej 5;
-- attack_push_claim oddaje tokeny obrońcy z włączonymi Atakami tylko raz, tylko atakującemu i tylko dla
-- zakończonego ataku ze skutkami; tokeny znikają razem z kontem.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(30);

-- A atakuje B, O to obcy gracz. Ranking w paśmie 63 300, bo testy biegną też na projekcie w chmurze,
-- w transakcji, która się cofa.
insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000030a1'), ('00000000-0000-0000-0000-0000000030b1'),
  ('00000000-0000-0000-0000-0000000030c1');
update public.players set rating = 63300, age = 0
where id in ('00000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-0000000030b1',
  '00000000-0000-0000-0000-0000000030c1');

set local role service_role;
select lives_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1',
  'tokB1_aaaaaaaaaaaaaaaaaaaa:APA91b', true)$$, 'serwer zapisuje token obrońcy');
select lives_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1',
  'tokB2_bbbbbbbbbbbbbbbbbbbb', false)$$, 'drugie urządzenie z wyłączonymi Atakami');
select is((select count(*)::int from public.push_tokens where player_id = '00000000-0000-0000-0000-0000000030b1'), 2,
  'dwa urządzenia obrońcy');
select lives_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1',
  'tokB2_bbbbbbbbbbbbbbbbbbbb', false)$$, 'ponowny zapis tego samego tokenu');
select is((select count(*)::int from public.push_tokens where player_id = '00000000-0000-0000-0000-0000000030b1'), 2,
  'ponowny zapis nie dubluje');
select throws_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1', 'zły token!', true)$$,
  'P0001', 'bad_token', 'zły token odrzucony');
select throws_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1', 'krotki', true)$$,
  'P0001', 'bad_token', 'za krótki token odrzucony');

-- token urządzenia O przechodzi na A (to samo urządzenie po zmianie konta)
select public.push_token_register('00000000-0000-0000-0000-0000000030c1', 'tokShared_cccccccccccccccc', true);
select public.push_token_register('00000000-0000-0000-0000-0000000030a1', 'tokShared_cccccccccccccccc', true);
select is((select player_id from public.push_tokens where token = 'tokShared_cccccccccccccccc'),
  '00000000-0000-0000-0000-0000000030a1'::uuid, 'token urządzenia przechodzi na nowe konto');

-- limit 5: szósty token wypycha najstarszy
select public.push_token_register('00000000-0000-0000-0000-0000000030c1', 'tokO_' || i || '_dddddddddddddddd', true)
from generate_series(1, 6) as i;
select is((select count(*)::int from public.push_tokens where player_id = '00000000-0000-0000-0000-0000000030c1'), 5,
  'najwyżej 5 tokenów na konto');

-- wyrejestrowanie dotyczy tylko własnego tokenu
select public.push_token_unregister('00000000-0000-0000-0000-0000000030c1', 'tokB2_bbbbbbbbbbbbbbbbbbbb');
select ok(exists (select 1 from public.push_tokens where token = 'tokB2_bbbbbbbbbbbbbbbbbbbb'),
  'obcy gracz nie usunie cudzego tokenu');
select public.push_token_unregister('00000000-0000-0000-0000-0000000030b1', 'tokB2_bbbbbbbbbbbbbbbbbbbb');
select ok(not exists (select 1 from public.push_tokens where token = 'tokB2_bbbbbbbbbbbbbbbbbbbb'),
  'właściciel usuwa swój token');
select public.push_token_register('00000000-0000-0000-0000-0000000030b1', 'tokB2_bbbbbbbbbbbbbbbbbbbb', false);

-- ---- push o ataku ----
reset role;
insert into public.attacks (id, attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot,
  status, result, loot, finished_at, outcome_applied_at, launched_at)
values
  ('00000000-0000-0000-0000-00000030aa01', '00000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-0000000030b1',
    1, 1, '{}', '{}', 'finished', '{"won": false, "percent": 35, "stars": [false, false, false]}',
    array[0, 0, 0, 0], now(), now(), now()),
  -- w weryfikacji (enforce): bez skutków, bez pusha
  ('00000000-0000-0000-0000-00000030aa02', '00000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-0000000030b1',
    1, 2, '{}', '{}', 'finished', '{"won": true, "percent": 80, "stars": [true, true, true]}',
    null, now(), null, now());
insert into public.attacks (id, attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot, status)
values ('00000000-0000-0000-0000-00000030aa03', '00000000-0000-0000-0000-0000000030a1',
  '00000000-0000-0000-0000-0000000030b1', 1, 3, '{}', '{}', 'started');

set local role service_role;
select is((select count(*)::int from public.attack_push_claim('00000000-0000-0000-0000-0000000030c1',
  '00000000-0000-0000-0000-00000030aa01')), 0, 'cudzy atak nie daje odbiorców');
create temp table p on commit drop as
  select * from public.attack_push_claim('00000000-0000-0000-0000-0000000030a1', '00000000-0000-0000-0000-00000030aa01');
select is((select array_agg(token) from p), array['tokB1_aaaaaaaaaaaaaaaaaaaa:APA91b'],
  'tylko urządzenie obrońcy z włączonymi Atakami');
select is((select won from p limit 1), false, 'wynik: obrona odparta');
select is((select percent from p limit 1), 35, 'procent zniszczeń');
select is((select count(*)::int from public.attack_push_claim('00000000-0000-0000-0000-0000000030a1',
  '00000000-0000-0000-0000-00000030aa01')), 0, 'drugi raz bez pusha (ponowione finish_attack)');
select is((select count(*)::int from public.attack_push_claim('00000000-0000-0000-0000-0000000030a1',
  '00000000-0000-0000-0000-00000030aa02')), 0, 'atak w weryfikacji bez pusha');
select is((select count(*)::int from public.attack_push_claim('00000000-0000-0000-0000-0000000030a1',
  '00000000-0000-0000-0000-00000030aa03')), 0, 'atak w toku bez pusha');
select public.push_token_drop('tokB1_aaaaaaaaaaaaaaaaaaaa:APA91b');
select ok(not exists (select 1 from public.push_tokens where token = 'tokB1_aaaaaaaaaaaaaaaaaaaa:APA91b'),
  'token odrzucony przez FCM znika');

-- ---- klient nie ma dostępu ----
reset role;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000030b1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select token from public.push_tokens$$, '42501', null, 'gracz nie czyta tokenów');
select throws_ok($$insert into public.push_tokens (player_id, token)
  values ('00000000-0000-0000-0000-0000000030b1', 'tokX_eeeeeeeeeeeeeeeeeeee')$$, '42501', null,
  'gracz nie zapisze tokenu z pominięciem serwera');
select throws_ok($$select public.attack_push_claim('00000000-0000-0000-0000-0000000030a1',
  '00000000-0000-0000-0000-00000030aa01')$$, '42501', null, 'gracz nie woła attack_push_claim');
select throws_ok($$select push_sent_at from public.attacks$$, '42501', null, 'gracz nie czyta znacznika pusha');
select throws_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1',
  'tokX_eeeeeeeeeeeeeeeeeeee', true)$$, '42501', null, 'gracz nie woła push_token_register');
select throws_ok($$select public.push_token_unregister('00000000-0000-0000-0000-0000000030b1',
  'tokB2_bbbbbbbbbbbbbbbbbbbb')$$, '42501', null, 'gracz nie woła push_token_unregister');
select throws_ok($$select public.push_token_drop('tokB2_bbbbbbbbbbbbbbbbbbbb')$$, '42501', null,
  'gracz nie woła push_token_drop');
reset role;
set local role anon;
select throws_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030b1',
  'tokX_eeeeeeeeeeeeeeeeeeee', true)$$, '42501', null, 'anon nie woła push_token_register');
reset role;

-- ---- limit 20 zapisów na godzinę ----
set local role service_role;
select lives_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030a1',
  'tokLimit_ffffffffffffffffff', true) from generate_series(1, 20 - 1)$$, 'zapisy w limicie (A ma już 1)');
select throws_ok($$select public.push_token_register('00000000-0000-0000-0000-0000000030a1',
  'tokLimit_ffffffffffffffffff', true)$$, 'P0001', 'rate_limited', '21. zapis w godzinie odrzucony');
reset role;

-- ---- usunięcie konta kasuje tokeny ----
-- bez claims gracza: wyzwalacz wersji klienta (client_version) nie dotyczy kasowania konta przez serwer
select set_config('request.jwt.claims', '', true);
delete from auth.users where id = '00000000-0000-0000-0000-0000000030b1';
select ok(not exists (select 1 from public.push_tokens where player_id = '00000000-0000-0000-0000-0000000030b1'),
  'tokeny znikają z kontem');

select * from finish();
rollback;
