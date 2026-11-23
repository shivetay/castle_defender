-- #81: garnizon Dworu zostaje w zamku, także w ataku na gracza.
--
-- Gracz przypisuje oddział do garnizonu na ekranie Obrona (zadanie Garnizon Dworu, DefensePlan.Task
-- GARRISON = 6). Garnizon broni donżonu z premią wytrzymałości i nie idzie do ataku. Klient nie wysyła go
-- w armii, ale klient nie jest zaufany: `public.begin_attack` liczy wojsko atakującego z kopii zamku na
-- serwerze bez oddziałów, które w tej samej kopii (`castles.data -> 'defense' -> 'orders'`) mają zadanie
-- garnizonu. Armia ataku z jednostkami garnizonu daje więc `army_not_owned`, jak armia spoza zamku.
-- Reszta funkcji jest bez zmian względem migracji `army_limits`.
--
-- Pojemności garnizonu (4 jednostki za poziom Dworu) serwer nie sprawdza: oddział ponad pojemność też
-- zostaje w zamku (mniej wojska do ataku, nic za darmo), a premię w bitwie klient przycina do pojemności
-- z kopii zamku (DefensePlan.battle_garrison), tak samo u atakującego i w powtórce obrońcy.

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
  'Start ataku (#25, #249, #81): limit 10 startów na 10 minut, armia z zamku atakującego bez garnizonu Dworu (#81) w limicie miejsc i utrzymania żywności, cel bez tarczy i bez innego ataku w toku; zwraca seedy i kopie zamku i obrony. Tylko dla service_role (Edge Function start_attack).';

revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;
