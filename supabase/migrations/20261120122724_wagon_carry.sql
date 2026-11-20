-- #235: Wóz łupowy. Nowy rodzaj jednostki (UnitTypes.Unit.WAGON = 15), który podnosi capacity łupu.
--
-- - `private.unit_carry`: Wóz unosi 50 surowców (piechota 5, konnica 10, taran 0; decyzja właścicielki,
--   TYMCZASOWE). `public.end_attack` liczy capacity z ocalałych, więc ocalały Wóz podnosi limit łupu,
--   a brak Wozu tylko go nie podnosi (atak bez wozów działa jak dotąd).
-- - `private.unit_count`: 16 rodzajów jednostek, więc `public.begin_attack` przyjmuje Wóz w armii
--   i sprawdza go z zapasem zamku atakującego jak każdą inną jednostkę (bez wozu w zamku nie ma go
--   w ataku: rekrutacja w Stajni jest w grze, a serwer widzi tylko wyszkolone oddziały z kopii zamku).
-- Liczby pilnuje test gry (`tests/test_attack_finish.gd`) po znacznikach w komentarzach.
--
-- `create or replace` zostawia uprawnienia funkcji; mimo to powtarzamy je jawnie (tylko service_role).

-- Ile surowców (suma rodzajów) unosi jedna ocalała jednostka rodzaju `unit` (UnitTypes.Unit).
-- CARRY = [5, 5, 5, 5, 5, 5, 10, 5, 5, 5, 10, 0, 5, 5, 10, 50]
create or replace function private.unit_carry(unit integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce((array[5, 5, 5, 5, 5, 5, 10, 5, 5, 5, 10, 0, 5, 5, 10, 50])[unit + 1], 0)
$$;

-- Liczba rodzajów jednostek (UnitTypes.count()). UNIT_COUNT = 16
create or replace function private.unit_count()
returns integer
language sql
immutable
set search_path = ''
as $$ select 16 $$;

revoke all on function private.unit_carry(integer) from public, anon, authenticated;
revoke all on function private.unit_count() from public, anon, authenticated;
grant execute on function private.unit_carry(integer) to service_role;
grant execute on function private.unit_count() to service_role;
