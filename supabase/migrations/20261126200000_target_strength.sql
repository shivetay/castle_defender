-- #293: siła obrony celu PvP liczona przez serwer, pokazywana w mgle wojny jako przedział (ADR 0004).
--
-- `private.defense_strength(castle, layout)` liczy siłę obrony z kopii zamku (`castles.data`) i układu
-- obrony (`defense_layouts.data`, ten sam, który dostaje atakujący w `launch_attack`) tym samym wzorem
-- co gra (`Strength.defense`, scripts/world/strength.gd): załoga (wyszkolone oddziały, garnizon Dworu
-- z premią wytrzymałości), pułapki i gotowe umocnienia (wał, palisada, brama, wieża). Wagi są
-- TYMCZASOWE (#263); tablice niżej pilnuje test gry (`tests/test_strength.gd`) po znacznikach
-- w komentarzach, a pgTAP (`target_strength_test.sql`) sprawdza wynik na przykładowym zamku, który
-- gra liczy w tym samym teście.
--
-- Klient nie dostaje dokładnej liczby: `private.strength_range_low` zwraca tylko dolną granicę
-- przedziału o stałych granicach (krok 50 do 500, 100 do 2000, wyżej 500), bez losowego szumu,
-- więc kolejne wyszukiwania niczego więcej nie zdradzą. Przedział idzie na kartę celu
-- (`match_targets`, kolumna `strength`) i do historii obron (`defense_history`, kolumna `defense`:
-- aktualna siła obrony zamku napastnika; usunięte konto albo zamek to null). Liczy się na żądanie,
-- bez nowej kolumny i wyzwalacza. Wszystko woła wyłącznie service_role (Edge Functions).
--
-- Zmiana typu wyniku wymaga `drop function`; uprawnienia funkcji powtarzamy jawnie.

-- Liczba całkowita z wartości JSON (jak int() w grze: część ułamkowa odpada), null dla nie-liczby
-- i liczby spoza zakresu int.
create function private.json_int(v jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case when jsonb_typeof(v) = 'number' and abs((v #>> '{}')::numeric) < 2147483648
    then trunc((v #>> '{}')::numeric)::integer end
$$;

-- Siła jednostki (UnitTypes.Unit) przy 100 % wytrzymałości i w garnizonie Dworu (GARRISON_HP_PERCENT = 120).
-- UNIT_POWER = [11, 8, 7, 11, 5, 0, 15, 11, 16, 8, 25, 50, 5, 6, 4, 0]
-- GARRISON_UNIT_POWER = [12, 9, 7, 13, 6, 0, 16, 12, 18, 9, 27, 56, 5, 7, 5, 0]
-- Siła pułapki (TrapConfig.Kind). TRAP_POWER = [6, 4, 4, 4, 7]
-- Siła odcinka umocnień: RAMPART = 0, PALISADE = 1, GATE = 2, TOWER = 3, po 5 poziomów każdy.
-- FORT_POWER = [3, 4, 6, 9, 13, 2, 3, 4, 6, 9, 4, 6, 8, 12, 18, 23, 25, 29, 34, 40]
-- Oddział ma najwyżej SQUAD_SIZE = 10 jednostek; zadanie garnizonu to GARRISON_TASK = 6.
create function private.defense_strength(p_castle jsonb, p_layout jsonb)
returns integer
language plpgsql
immutable
set search_path = ''
as $$
declare
  unit_power constant integer[] := array[11, 8, 7, 11, 5, 0, 15, 11, 16, 8, 25, 50, 5, 6, 4, 0];
  garrison_power constant integer[] := array[12, 9, 7, 13, 6, 0, 16, 12, 18, 9, 27, 56, 5, 7, 5, 0];
  trap_power constant integer[] := array[6, 4, 4, 4, 7];
  fort_power constant integer[] := array[3, 4, 6, 9, 13, 2, 3, 4, 6, 9, 4, 6, 8, 12, 18, 23, 25, 29, 34, 40];
  castle jsonb := case when jsonb_typeof(p_castle) = 'object' then p_castle else '{}'::jsonb end;
  layout jsonb;
  garrison bigint[];
  total bigint := 0;
begin
  -- układ obrony z defense_layouts, a bez wiersza obrona z zapisu zamku (jak w grze)
  layout := case
    when jsonb_typeof(p_layout) = 'object' then p_layout
    when jsonb_typeof(castle -> 'defense') = 'object' then castle -> 'defense'
    else '{}'::jsonb end;

  -- garnizon: ostatni poprawny rozkaz oddziału [id, zadanie, x, y, …] decyduje (DefensePlan.from_dict)
  select coalesce(array_agg(o.id), '{}') into garrison
  from (
    select distinct on (private.json_int(e.v -> 0)) private.json_int(e.v -> 0) as id, private.json_int(e.v -> 1) as task
    from jsonb_array_elements(case when jsonb_typeof(layout -> 'orders') = 'array'
      then layout -> 'orders' else '[]'::jsonb end) with ordinality as e(v, ord)
    where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 4 else false end
      and private.json_int(e.v -> 0) > 0
      and private.json_int(e.v -> 1) between 0 and 6
    order by private.json_int(e.v -> 0), e.ord desc
  ) o
  where o.task = 6;

  -- załoga: oddziały [id, rodzaj, liczba], pierwszy wpis danego id, liczba 0..SQUAD_SIZE (Recruitment.load_data)
  total := total + coalesce((
    select sum(least(greatest(s.n, 0), 10)
      * case when s.id = any (garrison) then garrison_power[s.unit + 1] else unit_power[s.unit + 1] end)
    from (
      select distinct on (private.json_int(e.v -> 0)) private.json_int(e.v -> 0) as id,
        private.json_int(e.v -> 1) as unit, private.json_int(e.v -> 2) as n
      from jsonb_array_elements(case when jsonb_typeof(castle -> 'recruitment' -> 'squads') = 'array'
        then castle -> 'recruitment' -> 'squads' else '[]'::jsonb end) with ordinality as e(v, ord)
      where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 3 else false end
        and private.json_int(e.v -> 0) > 0
        and private.json_int(e.v -> 1) between 0 and 15
        and private.json_int(e.v -> 2) is not null
      order by private.json_int(e.v -> 0), e.ord
    ) s
  ), 0);

  -- pułapki [rodzaj, x, y, …]: pierwsza na danej kratce (DefensePlan.from_dict)
  total := total + coalesce((
    select sum(trap_power[t.kind + 1])
    from (
      select distinct on (private.json_int(e.v -> 1), private.json_int(e.v -> 2)) private.json_int(e.v -> 0) as kind
      from jsonb_array_elements(case when jsonb_typeof(layout -> 'traps') = 'array'
        then layout -> 'traps' else '[]'::jsonb end) with ordinality as e(v, ord)
      where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 3 else false end
        and private.json_int(e.v -> 0) between 0 and 4
        and private.json_int(e.v -> 1) is not null
        and private.json_int(e.v -> 2) is not null
      order by private.json_int(e.v -> 1), private.json_int(e.v -> 2), e.ord
    ) t
  ), 0);

  -- umocnienia: budynki [id, rodzaj, poziom, x, y, szer., wys.], pierwszy wpis danego id; poziom
  -- powyżej 5 liczy się jak 5 (BattleConfig.building_hp), plac budowy (poziom 0) nie liczy się
  total := total + coalesce((
    select sum(fort_power[b.kind * 5 + least(b.lv, 5)])
    from (
      select distinct on (private.json_int(e.v -> 0)) private.json_int(e.v -> 1) as kind,
        private.json_int(e.v -> 2) as lv
      from jsonb_array_elements(case when jsonb_typeof(castle -> 'grid' -> 'buildings') = 'array'
        then castle -> 'grid' -> 'buildings' else '[]'::jsonb end) with ordinality as e(v, ord)
      where case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 7 else false end
        and private.json_int(e.v -> 0) is not null
      order by private.json_int(e.v -> 0), e.ord
    ) b
    where b.kind between 0 and 3 and b.lv >= 1
  ), 0);

  return least(total, 2147483647)::integer;
end;
$$;

-- Dolna granica przedziału siły (Strength.range_low): krok 50 do 500, 100 do 2000, wyżej 500;
-- najwyżej MAX_RANGE_LOW = 99500.
-- RANGE_STEPS = [50, 100, 500], RANGE_LIMITS = [500, 2000]
create function private.strength_range_low(p_value integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select v / step * step
  from (select least(greatest(coalesce(p_value, 0), 0), 99500) as v) x,
    lateral (select case when x.v < 500 then 50 when x.v < 2000 then 100 else 500 end as step) s
$$;

revoke all on function private.defense_strength(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.json_int(jsonb) from public, anon, authenticated;
revoke all on function private.strength_range_low(integer) from public, anon, authenticated;
grant execute on function private.defense_strength(jsonb, jsonb) to service_role;
grant execute on function private.json_int(jsonb) to service_role;
grant execute on function private.strength_range_low(integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Karta celu: match_targets z przedziałem siły obrony
-- ---------------------------------------------------------------------------------------------

drop function public.match_targets(uuid);

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
  loot integer[],
  strength integer
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  w timestamptz;
  n integer;
begin
  if p_attacker is null then
    return;
  end if;
  -- limit sprawdzany przed zapisem: odrzucone szukanie niczego nie zmienia, więc nie zależy od tego,
  -- czy wyjątek cofnie transakcję (licznik zostaje na 20 do końca okna)
  select t.window_start, t.searches into w, n
  from private.target_searches t where t.player_id = p_attacker for update;
  if found and w >= now() - interval '10 minutes' and n >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into private.target_searches as t (player_id, window_start, searches)
  values (p_attacker, now(), 1)
  on conflict (player_id) do update set
    window_start = case when t.window_start < now() - interval '10 minutes' then now() else t.window_start end,
    searches = case when t.window_start < now() - interval '10 minutes' then 1 else t.searches + 1 end;

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
    -- karta celu pokazuje ranking obrony (#27): atakujący mierzy się z obroną celu
    p.defense_rating,
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
    ),
    -- #293: siła obrony z kopii zamku i obrony na serwerze, tylko jako dolna granica przedziału
    private.strength_range_low(private.defense_strength(c.data,
      (select d.data from public.defense_layouts d where d.player_id = p.id)))
  from me, public.players p
  join public.castles c on c.player_id = p.id
  where p.id <> p_attacker
    and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0
    and abs(p.age - me.age) <= 1
    and abs(p.rating - me.rating) <= 100
    and not exists (
      select 1 from public.shields s where s.player_id = p.id and s.until > now()
    )
    -- #284: cel z atakiem w weryfikacji (enforce) czeka, aż wejdą skutki tamtego ataku
    and not exists (
      select 1 from public.attacks a
      where a.defender_id = p.id and a.verification = 'pending' and a.outcome_applied_at is null
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
  'Dobór przeciwnika (#24): do 3 graczy bez tarczy i bez ataku w weryfikacji (#284), epoka ±1, ranking ±100, bez ataku od p_attacker w 24 h; najwyżej 20 wywołań na 10 minut; karta pokazuje ranking obrony (#27) i przedział siły obrony (#293). Tylko dla service_role (Edge Function find_targets).';
revoke all on function public.match_targets(uuid) from public, anon, authenticated;
grant execute on function public.match_targets(uuid) to service_role;
-- ---------------------------------------------------------------------------------------------
-- Historia obron: przedział siły obrony zamku napastnika (#328 → #293)
-- ---------------------------------------------------------------------------------------------

drop function public.defense_history(uuid);

create function public.defense_history(p_player uuid)
returns table (
  id uuid,
  finished_at timestamptz,
  result jsonb,
  attacker_army jsonb,
  has_replay boolean,
  nickname text,
  defense integer
)
language sql
stable
security invoker
set search_path = ''
as $$
  -- HISTORY_LIMIT = 10
  select a.id, a.finished_at, a.result, a.attacker_army, a.orders <> '[]'::jsonb, p.nickname,
    -- aktualna siła obrony zamku napastnika, tylko jako dolna granica przedziału; bez zamku null
    case when c.player_id is not null then private.strength_range_low(private.defense_strength(c.data,
      (select d.data from public.defense_layouts d where d.player_id = c.player_id))) end
  from public.attacks a
  left join public.players p on p.id = a.attacker_id
  left join public.castles c on c.player_id = a.attacker_id
  where p_player is not null
    and a.defender_id = p_player
    and a.status = 'finished'
  order by a.finished_at desc, a.id
  limit 10
$$;

comment on function public.defense_history(uuid) is
  'Historia obron (#328): 10 ostatnich zakończonych ataków na p_player z nickiem napastnika, jego armią i przedziałem siły obrony jego zamku (#293). Tylko dla service_role (Edge Function defense_history).';

revoke all on function public.defense_history(uuid) from public, anon, authenticated;
grant execute on function public.defense_history(uuid) to service_role;
