-- #383: dobór przeciwnika, zwiad i start ataku tylko w tej samej epoce (ADR 0010).
--
-- Dotąd `match_targets`, `begin_attack` i `begin_scout` dopuszczały różnicę jednej epoki. Teraz gracz epoki II
-- nie trafia na gracza epoki I i odwrotnie. Ciała funkcji są skopiowane z ostatnich wersji
-- (`20261126200000_target_strength.sql`, `20261125211238_attack_verification.sql`,
-- `20261121104913_scouting.sql`); zmienia się tylko warunek epoki i komentarze. Brak graczy w epoce
-- uzupełniają po stronie gry zamki-boty (`TargetSearch.fill`), a atak na bota epoki nie sprawdza.
-- Sygnatury, uprawnienia (tylko service_role) i pozostałe warunki bez zmian.

create or replace function public.match_targets(p_attacker uuid)
returns table (
  player_id uuid,
  nickname text,
  castle_name text,
  ruler text,
  age smallint,
  rating integer,
  map_seed bigint,
  footprint jsonb,
  loot integer[],
  strength integer
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  w timestamptz;
  n integer;
begin
  if p_attacker is null then
    return;
  end if;
  -- limit sprawdzany przed zapisem: odrzucone szukanie niczego nie zmienia, więc nie zależy od tego,
  -- czy wyjątek cofnie transakcję (licznik zostaje na 20 do końca okna)
  select t.window_start, t.searches into w, n
  from private.target_searches t where t.player_id = p_attacker for update;
  if found and w >= now() - interval '10 minutes' and n >= 20 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;
  insert into private.target_searches as t (player_id, window_start, searches)
  values (p_attacker, now(), 1)
  on conflict (player_id) do update set
    window_start = case when t.window_start < now() - interval '10 minutes' then now() else t.window_start end,
    searches = case when t.window_start < now() - interval '10 minutes' then 1 else t.searches + 1 end;

  return query
  with me as (
    select p.age, p.rating from public.players p where p.id = p_attacker
  )
  select
    p.id,
    p.nickname,
    left(c.data -> 'profile' ->> 'castle_name', 16),
    left(coalesce(c.data -> 'profile' ->> 'ruler', ''), 20),
    p.age,
    -- karta celu pokazuje ranking obrony (#27): atakujący mierzy się z obroną celu
    p.defense_rating,
    c.map_seed,
    -- zarys budynków: wpis zapisu [id, rodzaj, poziom, x, y, szer., wys.] → [x, y, szer., wys.]
    coalesce((
      select jsonb_agg(jsonb_build_array(e.v -> 3, e.v -> 4, e.v -> 5, e.v -> 6) order by e.ord)
      from jsonb_array_elements(
        case when jsonb_typeof(c.data -> 'grid' -> 'buildings') = 'array'
          then c.data -> 'grid' -> 'buildings' else '[]'::jsonb end
      ) with ordinality as e(v, ord)
      -- CASE, bo SQL nie gwarantuje kolejności warunków w AND (długość skalara rzuca błąd)
      where e.ord <= 400
        and case when jsonb_typeof(e.v) = 'array' then jsonb_array_length(e.v) >= 7 else false end
    ), '[]'::jsonb),
    -- szacowany łup: LOOT_ESTIMATE_PERCENT = 5 procent zapasów (połowa chroniona × 20 procent łupu
    -- × co najmniej 50 procent zniszczeń po wygranej, jak BattleResult), w dół do pełnych dziesiątek,
    -- żeby karta nie zdradzała dokładnego stanu magazynu
    array(
      select (greatest(0, least(coalesce(
        case when jsonb_typeof(c.data -> 'economy' -> 'amounts' -> i) = 'number'
          then floor((c.data -> 'economy' -> 'amounts' ->> i)::numeric) end, 0), 10000000))::integer
        * 5 / 100 / 10 * 10)
      from generate_series(0, 3) as i
      order by i
    ),
    -- #293: siła obrony z kopii zamku i obrony na serwerze, tylko jako dolna granica przedziału
    private.strength_range_low(private.defense_strength(c.data,
      (select d.data from public.defense_layouts d where d.player_id = p.id)))
  from me, public.players p
  join public.castles c on c.player_id = p.id
  where p.id <> p_attacker
    and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0
    -- #383: tylko ta sama epoka (ADR 0010)
    and p.age = me.age
    and abs(p.rating - me.rating) <= 100
    and not exists (
      select 1 from public.shields s where s.player_id = p.id and s.until > now()
    )
    -- #284: cel z atakiem w weryfikacji (enforce) czeka, aż wejdą skutki tamtego ataku
    and not exists (
      select 1 from public.attacks a
      where a.defender_id = p.id and a.verification = 'pending' and a.outcome_applied_at is null
    )
    and not exists (
      select 1 from public.attacks a
      where a.attacker_id = p_attacker and a.defender_id = p.id
        and a.started_at > now() - interval '24 hours'
    )
  order by random()
  limit 3;
end;
$$;

comment on function public.match_targets(uuid) is
  'Dobór przeciwnika (#24): do 3 graczy bez tarczy i bez ataku w weryfikacji (#284), ta sama epoka (#383), ranking ±100, bez ataku od p_attacker w 24 h; najwyżej 20 wywołań na 10 minut; karta pokazuje ranking obrony (#27) i przedział siły obrony (#293). Tylko dla service_role (Edge Function find_targets).';
revoke all on function public.match_targets(uuid) from public, anon, authenticated;
grant execute on function public.match_targets(uuid) to service_role;

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

  select p.age, p.rating into v_age, v_rating from public.players p where p.id = p_attacker;
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
  end if;

  insert into public.attacks (attacker_id, defender_id, bot_idx, map_seed, battle_seed, attacker_army,
    defense_snapshot, castle_snapshot)
  values (p_attacker, p_defender, p_bot, v_seed, p_battle_seed, p_army, v_defense, v_castle)
  returning id into v_id;

  return query select v_id, v_seed, p_battle_seed, v_castle, v_defense;
end;
$$;

comment on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) is
  'Start ataku (#25, #249, #81, #274, #383): cel-gracz z tej samej epoki i rankingu ±100, limit 10 startów na 10 minut, zamek atakującego i obrońcy w limitach surowców (#274), armia z zamku atakującego bez garnizonu Dworu w limicie miejsc i utrzymania żywności, cel bez tarczy, bez innego ataku w toku i bez ataku w weryfikacji (#284); zwraca seedy, kopię zamku z czekającym łupem i obronę. Tylko dla service_role (Edge Function start_attack).';
revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;

create or replace function public.begin_scout(p_attacker uuid, p_defender uuid, p_duration smallint, p_seed bigint)
returns table (
  mission_id uuid,
  ends_at timestamptz,
  trackers smallint,
  scouts smallint
)
language plpgsql
volatile
security invoker
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_age smallint;
  d_age smallint;
  v_own jsonb;
  v_castle jsonb;
  v_defense jsonb;
  v_s3 boolean;
  v_trackers integer := 0;
  v_scouts integer := 0;
  v_sent integer;
  v_towers integer;
  c integer[] := array[60, 20, 10, 10];
  v_from integer;
  v_roll integer;
  v_outcome integer;
  v_returned integer;
  v_full integer;
  v_percent integer;
  v_region integer[];
  v_ends timestamptz;
  v_id uuid;
  e jsonb;
  u bigint;
  n bigint;
begin
  if p_attacker is null or p_defender is null then
    raise exception 'bad_target' using errcode = 'P0001';
  end if;
  if p_defender = p_attacker then
    raise exception 'self_scout' using errcode = 'P0001';
  end if;
  if p_duration is null or p_duration < 0 or p_duration > 2 then
    raise exception 'bad_duration' using errcode = 'P0001';
  end if;
  if p_seed is null or p_seed < 0 or p_seed > 2147483647 then
    raise exception 'bad_seed' using errcode = 'P0001';
  end if;

  -- równoległe wysyłki tego samego gracza idą po kolei (naraz jedna misja)
  select p.age into v_age from public.players p where p.id = p_attacker for update;
  if not found then
    raise exception 'attacker_not_found' using errcode = 'P0001';
  end if;
  select c.data into v_own from public.castles c where c.player_id = p_attacker;
  if not found then
    raise exception 'attacker_no_castle' using errcode = 'P0001';
  end if;
  if not exists (select 1 from private.castle_buildings(v_own) b where b.kind = 22 and b.level >= 1) then
    raise exception 'no_building' using errcode = 'P0001';
  end if;
  -- coalesce: zamek bez `research` daje NULL, a `if not NULL` nie rzuca wyjątku
  if not coalesce(jsonb_typeof(v_own -> 'research' -> 'done') = 'array'
      and (v_own -> 'research' -> 'done') @> '["S1"]'::jsonb, false) then
    raise exception 'no_tech' using errcode = 'P0001';
  end if;
  v_s3 := coalesce((v_own -> 'research' -> 'done') @> '["S3"]'::jsonb, false);
  if exists (select 1 from private.scout_missions m where m.attacker_id = p_attacker and m.ends_at > now()) then
    raise exception 'scout_busy' using errcode = 'P0001';
  end if;
  -- SCOUT_LIMIT = 30 misji na dobę
  if (select count(*) from private.scout_missions m
      where m.attacker_id = p_attacker and m.started_at > now() - interval '24 hours') >= 30 then
    raise exception 'rate_limited' using errcode = 'P0001';
  end if;

  -- zwiadowcy z oddziałów zamku [id, rodzaj, liczba]: najpierw Tropiciele, razem najwyżej 5
  for e in select x.value from jsonb_array_elements(
      case when jsonb_typeof(v_own -> 'recruitment' -> 'squads') = 'array'
        then v_own -> 'recruitment' -> 'squads' else '[]'::jsonb end) as x loop
    if jsonb_typeof(e) = 'array' and jsonb_array_length(e) >= 3 then
      u := private.json_int(e -> 1, 0, private.unit_count() - 1);
      n := private.json_int(e -> 2, 0, 10);
      if u = 5 and n is not null then
        v_trackers := v_trackers + n;
      elsif u = 14 and n is not null then
        v_scouts := v_scouts + n;
      end if;
    end if;
  end loop;
  v_trackers := least(v_trackers, 5);
  v_scouts := least(v_scouts, 5 - v_trackers);
  v_sent := v_trackers + v_scouts;
  if v_sent < 1 then
    raise exception 'no_scouts' using errcode = 'P0001';
  end if;

  -- cel: gracz z zamkiem z onboardingu, ta sama epoka (jak dobór przeciwnika, #383)
  select p.age into d_age from public.players p where p.id = p_defender;
  select c.data into v_castle from public.castles c
  where c.player_id = p_defender and char_length(coalesce(c.data -> 'profile' ->> 'castle_name', '')) > 0;
  if d_age is null or v_castle is null then
    raise exception 'target_not_found' using errcode = 'P0001';
  end if;
  if d_age <> v_age then
    raise exception 'target_out_of_range' using errcode = 'P0001';
  end if;
  select coalesce((select d.data from public.defense_layouts d where d.player_id = p_defender), '{}'::jsonb)
  into v_defense;
  select count(*) into v_towers from private.castle_buildings(v_castle) b where b.kind = 31 and b.level >= 1;

  -- szanse (ScoutConfig.chances): S3 zabiera po połowie z porażki i wykrycia, Wieża sygnałowa
  -- przenosi 20 punktów sukcesu na wykrycie
  if v_s3 then
    v_from := least(5, c[4]);
    c[4] := c[4] - v_from;
    c[1] := c[1] + v_from;
    v_from := least(10 - v_from, c[3]);
    c[3] := c[3] - v_from;
    c[1] := c[1] + v_from;
  end if;
  if v_towers > 0 then
    v_from := least(20, c[1]);
    c[1] := c[1] - v_from;
    c[3] := c[3] + v_from;
  end if;
  v_roll := (p_seed % 100)::integer;
  v_outcome := case when v_roll < c[1] then 0 when v_roll < c[1] + c[2] then 1
    when v_roll < c[1] + c[2] + c[3] then 2 else 3 end;
  v_returned := case v_outcome when 0 then v_sent when 1 then (v_sent + 1) / 2 when 2 then v_sent else 0 end;
  v_full := least((array[20, 35, 50])[p_duration + 1] + 5 * least(v_sent - 1, 4) + case when v_s3 then 10 else 0 end, 80);
  v_percent := case v_outcome when 0 then v_full when 1 then v_full / 2 else 0 end;
  v_region := private.scout_region(v_castle, v_percent, p_seed);
  v_ends := now() + make_interval(secs => (array[120, 600, 1800])[p_duration + 1]);

  -- na jeden cel jeden raport: starsze misje tego gracza na ten cel znikają
  delete from private.scout_missions m where m.attacker_id = p_attacker and m.defender_id = p_defender;
  insert into private.scout_missions (attacker_id, defender_id, duration, trackers, scouts, ends_at, outcome,
    percent, returned, intel)
  values (p_attacker, p_defender, p_duration, v_trackers, v_scouts, v_ends, v_outcome,
    case when v_region is null then 0 else v_percent end, v_returned,
    private.scout_intel(v_castle, v_defense, v_region))
  returning id into v_id;

  return query select v_id, v_ends, v_trackers::smallint, v_scouts::smallint;
end;
$$;

comment on function public.begin_scout(uuid, uuid, smallint, bigint) is
  'Zwiad na gracza (#28): Chata tropicieli, S1 i zwiadowcy z zamku atakującego na serwerze, naraz jedna misja, 30 na dobę; wynik z seeda serwera. Tylko dla service_role (Edge Function scout).';
revoke all on function public.begin_scout(uuid, uuid, smallint, bigint) from public, anon, authenticated;
grant execute on function public.begin_scout(uuid, uuid, smallint, bigint) to service_role;
