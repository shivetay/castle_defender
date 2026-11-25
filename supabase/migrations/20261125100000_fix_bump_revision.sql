-- Naprawa zapisu obrony (#298).
--
-- `private.bump_revision()` działa na `castles` i `defense_layouts`. Warunek
-- `tg_table_name = 'castles' and new.map_seed <> old.map_seed` to jedno wyrażenie SQL: PL/pgSQL
-- podstawia wszystkie pola `new`/`old` przed jego obliczeniem, więc przy `defense_layouts` (bez kolumny
-- `map_seed`) każdy UPDATE kończył się błędem 42703 „record "new" has no field "map_seed"”.
-- Sprawdzenie seedu jest teraz w zagnieżdżonym IF, który czyta `new.map_seed` tylko dla zamków.
-- Zachowanie dla `castles` się nie zmienia.

create or replace function private.bump_revision()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.player_id <> old.player_id then
    raise exception 'player_id is immutable';
  end if;
  if tg_table_name = 'castles' then
    if new.map_seed <> old.map_seed then
      raise exception 'map_seed is immutable';
    end if;
  end if;
  new.revision := old.revision + 1;
  new.updated_at := now();
  return new;
end;
$$;
revoke all on function private.bump_revision() from public, anon, authenticated;
