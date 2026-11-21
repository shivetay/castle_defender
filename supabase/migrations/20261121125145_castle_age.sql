-- Epoka gracza z zamku (#34): `players.age` (ranking w epoce, dobór przeciwnika ±1 epoka) liczy
-- serwer z zapisu zamku, a nie klient. Klient dalej nie ma uprawnień do tej kolumny.
--
-- W grze (Ages, BuildGrid.age) epoka zamku to epoka Dworu: poziomy liczą się narastająco, 1–5 to
-- epoka I, a 6–10 epoka II. Przejście I → II to przebudowa Dworu na poziom 6, która wymaga
-- zbadanych technologii kluczowych O1, G1 i A7 (Ages.TRANSITION_TECHS). Serwer uznaje epokę II
-- tylko wtedy, gdy zapis ma oba: Dwór na poziomie 6+ i te trzy technologie w `research.done`.
--
-- Epoka tylko rośnie (`greatest`): w grze nie da się cofnąć Dworu, a zmodyfikowany zapis z niższym
-- Dworem nie przeniesie gracza do słabszej epoki w rankingu i doborze przeciwnika.
-- MVP ma epoki I i II, więc serwer daje najwyżej epokę II (1).

-- Epoka zamku z zapisu: 1 przy Dworze (rodzaj 5, najniższe id jak BuildGrid.manor_id) na poziomie
-- 6..10 i zbadanych O1, G1, A7, inaczej 0. Poziom Dworu bez obcinania do 5 (inaczej niż
-- private.castle_buildings, które liczy premie).
create function private.castle_age(p_castle jsonb)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select case
    when coalesce((
        select least(greatest(private.json_int(x.e -> 2, -2147483648, 2147483647), 0), 10)
        from jsonb_array_elements(
            case when jsonb_typeof(p_castle -> 'grid' -> 'buildings') = 'array'
              then p_castle -> 'grid' -> 'buildings' else '[]'::jsonb end) as x(e)
        where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end
          and private.json_int(x.e -> 1, 0, 2147483647) = 5
          and private.json_int(x.e -> 0, 1, 2147483647) is not null
          and private.json_int(x.e -> 2, -2147483648, 2147483647) is not null
        order by private.json_int(x.e -> 0, 1, 2147483647)
        limit 1), 0) >= 6
      and jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
      and (p_castle -> 'research' -> 'done') @> '["O1", "G1", "A7"]'::jsonb
    then 1::smallint
    else 0::smallint
  end
$$;

revoke all on function private.castle_age(jsonb) from public, anon, authenticated;

-- Po zapisie zamku podnosi epokę gracza do epoki z zapisu. SECURITY DEFINER, bo gracz zapisuje
-- zamek jako `authenticated`, a ta rola nie ma prawa zmieniać `players.age`. Zmienia tylko wiersz
-- właściciela zapisanego zamku (new.player_id, którego RLS i bump_revision nie pozwalają zmienić).
create function private.sync_player_age()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_age smallint := private.castle_age(new.data);
begin
  if v_age > 0 then
    update public.players set age = v_age
    where id = new.player_id and age < v_age;
  end if;
  return null;
end;
$$;

revoke all on function private.sync_player_age() from public, anon, authenticated;

create trigger castles_sync_player_age
  after insert or update of data on public.castles
  for each row execute function private.sync_player_age();

-- Zamki zapisane przed tą migracją: epoka z obecnego zapisu.
update public.players p set age = private.castle_age(c.data)
from public.castles c
where c.player_id = p.id and private.castle_age(c.data) > p.age;
