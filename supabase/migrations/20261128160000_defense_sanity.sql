-- #421 (ADR 0020): układ obrony do ataku tylko taki, jaki ma zamek na serwerze.
--
-- Atak PvP dostaje kopię `defense_layouts.data` obrońcy (`begin_attack` → `attacks.defense_snapshot`), a koszt pułapek
-- liczy bilans zamku z `castles.data.defense` (`private.trap_counts`). Klient wysyła oba z tego samego słownika
-- (SupabaseClient: najpierw zamek, po udanym zapisie zamku ta sama obrona do `defense_layouts`), ale spreparowany
-- klient mógł zapisać do `defense_layouts` inny układ: pułapki, za które nie zapłacił, i zadania spoza armii.
--
-- Reguły (odrzucenie w całości kodem HTTP 422, SQLSTATE PT422, bez cichego przycinania):
-- - `castles.data.defense` (wyzwalacz `castles_check_defense`, każdy zapis `data`): kształt jak DefensePlan.to_dict,
--   kod `bad_defense`:
--   - `orders` = [[id oddziału > 0, zadanie 0..TASKS - 1, x, y, trasa?], ...], TASKS = 8 (DefensePlan.Task);
--     id bez powtórzeń i tylko oddziałów z `recruitment.squads` (serwer przy stratach zostawia oddział z liczbą 0,
--     a gra przed zapisem zdejmuje zadania rozwiązanych oddziałów, DefensePlan.prune);
--     miejsce na mapie 0..MAP_SIZE - 1, MAP_SIZE = 64 (TerrainMap.SIZE), albo NO_POST = [-1, -1];
--     trasa patrolu najwyżej MAX_ROUTE = 2 punkty na mapie;
--   - `traps` = [[rodzaj 0..TRAP_KINDS - 1, x, y, odkryta 0/1?], ...], TRAP_KINDS = 5 (TrapConfig.Kind), kratki
--     na mapie bez powtórzeń, najwyżej LIMIT_PER_MANOR_LEVEL = 2 na poziom Dworu (TrapConfig.limit, Dwór 1..10),
--     epoka TRAP_AGE = [0, 0, 0, 0, 1] i technologia TRAP_TECH = ["G18", "O2", "G1", "A42", "G24"] rodzaju zbadane
--     (TrapConfig.AGE, TrapConfig.TECH; obie nie cofają się w grze);
--   - `tower_priority` 0..TOWER_PRIORITIES - 1, TOWER_PRIORITIES = 4; `commander` -1..GENERALS - 1, GENERALS = 3.
--   Strefa obrony, kratki przy murach, zadanie dozwolone dla klasy i epoki, budynki i miejsce pułapki oraz
--   pojemność garnizonu zostają w symulacji (DefensePlan.order_allowed, battle_traps, battle_garrison, ta sama
--   u atakującego i na workerze weryfikacji): ruiny po ataku chwilowo łamią je uczciwym graczom.
-- - `defense_layouts.data` (wyzwalacz `defense_layouts_check_castle`, zapis z API jako gracz) musi być równe
--   `castles.data.defense` z wiersza zamku gracza, kod `defense_mismatch`. Bez zamku nie ma obrony.
-- - start ataku na gracza (`begin_attack`): kopia obrony różna od obrony z kopii zamku albo obrona zamku spoza
--   reguł kształtu → `defense_invalid` (P0001, start_attack zwraca 409). Bez cichej podmiany: obrońca wraca do celów po najbliższym zapisie z telefonu.
--
-- Zamki zapisane przed migracją, które łamią reguły kształtu, dostają raz obronę przyciętą do poprawnych wpisów,
-- a wiersze `defense_layouts` obronę z zamku, także brakujące wiersze (wyjątek od zasady „bez przycinania”, jak w #274).
-- Nowych danych o graczu nie ma. Liczby pilnuje test gry (`tests/test_defense_sanity.gd`) po znacznikach.

-- ---------------------------------------------------------------------------------------------
-- Funkcje pomocnicze (schemat private)
-- ---------------------------------------------------------------------------------------------

-- Id oddziałów z `recruitment.squads` = [[id, rodzaj, liczba], ...]; złe wpisy się nie liczą.
create function private.squad_ids(p_castle jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(array_agg(private.json_int(x.e -> 0, 1, 2147483647)), '{}'::bigint[])
  from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'recruitment' -> 'squads') = 'array'
      then p_castle -> 'recruitment' -> 'squads' else '[]'::jsonb end) as x(e)
  -- case, bo `and` w where nie gwarantuje kolejności, a jsonb_array_length na skalarze rzuca błąd
  where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 3 else false end
    and private.json_int(x.e -> 0, 1, 2147483647) is not null
$$;

-- Czy punkt [x, y] leży na mapie MAP_SIZE = 64; z `p_no_post` także NO_POST = [-1, -1].
create function private.defense_cell_ok(p jsonb, p_no_post boolean)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  x bigint := private.json_int(p -> 0, -1, 63);
  y bigint := private.json_int(p -> 1, -1, 63);
begin
  if x is null or y is null then
    return false;
  end if;
  if x = -1 or y = -1 then
    return p_no_post and x = -1 and y = -1;
  end if;
  return true;
end;
$$;

-- Czy wpis zadania [id, zadanie, x, y, trasa?] ma dobry kształt i należy do oddziału z `p_squads`.
create function private.defense_order_ok(e jsonb, p_squads bigint[])
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_id bigint;
  w jsonb;
begin
  if jsonb_typeof(e) <> 'array' or jsonb_array_length(e) not in (4, 5) then
    return false;
  end if;
  v_id := private.json_int(e -> 0, 1, 2147483647);
  -- TASKS = 8
  if v_id is null or private.json_int(e -> 1, 0, 7) is null or not (v_id = any (p_squads)) then
    return false;
  end if;
  if not private.defense_cell_ok(jsonb_build_array(e -> 2, e -> 3), true) then
    return false;
  end if;
  if jsonb_array_length(e) = 5 then
    -- MAX_ROUTE = 2
    if jsonb_typeof(e -> 4) <> 'array' or jsonb_array_length(e -> 4) > 2 then
      return false;
    end if;
    for w in select x from jsonb_array_elements(e -> 4) x loop
      if jsonb_typeof(w) <> 'array' or jsonb_array_length(w) <> 2 or not private.defense_cell_ok(w, false) then
        return false;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

-- Czy wpis pułapki [rodzaj, x, y, odkryta?] ma dobry kształt, a jej epoka i technologia są w zamku `p_castle`.
create function private.defense_trap_ok(e jsonb, p_castle jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  k bigint;
begin
  if jsonb_typeof(e) <> 'array' or jsonb_array_length(e) not in (3, 4) then
    return false;
  end if;
  -- TRAP_KINDS = 5
  k := private.json_int(e -> 0, 0, 4);
  if k is null or not private.defense_cell_ok(jsonb_build_array(e -> 1, e -> 2), false) then
    return false;
  end if;
  if jsonb_array_length(e) = 4 and private.json_int(e -> 3, 0, 1) is null then
    return false;
  end if;
  -- TRAP_AGE = [0, 0, 0, 0, 1]
  if (array[0, 0, 0, 0, 1])[k + 1] > private.castle_age(p_castle) then
    return false;
  end if;
  -- TRAP_TECH = ["G18", "O2", "G1", "A42", "G24"]
  return jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
    and (p_castle -> 'research' -> 'done') @> jsonb_build_array((array['G18', 'O2', 'G1', 'A42', 'G24'])[k + 1]);
end;
$$;

-- Najwięcej pułapek w zamku: LIMIT_PER_MANOR_LEVEL = 2 na poziom Dworu (rodzaj 5, najniższe id, 1..10; bez Dworu 1).
create function private.trap_limit(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select 2 * least(greatest(coalesce((select b.level from private.castle_levels(p_castle) b
      where b.kind = 5 order by b.id limit 1), 1), 1), 10)
$$;

-- Kod problemu z obroną w zapisie zamku (`bad_defense`) albo null. Brak obrony jest poprawny (nowa gra).
create function private.defense_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_def jsonb := p_castle -> 'defense';
  v_squads bigint[];
  e jsonb;
begin
  if v_def is null or jsonb_typeof(v_def) = 'null' then
    return null;
  end if;
  if jsonb_typeof(v_def) <> 'object' then
    return 'bad_defense';
  end if;
  -- TOWER_PRIORITIES = 4, GENERALS = 3
  if v_def ? 'tower_priority' and private.json_int(v_def -> 'tower_priority', 0, 3) is null then
    return 'bad_defense';
  end if;
  if v_def ? 'commander' and private.json_int(v_def -> 'commander', -1, 2) is null then
    return 'bad_defense';
  end if;
  if v_def ? 'orders' then
    if jsonb_typeof(v_def -> 'orders') <> 'array' then
      return 'bad_defense';
    end if;
    v_squads := private.squad_ids(p_castle);
    for e in select x from jsonb_array_elements(v_def -> 'orders') x loop
      if not private.defense_order_ok(e, v_squads) then
        return 'bad_defense';
      end if;
    end loop;
    if (select count(distinct x -> 0) <> count(*) from jsonb_array_elements(v_def -> 'orders') x) then
      return 'bad_defense';
    end if;
  end if;
  if v_def ? 'traps' then
    if jsonb_typeof(v_def -> 'traps') <> 'array' or jsonb_array_length(v_def -> 'traps') > private.trap_limit(p_castle) then
      return 'bad_defense';
    end if;
    for e in select x from jsonb_array_elements(v_def -> 'traps') x loop
      if not private.defense_trap_ok(e, p_castle) then
        return 'bad_defense';
      end if;
    end loop;
    if (select count(distinct jsonb_build_array(x -> 1, x -> 2)) <> count(*)
        from jsonb_array_elements(v_def -> 'traps') x) then
      return 'bad_defense';
    end if;
  end if;
  return null;
end;
$$;

-- Obrona zamku przycięta do poprawnych wpisów (tylko jednorazowe sprzątanie w tej migracji): pierwsze wystąpienie
-- id oddziału i kratki pułapki, pułapki do limitu w kolejności postawienia, zły priorytet wież 0, zły komendant -1.
create function private.defense_trimmed(p_castle jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_def jsonb := p_castle -> 'defense';
  v_squads bigint[] := private.squad_ids(p_castle);
  v_orders jsonb := '[]'::jsonb;
  v_traps jsonb := '[]'::jsonb;
  v_ids jsonb := '[]'::jsonb;
  v_cells jsonb := '[]'::jsonb;
  e jsonb;
begin
  if jsonb_typeof(v_def) <> 'object' then
    return '{}'::jsonb;
  end if;
  for e in select x from jsonb_array_elements(case when jsonb_typeof(v_def -> 'orders') = 'array'
      then v_def -> 'orders' else '[]'::jsonb end) x loop
    if private.defense_order_ok(e, v_squads) and not v_ids @> jsonb_build_array(e -> 0) then
      v_orders := v_orders || jsonb_build_array(e);
      v_ids := v_ids || jsonb_build_array(e -> 0);
    end if;
  end loop;
  for e in select x from jsonb_array_elements(case when jsonb_typeof(v_def -> 'traps') = 'array'
      then v_def -> 'traps' else '[]'::jsonb end) x loop
    if jsonb_array_length(v_traps) < private.trap_limit(p_castle) and private.defense_trap_ok(e, p_castle)
        and not v_cells @> jsonb_build_array(jsonb_build_array(e -> 1, e -> 2)) then
      v_traps := v_traps || jsonb_build_array(e);
      v_cells := v_cells || jsonb_build_array(jsonb_build_array(e -> 1, e -> 2));
    end if;
  end loop;
  return v_def || jsonb_build_object('orders', v_orders, 'traps', v_traps,
    'tower_priority', coalesce(private.json_int(v_def -> 'tower_priority', 0, 3), 0),
    'commander', coalesce(private.json_int(v_def -> 'commander', -1, 2), -1));
end;
$$;

revoke all on function private.squad_ids(jsonb) from public, anon, authenticated;
revoke all on function private.defense_cell_ok(jsonb, boolean) from public, anon, authenticated;
revoke all on function private.defense_order_ok(jsonb, bigint[]) from public, anon, authenticated;
revoke all on function private.defense_trap_ok(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.trap_limit(jsonb) from public, anon, authenticated;
revoke all on function private.defense_problem(jsonb) from public, anon, authenticated;
revoke all on function private.defense_trimmed(jsonb) from public, anon, authenticated;
grant execute on function private.defense_problem(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Jednorazowe sprzątanie zapisów sprzed migracji
-- ---------------------------------------------------------------------------------------------

update public.castles c
set data = jsonb_set(c.data, '{defense}', private.defense_trimmed(c.data))
where private.defense_problem(c.data) is not null;

update public.defense_layouts d
set data = coalesce(c.data -> 'defense', '{}'::jsonb)
from public.castles c
where c.player_id = d.player_id
  and d.data is distinct from coalesce(c.data -> 'defense', '{}'::jsonb);

-- zamek z obroną bez wiersza obrony (zapis obrony nie doszedł): bez tego obrońca nie byłby celem
insert into public.defense_layouts (player_id, save_version, data)
select c.player_id, c.save_version, c.data -> 'defense'
from public.castles c
where jsonb_typeof(c.data -> 'defense') = 'object'
  and not exists (select 1 from public.defense_layouts d where d.player_id = c.player_id);

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacze
-- ---------------------------------------------------------------------------------------------

-- security definer jak inne wyzwalacze zamku: funkcje pomocnicze nie są dostępne dla ról z API.
create function private.check_castle_defense()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if private.defense_problem(new.data) is not null then
    raise exception 'bad_defense' using errcode = 'PT422';
  end if;
  return new;
end;
$$;
revoke all on function private.check_castle_defense() from public, anon, authenticated;

create trigger castles_check_defense
  before insert or update of data on public.castles
  for each row execute function private.check_castle_defense();

-- Zapis obrony z API jako gracz (rola z tokenu `authenticated` albo `anon`) tylko równy obronie z zamku.
-- security definer: gracz czyta przez RLS tylko swój zamek, ale wyzwalacz nie może zależeć od polityk odczytu.
create function private.check_defense_layout()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_claims jsonb := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb, '{}'::jsonb);
  v_role text := coalesce(v_claims ->> 'role', '');
begin
  -- wiersz cudzego gracza odrzuca RLS; wyzwalacz nie porównuje z cudzym zamkiem, żeby nie zdradzić jego obrony
  if v_role in ('authenticated', 'anon') and new.player_id::text is distinct from (v_claims ->> 'sub') then
    return new;
  end if;
  if v_role in ('authenticated', 'anon') and new.data is distinct from (
      select coalesce(c.data -> 'defense', '{}'::jsonb) from public.castles c where c.player_id = new.player_id) then
    raise exception 'defense_mismatch' using errcode = 'PT422';
  end if;
  return new;
end;
$$;
revoke all on function private.check_defense_layout() from public, anon, authenticated;

create trigger defense_layouts_check_castle
  before insert or update of data on public.defense_layouts
  for each row execute function private.check_defense_layout();

-- ---------------------------------------------------------------------------------------------
-- Start ataku na gracza: obrona z defense_layouts = obrona z zamku (ciało z `20261127180000_bot_campaign.sql`,
-- zmiana tylko przy `defense_invalid`)
-- ---------------------------------------------------------------------------------------------

create or replace function public.begin_attack(p_attacker uuid, p_defender uuid, p_bot smallint, p_army jsonb,
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
  v_beaten smallint;
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
  v_units integer;
  v_upkeep integer;
  v_garrison bigint[];
  v_paid integer;
  d_paid integer;
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

  select p.age, p.rating, p.bots_beaten into v_age, v_rating, v_beaten from public.players p where p.id = p_attacker;
  if not found then
    raise exception 'attacker_not_found' using errcode = 'P0001';
  end if;
  select c.data, c.ruler_perk_paid into v_own, v_paid from public.castles c where c.player_id = p_attacker;
  if not found then
    raise exception 'attacker_no_castle' using errcode = 'P0001';
  end if;
  -- #274: zamek z surowcami spoza limitów (zapis sprzed tej migracji) nie wchodzi do PvP. Nic nie przycinamy:
  -- gracz poprawia zamek zwykłym zapisem z gry, który przechodzi przez wyzwalacz castles_resources.
  if private.castle_resources_problem(p_attacker, v_own, v_paid) is not null then
    raise exception 'castle_invalid' using errcode = 'P0001';
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
  -- #81: garnizon Dworu nie idzie do ataku. Oddziały z zadaniem obrony GARRISON = 6 w zapisie zamku
  -- (`defense.orders` = [[id oddziału, zadanie, x, y, trasa], ...], DefensePlan.to_dict) nie liczą się
  -- do wojska, którym atakujący może zaatakować. Zły wpis to brak garnizonu (jak w DefensePlan.from_dict).
  select coalesce(array_agg(private.json_int(o.value -> 0, 1, 2147483647)), '{}'::bigint[]) into v_garrison
  from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'defense' -> 'orders') = 'array'
        then v_own -> 'defense' -> 'orders' else '[]'::jsonb end) as o
  -- `case`, bo `and` w SQL nie gwarantuje kolejności, a jsonb_array_length na skalarze rzuca błąd
  where case when jsonb_typeof(o.value) <> 'array' then false
      when jsonb_array_length(o.value) < 4 then false
      else private.json_int(o.value -> 1, 0, 100) = 6
        and private.json_int(o.value -> 0, 1, 2147483647) is not null end;
  -- oddziały w zapisie zamku: [id, rodzaj, liczba]; złe wpisy się nie liczą, garnizon też nie
  for e in select x.value from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'recruitment' -> 'squads') = 'array'
        then v_own -> 'recruitment' -> 'squads' else '[]'::jsonb end) as x loop
    if jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 3
        and coalesce(private.json_int(e -> 0, 1, 2147483647) <> all (v_garrison), true) then
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

  -- #249: limit miejsc i utrzymania z kopii zamku atakującego na serwerze (Recruitment.army_limit,
  -- Recruitment.upkeep_limit). Liczy się armia z żądania, nie cały zamek: po rozbiórce Koszar albo
  -- Rybaka zamek może chwilowo mieć więcej wojska, niż utrzyma, a do ataku idzie tylko tyle, ile się mieści.
  v_units := 0;
  v_upkeep := 0;
  for i in 1 .. private.unit_count() loop
    v_units := v_units + want[i];
    v_upkeep := v_upkeep + want[i] * private.unit_upkeep(i - 1);
  end loop;
  if v_units > private.army_limit(v_own) then
    raise exception 'army_over_limit' using errcode = 'P0001';
  end if;
  if v_upkeep > private.food_production(v_own) then
    raise exception 'army_over_upkeep' using errcode = 'P0001';
  end if;

  -- wygasłe ataki w toku zwalniają cele (ATTACK_TIMEOUT = 10 minut), a nowy start atakującego
  -- porzuca jego poprzedni atak
  update public.attacks a set status = 'abandoned'
  where a.status = 'started'
    and (a.started_at < now() - interval '10 minutes' or a.attacker_id = p_attacker);

  if p_bot is not null then
    -- #386: zamki-boty po kolei (BotRoster.is_unlocked); postęp tylko z serwera (ADR 0015)
    if p_bot > v_beaten then
      raise exception 'bot_locked' using errcode = 'P0001';
    end if;
    select b.map_seed into v_seed from public.bot_castles b where b.idx = p_bot;
    if not found then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
  else
    select p.age, p.rating into d_age, d_rating from public.players p where p.id = p_defender;
    select c.map_seed, c.data, c.ruler_perk_paid into v_seed, v_castle, d_paid from public.castles c
    where c.player_id = p_defender
      and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0;
    if d_age is null or v_seed is null then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
    -- #274: obrońca z nierealnym zapisem nie jest celem, a kopia zamku do bitwy ma już łup z wcześniejszych
    -- ataków, którego telefon obrońcy jeszcze nie scalił (castle_loot_pending): nie da się złupić dwa razy
    -- tych samych zapasów
    if private.castle_resources_problem(p_defender, v_castle, d_paid) is not null then
      raise exception 'target_not_found' using errcode = 'P0001';
    end if;
    v_castle := private.castle_with_pending(p_defender, v_castle);
    if exists (select 1 from public.shields s where s.player_id = p_defender and s.until > now()) then
      raise exception 'target_shielded' using errcode = 'P0001';
    end if;
    -- #383: tylko ta sama epoka (ADR 0010)
    if d_age <> v_age or abs(d_rating - v_rating) > 100 then
      raise exception 'target_out_of_range' using errcode = 'P0001';
    end if;
    if exists (select 1 from public.attacks a
        where a.attacker_id = p_attacker and a.defender_id = p_defender
          and a.started_at > now() - interval '24 hours') then
      raise exception 'target_recent' using errcode = 'P0001';
    end if;
    -- #284: atak w weryfikacji (enforce) blokuje cel jak atak w toku, aż wejdą jego skutki
    if exists (select 1 from public.attacks a where a.defender_id = p_defender
        and (a.status = 'started' or (a.verification = 'pending' and a.outcome_applied_at is null))) then
      raise exception 'target_busy' using errcode = 'P0001';
    end if;
    select coalesce((select d.data from public.defense_layouts d where d.player_id = p_defender),
      '{}'::jsonb) into v_defense;
    -- #421 (ADR 0020): do ataku tylko obrona taka jak w zamku i w regułach kształtu; bez cichej podmiany
    if v_defense is distinct from coalesce(v_castle -> 'defense', '{}'::jsonb)
        or private.defense_problem(v_castle) is not null then
      raise exception 'defense_invalid' using errcode = 'P0001';
    end if;
  end if;

  insert into public.attacks (attacker_id, defender_id, bot_idx, map_seed, battle_seed, attacker_army,
    defense_snapshot, castle_snapshot)
  values (p_attacker, p_defender, p_bot, v_seed, p_battle_seed, p_army, v_defense, v_castle)
  returning id into v_id;

  return query select v_id, v_seed, p_battle_seed, v_castle, v_defense;
end;
$$;

comment on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) is
  'Start ataku (#25, #249, #81, #274, #383, #386): zamek-bot tylko odblokowany (bot_idx <= players.bots_beaten), cel-gracz z tej samej epoki i rankingu ±100, limit 10 startów na 10 minut, zamek atakującego i obrońcy w limitach surowców (#274), obrona celu równa obronie z zamku (#421), armia z zamku atakującego bez garnizonu Dworu w limicie miejsc i utrzymania żywności, cel bez tarczy, bez innego ataku w toku i bez ataku w weryfikacji (#284); zwraca seedy, kopię zamku z czekającym łupem i obronę. Tylko dla service_role (Edge Function start_attack).';
revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;
