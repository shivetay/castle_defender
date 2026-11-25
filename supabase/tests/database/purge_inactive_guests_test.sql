-- Testy czyszczenia nieaktywnych kont gości (#22), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: znika tylko anonimowe konto „Gracz” bez żadnej gry i bez aktywności od 7 dni, razem
-- z wierszem gracza; zostają konta świeże, z odświeżonym tokenem, z zamkiem, z atakiem, z własnym
-- nickiem i konta nieanonimowe; funkcji nie wywoła klient; zadanie pg_cron jest zaplanowane.
-- Testy biegną też na projekcie w chmurze w transakcji, która się cofa, więc sprawdzamy konkretne
-- konta, a nie łączną liczbę usuniętych.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(13);

-- G stary gość (do usunięcia), F świeży gość, R stary gość z niedawnym odświeżeniem tokenu,
-- C stary gość z zamkiem, A stary gość, który zaatakował bota, N stary gość z własnym nickiem,
-- E stare konto nieanonimowe.
create temp table test_ids (tag text primary key, id uuid not null) on commit drop;
insert into test_ids values
  ('G', '00000000-0000-0000-0000-0000000022a1'), ('F', '00000000-0000-0000-0000-0000000022a2'),
  ('R', '00000000-0000-0000-0000-0000000022a3'), ('C', '00000000-0000-0000-0000-0000000022a4'),
  ('A', '00000000-0000-0000-0000-0000000022a5'), ('N', '00000000-0000-0000-0000-0000000022a6'),
  ('E', '00000000-0000-0000-0000-0000000022a7');

insert into auth.users (id, is_anonymous) select id, tag <> 'E' from test_ids;
update public.players set nickname = 'Wojsław' where id = (select id from test_ids where tag = 'N');

-- Zamek C bez sprawdzeń serwera (te mają własne testy): wyzwalacze wyłączone na czas wstawienia.
set local session_replication_role = replica;
insert into public.castles (player_id, map_seed, save_version, data)
  select id, 2222, 12, '{}'::jsonb from test_ids where tag = 'C';
insert into public.attacks (attacker_id, bot_idx, map_seed, battle_seed)
  select id, 0, 1, 1 from test_ids where tag = 'A';
-- Wszyscy poza F nieaktywni od 30 dni (czasy ustawiamy bez wyzwalacza `touch_updated_at`).
update auth.users set created_at = now() - interval '30 days', updated_at = now() - interval '30 days',
  last_sign_in_at = now() - interval '30 days'
  where id in (select id from test_ids where tag <> 'F');
update public.players set created_at = now() - interval '30 days', updated_at = now() - interval '30 days'
  where id in (select id from test_ids where tag <> 'F');
set local session_replication_role = origin;
-- R odświeżył token wczoraj.
insert into auth.sessions (id, user_id, created_at, updated_at)
  select gen_random_uuid(), id, now() - interval '30 days', now() - interval '1 day'
  from test_ids where tag = 'R';

select is((select count(*)::int from public.attacks where attacker_id = (select id from test_ids where tag = 'A')),
  1, 'A ma atak na bota (warunek wstępny)');

-- Klient nie wywoła czyszczenia.
set local role authenticated;
select throws_ok($$ select private.purge_inactive_guests() $$, '42501', null, 'gracz nie wywoła czyszczenia');
reset role;

select throws_ok($$ select private.purge_inactive_guests(interval '1 hour') $$, 'P0001', null,
  'okno krótsze niż doba odrzucone');

select ok(private.purge_inactive_guests() >= 1, 'czyszczenie usuwa co najmniej starego gościa');

select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'G')), 0,
  'stary gość bez gier usunięty');
select is((select count(*)::int from public.players where id = (select id from test_ids where tag = 'G')), 0,
  'wiersz gracza usunięty kaskadą');
select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'F')), 1,
  'świeży gość zostaje');
select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'R')), 1,
  'gość z niedawnym odświeżeniem tokenu zostaje');
select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'C')), 1,
  'gość z zamkiem zostaje');
select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'A')), 1,
  'gość z atakiem zostaje');
select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'N')), 1,
  'gość z własnym nickiem zostaje');
select is((select count(*)::int from auth.users where id = (select id from test_ids where tag = 'E')), 1,
  'konto nieanonimowe zostaje');

select is((select count(*)::int from cron.job where jobname = 'purge_inactive_guests'
  and schedule = '23 3 * * *'), 1, 'zadanie pg_cron raz na dobę');

select * from finish();
rollback;
