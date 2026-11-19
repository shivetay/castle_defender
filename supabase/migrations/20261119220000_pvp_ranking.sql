-- #27: ranking PvP, osobno za atak i za obronę, w puli tej samej epoki.
--
-- Punkty to dwa wskaźniki w stylu Elo w `players`: `attack_rating` i `defense_rating` (start 1000).
-- Bitwa PvP to pojedynek ratingu ataku atakującego z ratingiem obrony obrońcy:
-- - oczekiwany wynik atakującego E = 1 / (1 + 10^((obrona - atak) / 400)),
-- - zmiana d = round(K × (S - E)), K = ELO_K = 32; S = 1 za wygraną atakującego, 0 w każdym innym
--   przypadku (przegrana albo atak porzucony),
-- - atakujący dostaje +d do ataku, obrońca -d do obrony (suma zero), punkty nie spadają poniżej 0.
--   Odparty atak podnosi więc ranking obrony, a przegrana obrona go obniża.
-- - Atak porzucony (wygasł po 10 minutach albo gracz zaczął inny atak) liczy się jak odparty: bez tego
--   atakujący zamykałby grę przed przegraną i nie tracił punktów.
-- - Ataki na zamki-boty nie zmieniają rankingu.
-- `attack_games` / `defense_games` liczą rozegrane bitwy PvP; w tabeli są tylko gracze z co najmniej
-- jedną bitwą w danej roli, żeby lista nie była pełna nowych kont z 1000 punktów.
--
-- Punkty zmienia wyłącznie wyzwalacz na `attacks` przy przejściu ataku z `started` do `finished`
-- albo `abandoned`. Status zmieniają tylko `begin_attack` i `end_attack` (service_role), a ponowione
-- `finish_attack` nie zmienia już statusu, więc jedna bitwa zmienia ranking dokładnie raz. Klient nie
-- ma uprawnień do tych kolumn (GRANT tylko na `nickname`). Wynik (`won`) w MVP pochodzi od klienta
-- po sprawdzeniu limitów w `end_attack`; pełna weryfikacja powtórką to #29.
--
-- Dobór przeciwnika (`match_targets`, #24) zostaje na kolumnie `rating`; przejście na
-- `attack_rating` vs `defense_rating` to osobna decyzja właścicielki.
--
-- `public.pvp_ranking(p_player, p_kind)` zwraca tabelę dla gracza z tokenu (Edge Function `ranking`):
-- najwyżej RANKING_TOP = 20 graczy z jego epoki według punktów ataku albo obrony, a pod nią jego
-- własny wiersz, gdy jest niżej. Wiersz ma tylko to, co pokazuje lista: miejsce, nick, nazwę zamku,
-- władcę, punkty i znacznik „to Ty”. Id innych graczy nie wychodzą z bazy.
-- Liczby w tej migracji pilnuje test gry (`tests/test_ranking_board.gd`) po znacznikach w komentarzach.

alter table public.players
  add column attack_rating integer not null default 1000 check (attack_rating >= 0),
  add column defense_rating integer not null default 1000 check (defense_rating >= 0),
  add column attack_games integer not null default 0 check (attack_games >= 0),
  add column defense_games integer not null default 0 check (defense_games >= 0);

comment on column public.players.attack_rating is 'Punkty rankingu ataku PvP (#27); zmienia tylko wyzwalacz na attacks.';
comment on column public.players.defense_rating is 'Punkty rankingu obrony PvP (#27); zmienia tylko wyzwalacz na attacks.';
comment on column public.players.attack_games is 'Liczba bitew PvP w roli atakującego (#27).';
comment on column public.players.defense_games is 'Liczba bitew PvP w roli obrońcy (#27).';

-- tabela rankingu filtruje po epoce i sortuje po punktach
create index players_age_attack_rating_idx on public.players (age, attack_rating desc) where attack_games > 0;
create index players_age_defense_rating_idx on public.players (age, defense_rating desc) where defense_games > 0;

-- ---------------------------------------------------------------------------------------------
-- Zmiana punktów po bitwie
-- ---------------------------------------------------------------------------------------------

-- Zmiana punktów atakującego (obrońca dostaje -wynik). `won`: atakujący wygrał.
-- ELO_K = 32, ELO_SCALE = 400
create function private.elo_delta(attack integer, defense integer, won boolean)
returns integer
language sql
immutable
set search_path = ''
as $$
  select round(32 * ((case when won then 1 else 0 end)
    - 1 / (1 + power(10::numeric, (defense - attack)::numeric / 400))))::integer
$$;

create function private.apply_pvp_rating()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  ra integer;
  rd integer;
  d integer;
begin
  -- blokada w stałej kolejności (jak w begin_attack), żeby wzajemne ataki się nie zakleszczyły
  perform 1 from public.players p
  where p.id = new.attacker_id or p.id = new.defender_id
  order by p.id
  for update;
  select p.attack_rating into ra from public.players p where p.id = new.attacker_id;
  select p.defense_rating into rd from public.players p where p.id = new.defender_id;
  if ra is null or rd is null then
    return null;
  end if;
  d := private.elo_delta(ra, rd,
    new.status = 'finished' and coalesce((new.result ->> 'won')::boolean, false));
  update public.players p
  set attack_rating = greatest(0, p.attack_rating + d), attack_games = p.attack_games + 1
  where p.id = new.attacker_id;
  update public.players p
  set defense_rating = greatest(0, p.defense_rating - d), defense_games = p.defense_games + 1
  where p.id = new.defender_id;
  return null;
end;
$$;

comment on function private.apply_pvp_rating() is
  'Ranking PvP (#27): po zakończeniu albo porzuceniu ataku na gracza zmienia punkty ataku i obrony (Elo, K = 32).';

-- tylko atak na gracza i tylko przejście z ataku w toku: ponowiony koniec ataku nic nie zmienia
create trigger attacks_pvp_rating
  after update of status on public.attacks
  for each row
  when (old.status = 'started' and new.status in ('finished', 'abandoned') and new.defender_id is not null)
  execute function private.apply_pvp_rating();

revoke all on function private.elo_delta(integer, integer, boolean) from public, anon, authenticated;
revoke all on function private.apply_pvp_rating() from public, anon, authenticated;
grant execute on function private.elo_delta(integer, integer, boolean) to service_role;
grant execute on function private.apply_pvp_rating() to service_role;

-- ---------------------------------------------------------------------------------------------
-- Tabela rankingu
-- ---------------------------------------------------------------------------------------------

create function public.pvp_ranking(p_player uuid, p_kind text)
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
  if p_player is null or p_kind is null or p_kind not in ('attack', 'defense') then
    raise exception 'bad_kind' using errcode = 'P0001';
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
      case when p_kind = 'attack' then p.attack_rating else p.defense_rating end as points,
      -- remis: to samo miejsce; kolejność w remisie stała (id), żeby lista nie skakała
      rank() over (order by case when p_kind = 'attack' then p.attack_rating else p.defense_rating end desc)::integer
        as place,
      row_number() over (order by case when p_kind = 'attack' then p.attack_rating else p.defense_rating end desc,
        p.id) as ord
    from public.players p
    join public.castles c on c.player_id = p.id
    where p.age = v_age
      and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0
      and case when p_kind = 'attack' then p.attack_games else p.defense_games end > 0
  )
  -- RANKING_TOP = 20
  select r.place, r.nickname, r.castle_name, r.ruler, r.points, r.id = p_player
  from ranked r
  where r.ord <= 20 or r.id = p_player
  order by r.ord;
end;
$$;

comment on function public.pvp_ranking(uuid, text) is
  'Ranking PvP (#27): 20 najlepszych graczy z epoki p_player w ataku albo obronie i jego własny wiersz. Tylko dla service_role (Edge Function ranking).';

revoke all on function public.pvp_ranking(uuid, text) from public, anon, authenticated;
grant execute on function public.pvp_ranking(uuid, text) to service_role;
