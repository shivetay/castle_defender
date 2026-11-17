-- Etap 9 (#21): schemat bazy pod asynchroniczne PvP i reguły dostępu (RLS).
--
-- Zasady:
-- - Klient (gra) ma tylko klucz publiczny i loguje się anonimowo (#22), więc działa jako rola
--   `authenticated`. Każda tabela ma RLS, a dostęp do tabel jest nadany jawnie (GRANT), także
--   na poziomie kolumn: gracz pisze tylko swoje dane i tylko te kolumny, które wolno mu zmieniać.
-- - Ataki, tarcze, nagrody za reklamy i ranking zapisuje wyłącznie serwer (Edge Functions z rolą
--   `service_role`, #25, #33). Klient może je tylko czytać, i to wyłącznie swoje.
-- - Seed terenu zamku (`map_seed`, #97, #166) jest stały: po założeniu zamku nie da się go zmienić.
-- - Zamki-boty (#26) to wspólna lista 20 zamków z seedem, czytelna dla wszystkich.

-- Nowe obiekty w `public` nie dostają już automatycznych uprawnień dla ról API; wszystko poniżej
-- jest nadane jawnie.
alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated;
alter default privileges for role postgres in schema public
  revoke execute on functions from anon, authenticated, public;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated;

-- Funkcje pomocnicze poza schematem udostępnianym przez API.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Gracze
-- ---------------------------------------------------------------------------------------------

create table public.players (
  id uuid primary key references auth.users (id) on delete cascade,
  nickname text not null default 'Gracz' check (char_length(nickname) between 1 and 20),
  -- ranking i epoka do doboru przeciwnika (#24, #27); zmienia je tylko serwer
  rating integer not null default 1000 check (rating >= 0),
  age smallint not null default 0 check (age between 0 and 9),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on table public.players is 'Gracz (konto Supabase Auth, także anonimowe). Ranking i epokę zmienia tylko serwer.';

-- ---------------------------------------------------------------------------------------------
-- Zamki i układy obrony
-- ---------------------------------------------------------------------------------------------

create table public.castles (
  player_id uuid primary key references public.players (id) on delete cascade,
  -- seed terenu gracza (#97); ustalony przy założeniu zamku, potem niezmienny (#166)
  map_seed bigint not null check (map_seed between 1 and 2147483647),
  -- wersja formatu zapisu gry (SaveGame.FORMAT_VERSION), do migracji danych
  save_version integer not null check (save_version >= 1),
  -- stan zamku jak w zapisie lokalnym: budynki, ekonomia, kolejka, badania, towary, armia
  -- i kolejki szkolenia (#88, #89), donżon jako cel (#120)
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  -- licznik zmian: rośnie przy każdym zapisie (optymistyczna współbieżność, #23)
  revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint castles_data_size check (pg_column_size(data) <= 262144)
);
comment on table public.castles is 'Zamek gracza: JSON stanu gry z wersją formatu i stałym seedem terenu.';

create table public.defense_layouts (
  player_id uuid primary key references public.players (id) on delete cascade,
  save_version integer not null check (save_version >= 1),
  -- ustawienia obrony (#19, #20): zadania oddziałów, pułapki (#100), priorytet wież
  data jsonb not null default '{}'::jsonb check (jsonb_typeof(data) = 'object'),
  revision bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint defense_layouts_data_size check (pg_column_size(data) <= 65536)
);
comment on table public.defense_layouts is 'Układ obrony gracza, który atakujący dostaje z serwera przy starcie ataku.';

-- ---------------------------------------------------------------------------------------------
-- Zamki-boty (#26)
-- ---------------------------------------------------------------------------------------------

create table public.bot_castles (
  idx smallint primary key check (idx between 0 and 19),
  name text not null check (char_length(name) between 1 and 40),
  -- seed zamku (BotRoster.seed_of w grze); zamek jest generowany z niego deterministycznie
  map_seed bigint not null check (map_seed between 0 and 2147483647),
  age smallint not null check (age between 0 and 9)
);
comment on table public.bot_castles is 'Wspólna lista 20 zamków-botów; seed musi zgadzać się z BotRoster.seed_of w grze.';

insert into public.bot_castles (idx, name, map_seed, age) values
  (0, 'Gródek', 1522671593, 0),
  (1, 'Bobrowa Wola', 1794635700, 0),
  (2, 'Lisi Jar', 2000785702, 0),
  (3, 'Kamienny Bród', 786423411, 0),
  (4, 'Wilcze Doły', 652894939, 0),
  (5, 'Sokola Góra', 955747868, 0),
  (6, 'Mszany Gród', 861633082, 0),
  (7, 'Zbójecki Gród', 1900177340, 0),
  (8, 'Bielsko Stare', 213453807, 0),
  (9, 'Czarny Las', 136845175, 0),
  (10, 'Dębowe Wzgórze', 1460975256, 0),
  (11, 'Jastrzębiec', 601804662, 0),
  (12, 'Krucza Skała', 1757690968, 0),
  (13, 'Niedźwiedzi Kąt', 563504191, 0),
  (14, 'Orle Gniazdo', 821957311, 0),
  (15, 'Żelazny Bród', 1990192917, 1),
  (16, 'Wronia Wieża', 541277618, 1),
  (17, 'Turzy Róg', 797847133, 1),
  (18, 'Smocza Jama', 308247635, 1),
  (19, 'Gród Pięciu Wież', 2034701, 1);

-- ---------------------------------------------------------------------------------------------
-- Ataki, tarcze, nagrody za reklamy (zapisuje tylko serwer)
-- ---------------------------------------------------------------------------------------------

create table public.attacks (
  id uuid primary key default gen_random_uuid(),
  attacker_id uuid not null references public.players (id) on delete cascade,
  -- cel: zamek innego gracza albo zamek-bot (dokładnie jedno z dwóch)
  defender_id uuid references public.players (id) on delete cascade,
  bot_idx smallint references public.bot_castles (idx),
  -- seed bitwy i rozkazy planu ataku: z nich powtórka odtwarza bitwę (#29)
  battle_seed bigint not null check (battle_seed between 0 and 2147483647),
  orders jsonb not null default '[]'::jsonb check (jsonb_typeof(orders) = 'array'),
  status text not null default 'started' check (status in ('started', 'finished', 'abandoned')),
  -- wynik (#99): procent zniszczeń, gwiazdki, wygrana; łup w kolejności surowców gry
  result jsonb check (result is null or jsonb_typeof(result) = 'object'),
  loot integer[] check (loot is null or (cardinality(loot) = 4 and 0 <= all (loot))),
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  constraint attacks_one_target check ((defender_id is null) <> (bot_idx is null)),
  constraint attacks_not_self check (defender_id is null or defender_id <> attacker_id),
  constraint attacks_finished_has_result check (status <> 'finished' or (result is not null and finished_at is not null))
);
comment on table public.attacks is 'Atak: seed bitwy, rozkazy i wynik. Zapisują go Edge Functions start_attack / finish_attack (#25).';

create index attacks_attacker_started_idx on public.attacks (attacker_id, started_at desc);
create index attacks_defender_started_idx on public.attacks (defender_id, started_at desc) where defender_id is not null;
create index attacks_bot_idx_idx on public.attacks (bot_idx) where bot_idx is not null;

create table public.shields (
  player_id uuid primary key references public.players (id) on delete cascade,
  -- tarcza obrońcy po ataku (#25, #99): do tej chwili nikt go nie zaatakuje
  until timestamptz not null
);
comment on table public.shields is 'Tarcza obrońcy po ataku; ustawia ją tylko finish_attack.';

create table public.ad_rewards (
  id bigint generated always as identity primary key,
  player_id uuid not null references public.players (id) on delete cascade,
  reward text not null check (char_length(reward) between 1 and 40),
  granted_at timestamptz not null default now()
);
comment on table public.ad_rewards is 'Nagrody za reklamy (#33); zapisuje je Edge Function ad_reward po weryfikacji SSV.';

create index ad_rewards_player_granted_idx on public.ad_rewards (player_id, granted_at desc);

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacze
-- ---------------------------------------------------------------------------------------------

-- Wiersz gracza powstaje razem z kontem (także anonimowym), więc zamek zawsze ma właściciela.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.players (id) values (new.id) on conflict (id) do nothing;
  return new;
end;
$$;
revoke all on function private.handle_new_user() from public, anon, authenticated;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Zapis zamku albo obrony: licznik zmian rośnie, czas się aktualizuje, a właściciel i seed terenu
-- się nie zmieniają (klient i tak nie ma do nich uprawnień; to druga linia obrony).
create function private.bump_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.player_id <> old.player_id then
    raise exception 'player_id is immutable';
  end if;
  if tg_table_name = 'castles' and new.map_seed <> old.map_seed then
    raise exception 'map_seed is immutable';
  end if;
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.bump_revision() from public, anon, authenticated;

create trigger castles_bump_revision
  before update on public.castles
  for each row execute function private.bump_revision();

create trigger defense_layouts_bump_revision
  before update on public.defense_layouts
  for each row execute function private.bump_revision();

create function private.touch_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.touch_updated_at() from public, anon, authenticated;

create trigger players_touch_updated_at
  before update on public.players
  for each row execute function private.touch_updated_at();

-- ---------------------------------------------------------------------------------------------
-- Uprawnienia i RLS
-- ---------------------------------------------------------------------------------------------

alter table public.players enable row level security;
alter table public.castles enable row level security;
alter table public.defense_layouts enable row level security;
alter table public.bot_castles enable row level security;
alter table public.attacks enable row level security;
alter table public.shields enable row level security;
alter table public.ad_rewards enable row level security;

revoke all on public.players, public.castles, public.defense_layouts, public.bot_castles, public.attacks,
  public.shields, public.ad_rewards from anon, authenticated;

-- serwer (Edge Functions) pisze wszystko; rola service_role i tak omija RLS
grant select, insert, update, delete on public.players, public.castles, public.defense_layouts,
  public.bot_castles, public.attacks, public.shields, public.ad_rewards to service_role;

-- Gracze: tylko własny wiersz; gracz zmienia wyłącznie swój nick.
grant select on public.players to authenticated;
grant update (nickname) on public.players to authenticated;

create policy "players: odczyt własnego konta" on public.players
  for select to authenticated
  using ((select auth.uid()) = id);

create policy "players: zmiana własnego nicku" on public.players
  for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- Zamek: gracz zakłada i zapisuje tylko swój; seedu terenu i właściciela nie zmieni,
-- a zamku nie usunie (nowa gra nadpisuje dane z tym samym seedem).
grant select on public.castles to authenticated;
grant insert (player_id, map_seed, save_version, data) on public.castles to authenticated;
grant update (save_version, data) on public.castles to authenticated;

create policy "castles: odczyt własnego zamku" on public.castles
  for select to authenticated
  using ((select auth.uid()) = player_id);

create policy "castles: założenie własnego zamku" on public.castles
  for insert to authenticated
  with check ((select auth.uid()) = player_id);

create policy "castles: zapis własnego zamku" on public.castles
  for update to authenticated
  using ((select auth.uid()) = player_id)
  with check ((select auth.uid()) = player_id);

-- Obrona: jak zamek. Atakujący dostaje cudzą obronę tylko przez start_attack (serwer).
grant select on public.defense_layouts to authenticated;
grant insert (player_id, save_version, data) on public.defense_layouts to authenticated;
grant update (save_version, data) on public.defense_layouts to authenticated;

create policy "defense_layouts: odczyt własnej obrony" on public.defense_layouts
  for select to authenticated
  using ((select auth.uid()) = player_id);

create policy "defense_layouts: założenie własnej obrony" on public.defense_layouts
  for insert to authenticated
  with check ((select auth.uid()) = player_id);

create policy "defense_layouts: zapis własnej obrony" on public.defense_layouts
  for update to authenticated
  using ((select auth.uid()) = player_id)
  with check ((select auth.uid()) = player_id);

-- Zamki-boty: lista publiczna, tylko do odczytu.
grant select on public.bot_castles to anon, authenticated;

create policy "bot_castles: odczyt dla wszystkich" on public.bot_castles
  for select to anon, authenticated
  using (true);

-- Ataki: gracz widzi ataki, w których brał udział (jako atakujący albo obrońca); zapisuje serwer.
grant select on public.attacks to authenticated;

create policy "attacks: odczyt własnych ataków i obron" on public.attacks
  for select to authenticated
  using ((select auth.uid()) = attacker_id or (select auth.uid()) = defender_id);

-- Tarcza i nagrody za reklamy: tylko odczyt własnych.
grant select on public.shields to authenticated;

create policy "shields: odczyt własnej tarczy" on public.shields
  for select to authenticated
  using ((select auth.uid()) = player_id);

grant select on public.ad_rewards to authenticated;

create policy "ad_rewards: odczyt własnych nagród" on public.ad_rewards
  for select to authenticated
  using ((select auth.uid()) = player_id);
