-- #35: Pole i spichlerz produkuje żywność, więc serwer liczy je w limicie utrzymania przy starcie ataku.
--
-- `public.begin_attack` porównuje utrzymanie armii ataku z produkcją żywności zamku
-- (`private.food_production`, migracja `*_army_limits.sql`). Do tej pory żywność dawał tylko Rybak.
-- Gracz, który karmi wojsko z Pól, dostawałby `army_over_upkeep`, choć gra pozwala mu na tę armię.
-- Nowa wersja funkcji liczy to samo co Economy.rates z Research.production_percent:
--   FOOD_BASE = 20 plus Rybacy FISHER_FOOD = [40, 60, 80, 110, 140] i Pola FARM_FOOD = [60, 90, 120, 160, 200]
--   według poziomu, z premią badania G2 = 15 procent, zaokrąglone w dół.
-- Rodzaje (BuildingTypes.Kind): FISHER = 16, FARM = 28. Odczyt budynków bez zmian
-- (`private.castle_buildings`: pierwszy wpis danego id, poziom 0..5, plac budowy nic nie daje).
-- Liczby pilnuje test gry (`tests/test_attack_limits.gd`) po znacznikach w komentarzach.
--
-- Funkcja zostaje w schemacie private i woła ją tylko `service_role` (przez begin_attack); `create or
-- replace` zachowuje uprawnienia, a revoke/grant poniżej mówią to wprost.

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
      * (100 + case when jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
          and (p_castle -> 'research' -> 'done') @> '["G2"]'::jsonb then 15 else 0 end)
      / 100)::integer
$$;

revoke all on function private.food_production(jsonb) from public, anon, authenticated;
grant execute on function private.food_production(jsonb) to service_role;
