-- #31: złoto i doświadczenie generałów muszą mieć pokrycie (klient nie jest zaufany).
--
-- Generałów werbuje i szkoli gra na telefonie (Dwór: rekrutacja za złoto, Wyszkol zużywa PD i złoto),
-- a zamek trafia na serwer w `castles.data`. Ekonomia jest na telefonie, więc serwer nie zna salda
-- złota, ale zna górną granicę tego, co gracz mógł zdobyć. Głównym źródłem jest PvP (decyzja
-- właścicielki): boty i fale PvE wystarczają najwyżej na rekrutację i jeden awans (poziom 2), a poziom 3
-- wymaga PD i złota z PvP.
--   złoto ogółem: START (50) + nagrody 5 fal PvE (10 + 15 + 20 + 30 + 50 = 125) + złoto z łupów
--                 zakończonych ataków gracza (`attacks.loot[4]`, liczy je i ogranicza `end_attack`);
--   złoto z PvP:  tylko łupy z ataków na graczy (`defender_id` nie jest null);
--   PD ogółem:    najwyżej 40 za bitwę (XP_BATTLE + XP_WIN) z zakończonych ataków i 5 fal PvE;
--   PD z PvP:     najwyżej 40 za zakończony atak na gracza.
-- Obie pule PD są wspólne dla wszystkich generałów (jak złoto): PD z jednej bitwy dostaje jeden generał,
-- więc zużyte i niewydane PD przyjętego generała zmniejszają pulę dla kolejnych.
-- Przed każdym zapisem zamku wyzwalacz przerabia `data -> generals`: generałowie po kolei kosztują
-- rekrutację (50) i awanse (poziom 2: 80 złota i 100 PD, poziom 3: 150 złota z PvP i 300 PD z PvP).
-- Generał, na którego nie starcza złota, traci poziomy albo znika (i wszyscy po nim), a poziomy bez
-- pokrycia w PD spadają. Do PvP (`launch_attack` → `private.castle_general`) i do kopii obrony trafiają
-- więc tylko generałowie z pokryciem. Złoto wydane na inne rzeczy (np. zwiad) nie jest tu odejmowane:
-- to górna granica, nie saldo. Liczby jak w grze (Generals, EconomyConfig.START, PveWaves.REWARDS);
-- test_generals.gd pilnuje zgodności.

create function private.checked_generals(p_player uuid, p_generals jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_gold bigint;
  v_pvp_gold bigint;
  v_battles bigint;
  v_pvp_battles bigint;
  v_xp_cap bigint;
  v_pvp_xp_cap bigint;
  v_spent bigint := 0;
  v_pvp_spent bigint := 0;
  v_out jsonb := '[]'::jsonb;
  v_seen integer[] := '{}';
  e jsonb;
  v_kind integer;
  v_level integer;
  v_xp bigint;
  v_perk integer;
  v_attack integer;
  v_cost bigint;
begin
  if p_generals is null or jsonb_typeof(p_generals) <> 'object' then
    return jsonb_build_object('roster', '[]'::jsonb, 'attack', -1);
  end if;
  select coalesce(sum(coalesce(a.loot[4], 0)), 0),
    coalesce(sum(coalesce(a.loot[4], 0)) filter (where a.defender_id is not null), 0),
    count(*), count(*) filter (where a.defender_id is not null)
  into v_gold, v_pvp_gold, v_battles, v_pvp_battles
  from public.attacks a
  where a.attacker_id = p_player and a.status = 'finished';
  v_gold := v_gold + 50 + 125;
  v_xp_cap := (v_battles + 5) * 40;
  v_pvp_xp_cap := v_pvp_battles * 40;

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
    -- rekrutacja: bez złota na nią ten i kolejni generałowie odpadają
    exit when v_spent + 50 > v_gold;
    v_cost := 50;
    v_level := coalesce(private.json_int(e -> 'level', 1, 3), 1)::integer;
    -- v_xp_cap i v_pvp_xp_cap to PD jeszcze nieprzydzielone: każdy przyjęty generał je zmniejsza (review #273),
    -- bo PD z jednej bitwy dostaje jeden generał. PD z PvP liczą się w obu pulach.
    -- poziom 2: złoto ogółem i 100 PD z dowolnych bitew
    if v_level >= 2 and (v_spent + v_cost + 80 > v_gold or v_xp_cap < 100) then
      v_level := 1;
    elsif v_level >= 2 then
      v_cost := v_cost + 80;
    end if;
    -- poziom 3: 150 złota z PvP (też w złocie ogółem) i 300 PD z PvP (też w PD ogółem, po poziomie 2)
    if v_level >= 3 and (v_spent + v_cost + 150 > v_gold or v_pvp_spent + 150 > v_pvp_gold
        or v_pvp_xp_cap < 300 or v_xp_cap - 100 < 300) then
      v_level := 2;
    elsif v_level >= 3 then
      v_cost := v_cost + 150;
      v_pvp_spent := v_pvp_spent + 150;
    end if;
    v_xp_cap := v_xp_cap - case when v_level >= 2 then 100 else 0 end - case when v_level >= 3 then 300 else 0 end;
    v_pvp_xp_cap := v_pvp_xp_cap - case when v_level >= 3 then 300 else 0 end;
    -- niewydane PD: na poziomie 1 z dowolnych bitew, wyżej boty już ich nie dają (tylko PvP)
    v_xp := coalesce(private.json_int(e -> 'xp', 0, 300), 0);
    if v_level = 1 then
      v_xp := least(v_xp, v_xp_cap);
    else
      v_xp := least(v_xp, v_pvp_xp_cap, v_xp_cap);
      v_pvp_xp_cap := v_pvp_xp_cap - v_xp;
    end if;
    v_xp_cap := v_xp_cap - v_xp;
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
  return jsonb_build_object('roster', v_out, 'attack', v_attack, 'pvp_gold',
    least(coalesce(private.json_int(p_generals -> 'pvp_gold', 0, 10000000), 0), greatest(0, v_pvp_gold - v_pvp_spent)));
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
