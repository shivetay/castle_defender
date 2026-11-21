-- #28 (część serwerowa): zwiad na gracza i pełne ukrycie obrony w planie ataku.
--
-- Zwiad na gracza liczy serwer. `public.begin_scout` (Edge Function `scout`) sprawdza z kopii zamku
-- atakującego na serwerze (`castles.data`), że ma on gotową Chatę tropicieli (SCOUT_HOUSE = 22),
-- zbadane S1 i zwiadowców w armii (TRACKER = 5, SCOUT = 14, najpierw Tropiciele, MAX_SCOUTS = 5).
-- Wynik losuje się z seeda z kryptograficznego źródła serwera; klient go nie wybiera. Serwer liczy
-- od razu, co zwiad odsłoni, z bieżącego zamku i obrony celu, ale oddaje wynik dopiero po końcu
-- misji (`public.scout_reports`, Edge Function `scout_reports`). Liczby jak w grze (ScoutConfig, TYMCZASOWE):
--   DURATION_S = [120, 600, 1800], REVEAL_PERCENT = [20, 35, 50], EXTRA_SCOUT_PERCENT = 5,
--   S3_PERCENT = 10, MAX_PERCENT = 80, CHANCES = [60, 20, 10, 10], S3_SUCCESS_BONUS = 10,
--   SIGNAL_TOWER_PENALTY = 20 (Wieża sygnałowa celu, SIGNAL_TOWER = 31, wykrywa zwiad).
-- Wynik: 0 sukces, 1 częściowy (wraca połowa w górę, połowa danych), 2 wykryci (wracają bez danych),
-- 3 porażka (giną wszyscy). Naraz jedna misja gracza, najwyżej 30 misji na dobę.
--
-- Odsłonięty fragment to prostokąt w obrębie zabudowy celu o polu `percent` procent zabudowy
-- (jak ScoutIntel.region_of w grze, ale położenie losuje serwer). W nim: budynki z rodzajem
-- i poziomem, miejsca oddziałów z zadaniem obrony (klasa jednostki, UNIT_CLASS niżej), trasy
-- patroli z choć jednym punktem w obszarze i pułapki. Oddziały bez zadania stoją w bitwie na
-- miejscach liczonych przez grę z całej obrony, więc zwiad ich nie pokazuje.
--
-- Pełne ukrycie obrony (decyzja właścicielki): `start_attack` przy ataku na gracza nie oddaje już
-- kopii zamku i obrony, tylko zarys budynków, donżon (cel ataku) i to, co odsłonił ostatni udany
-- zwiad tego atakującego na ten cel z ostatniej doby (`public.attack_preview`). Pełne kopie
-- (bez stanu zwiadu obrońcy) dostaje dopiero `public.launch_attack` po zatwierdzeniu planu, a wynik
-- (`end_attack`) serwer przyjmuje tylko po nim (wyzwalacz `attacks_require_launch`).
--
-- Wszystko woła wyłącznie `service_role` (Edge Functions) z id gracza z tokenu. Misje leżą
-- w schemacie `private` (poza API) i znikają razem z kontem atakującego albo celu.

alter table public.attacks
  add column launched_at timestamptz;
comment on column public.attacks.launched_at is
  'Kiedy atakujący zatwierdził plan i dostał pełną kopię obrony (launch_attack, #28); wynik tylko po nim.';

create table private.scout_missions (
  id uuid primary key default gen_random_uuid(),
  attacker_id uuid not null references public.players (id) on delete cascade,
  defender_id uuid not null references public.players (id) on delete cascade,
  duration smallint not null check (duration between 0 and 2),
  trackers smallint not null check (trackers between 0 and 5),
  scouts smallint not null check (scouts between 0 and 5),
  started_at timestamptz not null default now(),
  ends_at timestamptz not null,
  outcome smallint not null check (outcome between 0 and 3),
  percent smallint not null check (percent between 0 and 80),
  returned smallint not null check (returned >= 0),
  intel jsonb not null default '{}'::jsonb
    check (jsonb_typeof(intel) = 'object' and pg_column_size(intel) <= 65536),
  constraint scout_missions_sent check (trackers + scouts between 1 and 5 and returned <= trackers + scouts),
  constraint scout_missions_not_self check (attacker_id <> defender_id),
  constraint scout_missions_time check (ends_at > started_at)
);
comment on table private.scout_missions is
  'Zwiad na gracza (#28): wynik i odsłonięte dane z chwili wysłania; klient dostaje je dopiero po ends_at.';

create index scout_missions_attacker_idx on private.scout_missions (attacker_id, started_at desc);
create index scout_missions_defender_idx on private.scout_missions (defender_id);

alter table private.scout_missions enable row level security;
revoke all on private.scout_missions from public, anon, authenticated;
grant select, insert, delete on private.scout_missions to service_role;

-- Klasa jednostki (UnitTypes.unit_class): UNIT_CLASS = [0, 0, 2, 1, 4, 4, 3, 0, 1, 2, 3, -1, -1, 0, 4, 4]
create function private.unit_class(unit integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce((array[0, 0, 2, 1, 4, 4, 3, 0, 1, 2, 3, -1, -1, 0, 4, 4])[unit + 1], -1)
$$;

-- Prostokąty budynków z zapisu zamku: [x, y, szer., wys., rodzaj, poziom] (BuildGrid.save_data
-- [id, rodzaj, poziom, x, y, szer., wys.]); złe wpisy pomija, najwyżej 400 jak zarys w match_targets.
create function private.castle_rects(p_castle jsonb)
returns table (x integer, y integer, w integer, h integer, kind integer, level integer)
language sql
immutable
set search_path = ''
as $$
  select r.x, r.y, r.w, r.h, r.kind, r.level
  from (
    select private.json_int(e.v -> 3, 0, 63)::integer as x,
      private.json_int(e.v -> 4, 0, 63)::integer as y,
      private.json_int(e.v -> 5, 1, 64)::integer as w,
      private.json_int(e.v -> 6, 1, 64)::integer as h,
      private.json_int(e.v -> 1, 0, 255)::integer as kind,
      least(greatest(private.json_int(e.v -> 2, -1000, 1000), 0), 5)::integer as level,
      e.ord
    from jsonb_array_elements(
        case when jsonb_typeof(p_castle -> 'grid' -> 'buildings') = 'array'
          then p_castle -> 'grid' -> 'buildings' else '[]'::jsonb end) with ordinality as e(v, ord)
    -- CASE, bo SQL nie gwarantuje kolejności warunków w AND (długość skalara rzuca błąd)
    where e.ord <= 400
      and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 7 else false end
  ) r
  where r.x is not null and r.y is not null and r.w is not null and r.h is not null
    and r.kind is not null and r.level is not null
  order by r.ord
$$;

-- Czy kratka (cx, cy) leży w prostokącie p_r = [x, y, szer., wys.].
create function private.in_rect(p_r integer[], cx bigint, cy bigint)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select p_r is not null and cx >= p_r[1] and cy >= p_r[2] and cx < p_r[1] + p_r[3] and cy < p_r[2] + p_r[4]
$$;

-- Co odsłania obszar `p_region` [x, y, szer., wys.] z zamku `p_castle` i obrony `p_defense`:
-- {region, buildings: [[x, y, w, h, rodzaj, poziom]], squads: [[klasa, x, y]],
--  patrols: [[[x, y], ...]], traps: [[rodzaj, x, y]]}. Bez obszaru: pusty obiekt.
create function private.scout_intel(p_castle jsonb, p_defense jsonb, p_region integer[])
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case when p_region is null then '{}'::jsonb else jsonb_build_object(
    'region', to_jsonb(p_region),
    'buildings', coalesce((
      select jsonb_agg(jsonb_build_array(b.x, b.y, b.w, b.h, b.kind, b.level))
      from private.castle_rects(p_castle) b
      where b.x < p_region[1] + p_region[3] and b.x + b.w > p_region[1]
        and b.y < p_region[2] + p_region[4] and b.y + b.h > p_region[2]), '[]'::jsonb),
    -- zadania obrony [id oddziału, zadanie, x, y, trasa]; klasa z oddziału w zamku [id, rodzaj, liczba]
    'squads', coalesce((
      select jsonb_agg(jsonb_build_array(private.unit_class(s.unit), o.x, o.y) order by o.ord)
      from (
        select private.json_int(e.v -> 0, 1, 2147483647) as id,
          private.json_int(e.v -> 2, 0, 63) as x, private.json_int(e.v -> 3, 0, 63) as y, e.ord
        from jsonb_array_elements(case when jsonb_typeof(p_defense -> 'orders') = 'array'
            then p_defense -> 'orders' else '[]'::jsonb end) with ordinality as e(v, ord)
        where e.ord <= 64
          and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 4 else false end
      ) o
      join lateral (
        select private.json_int(q.v -> 1, 0, 15)::integer as unit
        from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'recruitment' -> 'squads') = 'array'
            then p_castle -> 'recruitment' -> 'squads' else '[]'::jsonb end) as q(v)
        where case when jsonb_typeof(q.v) = 'array' then jsonb_array_length(q.v) >= 3 else false end
          and private.json_int(q.v -> 0, 1, 2147483647) = o.id
          and coalesce(private.json_int(q.v -> 2, 1, 10), 0) > 0
        limit 1
      ) s on s.unit is not null
      where private.in_rect(p_region, o.x, o.y)), '[]'::jsonb),
    -- patrol (zadanie 1) z trasą (DefensePlan.MAX_ROUTE = 2 punkty): miejsce startu i trasa, gdy choć jeden punkt jest w obszarze
    'patrols', coalesce((
      select jsonb_agg(p.points order by p.ord)
      from (
        select e.ord,
          jsonb_build_array(jsonb_build_array(e.v -> 2, e.v -> 3)) || coalesce((
            select jsonb_agg(jsonb_build_array(w.v -> 0, w.v -> 1) order by w.ord)
            from jsonb_array_elements(e.v -> 4) with ordinality as w(v, ord)
            where w.ord <= 2
              and case when jsonb_typeof(w.v) = 'array' then jsonb_array_length(w.v) >= 2 else false end
              and private.json_int(w.v -> 0, 0, 63) is not null and private.json_int(w.v -> 1, 0, 63) is not null
          ), '[]'::jsonb) as points
        from jsonb_array_elements(case when jsonb_typeof(p_defense -> 'orders') = 'array'
            then p_defense -> 'orders' else '[]'::jsonb end) with ordinality as e(v, ord)
        where e.ord <= 64
          and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 5 else false end
          and private.json_int(e.v -> 1, 0, 10) = 1
          and jsonb_typeof(e.v -> 4) = 'array' and jsonb_array_length(e.v -> 4) > 0
          and private.json_int(e.v -> 2, 0, 63) is not null and private.json_int(e.v -> 3, 0, 63) is not null
      ) p
      where exists (
        select 1 from jsonb_array_elements(p.points) as c(v)
        where private.in_rect(p_region, (c.v ->> 0)::bigint, (c.v ->> 1)::bigint))), '[]'::jsonb),
    'traps', coalesce((
      select jsonb_agg(jsonb_build_array(t.kind, t.x, t.y) order by t.ord)
      from (
        select private.json_int(e.v -> 0, 0, 31) as kind,
          private.json_int(e.v -> 1, 0, 63) as x, private.json_int(e.v -> 2, 0, 63) as y, e.ord
        from jsonb_array_elements(case when jsonb_typeof(p_defense -> 'traps') = 'array'
            then p_defense -> 'traps' else '[]'::jsonb end) with ordinality as e(v, ord)
        where e.ord <= 64
          and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 3 else false end
      ) t
      where t.kind is not null and private.in_rect(p_region, t.x, t.y)), '[]'::jsonb)
  ) end
$$;

-- Obszar odsłonięty przez `p_percent` procent zabudowy `p_castle` w miejscu z `p_seed`
-- (ScoutIntel.region_of): proporcje zabudowy, boki w górę do całych kratek, zawsze w zabudowie.
create function private.scout_region(p_castle jsonb, p_percent integer, p_seed bigint)
returns integer[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  ox integer; oy integer; bw integer; bh integer;
  s integer; w integer; h integer;
begin
  if p_percent is null or p_percent <= 0 then
    return null;
  end if;
  select min(r.x), min(r.y), max(r.x + r.w) - min(r.x), max(r.y + r.h) - min(r.y)
  into ox, oy, bw, bh from private.castle_rects(p_castle) r;
  if ox is null then
    return null;
  end if;
  s := floor(sqrt((least(p_percent, 100) * 10000)::numeric))::integer;
  w := least(greatest((bw * s + 999) / 1000, 1), bw);
  h := least(greatest((bh * s + 999) / 1000, 1), bh);
  return array[ox + ((p_seed / 100) % (bw - w + 1))::integer,
    oy + ((p_seed / 100000) % (bh - h + 1))::integer, w, h];
end;
$$;

revoke all on function private.unit_class(integer) from public, anon, authenticated;
revoke all on function private.castle_rects(jsonb) from public, anon, authenticated;
revoke all on function private.in_rect(integer[], bigint, bigint) from public, anon, authenticated;
revoke all on function private.scout_intel(jsonb, jsonb, integer[]) from public, anon, authenticated;
revoke all on function private.scout_region(jsonb, integer, bigint) from public, anon, authenticated;
grant execute on function private.unit_class(integer) to service_role;
grant execute on function private.castle_rects(jsonb) to service_role;
grant execute on function private.in_rect(integer[], bigint, bigint) to service_role;
grant execute on function private.scout_intel(jsonb, jsonb, integer[]) to service_role;
grant execute on function private.scout_region(jsonb, integer, bigint) to service_role;

-- Wysłanie zwiadu: walidacja, wynik z `p_seed` i zapis misji. Zwraca tylko czas misji i ilu
-- zwiadowców poszło; wynik dopiero w scout_reports po ends_at.
create function public.begin_scout(p_attacker uuid, p_defender uuid, p_duration smallint, p_seed bigint)
returns table (
  mission_id uuid,
  ends_at timestamptz,
  trackers smallint,
  scouts smallint
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_age smallint;
  d_age smallint;
  v_own jsonb;
  v_castle jsonb;
  v_defense jsonb;
  v_s3 boolean;
  v_trackers integer := 0;
  v_scouts integer := 0;
  v_sent integer;
  v_towers integer;
  c integer[] := array[60, 20, 10, 10];
  v_from integer;
  v_roll integer;
  v_outcome integer;
  v_returned integer;
  v_full integer;
  v_percent integer;
  v_region integer[];
  v_ends timestamptz;
  v_id uuid;
  e jsonb;
  u bigint;
  n bigint;
begin
  if p_attacker is null or p_defender is null then
    raise exception 'bad_target' using errcode = 'P0001';
  end if;
  if p_defender = p_attacker then
    raise exception 'self_scout' using errcode = 'P0001';
  end if;
  if p_duration is null or p_duration < 0 or p_duration > 2 then
    raise exception 'bad_duration' using errcode = 'P0001';
  end if;
  if p_seed is null or p_seed < 0 or p_seed > 2147483647 then
    raise exception 'bad_seed' using errcode = 'P0001';
  end if;

  -- równoległe wysyłki tego samego gracza idą po kolei (naraz jedna misja)
  select p.age into v_age from public.players p where p.id = p_attacker for update;
  if not found then
    raise exception 'attacker_not_found' using errcode = 'P0001';
  end if;
  select c.data into v_own from public.castles c where c.player_id = p_attacker;
  if not found then
    raise exception 'attacker_no_castle' using errcode = 'P0001';
  end if;
  if not exists (select 1 from private.castle_buildings(v_own) b where b.kind = 22 and b.level >= 1) then
    raise exception 'no_building' using errcode = 'P0001';
  end if;
  -- coalesce: zamek bez `research` daje NULL, a `if not NULL` nie rzuca wyjątku
  if not coalesce(jsonb_typeof(v_own -> 'research' -> 'done') = 'array'
      and (v_own -> 'research' -> 'done') @> '["S1"]'::jsonb, false) then
    raise exception 'no_tech' using errcode = 'P0001';
  end if;
  v_s3 := coalesce((v_own -> 'research' -> 'done') @> '["S3"]'::jsonb, false);
  if exists (select 1 from private.scout_missions m where m.attacker_id = p_attacker and m.ends_at > now()) then
    raise exception 'scout_busy' using errcode = 'P0001';
  end if;
  -- SCOUT_LIMIT = 30 misji na dobę
  if (select count(*) from private.scout_missions m
      where m.attacker_id = p_attacker and m.started_at > now() - interval '24 hours') >= 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  -- zwiadowcy z oddziałów zamku [id, rodzaj, liczba]: najpierw Tropiciele, razem najwyżej 5
  for e in select x.value from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'recruitment' -> 'squads') = 'array'
        then v_own -> 'recruitment' -> 'squads' else '[]'::jsonb end) as x loop
    if jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 3 then
      u := private.json_int(e -> 1, 0, private.unit_count() - 1);
      n := private.json_int(e -> 2, 0, 10);
      if u = 5 and n is not null then
        v_trackers := v_trackers + n;
      elsif u = 14 and n is not null then
        v_scouts := v_scouts + n;
      end if;
    end if;
  end loop;
  v_trackers := least(v_trackers, 5);
  v_scouts := least(v_scouts, 5 - v_trackers);
  v_sent := v_trackers + v_scouts;
  if v_sent < 1 then
    raise exception 'no_scouts' using errcode = 'P0001';
  end if;

  -- cel: gracz z zamkiem z onboardingu, epoka ±1 (jak dobór przeciwnika)
  select p.age into d_age from public.players p where p.id = p_defender;
  select c.data into v_castle from public.castles c
  where c.player_id = p_defender and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0;
  if d_age is null or v_castle is null then
    raise exception 'target_not_found' using errcode = 'P0001';
  end if;
  if abs(d_age - v_age) > 1 then
    raise exception 'target_out_of_range' using errcode = 'P0001';
  end if;
  select coalesce((select d.data from public.defense_layouts d where d.player_id = p_defender), '{}'::jsonb)
  into v_defense;
  select count(*) into v_towers from private.castle_buildings(v_castle) b where b.kind = 31 and b.level >= 1;

  -- szanse (ScoutConfig.chances): S3 zabiera po połowie z porażki i wykrycia, Wieża sygnałowa
  -- przenosi 20 punktów sukcesu na wykrycie
  if v_s3 then
    v_from := least(5, c[4]);
    c[4] := c[4] - v_from;
    c[1] := c[1] + v_from;
    v_from := least(10 - v_from, c[3]);
    c[3] := c[3] - v_from;
    c[1] := c[1] + v_from;
  end if;
  if v_towers > 0 then
    v_from := least(20, c[1]);
    c[1] := c[1] - v_from;
    c[3] := c[3] + v_from;
  end if;
  v_roll := (p_seed % 100)::integer;
  v_outcome := case when v_roll < c[1] then 0 when v_roll < c[1] + c[2] then 1
    when v_roll < c[1] + c[2] + c[3] then 2 else 3 end;
  v_returned := case v_outcome when 0 then v_sent when 1 then (v_sent + 1) / 2 when 2 then v_sent else 0 end;
  v_full := least((array[20, 35, 50])[p_duration + 1] + 5 * least(v_sent - 1, 4) + case when v_s3 then 10 else 0 end, 80);
  v_percent := case v_outcome when 0 then v_full when 1 then v_full / 2 else 0 end;
  v_region := private.scout_region(v_castle, v_percent, p_seed);
  v_ends := now() + make_interval(secs => (array[120, 600, 1800])[p_duration + 1]);

  -- na jeden cel jeden raport: starsze misje tego gracza na ten cel znikają
  delete from private.scout_missions m where m.attacker_id = p_attacker and m.defender_id = p_defender;
  insert into private.scout_missions (attacker_id, defender_id, duration, trackers, scouts, ends_at, outcome,
    percent, returned, intel)
  values (p_attacker, p_defender, p_duration, v_trackers, v_scouts, v_ends, v_outcome,
    case when v_region is null then 0 else v_percent end, v_returned,
    private.scout_intel(v_castle, v_defense, v_region))
  returning id into v_id;

  return query select v_id, v_ends, v_trackers::smallint, v_scouts::smallint;
end;
$$;

comment on function public.begin_scout(uuid, uuid, smallint, bigint) is
  'Zwiad na gracza (#28): Chata tropicieli, S1 i zwiadowcy z zamku atakującego na serwerze, naraz jedna misja, 30 na dobę; wynik z seeda serwera. Tylko dla service_role (Edge Function scout).';
revoke all on function public.begin_scout(uuid, uuid, smallint, bigint) from public, anon, authenticated;
grant execute on function public.begin_scout(uuid, uuid, smallint, bigint) to service_role;

-- Misje gracza z ostatniej doby (i misja w drodze): wynik, ocaleli i odsłonięte dane tylko po końcu.
create function public.scout_reports(p_attacker uuid)
returns table (
  mission_id uuid,
  defender_id uuid,
  castle_name text,
  duration smallint,
  trackers smallint,
  scouts smallint,
  ends_at timestamptz,
  finished boolean,
  outcome smallint,
  percent smallint,
  returned smallint,
  intel jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select m.id, m.defender_id, left(c.data -> 'profile' ->> 'castle_name', 16), m.duration, m.trackers,
    m.scouts, m.ends_at, m.ends_at <= now(),
    case when m.ends_at <= now() then m.outcome end,
    case when m.ends_at <= now() then m.percent end,
    case when m.ends_at <= now() then m.returned end,
    case when m.ends_at <= now() then m.intel end
  from private.scout_missions m
  left join public.castles c on c.player_id = m.defender_id
  where m.attacker_id = p_attacker and m.ends_at > now() - interval '24 hours'
  order by m.ends_at desc
  limit 20
$$;

comment on function public.scout_reports(uuid) is
  'Raporty zwiadu gracza (#28) z ostatniej doby; wynik i odsłonięte dane dopiero po końcu misji. Tylko dla service_role (Edge Function scout_reports).';
revoke all on function public.scout_reports(uuid) from public, anon, authenticated;
grant execute on function public.scout_reports(uuid) to service_role;

-- Podgląd celu do planu ataku na gracza: zarys budynków, donżon (KEEP = 21, cel ataku) i odsłonięte
-- przez ostatni udany zwiad tego atakującego na ten cel z ostatniej doby. Z kopii z chwili startu
-- liczy się tylko zarys; odsłonięte dane są z chwili zwiadu.
create function public.attack_preview(p_attacker uuid, p_attack uuid)
returns table (
  footprint jsonb,
  keep integer[],
  intel jsonb
)
language sql
stable
security invoker
set search_path = ''
as $$
  select
    coalesce((select jsonb_agg(jsonb_build_array(r.x, r.y, r.w, r.h)) from private.castle_rects(a.castle_snapshot) r),
      '[]'::jsonb),
    (select array[r.x, r.y, r.w, r.h] from private.castle_rects(a.castle_snapshot) r where r.kind = 21 limit 1),
    coalesce((select m.intel from private.scout_missions m
      where m.attacker_id = a.attacker_id and m.defender_id = a.defender_id
        and m.ends_at <= now() and m.ends_at > now() - interval '24 hours' and m.percent > 0
      order by m.ends_at desc limit 1), '{}'::jsonb)
  from public.attacks a
  where a.id = p_attack and a.attacker_id = p_attacker and a.defender_id is not null
$$;

comment on function public.attack_preview(uuid, uuid) is
  'Plan ataku na gracza (#28): zarys, donżon i odsłonięte przez zwiad, bez pełnej obrony. Tylko dla service_role (Edge Function start_attack).';
revoke all on function public.attack_preview(uuid, uuid) from public, anon, authenticated;
grant execute on function public.attack_preview(uuid, uuid) to service_role;

-- Zatwierdzenie planu: pełne kopie zamku (bez stanu zwiadu obrońcy) i obrony z chwili startu.
-- Ponowienie dla tego samego ataku zwraca to samo i nie przesuwa launched_at.
create function public.launch_attack(p_attacker uuid, p_attack uuid)
returns table (
  castle jsonb,
  defense jsonb
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker and t.defender_id is not null
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'started' or a.started_at < now() - interval '10 minutes' then
    raise exception 'attack_expired' using errcode = 'P0001';
  end if;
  if a.launched_at is null then
    update public.attacks t set launched_at = now() where t.id = a.id;
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot;
end;
$$;

comment on function public.launch_attack(uuid, uuid) is
  'Atak na gracza po zatwierdzeniu planu (#28): pełne kopie zamku i obrony z chwili startu. Tylko dla service_role (Edge Function launch_attack).';
revoke all on function public.launch_attack(uuid, uuid) from public, anon, authenticated;
grant execute on function public.launch_attack(uuid, uuid) to service_role;

-- Wynik ataku na gracza tylko po zatwierdzeniu planu: bez launch_attack klient nie miał pełnej
-- obrony, więc nie policzył bitwy. Wyzwalacz łapie każdą drogę do statusu `finished`.
create function private.attacks_require_launch()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.status = 'finished' and old.status <> 'finished' and new.defender_id is not null
      and new.launched_at is null then
    raise exception 'not_launched' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function private.attacks_require_launch() from public, anon, authenticated;

create trigger attacks_require_launch
  before update on public.attacks
  for each row execute function private.attacks_require_launch();
