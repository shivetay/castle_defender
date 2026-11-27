-- #408: Targ (MARKET = 33), budynek sklepu. Stoi od startu jak Dwór, jeden na zamek, bez poziomów, bez
-- rozbiórki i przenoszenia, bez produkcji i bez kosztu. W bitwie jest przeszkodą bez wytrzymałości (nie cel).
--
-- Serwer musi to znać w zabudowie zamku (`*_building_sanity.sql`, najnowsza wersja w `*_mill.sql`):
-- - `private.castle_buildings_problem`: Targ najwyżej jeden i tylko na poziomie 1 (`bad_building`), jak inne
--   budynki bez poziomów: KEEP = 21, WATCHTOWER = 23, MARKET = 33 najwyżej poziom 1;
-- - nowy wyzwalacz `castles_check_market` (UPDATE `data` z tokenu gracza): Targ z poprzedniego zapisu zostaje
--   w tym samym prostokącie (x, y, w, h), kod `market_moved` (HTTP 422, SQLSTATE PT422). Targ bez wytrzymałości
--   blokuje drogę w bitwie, więc przeniesiony Targ byłby niezniszczalnym murem w dowolnym miejscu. Wyjątek: zapis,
--   w którym stoją same budynki startu (Dwór, donżon, Strażnica, Targ: `START_KINDS = (5, 21, 23, 33)`), czyli
--   „Zacznij od nowa” (#23), który stawia Targ od nowa na tym samym terenie;
-- - czasu budowy i kosztu Targ nie ma: `private.build_time_ms` i `private.build_cost` dają 0 dla rodzaju spoza
--   tablic, więc Targ dostawiony w starym zamku (gra stawia go sama przy wczytaniu) nie zużywa budowniczego
--   ani surowców. Wymaganej technologii też nie ma (`private.locked_new_building`).
-- Nowych danych o graczu nie ma. Liczby pilnuje test gry (`tests/test_market.gd`) i pgTAP
-- `supabase/tests/database/market_test.sql`.

-- Kod problemu z poziomami budynków w zapisie albo null (jak w `*_mill.sql`), z Targiem.
create or replace function private.castle_buildings_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_manor_id bigint;
  v_manor bigint;
begin
  if exists (select 1 from private.castle_levels(p_castle) b where b.level < 0 or b.level > 10) then
    return 'bad_building';
  end if;
  if exists (select 1 from private.castle_levels(p_castle) b where b.kind = 32 and b.level between 1 and 5) then
    return 'bad_building';
  end if;
  -- Targ: jeden, poziom 1 (bez placu budowy, bez poziomów)
  if exists (select 1 from private.castle_levels(p_castle) b where b.kind = 33 and b.level <> 1)
      or (select count(*) from private.castle_levels(p_castle) b where b.kind = 33) > 1 then
    return 'bad_building';
  end if;
  select b.id, greatest(b.level, 1) into v_manor_id, v_manor
  from private.castle_levels(p_castle) b where b.kind = 5 order by b.id limit 1;
  v_manor := coalesce(v_manor, 1);
  if exists (select 1 from private.castle_levels(p_castle) b
      where b.id is distinct from v_manor_id
        and b.level > case when b.kind in (21, 23, 33) then 1 else v_manor end) then
    return 'building_over_manor';
  end if;
  if v_manor >= 6 and not (jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
      and (p_castle -> 'research' -> 'done') @> '["O1", "G1", "A7"]'::jsonb) then
    return 'age_locked';
  end if;
  return null;
end;
$$;

revoke all on function private.castle_buildings_problem(jsonb) from public, anon, authenticated;
grant execute on function private.castle_buildings_problem(jsonb) to service_role;

-- Prostokąt Targu z zapisu jako [x, y, w, h] (pierwszy wpis rodzaju 33 jak w `private.castle_levels`) albo null.
create function private.market_rect(p_castle jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_array(x.e -> 3, x.e -> 4, x.e -> 5, x.e -> 6)
  from jsonb_array_elements(
      case when jsonb_typeof(p_castle -> 'grid' -> 'buildings') = 'array'
        then p_castle -> 'grid' -> 'buildings' else '[]'::jsonb end)
    with ordinality as x(e, ord)
  where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end
    and private.json_int(x.e -> 1, 0, 2147483647) = 33
  order by x.ord
  limit 1
$$;

revoke all on function private.market_rect(jsonb) from public, anon, authenticated;

-- Przed zapisem zamku przez gracza: Targ zostaje tam, gdzie stał (`market_moved`), chyba że w zapisie stoją
-- same budynki startu (nowa gra). SECURITY DEFINER jak inne wyzwalacze zamku, bo funkcje pomocnicze są
-- w schemacie private, a gracz zapisuje jako `authenticated`; czyta tylko `old` i `new` tego wiersza.
create function private.check_castle_market()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_old jsonb := private.market_rect(old.data);
begin
  -- serwer (service_role, migracje) pisze stan zaufany
  if v_role not in ('authenticated', 'anon') or v_old is null then
    return new;
  end if;
  -- START_KINDS = (5, 21, 23, 33): „Zacznij od nowa” stawia Targ od nowa
  if not exists (select 1 from private.castle_levels(new.data) b where b.kind not in (5, 21, 23, 33)) then
    return new;
  end if;
  if private.market_rect(new.data) is distinct from v_old then
    raise exception 'market_moved' using errcode = 'PT422';
  end if;
  return new;
end;
$$;

revoke all on function private.check_castle_market() from public, anon, authenticated;

create trigger castles_check_market
  before update of data on public.castles
  for each row execute function private.check_castle_market();
