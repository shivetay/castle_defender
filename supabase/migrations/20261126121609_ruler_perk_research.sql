-- #308: perk władcy z technologii zamiast wyboru z listy (ADR 0002).
--
-- Perka władcy nie wybiera się już z listy w `castles.data -> ruler -> perk`: odblokowuje go badanie
-- (RulerPerks). Perki tworzą 4 linie z poziomami, po jednej technologii na poziom; poziom 2 (epoka II)
-- wymaga poziomu 1 (epoka I). Pierwsza technologia perkowa wybiera linię na stałe (gra blokuje pozostałe
-- linie). Stan perka (RulerPerks.Perk) to linia z poziomem:
--   LINES = [["A60", "A61"], ["O23", "O24"], ["G25", "G26"], ["U14", "U15"]]
--   LINE_PERKS = [[0, 1], [2, 6], [3, 4], [5, 7]]
-- (CONQUEROR = 0, LOOTER = 1, STEWARD = 2, THRIFTY = 3, BUILDER = 4, BELOVED = 5, STEWARD_2 = 6,
-- BELOVED_2 = 7, brak perka -1). LOOTER to poziom 2 linii Zdobywcy (Zdobywca i Łupieżca), BUILDER poziom 2
-- linii Gospodarnego (Gospodarny i Budowniczy).
--
-- Serwer liczy perk z badań w zapisie (`research.done`) jak RulerPerks.from_done, więc klient nie ustawia go
-- sam: technologie z dwóch linii dają brak perka, poziom 2 działa tylko z poziomem 1 i od epoki II zamku.
-- Zmiany:
-- - drzewko `private.tech_tree` zna 8 technologii perków (epoka, wymagania); koszt i czas jak inne
--   technologie epoki;
-- - `private.castle_ruler_perk` liczy stan perka z badań; z niego korzystają `launch_attack` (perk atakującego,
--   `attacks.attacker_ruler_perk`), `end_attack` (Łupieżca, stan 1, bez zmian), `production_max`
--   i `food_production` (Gospodarny w stanach 3 i 4);
-- - wyzwalacz `castles_check_ruler_perk` (okno 24 h i płatne zmiany, #32) i kolumna `ruler_perk_free_at`
--   znikają. `ruler_perk_paid` zostaje w budżecie złota bez zmian (rekompensata w #349);
-- - zakres `attacks.attacker_ruler_perk` rośnie do 7.
-- Liczby pilnuje test gry (`tests/test_ruler_perks.gd`) po znacznikach w komentarzach.

drop trigger castles_check_ruler_perk on public.castles;
drop function private.check_castle_ruler_perk();
alter table public.castles drop column ruler_perk_free_at;

comment on column public.castles.ruler_perk_paid is
  'Liczba płatnych zmian perka władcy z listy (#32, po 50 złota) do budżetu złota. Od #308 już nie rośnie. Zmienia tylko serwer.';

alter table public.attacks drop constraint attacks_attacker_ruler_perk_check;
alter table public.attacks add constraint attacks_attacker_ruler_perk_check
  check (attacker_ruler_perk between -1 and 7);

-- Drzewko jak w `*_army_research_goods_sanity.sql`, z technologiami perków władcy:
--   TECH_TREE = {"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "A60": [0, []], "A61": [1, ["A60"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "O23": [0, []], "O24": [1, ["O23"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [1, ["G1"]], "G6": [1, ["G4"]], "G25": [0, []], "G26": [1, ["G25"]], "U1": [0, []], "U14": [0, []], "U15": [1, ["U14"]], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}
create or replace function private.tech_tree()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "A60": [0, []], "A61": [1, ["A60"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "O23": [0, []], "O24": [1, ["O23"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [1, ["G1"]], "G6": [1, ["G4"]], "G25": [0, []], "G26": [1, ["G25"]], "U1": [0, []], "U14": [0, []], "U15": [1, ["U14"]], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}'::jsonb
$$;

-- Stan perka władcy z badań w zapisie zamku: jedna linia, kolejne poziomy od pierwszego, poziom 2 od epoki II.
create or replace function private.castle_ruler_perk(p_data jsonb)
returns smallint
language sql
immutable
set search_path = ''
as $$
  with d as (
    select case when jsonb_typeof(p_data -> 'research' -> 'done') = 'array'
      then p_data -> 'research' -> 'done' else '[]'::jsonb end as done
  ),
  l as (
    select v.perk1, v.perk2,
      d.done @> jsonb_build_array(v.code1) as has1,
      d.done @> jsonb_build_array(v.code2) as has2
    from d, (values ('A60', 'A61', 0, 1), ('O23', 'O24', 2, 6), ('G25', 'G26', 3, 4), ('U14', 'U15', 5, 7))
      as v(code1, code2, perk1, perk2)
  )
  select case
    when (select count(*) from l where l.has1 or l.has2) <> 1 then -1
    else (select case
        when l.has1 and l.has2 and private.castle_age(p_data) >= 1 then l.perk2
        when l.has1 then l.perk1
        else -1 end
      from l where l.has1 or l.has2)
  end::smallint
$$;

revoke all on function private.castle_ruler_perk(jsonb) from public, anon, authenticated;
grant execute on function private.castle_ruler_perk(jsonb) to service_role;

-- Górna granica produkcji jak w `*_doctrine_levels.sql`, z Gospodarnym na obu poziomach linii:
--   THRIFTY = 3, BUILDER = 4, THRIFTY_PRODUCTION_BONUS = 10
create or replace function private.production_max(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with b as (select * from private.buildings_max(p_old, p_new)),
  raw as (
    select r, (array[20, 20, 20, 0])[r + 1] + coalesce((select sum((p.v -> 1 ->> (b.level - 1))::bigint)
        from b join jsonb_each('{"4": [0, [60, 90, 120, 160, 200]], "16": [2, [40, 60, 80, 110, 140]], "28": [2, [60, 90, 120, 160, 200]], "30": [1, [40, 60, 80, 110, 140]]}'::jsonb) p(k, v)
          on p.k = b.kind::text and (p.v ->> 0)::integer = r), 0) as amount
    from generate_series(0, 3) r
  ), bonus as (
    select r, coalesce((select sum((t.v ->> 1)::integer
          + 5 * (greatest(private.tech_level(p_old, t.k), private.tech_level(p_new, t.k)) - 1))
        from jsonb_each('{"G1": [0, 20], "G2": [2, 15]}'::jsonb) t(k, v)
        where (t.v ->> 0)::integer = r
          and greatest(private.tech_level(p_old, t.k), private.tech_level(p_new, t.k)) >= 1), 0)
      + case when private.castle_ruler_perk(p_old) in (3, 4) or private.castle_ruler_perk(p_new) in (3, 4)
          then 10 else 0 end as percent
    from generate_series(0, 3) r
  )
  select array(
    select raw.amount * (100 + bonus.percent) / 100
      -- HUNTER_FOOD = 2 na cykl, 6 cykli na godzinę na poziomie 1 razy LEVEL_PERCENT = [100, 150, 200, 275, 350]
      + case when raw.r = 2 then coalesce((select sum(2 * (6 * (array[100, 150, 200, 275, 350])[b.level] / 100))
          from b where b.kind = 6), 0) else 0 end
    from raw join bonus on bonus.r = raw.r
    order by raw.r)::bigint[]
$$;

-- Limit utrzymania jak w `*_doctrine_levels.sql`, z Gospodarnym na obu poziomach linii.
create or replace function private.food_production(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((20 + coalesce((select sum(case b.kind
          when 16 then (array[40, 60, 80, 110, 140])[b.level]
          when 28 then (array[60, 90, 120, 160, 200])[b.level]
          else 0 end)
        from private.castle_buildings(p_castle) b where b.kind in (16, 28) and b.level >= 1), 0))
      * (100 + case when private.tech_level(p_castle, 'G2') >= 1
          then 15 + 5 * (private.tech_level(p_castle, 'G2') - 1) else 0 end
        + case when private.castle_ruler_perk(p_castle) in (3, 4) then 10 else 0 end)
      / 100)::integer
$$;

revoke all on function private.production_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.food_production(jsonb) from public, anon, authenticated;
grant execute on function private.food_production(jsonb) to service_role;
