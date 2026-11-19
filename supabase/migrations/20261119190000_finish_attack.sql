-- #25: bezpieczny przebieg ataku po stronie serwera. Start ataku blokuje cel, koniec ataku zapisuje
-- wynik, łup i tarczę obrońcy, a serwer sprawdza limity.
--
-- `public.begin_attack` (woła Edge Function `start_attack`):
-- - id atakującego idzie z tokenu (Edge Function), nigdy z treści żądania;
-- - najwyżej START_LIMIT = 10 startów na 10 minut na gracza; gracz ma naraz najwyżej jeden atak
--   w toku, a nowy start porzuca poprzedni (bez łupu);
-- - armia: najwyżej tyle oddziałów, ile pozwala epoka atakującego (AttackPlan.MAX_SQUADS_BY_AGE),
--   w oddziale 1..10 jednostek (RecruitmentConfig.SQUAD_SIZE), i nie więcej jednostek danego rodzaju,
--   niż ma zamek atakującego na serwerze (`castles.data.recruitment.squads`);
-- - cel-gracz: ma zamek z nazwą, nie ma tarczy, epoka ±1, ranking ±100, atakujący nie zaczął ataku
--   na niego w ostatnich 24 godzinach (te same warunki co `match_targets`, #24) i nikt inny go teraz
--   nie atakuje. Wiersze obu graczy są blokowane w stałej kolejności (bez zakleszczeń), a unikalny
--   indeks na atakach w toku to druga linia obrony;
-- - atak w toku wygasa po ATTACK_TIMEOUT = 10 minutach (bitwa trwa najwyżej 180 s) i zwalnia cel;
-- - zwraca seed terenu, seed bitwy (losuje go Edge Function) i kopie zamku oraz obrony obrońcy,
--   z których klient liczy bitwę (pułapki też, bo bez nich symulacja dałaby inny wynik; pełna
--   weryfikacja powtórką na serwerze to #29).
--
-- `public.end_attack` (woła Edge Function `finish_attack`):
-- - tylko atak w toku, należący do wołającego, przed upływem ATTACK_TIMEOUT; drugi raz zwraca
--   zapisany wynik i niczego nie zmienia (idempotentne ponowienie);
-- - wynik: wygrana, procent 0..100 i 3 gwiazdki zgodne z procentem i wygraną (BattleResult, #99);
-- - ocalali: na każdy oddział z `attacker_army` liczba 0..jego liczebność;
-- - łup (#99): na każdy surowiec najwyżej niechroniona część zapasów obrońcy (z kopii zamku z chwili
--   startu; dla zamku-bota skarbiec z BattleResult.stash) × LOOT_PERCENT × procent łupu; po przegranej 0;
-- - capacity łupu: suma łupu najwyżej tyle, ile uniosą ocaleli (CARRY na jednostkę, `private.unit_carry`),
--   więc więcej jednostek wracających z grabieży daje wyższy limit. Wóz (#235) dopisze swój wpis
--   w nowej migracji z `private.unit_carry`;
-- - zawyżony wynik albo łup jest odrzucany (nie przycinany po cichu) i nic się nie zapisuje;
-- - tarcza obrońcy-gracza: SHIELD_PERCENT = 30 procent zniszczeń daje SHIELD_HOURS = 8 godzin
--   (decyzja właścicielki); istniejąca dłuższa tarcza się nie skraca.
-- Liczby w tej migracji pilnuje test gry (`tests/test_attack_finish.gd`) po znacznikach w komentarzach.
--
-- Obie funkcje czytają i piszą cudze wiersze, więc woła je wyłącznie `service_role`.

-- ---------------------------------------------------------------------------------------------
-- Pomocnicze (schemat private, tylko dla serwera)
-- ---------------------------------------------------------------------------------------------

-- Liczba całkowita z JSON w zakresie [lo, hi] albo null (zły typ, ułamek, poza zakresem).
create function private.json_int(j jsonb, lo bigint, hi bigint)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
  v numeric;
begin
  if j is null or jsonb_typeof(j) <> 'number' then
    return null;
  end if;
  v := (j #>> '{}')::numeric;
  if v <> trunc(v) or v < lo or v > hi then
    return null;
  end if;
  return v::bigint;
end;
$$;

-- Ile surowców (suma rodzajów) unosi jedna ocalała jednostka rodzaju `unit` (UnitTypes.Unit).
-- Piechota 5, konnica 10, taran 0 (decyzja właścicielki, TYMCZASOWE).
-- CARRY = [5, 5, 5, 5, 5, 5, 10, 5, 5, 5, 10, 0, 5, 5, 10]
create function private.unit_carry(unit integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce((array[5, 5, 5, 5, 5, 5, 10, 5, 5, 5, 10, 0, 5, 5, 10])[unit + 1], 0)
$$;

-- Liczba rodzajów jednostek (UnitTypes.count()). UNIT_COUNT = 15
create function private.unit_count()
returns integer
language sql
immutable
set search_path = ''
as $$ select 15 $$;

revoke all on function private.json_int(jsonb, bigint, bigint) from public, anon, authenticated;
revoke all on function private.unit_carry(integer) from public, anon, authenticated;
revoke all on function private.unit_count() from public, anon, authenticated;
grant execute on function private.json_int(jsonb, bigint, bigint) to service_role;
grant execute on function private.unit_carry(integer) to service_role;
grant execute on function private.unit_count() to service_role;

-- Jeden atak w toku na obrońcę naraz (druga linia obrony za blokadą w begin_attack).
create unique index attacks_one_started_per_defender on public.attacks (defender_id)
  where status = 'started' and defender_id is not null;
-- sprzątanie wygasłych ataków w toku
create index attacks_started_idx on public.attacks (started_at) where status = 'started';

-- ---------------------------------------------------------------------------------------------
-- Start ataku
-- ---------------------------------------------------------------------------------------------

create function public.begin_attack(p_attacker uuid, p_defender uuid, p_bot smallint, p_army jsonb,
  p_battle_seed bigint)
returns table (
  attack_id uuid,
  map_seed bigint,
  battle_seed bigint,
  castle jsonb,
  defense jsonb
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_age smallint;
  v_rating integer;
  v_own jsonb;
  d_age smallint;
  d_rating integer;
  v_seed bigint;
  v_castle jsonb;
  v_defense jsonb;
  v_id uuid;
  e jsonb;
  u bigint;
  n bigint;
  want integer[];
  have integer[];
begin
  if p_attacker is null or (p_defender is null) = (p_bot is null) then
    raise exception 'bad_target' using errcode = 'P0001';
  end if;
  if p_defender = p_attacker then
    raise exception 'self_attack' using errcode = 'P0001';
  end if;
  if p_battle_seed is null or p_battle_seed < 0 or p_battle_seed > 2147483647 then
    raise exception 'bad_seed' using errcode = 'P0001';
  end if;

  -- blokada wierszy graczy w stałej kolejności: równoległe starty tego samego atakującego albo na
  -- tego samego obrońcę idą po kolei, a wzajemny atak dwóch graczy się nie zakleszczy
  perform 1 from public.players p
  where p.id = p_attacker or p.id = p_defender
  order by p.id
  for update;

  select p.age, p.rating into v_age, v_rating from public.players p where p.id = p_attacker;
  if not found then
    raise exception 'attacker_not_found' using errcode = 'P0001';
  end if;
  select c.data into v_own from public.castles c where c.player_id = p_attacker;
  if not found then
    raise exception 'attacker_no_castle' using errcode = 'P0001';
  end if;

  -- limit sprawdzany przed zapisem; START_LIMIT = 10
  if (select count(*) from public.attacks a
      where a.attacker_id = p_attacker and a.started_at > now() - interval '10 minutes') >= 10 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  -- armia: [[rodzaj, liczba], ...]; MAX_SQUADS_BY_AGE = [3, 4, 5, 6, 7, 8], SQUAD_SIZE = 10
  if p_army is null or jsonb_typeof(p_army) <> 'array' or jsonb_array_length(p_army) < 1
      or jsonb_array_length(p_army) > (array[3, 4, 5, 6, 7, 8])[least(greatest(v_age, 0), 5) + 1] then
    raise exception 'bad_army' using errcode = 'P0001';
  end if;
  want := array_fill(0, array[private.unit_count()]);
  have := array_fill(0, array[private.unit_count()]);
  for e in select x.value from jsonb_array_elements(p_army) as x loop
    if jsonb_typeof(e) <> 'array' or jsonb_array_length(e) <> 2 then
      raise exception 'bad_army' using errcode = 'P0001';
    end if;
    u := private.json_int(e -> 0, 0, private.unit_count() - 1);
    n := private.json_int(e -> 1, 1, 10);
    if u is null or n is null then
      raise exception 'bad_army' using errcode = 'P0001';
    end if;
    want[u + 1] := want[u + 1] + n;
  end loop;
  -- oddziały w zapisie zamku: [id, rodzaj, liczba]; złe wpisy się nie liczą
  for e in select x.value from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'recruitment' -> 'squads') = 'array'
        then v_own -> 'recruitment' -> 'squads' else '[]'::jsonb end) as x loop
    if jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 3 then
      u := private.json_int(e -> 1, 0, private.unit_count() - 1);
      n := private.json_int(e -> 2, 0, 10);
      if u is not null and n is not null then
        have[u + 1] := have[u + 1] + n;
      end if;
    end if;
  end loop;
  for i in 1 .. private.unit_count() loop
    if want[i] > have[i] then
      raise exception 'army_not_owned' using errcode = 'P0001';
    end if;
  end loop;

  -- wygasłe ataki w toku zwalniają cele (ATTACK_TIMEOUT = 10 minut), a nowy start atakującego
  -- porzuca jego poprzedni atak
  update public.attacks a set status = 'abandoned'
  where a.status = 'started'
    and (a.started_at < now() - interval '10 minutes' or a.attacker_id = p_attacker);

  if p_bot is not null then
    select b.map_seed into v_seed from public.bot_castles b where b.idx = p_bot;
    if not found then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
  else
    select p.age, p.rating into d_age, d_rating from public.players p where p.id = p_defender;
    select c.map_seed, c.data into v_seed, v_castle from public.castles c
    where c.player_id = p_defender
      and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0;
    if d_age is null or v_seed is null then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.shields s where s.player_id = p_defender and s.until > now()) then
      raise exception 'target_shielded' using errcode = 'P0001';
    end if;
    if abs(d_age - v_age) > 1 or abs(d_rating - v_rating) > 100 then
      raise exception 'target_out_of_range' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.attacks a
        where a.attacker_id = p_attacker and a.defender_id = p_defender
          and a.started_at > now() - interval '24 hours') then
      raise exception 'target_recent' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.attacks a where a.defender_id = p_defender and a.status = 'started') then
      raise exception 'target_busy' using errcode = 'P0001';
    end if;
    select coalesce((select d.data from public.defense_layouts d where d.player_id = p_defender),
      '{}'::jsonb) into v_defense;
  end if;

  insert into public.attacks (attacker_id, defender_id, bot_idx, map_seed, battle_seed, attacker_army,
    defense_snapshot, castle_snapshot)
  values (p_attacker, p_defender, p_bot, v_seed, p_battle_seed, p_army, v_defense, v_castle)
  returning id into v_id;

  return query select v_id, v_seed, p_battle_seed, v_castle, v_defense;
end;
$$;

comment on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) is
  'Start ataku (#25): limit 10 startów na 10 minut, armia z zamku atakującego, cel bez tarczy i bez innego ataku w toku; zwraca seedy i kopie zamku i obrony. Tylko dla service_role (Edge Function start_attack).';

-- ---------------------------------------------------------------------------------------------
-- Koniec ataku
-- ---------------------------------------------------------------------------------------------

create function public.end_attack(p_attacker uuid, p_attack uuid, p_result jsonb, p_loot jsonb,
  p_survivors jsonb)
returns table (
  status text,
  result jsonb,
  loot integer[],
  shield_until timestamptz
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  a public.attacks%rowtype;
  v_won boolean;
  v_percent bigint;
  v_stars jsonb;
  v_loot_pct bigint;
  v_loot integer[] := array[0, 0, 0, 0];
  v_capacity bigint := 0;
  v_sum bigint := 0;
  v_stash bigint;
  v_cap bigint;
  v_squad jsonb;
  v_alive bigint;
  v_count bigint;
  v_shield timestamptz;
  x bigint;
begin
  select * into a from public.attacks t
  where t.id = p_attack and t.attacker_id = p_attacker
  for update;
  if not found then
    raise exception 'attack_not_found' using errcode = 'P0001';
  end if;

  if a.status = 'finished' then
    return query select a.status, a.result, a.loot,
      (select s.until from public.shields s where s.player_id = a.defender_id);
    return;
  end if;
  -- wygasły atak: zapis porzucenia bez wyjątku, żeby się nie cofnął
  if a.status = 'started' and a.started_at < now() - interval '10 minutes' then
    update public.attacks t set status = 'abandoned' where t.id = a.id;
    a.status := 'abandoned';
  end if;
  if a.status <> 'started' then
    return query select a.status, null::jsonb, null::integer[], null::timestamptz;
    return;
  end if;

  -- wynik: dokładnie {won, percent, stars}; STAR_PERCENT = 50
  if p_result is null or jsonb_typeof(p_result) <> 'object'
      or (select count(*) from jsonb_object_keys(p_result)) <> 3
      or jsonb_typeof(p_result -> 'won') is distinct from 'boolean'
      or jsonb_typeof(p_result -> 'stars') is distinct from 'array' then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;
  v_won := (p_result ->> 'won')::boolean;
  v_percent := private.json_int(p_result -> 'percent', 0, 100);
  v_stars := p_result -> 'stars';
  if v_percent is null or jsonb_array_length(v_stars) <> 3
      or jsonb_typeof(v_stars -> 0) <> 'boolean' or jsonb_typeof(v_stars -> 1) <> 'boolean'
      or jsonb_typeof(v_stars -> 2) <> 'boolean'
      or (v_stars ->> 1)::boolean <> (v_percent >= 50)
      or (v_stars ->> 2)::boolean <> v_won then
    raise exception 'bad_result' using errcode = 'P0001';
  end if;

  -- ocaleli: liczba na każdy oddział z armii zapisanej przy starcie
  if p_survivors is null or jsonb_typeof(p_survivors) <> 'array'
      or jsonb_array_length(p_survivors) <> jsonb_array_length(a.attacker_army) then
    raise exception 'bad_survivors' using errcode = 'P0001';
  end if;
  for i in 0 .. jsonb_array_length(a.attacker_army) - 1 loop
    v_squad := a.attacker_army -> i;
    v_count := private.json_int(v_squad -> 1, 0, 10);
    v_alive := private.json_int(p_survivors -> i, 0, coalesce(v_count, 0));
    if v_alive is null then
      raise exception 'bad_survivors' using errcode = 'P0001';
    end if;
    v_capacity := v_capacity + v_alive * private.unit_carry(private.json_int(v_squad -> 0, 0, 1000)::integer);
  end loop;

  -- łup: 4 liczby w kolejności EconomyConfig.Res (drewno, kamień, żywność, złoto)
  if p_loot is null or jsonb_typeof(p_loot) <> 'array' or jsonb_array_length(p_loot) <> 4 then
    raise exception 'bad_loot' using errcode = 'P0001';
  end if;
  -- WIN_LOOT_PERCENT = 50: wygrana liczy łup co najmniej jak przy połowie zniszczeń
  v_loot_pct := case when v_won then greatest(v_percent, 50) else 0 end;
  for i in 0 .. 3 loop
    x := private.json_int(p_loot -> i, 0, 10000000);
    if x is null then
      raise exception 'bad_loot' using errcode = 'P0001';
    end if;
    if a.defender_id is not null then
      v_stash := coalesce(private.json_int(a.castle_snapshot -> 'economy' -> 'amounts' -> i, 0, 10000000), 0);
    elsif i = 3 then
      -- skarbiec zamku-bota (BotRoster): GOLD_BASE = 20, GOLD_STEP = 10
      v_stash := 20 + 10 * a.bot_idx;
    else
      -- STASH_BASE = 1000, STASH_STEP = 500
      v_stash := 1000 + 500 * a.bot_idx;
    end if;
    -- PROTECTED_PERCENT = 50, LOOT_PERCENT = 20; dzielenie całkowite jak BattleResult.compute_loot
    v_cap := v_stash * (100 - 50) / 100 * 20 / 100 * v_loot_pct / 100;
    if x > v_cap then
      raise exception 'loot_too_high' using errcode = 'P0001';
    end if;
    v_loot[i + 1] := x::integer;
    v_sum := v_sum + x;
  end loop;
  if v_sum > v_capacity then
    raise exception 'loot_too_high' using errcode = 'P0001';
  end if;

  update public.attacks t set status = 'finished', result = p_result, loot = v_loot, finished_at = now()
  where t.id = a.id;

  -- SHIELD_PERCENT = 30, SHIELD_HOURS = 8
  if a.defender_id is not null and v_percent >= 30 then
    insert into public.shields as s (player_id, until) values (a.defender_id, now() + interval '8 hours')
    on conflict (player_id) do update set until = greatest(s.until, excluded.until);
  end if;
  if a.defender_id is not null then
    select s.until into v_shield from public.shields s where s.player_id = a.defender_id;
  end if;

  return query select 'finished'::text, p_result, v_loot, v_shield;
end;
$$;

comment on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) is
  'Koniec ataku (#25): wynik i łup w limitach (zapasy obrońcy, capacity ocalałych), tarcza 8 h od 30 procent zniszczeń; ponowienie zwraca zapisany wynik. Tylko dla service_role (Edge Function finish_attack).';

revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
revoke all on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;
grant execute on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) to service_role;
