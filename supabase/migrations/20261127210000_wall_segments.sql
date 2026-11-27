-- #371: odcinki wału i palisady 1/2/3 kratki, dłuższe za złoto (review PR 414).
--
-- Gra stawia odcinek 2 albo 3 kratek wału (rodzaj 0) albo palisady (rodzaj 1) jednym zleceniem w kolejce:
-- `queue.orders[i].building_id` to pierwsza kratka, `queue.orders[i].extra_ids` pozostałe (BuildQueue.Order).
-- Materiały i czas liczą się ×długość, a do tego dopłata w złocie za długość 1, 2, 3 (BuildConfig.SEGMENT_GOLD):
--   SEGMENT_GOLD = [0, 2, 5]
-- Kolejka jest w zapisie zamku (`castles.data.queue`), więc serwer musi znać odcinki w trzech miejscach:
-- - `private.build_paid`: kratki z `extra_ids` są opłacone jak zlecenie z kolejki (ten sam poziom), więc
--   `private.build_flow` liczy materiały ×N przy zleceniu i zwrot ×N przy anulowaniu;
-- - `private.build_flow`: dopłata w złocie przy nowym zleceniu odcinka i jej zwrot, gdy zlecenie znika bez
--   ukończenia (główna kratka nie ma w nowym zapisie poziomu zlecenia);
-- - `private.queue_head_ms`: zlecenie w toku trwa czas poziomu ×(1 + liczba kratek z `extra_ids`).
--
-- Kratki odcinka liczą się tak jak w BuildQueue.load_data: tylko istniejące budynki tego samego rodzaju co
-- główna kratka, bez niej samej i bez powtórzeń, najwyżej SEGMENT_MAX − 1 = 2, w kolejności z zapisu.
-- Serwer dokłada warunki, które gra spełnia przy każdym zleceniu: odcinek to tylko wał albo palisada
-- na poziomie 1 (postawienie). Dopłata liczy się po kluczu (główna kratka, poziom, dopłata), więc wydatek
-- i zwrot są symetryczne: zmiana liczby kratek w zleceniu to zwrot starej dopłaty i wydatek nowej.
-- Ograniczenie: odcinek zlecony i ukończony między dwoma zapisami (bez sieci) jest dla serwera N zwykłymi
-- kratkami bez dopłaty; złoto w telefonie spada wtedy o dopłatę więcej, w granicy HIDE_SLACK złota (20, odnawiane
-- w godzinę). Gra zapisuje zamek zaraz po zleceniu, więc przy sieci zlecenie widać w kolejce.
-- Nowych danych o graczu nie ma.
--
-- Każda funkcja to najnowsza wersja z wcześniejszych migracji (`*_mill.sql`, `*_economy_growth.sql`,
-- `*_building_sanity.sql`) z odcinkami. `create or replace` zostawia uprawnienia; mimo to powtarzamy je jawnie
-- (tylko service_role). Liczby pilnuje `tests/test_wall_segments.gd` po znaczniku SEGMENT_GOLD w tym komentarzu,
-- a pgTAP `supabase/tests/database/wall_segments_test.sql`.

-- Zlecenia odcinków w kolejce `p_castle`: pozycja w kolejce, główna kratka, rodzaj, poziom, kratki z `extra_ids`
-- (puste dla zwykłego zlecenia) i dopłata w złocie.
create function private.segment_orders(p_castle jsonb)
returns table (pos bigint, id bigint, kind bigint, level bigint, extra_ids bigint[], gold bigint)
language sql
immutable
set search_path = ''
as $$
  with q as (
    select o.ord - 1 as pos, o.e, private.json_int(o.e -> 'building_id', 1, 2147483647) as id,
      private.json_int(o.e -> 'level', 1, 10) as level
    from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'queue' -> 'orders') = 'array'
        then p_castle -> 'queue' -> 'orders' else '[]'::jsonb end) with ordinality as o(e, ord)
    where jsonb_typeof(o.e) = 'object'
  ),
  s as (
    select q.pos, b.id, b.kind, q.level,
      coalesce((
        select array_agg(x.id order by x.first)
        from (
          select xb.id, min(x.ord) as first
          from jsonb_array_elements(case when jsonb_typeof(q.e -> 'extra_ids') = 'array'
              then q.e -> 'extra_ids' else '[]'::jsonb end) with ordinality as x(v, ord)
          join private.castle_levels(p_castle) xb on xb.id = private.json_int(x.v, 1, 2147483647)
          where xb.kind = b.kind and xb.id <> b.id
          group by xb.id
          order by min(x.ord)
          limit 2
        ) x), '{}'::bigint[]) as extra_ids
    from q
    join private.castle_levels(p_castle) b on b.id = q.id
    where q.level = 1 and b.kind in (0, 1)
  )
  select s.pos, s.id, s.kind, s.level, s.extra_ids,
    -- SEGMENT_GOLD = [0, 2, 5]
    (array[0, 2, 5])[cardinality(s.extra_ids) + 1]::bigint
  from s
$$;

-- Poziomy opłacone w zapisie (jak w `*_mill.sql`) i kratki odcinków z kolejki z poziomem zlecenia.
create or replace function private.build_paid(p_castle jsonb)
returns table (id bigint, kind bigint, level bigint, queued boolean)
language sql
immutable
set search_path = ''
as $$
  select b.id, b.kind, l::bigint, false
  from private.castle_levels(p_castle) b
  cross join lateral generate_series(case when b.kind = 32 then 6 else 1 end, least(greatest(b.level, 0), 10)) as l
  union
  select b.id, b.kind, q.level, true
  from (
    select private.json_int(o -> 'building_id', 1, 2147483647) as id, private.json_int(o -> 'level', 1, 10) as level
    from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'queue' -> 'orders') = 'array'
        then p_castle -> 'queue' -> 'orders' else '[]'::jsonb end) o
    where jsonb_typeof(o) = 'object'
  ) q
  join private.castle_levels(p_castle) b on b.id = q.id
  where q.level is not null
  union
  select x.id, s.kind, s.level, true
  from private.segment_orders(p_castle) s
  cross join lateral unnest(s.extra_ids) as x(id)
$$;

-- Wydatek i zwrot budowy (jak w `*_economy_growth.sql`) z dopłatą w złocie za odcinki: nowe zlecenie odcinka
-- (klucz: główna kratka, poziom, dopłata) to wydatek, a zlecenie, które zniknęło bez ukończenia głównej kratki,
-- to zwrot.
create or replace function private.build_flow(p_old jsonb, p_new jsonb)
returns table (spend bigint[], refund bigint[])
language sql
immutable
set search_path = ''
as $$
  with n as (select distinct x.id, x.kind, x.level from private.build_paid(p_new) x),
  o as (select distinct x.id, x.kind, x.level from private.build_paid(p_old) x),
  oq as (select distinct x.id, x.kind, x.level from private.build_paid(p_old) x where x.queued
    and not exists (select 1 from private.build_paid(p_old) y
      where not y.queued and y.id = x.id and y.kind = x.kind and y.level = x.level)),
  s as (select private.build_cost(n.kind, n.level) c from n
    where not exists (select 1 from o where o.id = n.id and o.kind = n.kind and o.level = n.level)),
  r as (select private.build_cost(oq.kind, oq.level) c from oq
    where not exists (select 1 from n where n.id = oq.id and n.kind = oq.kind and n.level = oq.level)),
  ns as (select distinct x.id, x.level, x.gold from private.segment_orders(p_new) x where x.gold > 0),
  os as (select distinct x.id, x.level, x.gold from private.segment_orders(p_old) x where x.gold > 0),
  sg as (select coalesce(sum(ns.gold), 0) g from ns
    where not exists (select 1 from os where os.id = ns.id and os.level = ns.level and os.gold = ns.gold)),
  rg as (select coalesce(sum(os.gold), 0) g from os
    where not exists (select 1 from ns where ns.id = os.id and ns.level = os.level and ns.gold = os.gold)
      and not exists (select 1 from private.castle_levels(p_new) b where b.id = os.id and b.level >= os.level))
  select
    array(select (coalesce((select sum(s.c[i]) from s), 0) + case when i = 4 then (select sg.g from sg) else 0 end)::bigint
      from generate_series(1, 4) i order by i),
    array(select (coalesce((select sum(r.c[i]) from r), 0) + case when i = 4 then (select rg.g from rg) else 0 end)::bigint
      from generate_series(1, 4) i order by i)
$$;

-- Pełny czas zlecenia w toku (jak w `*_building_sanity.sql`); odcinek trwa czas poziomu ×(1 + kratki z extra_ids).
create or replace function private.queue_head_ms(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce((
    select private.build_time_ms(b.kind, private.json_int(q.o -> 'level', 1, 10))
      * (1 + coalesce((select cardinality(s.extra_ids) from private.segment_orders(p_castle) s where s.pos = 0), 0))
    from (select p_castle -> 'queue' -> 'orders' -> 0 as o) q
    join private.castle_levels(p_castle) b on b.id = private.json_int(q.o -> 'building_id', 1, 2147483647)
    where jsonb_typeof(p_castle -> 'queue' -> 'orders') = 'array'), 0)
$$;

revoke all on function private.segment_orders(jsonb) from public, anon, authenticated;
revoke all on function private.build_paid(jsonb) from public, anon, authenticated;
revoke all on function private.build_flow(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.queue_head_ms(jsonb) from public, anon, authenticated;
