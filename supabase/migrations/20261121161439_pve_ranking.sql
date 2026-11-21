-- #242: ranking PvE, osobny od rankingu PvP (#27), w puli tej samej epoki.
--
-- Punkty to `players.pve_points` (start 0). Dostaje się je za wygrany atak na zamek-bota (#26):
-- - za zamek `bot_idx` PVE_BASE + PVE_STEP × bot_idx = 10 + 5 × bot_idx punktów, więc mocniejszy bot
--   (wyższy numer na liście) daje więcej,
-- - ten sam zamek-bot daje punkty najwyżej raz na PVE_COOLDOWN_HOURS = 24 godziny, żeby nie dało się
--   nabijać punktów na najłatwiejszym bocie (licznik w `private.pve_awards`),
-- - przegrana i porzucony atak nie dają ani nie zabierają punktów.
-- `pve_wins` liczy wygrane, które dały punkty; w tabeli są tylko gracze z co najmniej jedną taką
-- wygraną. Boty nie są graczami, więc nigdy nie zajmują miejsc w tabeli, są tylko celem.
--
-- Punkty zmienia wyłącznie wyzwalacz na `attacks` przy przejściu ataku na bota ze `started` do
-- `finished` z wygraną. Status zmienia tylko `end_attack` (service_role), a ponowione `finish_attack`
-- nie zmienia już statusu, więc jedna bitwa liczy się najwyżej raz. Klient nie ma uprawnień do tych
-- kolumn (GRANT update tylko na `nickname`). Wynik (`won`) w MVP pochodzi od klienta po sprawdzeniu
-- limitów w `end_attack`, jak w PvP; pełna weryfikacja powtórką to #29.
--
-- `public.pve_ranking(p_player)` zwraca tabelę dla gracza z tokenu (Edge Function `ranking`, rodzaj
-- „pve”): najwyżej RANKING_TOP = 20 graczy z jego epoki według punktów PvE, a pod nią jego własny
-- wiersz, gdy jest niżej. Wiersz ma te same pola co ranking PvP. Id innych graczy nie wychodzą z bazy.
-- Liczby w tej migracji pilnuje test gry (`tests/test_pve_ranking.gd`) po znacznikach w komentarzach.

alter table public.players
  add column pve_points integer not null default 0 check (pve_points >= 0),
  add column pve_wins integer not null default 0 check (pve_wins >= 0);

comment on column public.players.pve_points is 'Punkty rankingu PvE (#242); zmienia tylko wyzwalacz na attacks.';
comment on column public.players.pve_wins is 'Wygrane z zamkami-botami, które dały punkty PvE (#242).';

create index players_age_pve_points_idx on public.players (age, pve_points desc) where pve_wins > 0;

-- Kiedy gracz ostatnio dostał punkty za danego bota. Poza API, znika razem z kontem gracza.
create table private.pve_awards (
  player_id uuid not null references public.players (id) on delete cascade,
  bot_idx smallint not null references public.bot_castles (idx),
  awarded_at timestamptz not null default now(),
  primary key (player_id, bot_idx)
);
comment on table private.pve_awards is 'Ostatnie punkty PvE za zamek-bota (#242); pisze tylko wyzwalacz attacks_pve_points.';

alter table private.pve_awards enable row level security;
revoke all on private.pve_awards from public, anon, authenticated;
grant select, insert, update, delete on private.pve_awards to service_role;

-- ---------------------------------------------------------------------------------------------
-- Punkty po wygranej z botem
-- ---------------------------------------------------------------------------------------------

-- Punkty za zamek-bota `bot_idx`. PVE_BASE = 10, PVE_STEP = 5
create function private.pve_points(bot_idx smallint)
returns integer
language sql
immutable
set search_path = ''
as $$
  select 10 + 5 * greatest(bot_idx, 0)::integer
$$;

create function private.apply_pve_points()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_last timestamptz;
begin
  -- blokada gracza: dwa równoległe końce ataku nie dodadzą punktów za tego samego bota dwa razy
  perform 1 from public.players p where p.id = new.attacker_id for update;
  if not found then
    return null;
  end if;
  select w.awarded_at into v_last from private.pve_awards w
  where w.player_id = new.attacker_id and w.bot_idx = new.bot_idx;
  -- PVE_COOLDOWN_HOURS = 24
  if v_last is not null and v_last > now() - interval '24 hours' then
    return null;
  end if;
  insert into private.pve_awards as w (player_id, bot_idx, awarded_at)
  values (new.attacker_id, new.bot_idx, now())
  on conflict (player_id, bot_idx) do update set awarded_at = excluded.awarded_at;
  update public.players p
  set pve_points = p.pve_points + private.pve_points(new.bot_idx), pve_wins = p.pve_wins + 1
  where p.id = new.attacker_id;
  return null;
end;
$$;

comment on function private.apply_pve_points() is
  'Ranking PvE (#242): po wygranym ataku na zamek-bota dodaje 10 + 5 × bot_idx punktów, najwyżej raz na 24 h za tego samego bota.';

-- tylko atak na bota, tylko wygrana i tylko przejście z ataku w toku: ponowiony koniec nic nie zmienia
create trigger attacks_pve_points
  after update of status on public.attacks
  for each row
  when (old.status = 'started' and new.status = 'finished' and new.bot_idx is not null
    and new.result -> 'won' = 'true'::jsonb)
  execute function private.apply_pve_points();

revoke all on function private.pve_points(smallint) from public, anon, authenticated;
revoke all on function private.apply_pve_points() from public, anon, authenticated;
grant execute on function private.pve_points(smallint) to service_role;
grant execute on function private.apply_pve_points() to service_role;

-- ---------------------------------------------------------------------------------------------
-- Tabela rankingu
-- ---------------------------------------------------------------------------------------------

create function public.pve_ranking(p_player uuid)
returns table (
  place integer,
  nickname text,
  castle_name text,
  ruler text,
  points integer,
  is_me boolean
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_age smallint;
begin
  if p_player is null then
    return;
  end if;
  select p.age into v_age from public.players p where p.id = p_player;
  if not found then
    return;
  end if;

  return query
  with ranked as (
    select
      p.id,
      p.nickname,
      left(c.data -> 'profile' ->> 'castle_name', 16) as castle_name,
      left(coalesce(c.data -> 'profile' ->> 'ruler', ''), 20) as ruler,
      p.pve_points as points,
      -- remis: to samo miejsce; kolejność w remisie stała (id), żeby lista nie skakała
      rank() over (order by p.pve_points desc)::integer as place,
      row_number() over (order by p.pve_points desc, p.id) as ord
    from public.players p
    join public.castles c on c.player_id = p.id
    where p.age = v_age
      and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0
      and p.pve_wins > 0
  )
  -- RANKING_TOP = 20
  select r.place, r.nickname, r.castle_name, r.ruler, r.points, r.id = p_player
  from ranked r
  where r.ord <= 20 or r.id = p_player
  order by r.ord;
end;
$$;

comment on function public.pve_ranking(uuid) is
  'Ranking PvE (#242): 20 najlepszych graczy z epoki p_player według punktów za zamki-boty i jego własny wiersz. Tylko dla service_role (Edge Function ranking).';

revoke all on function public.pve_ranking(uuid) from public, anon, authenticated;
grant execute on function public.pve_ranking(uuid) to service_role;
