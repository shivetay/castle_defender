-- #99: odbudowa zamku obrońcy po ataku PvP. Bitwa idzie na kopii zamku, więc atak niczego w zamku
-- obrońcy nie zmienia; serwer zapisuje tylko, które budynki padły (`attacks.destroyed`). Obrońca czyta
-- swoje obrony (RLS z init_pvp_schema: tylko ataki, w których brał udział) i widzi te budynki jako
-- ruiny, które same się odbudowują (Ruins w grze). W ruinie Chata drwala i Rybak produkują mniej.
--
-- `public.record_destroyed` (woła Edge Function `finish_attack` po `end_attack`):
-- - id atakującego idzie z tokenu (Edge Function), nigdy z treści żądania;
-- - tylko własny, zakończony atak na gracza; dla zamku-bota nic nie zapisuje (bot powstaje z seeda);
-- - pierwszy zapis wygrywa: ponowienie zwraca zapisaną listę i niczego nie zmienia;
-- - lista: najwyżej MAX_DESTROYED = 200 różnych id, każde to gotowy budynek (poziom co najmniej 1)
--   z kopii zamku z chwili startu (`castle_snapshot`), bez wału i palisady (WALL_KINDS = [0, 1],
--   BuildingTypes.is_wall), jak BattleResult;
-- - najwyżej tyle budynków, ile wynika z procentu zniszczeń przyjętego przez `end_attack`:
--   liczba × 100 / budynki z kopii nie może przekroczyć procentu, więc atakujący nie „zburzy” więcej,
--   niż zgłosił w wyniku. Pełna weryfikacja powtórką na serwerze to #29;
-- - zła lista jest odrzucana w całości (nic się nie zapisuje), a wynik ataku i łup zostają.
-- Liczby w tej migracji pilnuje test gry (`tests/test_ruins.gd`) po znacznikach w komentarzach.
--
-- Funkcja czyta i pisze cudze wiersze, więc woła ją wyłącznie `service_role`. Nowa kolumna to dane gry
-- (id budynków), bez danych osobowych; kasuje się z kontem razem z atakiem (on delete cascade).

alter table public.attacks
  add column destroyed integer[]
    check (destroyed is null or (cardinality(destroyed) <= 200 and 0 < all (destroyed)));

-- odczyt jest kolumnowy (migracja attack_snapshots): dopisz nową kolumnę; RLS dalej pokazuje graczowi
-- tylko ataki, w których brał udział, a zapis ma tylko service_role
grant select (destroyed) on public.attacks to authenticated;

comment on column public.attacks.destroyed is
  'Id budynków obrońcy zniszczonych w ataku (#99); z nich obrońca odbudowuje zamek. Zapisuje tylko record_destroyed (service_role).';

create function public.record_destroyed(p_attacker uuid, p_attack uuid, p_destroyed jsonb)
returns integer[]
language plpgsql
volatile
security invoker
set search_path = ''
as $$
declare
  a public.attacks%rowtype;
  v_ids integer[] := '{}';
  v_total bigint;
  v_percent bigint;
  e jsonb;
  x bigint;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.status <> 'finished' then
    raise exception 'attack_not_finished' using errcode = 'P0001';
  end if;
  if a.defender_id is null then
    return null;
  end if;
  if a.destroyed is not null then
    return a.destroyed;
  end if;

  -- MAX_DESTROYED = 200
  if p_destroyed is null or jsonb_typeof(p_destroyed) <> 'array' or jsonb_array_length(p_destroyed) > 200 then
    raise exception 'bad_destroyed' using errcode = 'P0001';
  end if;
  for e in select y.value from jsonb_array_elements(p_destroyed) as y loop
    x := private.json_int(e, 1, 2147483647);
    if x is null or x::integer = any (v_ids) then
      raise exception 'bad_destroyed' using errcode = 'P0001';
    end if;
    v_ids := v_ids || x::integer;
  end loop;

  -- budynki z kopii zamku jak w BattleResult: gotowe, bez wału (0) i palisady (1)
  if exists (
    select 1 from unnest(v_ids) as d(id)
    where not exists (
      select 1 from private.castle_buildings(a.castle_snapshot) b
      where b.id = d.id and b.level >= 1 and b.kind not in (0, 1))) then
    raise exception 'bad_destroyed' using errcode = 'P0001';
  end if;
  select count(*) into v_total from private.castle_buildings(a.castle_snapshot) b
  where b.level >= 1 and b.kind not in (0, 1);
  v_percent := coalesce(private.json_int(a.result -> 'percent', 0, 100), 0);
  -- dzielenie całkowite jak BattleResult.of
  if cardinality(v_ids) > 0 and cardinality(v_ids)::bigint * 100 / greatest(v_total, 1) > v_percent then
    raise exception 'destroyed_too_many' using errcode = 'P0001';
  end if;

  update public.attacks t set destroyed = v_ids where t.id = a.id;
  return v_ids;
end;
$$;

comment on function public.record_destroyed(uuid, uuid, jsonb) is
  'Zniszczone budynki obrońcy po ataku (#99): tylko własny zakończony atak na gracza, gotowe budynki z kopii zamku bez umocnień, nie więcej niż procent zniszczeń; pierwszy zapis wygrywa. Tylko dla service_role (Edge Function finish_attack).';

revoke all on function public.record_destroyed(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.record_destroyed(uuid, uuid, jsonb) to service_role;

-- odczyt ostatnich obron gracza (DefenseLog): defender_id + finished_at
create index attacks_defender_finished_idx on public.attacks (defender_id, finished_at desc)
  where defender_id is not null and status = 'finished';
