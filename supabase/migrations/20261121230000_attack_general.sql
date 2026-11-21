-- #31: generał ataku w ataku na gracza.
--
-- Generał wpływa na bitwę (perki działają na całą armię), więc atakujący i obrońca w powtórce (#29) muszą liczyć bitwę
-- z tym samym generałem. Klient przy zatwierdzeniu planu (`launch_attack`) podaje tylko rodzaj generała
-- (0..2: Wódz drużyny, Łowczy, Budowniczy kopców). Poziom i perk serwer bierze z zamku atakującego na
-- serwerze (`castles.data -> generals -> roster`), jak badania, a nie z żądania, zapisuje w
-- `attacks.attacker_general` i oddaje klientowi. Powtórka oddaje tego samego generała.
--
-- Komendant obrony nie potrzebuje zmian: jest w kopii obrony (`defense_snapshot -> commander`), a jego
-- poziom i perk w kopii zamku obrońcy (`castle_snapshot -> generals`), obie z chwili startu.
--
-- Zakresy jak w grze (Generals): rodzaj 0..2, poziom 1..3 (MVP), perk dodatkowy 0..1 (Szybki marsz, Ostrożny) tylko na poziomie 3,
-- inaczej -1. Zły albo brakujący wpis w zamku: poziom 1 bez perka; brak generała tego rodzaju: bez
-- generała (null). Stara `launch_attack(uuid, uuid, jsonb)` zostaje dla wdrożonej Edge Function sprzed #31.

alter table public.attacks
  add column attacker_general jsonb
    check (attacker_general is null or (jsonb_typeof(attacker_general) = 'object'
      and pg_column_size(attacker_general) <= 256));

comment on column public.attacks.attacker_general is
  'Generał ataku {kind, level, perk} z zamku atakującego na serwerze w chwili zatwierdzenia planu (#31). Tylko dla serwera.';

-- Generał rodzaju `p_kind` z danych zamku: pierwszy pasujący wpis listy, poziom i perk w zakresach gry.
create function private.castle_general(p_data jsonb, p_kind integer)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with g as (
    select e.v
    from jsonb_array_elements(case when jsonb_typeof(p_data -> 'generals' -> 'roster') = 'array'
        then p_data -> 'generals' -> 'roster' else '[]'::jsonb end) with ordinality as e(v, ord)
    where jsonb_typeof(e.v) = 'object' and private.json_int(e.v -> 'kind', 0, 2) = p_kind
    order by e.ord
    limit 1
  ), l as (
    select g.v, coalesce(private.json_int(g.v -> 'level', 1, 3), 1)::integer as level from g
  )
  select jsonb_build_object('kind', p_kind, 'level', l.level,
    'perk', case when l.level >= 3 then coalesce(private.json_int(l.v -> 'perk', 0, 1), -1)::integer else -1 end)
  from l
$$;

revoke all on function private.castle_general(jsonb, integer) from public, anon, authenticated;
grant execute on function private.castle_general(jsonb, integer) to service_role;

-- Zatwierdzenie planu (#28, #29) z generałem ataku (#31). `p_general`: rodzaj generała albo null (bez
-- generała). Pierwsze wywołanie zapisuje plan, badania i generała; ponowienie oddaje to samo.
create function public.launch_attack(p_attacker uuid, p_attack uuid, p_plan jsonb, p_general integer)
returns table (
  castle jsonb,
  defense jsonb,
  plan jsonb,
  techs text[],
  general jsonb
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_data jsonb;
  v_done jsonb;
begin
  if p_general is not null and (p_general < 0 or p_general > 2) then
    raise exception 'bad_general' using errcode = 'P0001';
  end if;
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
    select c.data into v_data from public.castles c where c.player_id = p_attacker;
    v_done := v_data -> 'research' -> 'done';
    a.attacker_techs := array(
      select code from unnest(array['A1', 'A2', 'A7']) as code
      where jsonb_typeof(v_done) = 'array' and v_done @> jsonb_build_array(code));
    a.attacker_general := case when p_general is null then null else private.castle_general(v_data, p_general) end;
    update public.attacks t set launched_at = now(), orders = a.orders, attacker_techs = a.attacker_techs,
      attacker_general = a.attacker_general
    where t.id = a.id;
  end if;
  return query select a.castle_snapshot - 'scout', a.defense_snapshot, a.orders,
    coalesce(a.attacker_techs, '{}'), a.attacker_general;
end;
$$;

comment on function public.launch_attack(uuid, uuid, jsonb, integer) is
  'Atak na gracza po zatwierdzeniu planu (#28): pełne kopie zamku i obrony z chwili startu; zapisuje plan, badania i generała ataku z zamku atakującego (#29, #31). Tylko dla service_role (Edge Function launch_attack).';
revoke all on function public.launch_attack(uuid, uuid, jsonb, integer) from public, anon, authenticated;
grant execute on function public.launch_attack(uuid, uuid, jsonb, integer) to service_role;

-- Powtórka obrony (#29) z generałem ataku (#31). Typ wyniku się zmienia, więc funkcja powstaje od nowa;
-- wdrożona Edge Function sprzed #31 woła ją tak samo i nową kolumnę pomija.
drop function public.attack_replay(uuid, uuid);

create function public.attack_replay(p_player uuid, p_attack uuid)
returns table (
  map_seed bigint,
  battle_seed bigint,
  castle jsonb,
  defense jsonb,
  army jsonb,
  plan jsonb,
  techs text[],
  general jsonb,
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
    a.attacker_army, a.orders, a.attacker_techs, a.attacker_general, a.result, a.loot, a.finished_at;
end;
$$;

comment on function public.attack_replay(uuid, uuid) is
  'Dane do powtórki zakończonej obrony (#29): kopie z chwili startu, armia, plan, badania i generał atakującego (#31). Tylko obrońca; tylko dla service_role (Edge Function attack_replay).';
revoke all on function public.attack_replay(uuid, uuid) from public, anon, authenticated;
grant execute on function public.attack_replay(uuid, uuid) to service_role;
