-- #371: ulepszanie całego odcinka wału albo palisady (decyzja właścicielki po review PR 414).
--
-- Odcinek 2 albo 3 kratek zostaje w grze jednym odcinkiem także po ukończeniu (BuildGrid.segments). Ulepszenie
-- dowolnej kratki to jedno zlecenie całego odcinka: `building_id` to pierwsza kratka, `extra_ids` pozostałe,
-- materiały i czas ×długość, bez dopłaty w złocie (BuildConfig.segment_cost dolicza SEGMENT_GOLD tylko przy
-- postawieniu, na poziomie 1). Dotąd `private.segment_orders` (`*_wall_segments.sql`) brała `extra_ids` tylko
-- z zleceń poziomu 1, więc serwer nie widziałby wydatku i zwrotu za dodatkowe kratki ulepszenia. Teraz:
-- - `extra_ids` liczą się dla zleceń wału i palisady na każdym poziomie (ten sam rodzaj, istniejące, bez
--   powtórzeń, najwyżej 2), więc `private.build_paid` i `private.build_flow` widzą koszt ×N, a
--   `private.queue_head_ms` czas ×N (obie funkcje biorą kratki z `segment_orders`, więc się nie zmieniają);
-- - dopłata w złocie tylko przy postawieniu (poziom 1):
--   SEGMENT_GOLD = [0, 2, 5]
-- Koszt każdego poziomu każdej kratki serwer i tak liczy osobno z siatki, więc ulepszenie odcinka nie daje
-- poziomów taniej. Grupy odcinków w siatce (`grid.segments`) serwer nie czyta: nie zmieniają kosztu ani bitwy.
-- Nowych danych o graczu nie ma. Testy: pgTAP `supabase/tests/database/wall_segments_test.sql`,
-- gra `tests/test_wall_segments.gd` (znacznik SEGMENT_GOLD i warunek poziomu 1).

create or replace function private.segment_orders(p_castle jsonb)
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
    where q.level is not null and b.kind in (0, 1)
  )
  select s.pos, s.id, s.kind, s.level, s.extra_ids,
    -- SEGMENT_GOLD = [0, 2, 5], tylko przy postawieniu
    case when s.level = 1 then (array[0, 2, 5])[cardinality(s.extra_ids) + 1] else 0 end::bigint
  from s
$$;

revoke all on function private.segment_orders(jsonb) from public, anon, authenticated;
