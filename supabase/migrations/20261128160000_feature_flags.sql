-- #280 (część #269): flagi ofert, eventów i funkcji z panelu admina (ADR 0020).
--
-- Tabelę założył panel `castle_defender_admin` (`20261123090000_feature_flags.sql`). Od tej migracji schemat, RLS
-- i testy pgTAP są w repo gry, tak jak sklep (ADR 0014); panel to tylko UI na tym samym projekcie. Migracja jest
-- idempotentna: na projekcie z tabelą panelu zmienia uprawnienia i zostawia wiersze, na czystej bazie zakłada
-- wszystko od zera. Ten schemat jest KONTRAKTEM z panelem: nazw kolumn nie zmieniamy bez zmiany w panelu.
--
-- Wiersz: `key` (`[a-z0-9._]`, do 64 znaków, klient mapuje po kluczu, nie po uuid), `kind` (offer, event, feature),
-- `label` i `description` dla panelu, `enabled`, opcjonalne okno `starts_at`..`ends_at`, `metadata` (jsonb).
-- Flaga jest aktywna, gdy enabled i teraz jest w oknie (oba końce włącznie). Klient bez wiersza bierze stan
-- domyślny z przedrostka klucza: `feature.*` włączone, reszta wyłączona (`scripts/net/feature_flags.gd`).
-- Flaga steruje tylko widocznością w kliencie; nagród ani dostępu nie przyznaje.
--
-- Uprawnienia:
-- - gracz (authenticated, także konto anonimowe) czyta wszystkie wiersze, ale bez `id` i `updated_by` (uuid admina,
--   jak w sklepie z review #412). Admin czyta przez tę samą rolę, więc panel też nie wybiera tych kolumn
--   i przełącza flagi po `key`;
-- - admin (JWT z `app_metadata.role = 'admin'`, `public.is_admin()` z `*_shop.sql`) dodaje i zmienia wiersze tylko
--   w kolumnach z jawnych grantów; `key` i `kind` po dodaniu się nie zmieniają. `updated_at` i `updated_by` ustawia
--   wyzwalacz (updated_by = auth.uid()). DELETE nie ma nikt: flagę się wyłącza;
-- - anon nie ma dostępu (gra zawsze ma sesję anonimowego konta).
--
-- Dane gracza: żadne. Testy: `supabase/tests/database/feature_flags_test.sql`, klient `tests/test_feature_flags.gd`
-- (sprawdza CHECK rodzaju, klucza i grant SELECT po tekście tej migracji).

create table if not exists public.feature_flags (
  id uuid primary key default gen_random_uuid(),
  key text not null unique,
  kind text not null,
  label text not null,
  description text not null default '',
  enabled boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users (id) on delete set null,
  constraint feature_flags_window_chk check (starts_at is null or ends_at is null or starts_at <= ends_at)
);

comment on table public.feature_flags is
  'Flagi ofert, eventów i funkcji (#280, ADR 0020). Zapis tylko admin (app_metadata.role = admin), gracz czyta.';

create index if not exists feature_flags_kind_idx on public.feature_flags (kind);

-- rodzaj feature (całe funkcje gry) obok ofert i eventów
alter table public.feature_flags drop constraint if exists feature_flags_kind_check;
alter table public.feature_flags add constraint feature_flags_kind_check
  check (kind in ('offer', 'event', 'feature'));
-- KEY_MAX = 64: klucz jak w kliencie (FeatureFlags.valid_key)
alter table public.feature_flags drop constraint if exists feature_flags_key_format;
alter table public.feature_flags add constraint feature_flags_key_format
  check (key ~ '^[a-z0-9._]{1,64}$');

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacz: kto i kiedy zmienił (zamiast `public.set_feature_flags_updated_at` z panelu)
-- ---------------------------------------------------------------------------------------------

drop trigger if exists feature_flags_set_updated_at on public.feature_flags;
drop function if exists public.set_feature_flags_updated_at();

create or replace function private.feature_flags_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  return new;
end;
$$;

revoke all on function private.feature_flags_touch() from public, anon, authenticated;

drop trigger if exists feature_flags_touch on public.feature_flags;
create trigger feature_flags_touch before insert or update on public.feature_flags
  for each row execute function private.feature_flags_touch();

-- ---------------------------------------------------------------------------------------------
-- RLS i uprawnienia
-- ---------------------------------------------------------------------------------------------

alter table public.feature_flags enable row level security;

drop policy if exists "feature_flags: public read" on public.feature_flags;
drop policy if exists "feature_flags: admin insert" on public.feature_flags;
drop policy if exists "feature_flags: admin update" on public.feature_flags;
drop policy if exists "feature_flags: admin delete" on public.feature_flags;
drop policy if exists "feature_flags: gracz czyta" on public.feature_flags;
drop policy if exists "feature_flags: admin dodaje" on public.feature_flags;
drop policy if exists "feature_flags: admin zmienia" on public.feature_flags;

revoke all on public.feature_flags from public, anon, authenticated, service_role;

-- SELECT kolumnowy bez `id` i `updated_by`: gracz nie pozna uuid admina. Zapis bez id, updated_at, updated_by.
grant select (key, kind, label, description, enabled, starts_at, ends_at, metadata, updated_at)
  on public.feature_flags to authenticated;
grant insert (key, kind, label, description, enabled, starts_at, ends_at, metadata),
  update (label, description, enabled, starts_at, ends_at, metadata)
  on public.feature_flags to authenticated;

create policy "feature_flags: gracz czyta" on public.feature_flags
  for select to authenticated
  using (true);
create policy "feature_flags: admin dodaje" on public.feature_flags
  for insert to authenticated
  with check ((select public.is_admin()));
create policy "feature_flags: admin zmienia" on public.feature_flags
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

-- ---------------------------------------------------------------------------------------------
-- Wiersze startowe (jak w panelu; istniejących nie rusza)
-- ---------------------------------------------------------------------------------------------

insert into public.feature_flags (key, kind, label, description, enabled)
values
  ('offer.merchant_wagon', 'offer', 'Wóz sprzedawcy', 'Oferta specjalna / wizyta wozu sprzedawcy (#268).', false),
  ('event.weekly', 'event', 'Wydarzenie tygodniowe', 'Flaga wydarzeń tygodniowych (#58).', false),
  ('event.weekend', 'event', 'Wydarzenie weekendowe', 'Flaga wydarzeń weekendowych (#58).', false)
on conflict (key) do nothing;
