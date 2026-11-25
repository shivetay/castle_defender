-- Zaślepka platformy Supabase dla testów pgTAP w CI (.github/scripts/run_pgtap.sh).
-- Wgrywana do świeżego klastra Postgres 16 PRZED migracjami z supabase/migrations.
-- Odtwarza tylko to, na czym opierają się migracje i testy: role API, schematy auth/extensions,
-- auth.users, auth.uid() z request.jwt.claims, uprawnienia i domyślne granty w public jak w Supabase.
-- Nie zawiera żadnych sekretów; role nie mają haseł ani prawa logowania.

-- Role API (jak w Supabase): bez logowania, bez dziedziczenia; service_role omija RLS.
create role anon nologin noinherit;
create role authenticated nologin noinherit;
create role service_role nologin noinherit bypassrls;
-- authenticator przełącza się na role API (PostgREST); tu bez hasła, tylko dla zgodności.
create role authenticator nologin noinherit;
grant anon, authenticated, service_role to authenticator;

create schema auth;
create schema extensions;

-- Minimalny auth.users: kolumny, których używają migracje i testy.
create table auth.users (
  id uuid primary key,
  email text,
  raw_user_meta_data jsonb,
  raw_app_meta_data jsonb,
  is_anonymous boolean not null default false,
  created_at timestamptz default now(),
  last_sign_in_at timestamptz
);

-- auth.uid()/auth.role()/auth.jwt() czytają request.jwt.claims, jak w Supabase.
create function auth.jwt() returns jsonb
language sql stable
as $$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb
$$;

create function auth.uid() returns uuid
language sql stable
as $$
  select nullif(auth.jwt() ->> 'sub', '')::uuid
$$;

create function auth.role() returns text
language sql stable
as $$
  select nullif(auth.jwt() ->> 'role', '')
$$;

grant usage on schema public to anon, authenticated, service_role;
grant usage on schema auth to anon, authenticated, service_role;
grant usage on schema extensions to anon, authenticated, service_role;
grant execute on function auth.jwt(), auth.uid(), auth.role() to anon, authenticated, service_role;

-- Domyślne uprawnienia w public jak w Supabase: obiekty tworzone przez postgres są dostępne dla ról
-- API. Migracja init_pvp_schema świadomie je odbiera, więc testy sprawdzają realny stan po migracjach.
alter default privileges for role postgres in schema public
  grant all on tables to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on functions to anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  grant all on sequences to anon, authenticated, service_role;

create extension pgtap with schema extensions;
