-- #31: złoto i doświadczenie generałów muszą mieć pokrycie (klient nie jest zaufany).
--
-- Generałów werbuje i szkoli gra na telefonie (Dwór: rekrutacja za złoto, Wyszkol zużywa PD i złoto),
-- a zamek trafia na serwer w `castles.data`. Ekonomia jest na telefonie, więc serwer nie zna salda
-- złota, ale zna górną granicę tego, co gracz mógł zdobyć:
--   złoto: START (50) + nagrody 5 fal PvE (10 + 15 + 20 + 30 + 50 = 125) + złoto z łupów zakończonych
--          ataków gracza (`attacks.loot[4]`, liczy je i ogranicza `end_attack`);
--   PD:    najwyżej 40 za bitwę (XP_BATTLE + XP_WIN) z zakończonych ataków gracza i 5 fal PvE.
-- Przed każdym zapisem zamku wyzwalacz przerabia `data -> generals`: generałowie po kolei kosztują
-- rekrutację (300) i awanse (poziom 2: 400, poziom 3: 1000 złota oraz 100 i 300 PD). Generał, na którego
-- nie starcza złota, traci poziomy albo znika (i wszyscy po nim), a poziomy bez pokrycia w PD spadają.
-- Do PvP (`launch_attack` → `private.castle_general`) i do kopii obrony trafiają więc tylko generałowie
-- z pokryciem. Złoto wydane na inne rzeczy (np. zwiad) nie jest tu odejmowane: to górna granica, nie saldo.
-- Liczby jak w grze (Generals, EconomyConfig.START, PveWaves.REWARDS); test_generals.gd pilnuje zgodności.

create function private.checked_generals(p_player uuid, p_generals jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gold bigint;
  v_battles bigint;
  v_xp_cap bigint;
  v_spent bigint := 0;
  v_out jsonb := '[]'::jsonb;
  v_seen integer[] := '{}';
  e jsonb;
  v_kind integer;
  v_level integer;
  v_xp bigint;
  v_perk integer;
  v_attack integer;
  v_cost bigint;
  v_xp_spent bigint;
begin
  if p_generals is null or jsonb_typeof(p_generals) <> 'object' then
    return jsonb_build_object('roster', '[]'::jsonb, 'attack', -1);
  end if;
  select coalesce(sum(coalesce(a.loot[4], 0)), 0), count(*) into v_gold, v_battles
  from public.attacks a
  where a.attacker_id = p_player and a.status = 'finished';
  v_gold := v_gold + 50 + 125;
  v_xp_cap := (v_battles + 5) * 40;

  for e in
    select x.v from jsonb_array_elements(case when jsonb_typeof(p_generals -> 'roster') = 'array'
        then p_generals -> 'roster' else '[]'::jsonb end) with ordinality as x(v, ord)
    order by x.ord
  loop
    exit when jsonb_array_length(v_out) >= 3;
    if jsonb_typeof(e) <> 'object' then
      continue;
    end if;
    v_kind := private.json_int(e -> 'kind', 0, 2)::integer;
    if v_kind is null or v_kind = any (v_seen) then
      continue;
    end if;
    -- złoto: rekrutacja, potem awanse, póki starcza
    exit when v_spent + 300 > v_gold;
    v_level := coalesce(private.json_int(e -> 'level', 1, 3), 1)::integer;
    v_cost := 300;
    if v_level >= 2 then
      if v_spent + v_cost + 400 > v_gold then
        v_level := 1;
      else
        v_cost := v_cost + 400;
      end if;
    end if;
    if v_level >= 3 then
      if v_spent + v_cost + 1000 > v_gold then
        v_level := 2;
      else
        v_cost := v_cost + 1000;
      end if;
    end if;
    -- PD: zużyte na awanse i niewydane razem najwyżej tyle, ile dały bitwy
    v_xp := coalesce(private.json_int(e -> 'xp', 0, 300), 0);
    loop
      v_xp_spent := case when v_level >= 2 then 100 else 0 end + case when v_level >= 3 then 300 else 0 end;
      exit when v_xp_spent <= v_xp_cap or v_level = 1;
      v_cost := v_cost - case when v_level = 3 then 1000 else 400 end;
      v_level := v_level - 1;
    end loop;
    v_xp := least(v_xp, greatest(0, v_xp_cap - v_xp_spent));
    v_perk := case when v_level >= 3 then coalesce(private.json_int(e -> 'perk', 0, 1), -1)::integer else -1 end;
    v_spent := v_spent + v_cost;
    v_seen := v_seen || v_kind;
    v_out := v_out || jsonb_build_array(jsonb_build_object('kind', v_kind, 'level', v_level, 'xp', v_xp,
      'perk', v_perk));
  end loop;

  v_attack := private.json_int(p_generals -> 'attack', 0, 2)::integer;
  if v_attack is null or not (v_attack = any (v_seen)) then
    v_attack := -1;
  end if;
  return jsonb_build_object('roster', v_out, 'attack', v_attack);
end;
$$;

comment on function private.checked_generals(uuid, jsonb) is
  'Generałowie z zapisu zamku przycięci do złota i PD, które gracz mógł zdobyć według serwera (#31).';
revoke all on function private.checked_generals(uuid, jsonb) from public, anon, authenticated;

-- Przed zapisem zamku: generałowie tylko z pokryciem. SECURITY DEFINER (przez checked_generals), bo gracz
-- zapisuje jako `authenticated` i nie czyta wszystkich kolumn `attacks`; liczy tylko ataki właściciela
-- zapisywanego zamku (new.player_id, którego RLS nie pozwala zmienić). Zapis bez generałów zostaje bez nich.
create function private.check_castle_generals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.data ? 'generals' then
    new.data := jsonb_set(new.data, '{generals}', private.checked_generals(new.player_id, new.data -> 'generals'));
  end if;
  return new;
end;
$$;

revoke all on function private.check_castle_generals() from public, anon, authenticated;

create trigger castles_check_generals
  before insert or update of data on public.castles
  for each row execute function private.check_castle_generals();
