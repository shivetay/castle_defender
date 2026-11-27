-- #408 (część #174): sklep w Targu, darmowe oferty z odnowieniem (ADR 0012).
--
-- Właścicielka układa oferty w panelu admina (`castle_defender_admin`, ten sam projekt Supabase) w grupy po
-- najwyżej 3 oferty. Schemat, RLS i testy są w repo gry; panel to tylko UI. Ten schemat jest KONTRAKTEM z panelem:
-- nazw tabel, kolumn i funkcji nie zmieniamy bez zmiany w panelu.
--
-- Tabele:
-- - `public.shop_groups`: nazwa (1–24 znaki), kolejność, aktywna, opcjonalne okno od–do, archiwum;
-- - `public.shop_offers`: grupa, slot 1–3 (najwyżej MAX_OFFERS = 3 żywe oferty na grupę: unikalny indeks
--   (group_id, slot) bez zarchiwizowanych), nazwa, surowiec w kolejności EconomyConfig.Res (0 drewno, 1 kamień,
--   2 żywność, 3 złoto), ilość (GOLD_MAX = 100, RES_MAX = 2000), odnowienie COOLDOWN_MIN = 60 .. COOLDOWN_MAX = 43200
--   minut, aktywna, archiwum;
-- - `public.shop_claims`: historia odbiorów gracza (kto, która oferta, kiedy, co i ile). Odnowienie liczy się od
--   ostatniego odbioru tej oferty przez tego gracza, na zegarze serwera.
--
-- Uprawnienia:
-- - admin to JWT z `app_metadata.role = 'admin'` (`public.is_admin()`, ta sama definicja co w repo panelu; tylko
--   `app_metadata`, którego gracz nie zmieni). Admin czyta wszystko i zapisuje (INSERT, UPDATE) tylko kolumny
--   z jawnych grantów; `updated_at` i `updated_by` ustawia wyzwalacz (updated_by = auth.uid()). DELETE nie ma nikt:
--   usuwanie to archiwum (`archived_at`);
-- - gracz (authenticated, także konto anonimowe) czyta tylko grupy aktywne, niezarchiwizowane i w oknie czasu
--   oraz ich aktywne, niezarchiwizowane oferty, a z odbiorów tylko własne. Nie pisze nic: odbiór idzie przez
--   Edge Function `shop_claim` i `public.claim_offer` (tylko service_role);
-- - anon nie ma dostępu.
--
-- Archiwum (wyzwalacze, jedna akcja w panelu):
-- - archiwizacja grupy archiwizuje jej żywe oferty z tym samym czasem;
-- - przywrócenie grupy ustawia ją jako nieaktywną i przywraca oferty zarchiwizowane razem z nią, także
--   nieaktywne (oferta zarchiwizowana wcześniej osobno zostaje w archiwum; oferta, której slot zajęła w tym czasie
--   inna, też);
-- - przywrócenie oferty ustawia ją jako nieaktywną; oferty w zarchiwizowanej grupie nie da się dodać ani przywrócić
--   (`group_archived`).
--
-- Odbiór (`public.claim_offer`, Edge Function `shop_claim`): oferta i grupa widoczne (aktywne, poza archiwum,
-- w oknie), odnowienie minęło (`cooldown`), surowiec zmieści się w magazynie razem z łupem czekającym (`storage_full`,
-- złoto nie ma magazynu). Nagroda trafia do `castle_loot_pending`, którą zapis zamku scala z zapasami i zwraca
-- w `castles.loot_applied` (jak łup PvP i nagroda fali PvE). Blokada wiersza gracza szereguje odbiory, więc dwa
-- równoległe żądania nie odbiorą oferty dwa razy.
--
-- Złoto z ofert wlicza się do `private.ruler_gold_left` (wymóg źródła złota z `*_resource_sanity.sql`), inaczej
-- zapis zamku po odbiorze złota kończyłby się `gold_unbacked`.
--
-- Dane gracza: tylko odbiory (id konta, oferta, czas, surowiec, ilość); kasują się z kontem (on delete cascade
-- przez `public.players`). Liczby pilnuje test gry (`tests/test_shop.gd`) po znacznikach w komentarzach,
-- a pgTAP `supabase/tests/database/shop_test.sql`.

-- ---------------------------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------------------------

-- Ta sama definicja co w `castle_defender_admin` (`*_feature_flags.sql`): rola wyłącznie z app_metadata.
create or replace function public.is_admin()
returns boolean
language sql
stable
set search_path = ''
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'admin', false);
$$;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated, service_role;

-- ---------------------------------------------------------------------------------------------
-- Tabele
-- ---------------------------------------------------------------------------------------------

create table public.shop_groups (
  id bigint generated always as identity primary key,
  name text not null check (char_length(name) between 1 and 24),
  sort_order integer not null default 0,
  active boolean not null default false,
  starts_at timestamptz,
  ends_at timestamptz,
  archived_at timestamptz,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  constraint shop_groups_window check (ends_at is null or starts_at is null or ends_at > starts_at)
);
comment on table public.shop_groups is
  'Grupy ofert sklepu w Targu (#408). Zapis tylko admin (app_metadata.role = admin), gracz czyta aktywne w oknie.';

create table public.shop_offers (
  id bigint generated always as identity primary key,
  group_id bigint not null references public.shop_groups (id) on delete restrict,
  slot smallint not null check (slot between 1 and 3),
  name text not null check (char_length(name) between 1 and 24),
  -- EconomyConfig.Res: 0 drewno, 1 kamień, 2 żywność, 3 złoto
  resource smallint not null check (resource between 0 and 3),
  -- GOLD_MAX = 100, RES_MAX = 2000
  amount integer not null check (amount > 0 and amount <= case when resource = 3 then 100 else 2000 end),
  -- COOLDOWN_MIN = 60, COOLDOWN_MAX = 43200 (minuty)
  cooldown_minutes integer not null check (cooldown_minutes between 60 and 43200),
  active boolean not null default false,
  archived_at timestamptz,
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now()
);
comment on table public.shop_offers is
  'Darmowe oferty sklepu (#408): jeden surowiec i ilość, odnowienie per gracz. MAX_OFFERS = 3 żywe na grupę (slot 1–3).';

-- MAX_OFFERS = 3: slot 1–3 i jedna żywa oferta na slot
create unique index shop_offers_live_slot on public.shop_offers (group_id, slot) where archived_at is null;
create index shop_offers_group_idx on public.shop_offers (group_id);

create table public.shop_claims (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  offer_id bigint not null references public.shop_offers (id) on delete restrict,
  claimed_at timestamptz not null default now(),
  -- kopia nagrody z chwili odbioru (oferta może się potem zmienić)
  resource smallint not null check (resource between 0 and 3),
  amount integer not null check (amount > 0 and amount <= 2000)
);
comment on table public.shop_claims is
  'Odbiory ofert sklepu (#408). Pisze tylko public.claim_offer (Edge Function shop_claim); gracz czyta własne.';

create index shop_claims_player_offer_idx on public.shop_claims (player_id, offer_id, claimed_at desc);
create index shop_claims_offer_idx on public.shop_claims (offer_id);

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacze: kto i kiedy zmienił, archiwum
-- ---------------------------------------------------------------------------------------------

-- Grupa: updated_at i updated_by z tokenu; przywrócona z archiwum jest nieaktywna.
create function private.shop_group_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' and old.archived_at is not null and new.archived_at is null then
    new.active := false;
  end if;
  return new;
end;
$$;

-- Po zmianie archiwum grupy: archiwizacja zabiera żywe oferty, przywrócenie oddaje te zarchiwizowane razem z nią
-- (nieaktywne), o ile ich slot jest wolny.
create function private.shop_group_archive()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.archived_at is null and new.archived_at is not null then
    update public.shop_offers o set archived_at = new.archived_at
    where o.group_id = new.id and o.archived_at is null;
  elsif old.archived_at is not null and new.archived_at is null then
    update public.shop_offers o set archived_at = null, active = false
    where o.group_id = new.id and o.archived_at = old.archived_at
      and not exists (select 1 from public.shop_offers l
        where l.group_id = o.group_id and l.slot = o.slot and l.archived_at is null);
  end if;
  return null;
end;
$$;

-- Oferta: updated_at i updated_by z tokenu; przywrócona z archiwum jest nieaktywna; żywa oferta tylko w żywej grupie.
create function private.shop_offer_touch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  new.updated_by := auth.uid();
  if tg_op = 'UPDATE' and old.archived_at is not null and new.archived_at is null then
    new.active := false;
  end if;
  if new.archived_at is null
      and exists (select 1 from public.shop_groups g where g.id = new.group_id and g.archived_at is not null) then
    raise exception 'group_archived' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

revoke all on function private.shop_group_touch() from public, anon, authenticated;
revoke all on function private.shop_group_archive() from public, anon, authenticated;
revoke all on function private.shop_offer_touch() from public, anon, authenticated;

create trigger shop_groups_touch before insert or update on public.shop_groups
  for each row execute function private.shop_group_touch();
create trigger shop_groups_archive after update of archived_at on public.shop_groups
  for each row execute function private.shop_group_archive();
create trigger shop_offers_touch before insert or update on public.shop_offers
  for each row execute function private.shop_offer_touch();

-- ---------------------------------------------------------------------------------------------
-- RLS i uprawnienia
-- ---------------------------------------------------------------------------------------------

alter table public.shop_groups enable row level security;
alter table public.shop_offers enable row level security;
alter table public.shop_claims enable row level security;

revoke all on public.shop_groups from public, anon, authenticated, service_role;
revoke all on public.shop_offers from public, anon, authenticated, service_role;
revoke all on public.shop_claims from public, anon, authenticated, service_role;

-- odczyt: gracz przez polityki (widoczne), admin wszystko; zapis tylko admin, bez id i updated_at
grant select on public.shop_groups to authenticated;
grant insert (name, sort_order, active, starts_at, ends_at, archived_at, updated_by),
  update (name, sort_order, active, starts_at, ends_at, archived_at, updated_by)
  on public.shop_groups to authenticated;
grant select on public.shop_offers to authenticated;
grant insert (group_id, slot, name, resource, amount, cooldown_minutes, active, archived_at, updated_by),
  update (group_id, slot, name, resource, amount, cooldown_minutes, active, archived_at, updated_by)
  on public.shop_offers to authenticated;
grant select on public.shop_claims to authenticated;
-- serwer (claim_offer jako service_role): czyta oferty, zapisuje odbiory
grant select on public.shop_groups, public.shop_offers to service_role;
grant select, insert on public.shop_claims to service_role;

-- Grupa widoczna dla gracza (VISIBLE): aktywna, poza archiwum, w oknie od–do (zegar serwera). Warunek jest
-- wpisany wprost w polityki i funkcje, bo gracz nie ma dostępu do schematu private.
create policy "shop_groups: gracz czyta widoczne" on public.shop_groups
  for select to authenticated
  using (active and archived_at is null and (starts_at is null or starts_at <= now()) and (ends_at is null or ends_at > now()));
create policy "shop_groups: admin czyta" on public.shop_groups
  for select to authenticated
  using ((select public.is_admin()));
create policy "shop_groups: admin dodaje" on public.shop_groups
  for insert to authenticated
  with check ((select public.is_admin()));
create policy "shop_groups: admin zmienia" on public.shop_groups
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "shop_offers: gracz czyta widoczne" on public.shop_offers
  for select to authenticated
  using (active and archived_at is null and exists (
    select 1 from public.shop_groups g where g.id = group_id
      and g.active and g.archived_at is null and (g.starts_at is null or g.starts_at <= now())
      and (g.ends_at is null or g.ends_at > now())));
create policy "shop_offers: admin czyta" on public.shop_offers
  for select to authenticated
  using ((select public.is_admin()));
create policy "shop_offers: admin dodaje" on public.shop_offers
  for insert to authenticated
  with check ((select public.is_admin()));
create policy "shop_offers: admin zmienia" on public.shop_offers
  for update to authenticated
  using ((select public.is_admin()))
  with check ((select public.is_admin()));

create policy "shop_claims: gracz czyta własne" on public.shop_claims
  for select to authenticated
  using ((select auth.uid()) = player_id);

-- ---------------------------------------------------------------------------------------------
-- Katalog dla gracza (REST: POST /rest/v1/rpc/shop_catalog)
-- ---------------------------------------------------------------------------------------------

-- Widoczne grupy i oferty w kolejności (sort_order, id grupy, slot) z czasem, od którego gracz znowu odbierze
-- ofertę (null: można teraz) i czasem serwera, od którego telefon liczy odliczanie. SECURITY INVOKER: RLS
-- przepuszcza tylko widoczne oferty i własne odbiory.
create function public.shop_catalog()
returns table (
  group_id bigint,
  group_name text,
  sort_order integer,
  offer_id bigint,
  slot smallint,
  name text,
  resource smallint,
  amount integer,
  cooldown_minutes integer,
  next_available_at timestamptz,
  server_now timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select g.id, g.name, g.sort_order, o.id, o.slot, o.name, o.resource, o.amount, o.cooldown_minutes,
    case when c.last_at + make_interval(mins => o.cooldown_minutes) > now()
      then c.last_at + make_interval(mins => o.cooldown_minutes) end,
    now()
  from public.shop_groups g
  join public.shop_offers o on o.group_id = g.id
  left join lateral (select max(sc.claimed_at) as last_at from public.shop_claims sc
    where sc.offer_id = o.id and sc.player_id = (select auth.uid())) c on true
  where g.active and g.archived_at is null and (g.starts_at is null or g.starts_at <= now())
    and (g.ends_at is null or g.ends_at > now())
    and o.active and o.archived_at is null
  order by g.sort_order, g.id, o.slot
$$;

comment on function public.shop_catalog() is
  'Sklep w Targu (#408): widoczne grupy i oferty z next_available_at gracza (null: do odbioru) i czasem serwera.';
revoke all on function public.shop_catalog() from public, anon, authenticated;
grant execute on function public.shop_catalog() to authenticated;

-- ---------------------------------------------------------------------------------------------
-- Odbiór (Edge Function `shop_claim`, rola service_role; id gracza wyłącznie z tokenu)
-- ---------------------------------------------------------------------------------------------

create function public.claim_offer(p_player uuid, p_offer bigint)
returns table (
  offer_id bigint,
  resource smallint,
  amount integer,
  claimed_at timestamptz,
  next_available_at timestamptz
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  o public.shop_offers%rowtype;
  v_last timestamptz;
  v_castle jsonb;
  v_have bigint;
  v_cap bigint;
  v_delta bigint[] := array[0, 0, 0, 0];
  v_at timestamptz := now();
begin
  -- jeden odbiór naraz na gracza: blokada wiersza gracza (jak begin_wave)
  perform 1 from public.players p where p.id = p_player for update;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0001';
  end if;
  select c.data into v_castle from public.castles c where c.player_id = p_player;
  if v_castle is null then
    raise exception 'no_castle' using errcode = 'P0001';
  end if;
  select t.* into o from public.shop_offers t
  join public.shop_groups g on g.id = t.group_id
  where t.id = p_offer and t.active and t.archived_at is null
    and g.active and g.archived_at is null and (g.starts_at is null or g.starts_at <= now())
    and (g.ends_at is null or g.ends_at > now());
  if not found then
    raise exception 'offer_unavailable' using errcode = 'P0001';
  end if;
  select max(sc.claimed_at) into v_last from public.shop_claims sc
  where sc.player_id = p_player and sc.offer_id = o.id;
  if v_last is not null and v_last + make_interval(mins => o.cooldown_minutes) > v_at then
    raise exception 'cooldown' using errcode = 'P0001';
  end if;
  -- magazyn: zapasy z zamku razem z łupem czekającym; złoto (3) nie ma magazynu
  if o.resource < 3 then
    v_castle := private.castle_with_pending(p_player, v_castle);
    v_have := private.json_int(v_castle -> 'economy' -> 'amounts' -> o.resource::integer, 0, 10000000);
    v_cap := private.castle_capacity(v_castle);
    if v_have is null or v_have + o.amount > v_cap then
      raise exception 'storage_full' using errcode = 'P0001';
    end if;
  end if;
  insert into public.shop_claims (player_id, offer_id, claimed_at, resource, amount)
  values (p_player, o.id, v_at, o.resource, o.amount);
  v_delta[o.resource + 1] := o.amount;
  perform private.add_loot_pending(p_player, v_delta);
  return query select o.id, o.resource, o.amount, v_at, v_at + make_interval(mins => o.cooldown_minutes);
end;
$$;

comment on function public.claim_offer(uuid, bigint) is
  'Odbiór oferty sklepu (#408): widoczna oferta, odnowienie od ostatniego odbioru (cooldown), magazyn (storage_full); nagroda do castle_loot_pending. Tylko dla service_role (Edge Function shop_claim).';
revoke all on function public.claim_offer(uuid, bigint) from public, anon, authenticated;
grant execute on function public.claim_offer(uuid, bigint) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Złoto z ofert w budżecie złota (jak w `*_ruler_perk.sql`)
-- ---------------------------------------------------------------------------------------------

-- Złoto, które gracz mógł jeszcze wydać według serwera: start (50) + fale PvE (125) + łupy z zakończonych
-- ataków + złoto odebrane w sklepie (#408), minus generałowie z `p_generals` i `p_paid` płatnych zmian perka.
create or replace function private.ruler_gold_left(p_player uuid, p_generals jsonb, p_paid integer)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select 50 + 125
    + coalesce((select sum(coalesce(a.loot[4], 0)) from public.attacks a
        where a.attacker_id = p_player and a.status = 'finished'), 0)
    + coalesce((select sum(c.amount) from public.shop_claims c
        where c.player_id = p_player and c.resource = 3), 0)
    - coalesce((select sum(50
          + case when private.json_int(g -> 'level', 1, 3) >= 2 then 80 else 0 end
          + case when private.json_int(g -> 'level', 1, 3) >= 3 then 150 else 0 end)
        from jsonb_array_elements(case when jsonb_typeof(p_generals -> 'roster') = 'array'
          then p_generals -> 'roster' else '[]'::jsonb end) g), 0)
    - 50 * coalesce(p_paid, 0)
$$;

revoke all on function private.ruler_gold_left(uuid, jsonb, integer) from public, anon, authenticated;
grant execute on function private.ruler_gold_left(uuid, jsonb, integer) to service_role;
