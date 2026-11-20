-- #249: serwer pilnuje limitu armii i utrzymania w żywności przy starcie ataku (#214, klient w #247).
--
-- Do tej pory `public.begin_attack` sprawdzał tylko, czy armia ataku jest w zamku atakującego. Klient,
-- który pominie UI (albo wyśle zamek z armią ponad limit), mógł iść do ataku z wojskiem, którego
-- zamek nie utrzyma. Teraz z kopii zamku na serwerze (`castles.data`) liczymy to samo co gra:
-- - limit miejsc (Recruitment.army_limit): Dwór × ARMY_PER_MANOR_LEVEL = 10 plus suma poziomów Koszar
--   × ARMY_PER_BARRACKS_LEVEL = 2. Bez Dworu w zapisie liczy się poziom 1 (BuildGrid.manor_level);
-- - limit utrzymania (Recruitment.upkeep_limit): produkcja żywności na godzinę, czyli
--   FOOD_BASE = 20 plus Rybacy FISHER_FOOD = [40, 60, 80, 110, 140] według poziomu, z premią badania
--   G2 = 15 procent (TechTree.PRODUCTION_BONUS), zaokrąglone w dół jak w Economy.rates;
-- - utrzymanie jednostki (UnitTypes.UPKEEP): UPKEEP = [1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 0, 1, 1, 2, 2].
-- Armia ataku ponad limit miejsc daje `army_over_limit`, ponad produkcję żywności `army_over_upkeep`;
-- nic się wtedy nie zapisuje. Sprawdzamy armię z żądania, a nie cały zamek, bo po rozbiórce Koszar
-- albo Rybaka zamek może legalnie mieć chwilowo za dużo wojska (gra zabiera je głodem, #214).
--
-- Budynki w zapisie: `grid.buildings` = [[id, rodzaj, poziom, x, y, szer., wys.], ...] (BuildGrid.save_data).
-- Jak przy wczytywaniu w grze: wpis z id <= 0, krótszy niż 7 pól albo z powtórzonym id się nie liczy,
-- poziom przycina się do 0..5, a plac budowy (poziom 0) nic nie produkuje. Rodzaje (BuildingTypes.Kind):
-- MANOR = 5, FISHER = 16, BARRACKS = 18. Serwer nie zna terenu, więc nie sprawdza, czy budynek mieści
-- się na mapie; pełna weryfikacja stanu zamku to powtórka po stronie serwera (#29).
-- Liczby pilnuje test gry (`tests/test_attack_limits.gd`) po znacznikach w komentarzach.
--
-- Funkcje pomocnicze są w schemacie private i woła je tylko `service_role` (przez begin_attack).

-- Utrzymanie jednej jednostki rodzaju `unit` w żywności na godzinę (UnitTypes.UPKEEP).
create function private.unit_upkeep(unit integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select coalesce((array[1, 1, 1, 1, 1, 1, 2, 1, 1, 1, 2, 0, 1, 1, 2, 2])[unit + 1], 0)
$$;

-- Budynki z zapisu zamku jak po BuildGrid.load_data: pierwszy wpis danego id, poziom 0..5.
create function private.castle_buildings(p_castle jsonb)
returns table (id bigint, kind bigint, level integer)
language sql
immutable
set search_path = ''
as $$
  select distinct on (b.id) b.id, b.kind, least(greatest(b.lvl, 0), 5)::integer
  from (
    select private.json_int(x.e -> 0, 1, 2147483647) as id,
      private.json_int(x.e -> 1, 0, 2147483647) as kind,
      private.json_int(x.e -> 2, -2147483648, 2147483647) as lvl,
      x.ord
    from jsonb_array_elements(
        case when jsonb_typeof(p_castle -> 'grid' -> 'buildings') = 'array'
          then p_castle -> 'grid' -> 'buildings' else '[]'::jsonb end)
      with ordinality as x(e, ord)
    -- case, bo `and` w where nie gwarantuje kolejności, a jsonb_array_length na skalarze rzuca błąd
    where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end
  ) b
  where b.id is not null and b.kind is not null and b.lvl is not null
  order by b.id, b.ord
$$;

-- Limit miejsc w armii (Recruitment.army_limit): Dwór o najniższym id (BuildGrid.manor_id) co
-- najmniej poziom 1, plus poziomy wszystkich Koszar.
create function private.army_limit(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select 10 * coalesce((select greatest(b.level, 1) from private.castle_buildings(p_castle) b
      where b.kind = 5 order by b.id limit 1), 1)
    + 2 * coalesce((select sum(b.level) from private.castle_buildings(p_castle) b where b.kind = 18), 0)::integer
$$;

-- Produkcja żywności na godzinę (Economy.rates z Research.production_percent): gród plus Rybacy,
-- z premią G2, gdy jest w `research.done`.
create function private.food_production(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((20 + coalesce((select sum((array[40, 60, 80, 110, 140])[b.level])
        from private.castle_buildings(p_castle) b where b.kind = 16 and b.level >= 1), 0))
      * (100 + case when jsonb_typeof(p_castle -> 'research' -> 'done') = 'array'
          and (p_castle -> 'research' -> 'done') @> '["G2"]'::jsonb then 15 else 0 end)
      / 100)::integer
$$;

revoke all on function private.unit_upkeep(integer) from public, anon, authenticated;
revoke all on function private.castle_buildings(jsonb) from public, anon, authenticated;
revoke all on function private.army_limit(jsonb) from public, anon, authenticated;
revoke all on function private.food_production(jsonb) from public, anon, authenticated;
grant execute on function private.unit_upkeep(integer) to service_role;
grant execute on function private.castle_buildings(jsonb) to service_role;
grant execute on function private.army_limit(jsonb) to service_role;
grant execute on function private.food_production(jsonb) to service_role;

-- Start ataku: jak w *_finish_attack.sql, z limitem miejsc i utrzymania po sprawdzeniu zapasu armii.
-- `create or replace` zostawia uprawnienia; mimo to powtarzamy je jawnie (tylko service_role).
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
  'Start ataku (#25, #249): limit 10 startów na 10 minut, armia z zamku atakującego w limicie miejsc i utrzymania żywności, cel bez tarczy i bez innego ataku w toku; zwraca seedy i kopie zamku i obrony. Tylko dla service_role (Edge Function start_attack).';

revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;
