-- #24: dobór przeciwnika do ataku PvP.
--
-- `public.match_targets(p_attacker)` zwraca do 3 graczy, których atakujący może zaatakować:
-- - nie on sam i nie gracz bez zamku z tożsamością z onboardingu (#228: nazwa zamku w `castles.data`),
-- - bez aktywnej tarczy (`shields.until` w przyszłości),
-- - epoka różni się najwyżej o 1, ranking najwyżej o 100,
-- - atakujący nie zaczął ataku na tego gracza w ostatnich 24 godzinach.
-- Braki (mniej niż 3 graczy) gra uzupełnia zamkami-botami (#26), więc zawsze są 3 cele.
--
-- Funkcja czyta cudze wiersze, więc woła ją wyłącznie serwer: Edge Function `find_targets` z rolą
-- `service_role`, z id atakującego wziętym z jego tokenu. Klient (`anon`, `authenticated`) nie ma
-- prawa jej wykonać, więc nie podstawi cudzego `p_attacker` i nie przeczyta zamków innych graczy.
--
-- Odpowiedź zawiera tylko to, co pokazuje karta celu: nick, nazwę zamku, władcę, epokę, ranking,
-- seed terenu (ten sam, który i tak zwraca start_attack), zarys budynków i szacowany łup.
-- Zarys to same prostokąty [x, y, szer., wys.] bez rodzajów i poziomów budynków; obrony, pułapek
-- i wojska nie ma wcale (odsłania je zwiad, #28).
--
-- Limit (skill pvp-anti-cheat): najwyżej 20 szukań na 10 minut na gracza, żeby nie dało się
-- losować celów w kółko w poszukiwaniu najsłabszego ani przeglądać po kolei zamków innych graczy.
-- Licznik leży w schemacie `private` (poza API) i znika razem z kontem gracza.

create table private.target_searches (
  player_id uuid primary key references public.players (id) on delete cascade,
  window_start timestamptz not null default now(),
  searches integer not null default 0 check (searches >= 0)
);
comment on table private.target_searches is 'Licznik szukań przeciwnika (#24) w bieżącym oknie 10 minut; pisze tylko match_targets.';

alter table private.target_searches enable row level security;
revoke all on private.target_searches from public, anon, authenticated;
grant usage on schema private to service_role;
grant select, insert, update on private.target_searches to service_role;

create function public.match_targets(p_attacker uuid)
returns table (
  player_id uuid,
  nickname text,
  castle_name text,
  ruler text,
  age smallint,
  rating integer,
  map_seed bigint,
  footprint jsonb,
  loot integer[]
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  n integer;
begin
  if p_attacker is null then
    return;
  end if;
  insert into private.target_searches as t (player_id, window_start, searches)
  values (p_attacker, now(), 1)
  on conflict (player_id) do update set
    window_start = case when t.window_start < now() - interval '10 minutes' then now() else t.window_start end,
    searches = case when t.window_start < now() - interval '10 minutes' then 1 else t.searches + 1 end
  returning t.searches into n;
  if n > 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  return query
  with me as (
    select p.age, p.rating from public.players p where p.id = p_attacker
  )
  select
    p.id,
    p.nickname,
    left(c.data -> 'profile' ->> 'castle_name', 16),
    left(coalesce(c.data -> 'profile' ->> 'ruler', ''), 20),
    p.age,
    p.rating,
    c.map_seed,
    -- zarys budynków: wpis zapisu [id, rodzaj, poziom, x, y, szer., wys.] → [x, y, szer., wys.]
    coalesce((
      select jsonb_agg(jsonb_build_array(e.v -> 3, e.v -> 4, e.v -> 5, e.v -> 6) order by e.ord)
      from jsonb_array_elements(
        case when jsonb_typeof(c.data -> 'grid' -> 'buildings') = 'array'
          then c.data -> 'grid' -> 'buildings' else '[]'::jsonb end
      ) with ordinality as e(v, ord)
      -- CASE, bo SQL nie gwarantuje kolejności warunków w AND (długość skalara rzuca błąd)
      where e.ord <= 400
        and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 7 else false end
    ), '[]'::jsonb),
    -- szacowany łup: LOOT_ESTIMATE_PERCENT = 5 procent zapasów (połowa chroniona × 20 procent łupu
    -- × co najmniej 50 procent zniszczeń po wygranej, jak BattleResult), w dół do pełnych dziesiątek,
    -- żeby karta nie zdradzała dokładnego stanu magazynu
    array(
      select (greatest(0, least(coalesce(
        case when jsonb_typeof(c.data -> 'economy' -> 'amounts' -> i) = 'number'
          then floor((c.data -> 'economy' -> 'amounts' ->> i)::numeric) end, 0), 10000000))::integer
        * 5 / 100 / 10 * 10)
      from generate_series(0, 3) as i
      order by i
    )
  from me, public.players p
  join public.castles c on c.player_id = p.id
  where p.id <> p_attacker
    and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0
    and abs(p.age - me.age) <= 1
    and abs(p.rating - me.rating) <= 100
    and not exists (
      select 1 from public.shields s where s.player_id = p.id and s.until > now()
    )
    and not exists (
      select 1 from public.attacks a
      where a.attacker_id = p_attacker and a.defender_id = p.id
        and a.started_at > now() - interval '24 hours'
    )
  order by random()
  limit 3;
end;
$$;

comment on function public.match_targets(uuid) is
  'Dobór przeciwnika (#24): do 3 graczy bez tarczy, epoka ±1, ranking ±100, bez ataku od p_attacker w 24 h; najwyżej 20 wywołań na 10 minut. Tylko dla service_role (Edge Function find_targets).';

revoke all on function public.match_targets(uuid) from public, anon, authenticated;
grant execute on function public.match_targets(uuid) to service_role;

-- dobór filtruje po epoce i rankingu
create index players_age_rating_idx on public.players (age, rating);
