-- #274 (etap 4): zabudowa w `castles.data` bez zaufanej edycji lokalnej.
--
-- Serwer czyta z zapisu zamku poziom Dworu i innych budynków jako prawdę: limit armii
-- (`private.army_limit`), produkcja żywności i limit utrzymania (`private.food_production`), pojemność
-- magazynów (`private.castle_capacity`), epoka gracza (`private.castle_age`) i garnizon Dworu (#81).
-- Klient nie jest zaufany, więc przy każdym zapisie zamku (wyzwalacz `castles_check_buildings`, INSERT
-- i UPDATE `data`) zabudowa musi dać się zbudować w grze. Zapis spoza reguł jest odrzucany w całości kodem
-- HTTP 422 (SQLSTATE PT422), bez cichego przycinania; telefon przywraca wtedy zamek z serwera
-- (SupabaseClient, #274 etap 1). Kod w treści błędu:
-- - bad_building: poziom budynku spoza 0..MAX_TOTAL_LEVEL = 10 (Ages);
-- - building_over_manor: budynek wyżej niż Dwór (BuildConfig.max_level). Dwór to rodzaj MANOR = 5
--   o najniższym id (BuildGrid.manor_id), bez Dworu liczy się poziom 1. Rodzaje bez poziomów
--   (BuildingTypes.has_levels: KEEP = 21, WATCHTOWER = 23) najwyżej poziom 1, a drugi Dwór najwyżej
--   tyle, co pierwszy;
-- - age_locked: Dwór na poziomie 6+ (epoka II) bez zbadanych technologii przejścia O1, G1, A7
--   (Ages.TRANSITION_TECHS), jak `private.castle_age`;
-- - build_too_fast: zabudowa urosła bardziej, niż zdążyłby zbudować jeden budowniczy (BuildConfig.BUILDERS = 1)
--   od poprzedniego zapisu zamku na serwerze.
--
-- Czas budowy jak BuildConfig.time_ms (poziomy narastająco przez epoki):
--   BASE_TIME_S = [5, 10, 30, 60, 45, 0, 40, 50, 60, 50, 40, 60, 50, 60, 45, 30, 40, 60, 60, 75, 70, 90, 70, 0, 60, 45, 5, 60, 40, 30, 50, 50]
--   (sekundy poziomu 1 według BuildingTypes.Kind), TIME_MULT = [1, 3, 10, 30, 90] dla poziomów epoki,
--   AGE_TIME_MULT = [1, 2] dla epok, a Dwór ma własne MANOR_TIME_S = [0, 600, 3600, 14400, 43200, 43200, 1200, 7200, 28800, 86400].
-- Potrzebny czas to suma czasów poziomów, które przybyły od poprzedniego zapisu (ten sam id i rodzaj; nowy
-- budynek od zera, plac budowy na poziomie 0 nic nie kosztuje), razy BUILDER_TIME_PERCENT = 90 procent, bo
-- zlecenie z perkiem Budowniczy (#32) trwa krócej, a perk mógł się zmienić po zleceniu. Budżet to czas
-- od poprzedniego zapisu na zegarze serwera (`old.updated_at`) plus pełny czas zlecenia, które było
-- w toku przy poprzednim zapisie (`queue.orders[0]`, zaczęło się przed nim), plus TOLERANCE = 5 minut
-- (opóźnienie sieci i krótkie odcinki umocnień, które gra domyka sama). Stałe przesunięcie zegara telefonu
-- nie przeszkadza: gra liczy budowę z różnicy dwóch chwil na tym samym zegarze. Przestawienie zegara
-- do przodu (przyspieszenie budowy) jest tym, co ten limit łapie.
-- Pierwszy zapis zamku (INSERT) liczy od założenia konta (`players.created_at`) z zapasem
-- INSERT_GRACE = 6 godzin na grę bez sieci przed pierwszym połączeniem; za darmo stoją Dwór na poziomie 1
-- i donżon, jak w nowej grze.
-- Limit czasu dotyczy zapisów z API jako gracz (rola z tokenu `authenticated` albo `anon`); serwer (Edge
-- Functions, migracje) pisze stan zaufany. Reguły poziomów dotyczą każdego zapisu.
--
-- `public.begin_attack` nie wpuszcza do PvP zamku, który łamie reguły poziomów: `private.castle_resources_problem`
-- (etap 1) zwraca teraz też kod zabudowy, więc atakujący dostaje `castle_invalid`, a obrońca nie jest celem.
-- Pokrycie kosztów budowy w surowcach wymaga limitu przyrostu produkcji (etap 3) i jest poza tą migracją.
-- Zamki zapisane przed migracją, które łamią reguły poziomów, dostają raz poziomy przycięte do Dworu
-- (a Dwór bez technologii epoki II do poziomu 5); to jedyny wyjątek od zasady „bez przycinania”.
-- Liczby pilnuje test gry (`tests/test_building_sanity.gd`) po znacznikach w komentarzach.

-- ---------------------------------------------------------------------------------------------
-- Funkcje pomocnicze (schemat private)
-- ---------------------------------------------------------------------------------------------

-- Budynki z zapisu jak po BuildGrid.load_data (pierwszy wpis danego id, wpis krótszy niż 7 pól się nie
-- liczy), ale z surowym poziomem (bez przycinania do 0..5 jak `private.castle_buildings`).
create function private.castle_levels(p_castle jsonb)
returns table (id bigint, kind bigint, level bigint)
language sql
immutable
set search_path = ''
as $$
  select distinct on (b.id) b.id, b.kind, b.lvl
  from (
    select private.json_int(x.e -> 0, 1, 2147483647) as id,
      private.json_int(x.e -> 1, 0, 2147483647) as kind,
      private.json_int(x.e -> 2, -2147483648, 2147483647) as lvl,
      x.ord
    from jsonb_array_elements(
        case when jsonb_typeof(p_castle -> 'grid' -> 'buildings') = 'array'
          then p_castle -> 'grid' -> 'buildings' else '[]'::jsonb end)
      with ordinality as x(e, ord)
    -- case, bo `and` w where nie gwarantuje kolejności, a jsonb_array_length na skalarze rzuca błąd
    where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end
  ) b
  where b.id is not null and b.kind is not null and b.lvl is not null
  order by b.id, b.ord
$$;

-- Czas budowy poziomu `p_level` (narastająco, 1..10) budynku rodzaju `p_kind` w ms (BuildConfig.time_ms).
create function private.build_time_ms(p_kind bigint, p_level bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select case
    when p_level < 1 or p_level > 10 then 0::bigint
    when p_kind = 5 then (array[0, 600, 3600, 14400, 43200, 43200, 1200, 7200, 28800, 86400])[p_level]::bigint * 1000
    else coalesce((array[5, 10, 30, 60, 45, 0, 40, 50, 60, 50, 40, 60, 50, 60, 45, 30, 40, 60, 60, 75, 70, 90, 70, 0, 60, 45, 5, 60, 40, 30, 50, 50])[p_kind + 1], 0)::bigint
      * (array[1, 3, 10, 30, 90])[(p_level - 1) % 5 + 1] * (array[1, 2])[(p_level - 1) / 5 + 1] * 1000
  end
$$;

-- Kod problemu z poziomami budynków w zapisie albo null.
create function private.castle_buildings_problem(p_castle jsonb)
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
  select b.id, greatest(b.level, 1) into v_manor_id, v_manor
  from private.castle_levels(p_castle) b where b.kind = 5 order by b.id limit 1;
  v_manor := coalesce(v_manor, 1);
  if exists (select 1 from private.castle_levels(p_castle) b
      where b.id is distinct from v_manor_id
        and b.level > case when b.kind in (21, 23) then 1 else v_manor end) then
    return 'building_over_manor';
  end if;
  if v_manor >= 6 and not (jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
      and (p_castle -> 'research' -> 'done') @> '["O1", "G1", "A7"]'::jsonb) then
    return 'age_locked';
  end if;
  return null;
end;
$$;

-- Zabudowa nowej gry dla budynków z zapisu `p_castle`: Dwór (najniższe id) i donżon na poziomie 1.
create function private.start_buildings(p_castle jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object('grid', jsonb_build_object('buildings', coalesce(jsonb_agg(
      jsonb_build_array(b.id, b.kind, 1, 0, 0, 0, 0)), '[]'::jsonb)))
  from private.castle_levels(p_castle) b
  where b.kind = 21
    or (b.kind = 5 and b.id = (select min(m.id) from private.castle_levels(p_castle) m where m.kind = 5))
$$;

-- Czas budowy (ms) poziomów, które przybyły w `p_new` względem `p_old` (ten sam id i rodzaj).
create function private.build_need_ms(p_old jsonb, p_new jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(private.build_time_ms(n.kind, l)), 0)::bigint
  from private.castle_levels(p_new) n
  left join private.castle_levels(p_old) o on o.id = n.id and o.kind = n.kind
  cross join lateral generate_series(greatest(coalesce(o.level, 0), 0) + 1, least(n.level, 10)) as l
$$;

-- Pełny czas zlecenia, które w zapisie `p_castle` było w toku (pierwsze w kolejce), w ms.
create function private.queue_slack_ms(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce((
    select private.build_time_ms(b.kind, private.json_int(o -> 'level', 1, 10))
    from (select p_castle -> 'queue' -> 'orders' -> 0 as o) q
    join private.castle_levels(p_castle) b on b.id = private.json_int(q.o -> 'building_id', 1, 2147483647)
    where jsonb_typeof(p_castle -> 'queue' -> 'orders') = 'array'), 0)
$$;

revoke all on function private.castle_levels(jsonb) from public, anon, authenticated;
revoke all on function private.build_time_ms(bigint, bigint) from public, anon, authenticated;
revoke all on function private.castle_buildings_problem(jsonb) from public, anon, authenticated;
revoke all on function private.start_buildings(jsonb) from public, anon, authenticated;
revoke all on function private.build_need_ms(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.queue_slack_ms(jsonb) from public, anon, authenticated;
-- begin_attack woła castle_buildings_problem (przez castle_resources_problem) jako service_role
grant execute on function private.castle_levels(jsonb) to service_role;
grant execute on function private.castle_buildings_problem(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Zamki sprzed migracji
-- ---------------------------------------------------------------------------------------------

-- Jednorazowo: poziom spoza 0..10 do zakresu, Dwór bez technologii epoki II najwyżej 5, a pozostałe budynki
-- najwyżej do Dworu (bez poziomów: 1). Wyzwalacz surowców (etap 1) jest na ten czas wyłączony: zamek
-- ze złym kształtem `economy` (który i tak nie wejdzie do PvP) nie może zatrzymać migracji.
alter table public.castles disable trigger castles_resources;
update public.castles c
set data = jsonb_set(c.data, '{grid,buildings}', (
    select jsonb_agg(case
        when not (case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end)
          or private.json_int(x.e -> 2, -2147483648, 2147483647) is null
          or private.json_int(x.e -> 1, 0, 2147483647) is null then x.e
        else jsonb_set(x.e, '{2}', to_jsonb(least(greatest(private.json_int(x.e -> 2, -2147483648, 2147483647), 0),
          case
            when private.json_int(x.e -> 1, 0, 2147483647) in (21, 23) then 1
            when private.json_int(x.e -> 1, 0, 2147483647) = 5
                and private.json_int(x.e -> 0, 1, 2147483647) = m.id then m.cap
            else m.level end)))
      end order by x.ord)
    from jsonb_array_elements(c.data -> 'grid' -> 'buildings') with ordinality as x(e, ord),
      lateral (
        select mb.id,
          -- Dwór bez technologii przejścia zostaje w epoce I
          case when jsonb_typeof(c.data -> 'research' -> 'done') = 'array'
              and (c.data -> 'research' -> 'done') @> '["O1", "G1", "A7"]'::jsonb then 10 else 5 end as cap,
          least(greatest(coalesce(mb.level, 1), 1), case when jsonb_typeof(c.data -> 'research' -> 'done') = 'array'
              and (c.data -> 'research' -> 'done') @> '["O1", "G1", "A7"]'::jsonb then 10 else 5 end) as level
        from (select null::int) one
        left join lateral (select b.id, b.level from private.castle_levels(c.data) b where b.kind = 5
          order by b.id limit 1) mb on true) m))
where jsonb_typeof(c.data -> 'grid' -> 'buildings') = 'array'
  and private.castle_buildings_problem(c.data) is not null;
alter table public.castles enable trigger castles_resources;

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacz zapisu zamku
-- ---------------------------------------------------------------------------------------------

-- Przed zapisem zamku: poziomy budynków w regułach gry i przyrost zabudowy w czasie jednego budowniczego.
-- SECURITY DEFINER, bo funkcje pomocnicze są w schemacie private, a gracz zapisuje jako `authenticated`;
-- czyta tylko `players.created_at` właściciela zapisywanego zamku (new.player_id). Nazwa
-- `castles_check_buildings` sortuje się po `castles_bump_revision`, ale wyzwalacz bierze czas poprzedniego
-- zapisu z `old.updated_at`, którego bump_revision nie zmienia.
create function private.check_castle_buildings()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem text := private.castle_buildings_problem(new.data);
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_old jsonb;
  v_budget numeric;
  v_need bigint;
begin
  if v_problem is not null then
    raise exception '%', v_problem using errcode = 'PT422';
  end if;
  -- serwer (service_role, migracje) pisze stan zaufany; limit czasu dotyczy gracza
  if v_role not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    v_old := private.start_buildings(new.data);
    -- INSERT_GRACE = 6 godzin
    select extract(epoch from now() - p.created_at) * 1000 + 6 * 3600 * 1000 into v_budget
    from public.players p where p.id = new.player_id;
    v_budget := coalesce(v_budget, 6 * 3600 * 1000);
  else
    v_old := old.data;
    v_budget := extract(epoch from now() - old.updated_at) * 1000 + private.queue_slack_ms(old.data);
  end if;
  -- TOLERANCE = 5 minut, BUILDER_TIME_PERCENT = 90
  v_budget := v_budget + 5 * 60 * 1000;
  v_need := private.build_need_ms(v_old, new.data) * 90 / 100;
  if v_need > v_budget then
    raise exception 'build_too_fast' using errcode = 'PT422';
  end if;
  return new;
end;
$$;

revoke all on function private.check_castle_buildings() from public, anon, authenticated;

create trigger castles_check_buildings
  before insert or update of data on public.castles
  for each row execute function private.check_castle_buildings();

-- ---------------------------------------------------------------------------------------------
-- Zamek spoza reguł zabudowy nie wchodzi do PvP (begin_attack przez castle_resources_problem)
-- ---------------------------------------------------------------------------------------------

-- Jak w `*_resource_sanity.sql`, z kodem zabudowy przed surowcami.
create or replace function private.castle_resources_problem(p_player uuid, p_castle jsonb, p_paid integer)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_economy jsonb := p_castle -> 'economy';
  v_amounts jsonb;
  v_cap integer;
  v_building text := private.castle_buildings_problem(p_castle);
  x bigint;
begin
  if v_building is not null then
    return v_building;
  end if;
  if v_economy is null then
    return null;
  end if;
  v_amounts := v_economy -> 'amounts';
  if jsonb_typeof(v_economy) <> 'object' or jsonb_typeof(v_amounts) is distinct from 'array'
      or jsonb_array_length(v_amounts) <> 4 then
    return 'bad_economy';
  end if;
  v_cap := private.castle_capacity(p_castle);
  for i in 0 .. 3 loop
    x := private.json_int(v_amounts -> i, 0, 10000000);
    if x is null then
      return 'bad_economy';
    end if;
    if i < 3 and x > v_cap then
      return 'over_capacity';
    end if;
    if i = 3 and x > private.ruler_gold_left(p_player, p_castle -> 'generals', p_paid) then
      return 'gold_unbacked';
    end if;
  end loop;
  return null;
end;
$$;

revoke all on function private.castle_resources_problem(uuid, jsonb, integer) from public, anon, authenticated;
grant execute on function private.castle_resources_problem(uuid, jsonb, integer) to service_role;
