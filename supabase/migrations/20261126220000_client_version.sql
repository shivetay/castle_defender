-- #336: wymuszenie aktualizacji wersji klienta (ADR 0005).
--
-- `private.client_versions` (jeden wiersz) trzyma progi: `min_code` (wersja niższa blokuje grę),
-- `recommended_code` (niższa dostaje komunikat o nowej wersji) i `store_url` (link do sklepu).
-- Kod wersji to MAJOR*10000 + MINOR*100 + PATCH (tools/version.py, jak `private.sim_versions`).
-- Progi zmienia właścicielka w SQL Editorze (docs/PO-WYDANIU.md). Klient czyta je tylko przez
-- `public.client_version_policy()` (anon i authenticated, bez prawa zapisu).
--
-- Klient wysyła swoją wersję w nagłówku `X-Client-Version`. Zapisy gracza do `castles`,
-- `defense_layouts` i `players` z wersją poniżej `min_code` albo bez nagłówka (wersje sprzed #336)
-- odrzuca wyzwalacz błędem `update_required` z SQLSTATE PT426, który PostgREST zamienia na HTTP 426.
-- Sprawdzenie dotyczy tylko tokenów anon/authenticated: Edge Functions (service_role), worker
-- weryfikacji i SQL Editor zapisują bez nagłówka. Nagłówek da się podrobić, więc to bariera dla
-- starego APK, a nie zabezpieczenie przed oszustem (wynik ataku chroni weryfikacja powtórki).

create table private.client_versions (
  id boolean primary key default true check (id),
  min_code integer not null default 0 check (min_code >= 0),
  recommended_code integer not null default 0,
  store_url text not null default 'market://details?id=com.shivetay.dunhold'
    check (store_url ~ '^(market://|https://)' and length(store_url) <= 200),
  updated_at timestamptz not null default now(),
  check (recommended_code >= min_code)
);
comment on table private.client_versions is
  'Progi wersji klienta (#336, ADR 0005): min_code blokuje grę, recommended_code pokazuje komunikat. Zmiana tylko w SQL Editorze.';
alter table private.client_versions enable row level security;
revoke all on private.client_versions from public, anon, authenticated, service_role;
insert into private.client_versions default values;

-- Polityka dla klienta: tylko progi i link, nic o graczu. Woła ją też gra bez konta (anon).
create function public.client_version_policy()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select jsonb_build_object('min_code', v.min_code, 'recommended_code', v.recommended_code,
      'store_url', v.store_url) from private.client_versions v where v.id),
    '{"min_code": 0, "recommended_code": 0, "store_url": "market://details?id=com.shivetay.dunhold"}'::jsonb)
$$;
comment on function public.client_version_policy() is
  'Progi wersji klienta (#336): min_code, recommended_code, store_url. Tylko odczyt.';
revoke all on function public.client_version_policy() from public;
grant execute on function public.client_version_policy() to anon, authenticated, service_role;

-- Minimum dla Edge Functions (service_role): jedna liczba, bez reszty polityki.
create function private.client_min_code()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select v.min_code from private.client_versions v where v.id), 0)
$$;
revoke all on function private.client_min_code() from public, anon, authenticated;

-- Wersja klienta z nagłówka żądania PostgREST; brak albo coś innego niż liczba to 0.
create function private.request_client_code()
returns integer
language plpgsql
stable
set search_path = ''
as $$
declare
  raw text;
begin
  begin
    raw := nullif(current_setting('request.headers', true), '')::json ->> 'x-client-version';
  exception when others then
    return 0;
  end;
  if raw is null or raw !~ '^[0-9]{1,9}$' then
    return 0;
  end if;
  return raw::integer;
end;
$$;
revoke all on function private.request_client_code() from public, anon, authenticated;

create function private.require_client_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- rola z tokenu (auth.role()), nie current_user: zapis z funkcji security definer wywołanej
  -- przez gracza też jest zapisem gracza
  if coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '')
      in ('anon', 'authenticated')
      and private.request_client_code() < private.client_min_code() then
    raise exception 'update_required' using errcode = 'PT426',
      hint = 'Zaktualizuj grę w sklepie.';
  end if;
  return coalesce(new, old);
end;
$$;
revoke all on function private.require_client_version() from public, anon, authenticated;

-- Nazwy z `_a_`: wyzwalacze BEFORE odpalają się alfabetycznie, więc stary klient dostaje
-- `update_required`, zanim inne sprawdzenia zamku odrzucą jego dane innym kodem.
create trigger castles_a_client_version
  before insert or update or delete on public.castles
  for each row execute function private.require_client_version();
create trigger defense_layouts_a_client_version
  before insert or update or delete on public.defense_layouts
  for each row execute function private.require_client_version();
create trigger players_a_client_version
  before insert or update or delete on public.players
  for each row execute function private.require_client_version();
