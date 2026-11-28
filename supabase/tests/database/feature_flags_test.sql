-- Testy flag z panelu admina (#280, ADR 0020, migracja `*_feature_flags.sql`), uruchamiane przez `supabase test db`.
-- Kryteria: gracz (authenticated) czyta flagi bez `id` i `updated_by`, ale nic nie zmieni ani nie doda; anon nic;
-- admin (app_metadata.role = admin) dodaje i zmienia wiersze, ale nie `key`, `kind` ani `updated_by` (ustawia je
-- wyzwalacz), a usuwać nie może nikt. CHECK: rodzaj offer/event/feature, klucz `[a-z0-9._]` do 64 znaków, okno od ≤ do.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(24);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000280f1'),  -- admin
  ('00000000-0000-0000-0000-0000000280a2'),  -- gracz
  ('00000000-0000-0000-0000-0000000280b2');  -- gracz z user_metadata.role = admin

create function pg_temp.as_admin() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000280f1", "role": "authenticated",
    "app_metadata": {"role": "admin"}}', true)
$$;
create function pg_temp.as_player() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000280a2", "role": "authenticated"}', true)
$$;
create function pg_temp.as_fake_admin() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000280b2", "role": "authenticated",
    "user_metadata": {"role": "admin"}}', true)
$$;

-- ---- schemat ----
select ok((select c.relrowsecurity from pg_class c where c.oid = 'public.feature_flags'::regclass), 'RLS na feature_flags');
select is((select count(*)::int from public.feature_flags
    where key in ('offer.merchant_wagon', 'event.weekly', 'event.weekend') and not enabled), 3,
  'wiersze startowe wyłączone');
select is((select count(*)::int from pg_policies where tablename = 'feature_flags' and cmd = 'DELETE'), 0,
  'bez polityki DELETE');

-- ---- gracz czyta, ale nie zmienia ----
select pg_temp.as_player();
set local role authenticated;
select is((select count(*)::int from public.feature_flags), 3, 'gracz widzi flagi');
select lives_ok($$select key, kind, label, description, enabled, starts_at, ends_at, metadata, updated_at
    from public.feature_flags$$, 'gracz czyta kolumny z grantu');
select throws_ok($$select updated_by from public.feature_flags$$, '42501', null, 'gracz nie czyta updated_by');
select throws_ok($$select id from public.feature_flags$$, '42501', null, 'gracz nie czyta id');
select throws_ok($$insert into public.feature_flags (key, kind, label, enabled) values ('feature.hack', 'feature', 'X', true)$$,
  '42501', null, 'gracz nie dodaje flag');
update public.feature_flags set enabled = true where key = 'event.weekly';
select throws_ok($$delete from public.feature_flags where key = 'event.weekly'$$, '42501', null, 'gracz nie usuwa');
reset role;
select ok(not (select enabled from public.feature_flags where key = 'event.weekly'), 'gracz nie włączył flagi');

select pg_temp.as_fake_admin();
set local role authenticated;
update public.feature_flags set enabled = true where key = 'event.weekly';
reset role;
select ok(not (select enabled from public.feature_flags where key = 'event.weekly'), 'user_metadata nie daje admina');

-- ---- anon nic ----
select set_config('request.jwt.claims', '{"role": "anon"}', true);
set local role anon;
select throws_ok($$select key from public.feature_flags$$, '42501', null, 'anon nie czyta');
select throws_ok($$update public.feature_flags set enabled = true$$, '42501', null, 'anon nie zmienia');
reset role;

-- ---- admin ----
select pg_temp.as_admin();
set local role authenticated;
select lives_ok($$update public.feature_flags set enabled = true, starts_at = '2026-12-01T00:00:00Z',
    ends_at = '2026-12-07T23:59:59Z' where key = 'event.weekly'$$, 'admin włącza flagę z oknem');
select throws_ok($$update public.feature_flags set updated_by = '00000000-0000-0000-0000-0000000280a2'
    where key = 'event.weekly'$$, '42501', null, 'admin nie ustawia updated_by');
select throws_ok($$update public.feature_flags set key = 'event.other' where key = 'event.weekly'$$, '42501', null,
  'klucz się nie zmienia');
select throws_ok($$update public.feature_flags set kind = 'offer' where key = 'event.weekly'$$, '42501', null,
  'rodzaj się nie zmienia');
select lives_ok($$insert into public.feature_flags (key, kind, label, enabled) values ('feature.shop', 'feature', 'Sklep', true)$$,
  'admin dodaje flagę funkcji');
select throws_ok($$insert into public.feature_flags (key, kind, label) values ('other.x', 'other', 'X')$$, '23514', null,
  'nieznany rodzaj odrzucony');
select throws_ok($$insert into public.feature_flags (key, kind, label) values ('Event Weekly', 'event', 'X')$$, '23514', null,
  'zły klucz odrzucony');
select throws_ok(format($$insert into public.feature_flags (key, kind, label) values (%L, 'event', 'X')$$,
    'event.' || repeat('a', 59)), '23514', null, 'klucz ponad 64 znaki odrzucony');
select throws_ok($$update public.feature_flags set starts_at = '2026-12-08T00:00:00Z' where key = 'event.weekly'$$,
  '23514', null, 'start po końcu odrzucony');
select throws_ok($$delete from public.feature_flags where key = 'feature.shop'$$, '42501', null, 'admin też nie usuwa');
reset role;
select is((select updated_by from public.feature_flags where key = 'event.weekly'),
  '00000000-0000-0000-0000-0000000280f1'::uuid, 'updated_by z tokenu admina');

select * from finish();
rollback;
