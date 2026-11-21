-- #29: powtórka bitwy u obrońcy.
--
-- Powtórka nie jest wideo: obrońca liczy bitwę jeszcze raz z tych samych danych, z których liczył ją
-- atakujący, więc widzi ten sam przebieg. Do kopii z chwili startu (zamek, obrona, armia, seedy)
-- brakowało dwóch rzeczy, które zna tylko atakujący:
-- - plan ataku (rozkazy oddziałów). Zapisuje go `launch_attack` przy zatwierdzeniu, w `attacks.orders`
--   (kolumna była na to od początku). Pierwszy zapis wygrywa: ponowienie nie zmienia planu, a klient
--   liczy bitwę z planu, który oddał serwer.
-- - badania atakującego, które działają w bitwie (A1, A2, A7). Serwer bierze je z zamku atakującego
--   na serwerze (`castles.data -> research -> done`), a nie z żądania, i też oddaje je klientowi.
--
-- `public.attack_replay` oddaje obrońcy dane jego zakończonej obrony. Atakujący i obcy gracz ich nie
-- dostaną (kopia zamku to pełny stan gry obrońcy). Obie funkcje woła tylko service_role (Edge Functions).

alter table public.attacks
  add column attacker_techs text[]
    check (attacker_techs is null or (cardinality(attacker_techs) <= 3
      and attacker_techs <@ array['A1', 'A2', 'A7']::text[])),
  add constraint attacks_orders_size check (pg_column_size(orders) <= 8192);

comment on column public.attacks.attacker_techs is
  'Badania atakującego działające w bitwie (A1, A2, A7) z jego zamku na serwerze w chwili zatwierdzenia planu (#29). Tylko dla serwera.';
comment on column public.attacks.orders is
  'Plan ataku (AttackPlan.to_dict()["orders"]) zapisany przy zatwierdzeniu (launch_attack, #29); z niego powtórka odtwarza bitwę.';

-- Plan z klienta: tablica rozkazów, po jednym na oddział armii ze startu (oddziały 1..n bez powtórek),
-- same liczby całkowite w zakresach gry. Klucze spoza listy, złe typy i za duże wartości → `bad_plan`.
-- Zwraca plan bez zmian (tylko sprawdza), żeby nie zgubić niczego, co klient policzył.
create function private.check_plan(p_plan jsonb, p_squads integer)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  e jsonb;
  w jsonb;
  k text;
  v_seen integer[] := '{}';
  v_squad integer;
begin
  if p_plan is null or jsonb_typeof(p_plan) <> 'array' or jsonb_array_length(p_plan) < 1
      or jsonb_array_length(p_plan) > p_squads or pg_column_size(p_plan) > 8192 then
    raise exception 'bad_plan' using errcode = 'P0001';
  end if;
  for e in select value from jsonb_array_elements(p_plan) loop
    if jsonb_typeof(e) <> 'object' then
      raise exception 'bad_plan' using errcode = 'P0001';
    end if;
    for k in select jsonb_object_keys(e) loop
      if k not in ('squad', 'manoeuvre', 'target', 'waypoints', 'start', 'start_value', 'retreat', 'flank_left') then
        raise exception 'bad_plan' using errcode = 'P0001';
      end if;
    end loop;
    if not (private.json_int(e -> 'squad', 1, p_squads) is not null
        and private.json_int(e -> 'manoeuvre', 0, 6) is not null
        and private.json_int(e -> 'start', 0, 2) is not null
        and private.json_int(e -> 'start_value', 0, 600) is not null
        and private.json_int(e -> 'retreat', 0, 100) is not null
        and jsonb_typeof(e -> 'flank_left') = 'boolean'
        and private.plan_cell(e -> 'target', -1)
        and jsonb_typeof(e -> 'waypoints') = 'array' and jsonb_array_length(e -> 'waypoints') <= 3) then
      raise exception 'bad_plan' using errcode = 'P0001';
    end if;
    for w in select value from jsonb_array_elements(e -> 'waypoints') loop
      if not private.plan_cell(w, 0) then
        raise exception 'bad_plan' using errcode = 'P0001';
      end if;
    end loop;
    v_squad := (e ->> 'squad')::integer;
    if v_squad = any (v_seen) then
      raise exception 'bad_plan' using errcode = 'P0001';
    end if;
    v_seen := v_seen || v_squad;
  end loop;
  return p_plan;
end;
$$;

-- Kratka [x, y] na mapie 64×64; z `lo` = -1 także „bez celu” [-1, -1].
create function private.plan_cell(p jsonb, lo integer)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_typeof(p) = 'array' and jsonb_array_length(p) = 2
    and private.json_int(p -> 0, lo, 63) is not null and private.json_int(p -> 1, lo, 63) is not null
    and ((p ->> 0)::numeric >= 0) = ((p ->> 1)::numeric >= 0), false)
$$;

revoke all on function private.check_plan(jsonb, integer), private.plan_cell(jsonb, integer)
  from public, anon, authenticated;
grant execute on function private.check_plan(jsonb, integer), private.plan_cell(jsonb, integer) to service_role;

-- Zatwierdzenie planu (#28) z planem (#29). Przy pierwszym wywołaniu zapisuje plan, badania atakującego
-- z jego zamku na serwerze i chwilę zatwierdzenia; ponowienie zwraca to samo, z zapisanym planem.
drop function public.launch_attack(uuid, uuid);
create function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb)
returns table (
  castle jsonb,
  defense jsonb,
  plan jsonb,
  techs text[]
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_done jsonb;
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
    a.orders := private.check_plan(p_plan, jsonb_array_length(a.attacker_army));
    select c.data -> 'research' -> 'done' into v_done from public.castles c where c.player_id = p_attacker;
    a.attacker_techs := array(
      select code from unnest(array['A1', 'A2', 'A7']) as code
      where jsonb_typeof(v_done) = 'array' and v_done @> jsonb_build_array(code));
    update public.attacks t set launched_at = now(), orders = a.orders, attacker_techs = a.attacker_techs
    where t.id = a.id;
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot, a.orders,
    coalesce(a.attacker_techs, '{}');
end;
$$;

comment on function public.launch_attack(uuid, uuid, jsonb) is
  'Atak na gracza po zatwierdzeniu planu (#28): pełne kopie zamku i obrony z chwili startu; zapisuje plan i badania atakującego do powtórki (#29). Tylko dla service_role (Edge Function launch_attack).';
revoke all on function public.launch_attack(uuid, uuid, jsonb) from public, anon, authenticated;
grant execute on function public.launch_attack(uuid, uuid, jsonb) to service_role;

-- Powtórka obrony (#29): tylko obrońca i tylko zakończony atak z planem zapisanym przy zatwierdzeniu
-- (ataki sprzed #29 go nie mają: `replay_missing`). Bez danych atakującego poza jego armią i planem.
create function public.attack_replay(p_player uuid, p_attack uuid)
returns table (
  map_seed bigint,
  battle_seed bigint,
  castle jsonb,
  defense jsonb,
  army jsonb,
  plan jsonb,
  techs text[],
  result jsonb,
  loot integer[],
  finished_at timestamptz
)
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.defender_id = p_player and t.status = 'finished';
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;
  if a.attacker_techs is null or a.castle_snapshot is null or a.defense_snapshot is null then
    raise exception 'replay_missing' using errcode = 'P0001';
  end if;
  return query select a.map_seed, a.battle_seed, a.castle_snapshot - 'scout', a.defense_snapshot,
    a.attacker_army, a.orders, a.attacker_techs, a.result, a.loot, a.finished_at;
end;
$$;

comment on function public.attack_replay(uuid, uuid) is
  'Dane do powtórki zakończonej obrony (#29): kopie z chwili startu, armia, plan i badania atakującego. Tylko obrońca; tylko dla service_role (Edge Function attack_replay).';
revoke all on function public.attack_replay(uuid, uuid) from public, anon, authenticated;
grant execute on function public.attack_replay(uuid, uuid) to service_role;
