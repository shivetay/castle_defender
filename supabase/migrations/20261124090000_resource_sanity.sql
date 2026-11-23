-- #274 (etapy 1 i 2): surowce w `castles.data` bez zaufanej edycji lokalnej.
--
-- Ekonomię nalicza telefon, a serwer czyta `castles.data -> economy -> amounts` jako prawdę przy ataku
-- (limit łupu z kopii obrońcy). Klient nie jest zaufany, więc:
--
-- Etap 1, sanity przy każdym zapisie zamku (wyzwalacz `castles_resources`, INSERT i UPDATE `data`):
-- - `economy.amounts` to dokładnie 4 liczby całkowite 0..MAX_AMOUNT = 10000000 w kolejności EconomyConfig.Res
--   (drewno, kamień, żywność, złoto). Zapis bez `economy` przechodzi (nic nie wnosi do PvP);
-- - drewno, kamień i żywność najwyżej do pojemności magazynów z tego samego zapisu (Economy.capacities_for):
--   CAPACITY = [1000, 1000, 1000, 0] z Dworu plus każdy ukończony Magazyn (WAREHOUSE = 25) według poziomu
--   WAREHOUSE_CAPACITY = [500, 750, 1000, 1500, 2000]. Budynki czyta `private.castle_buildings` (poziom 0..5,
--   plac budowy nic nie mieści), jak limit armii;
-- - złoto nie ma magazynu, więc ma wymóg źródła (decyzja właścicielki, #274): najwyżej tyle, ile gracz mógł
--   zdobyć według serwera, czyli `private.ruler_gold_left` (start 50 + nagrody fal PvE 125 + łupy złota
--   z zakończonych ataków na serwerze, minus generałowie z tego zapisu i płatne zmiany perka władcy).
--   Złoto z wyprawy na zamek-bota gra dolicza tylko po przyjęciu wyniku przez serwer (#274);
-- - zapis spoza tych granic jest odrzucany w całości kodem HTTP 422 (SQLSTATE PT422), bez cichego
--   przycinania; telefon przywraca wtedy zamek z serwera (SupabaseClient). Kod w treści błędu:
--   bad_economy, over_capacity albo gold_unbacked;
-- - rate limit: najwyżej PUSH_LIMIT = 90 zapisów zamku (UPDATE) w oknie 10 minut, liczonych zegarem serwera
--   w `castles.push_window_at` i `castles.push_count`. Gra zapisuje najwyżej co PUSH_INTERVAL_S = 15 sekund
--   (40 na 10 minut) i od razu przy wyjściu albo przed atakiem. Ponad limit: HTTP 429 (SQLSTATE PT429),
--   a telefon ponawia po przerwie;
-- - `public.begin_attack` nie wpuszcza do PvP zamku, który nie przechodzi tych samych reguł (zapis sprzed
--   migracji): atakujący dostaje `castle_invalid`, a taki obrońca nie jest celem (`target_not_found`).
--
-- Etap 2, łup PvP na serwerze: `public.end_attack` po przyjęciu wyniku ataku na gracza zapisuje w tej samej
-- transakcji +łup atakującemu i -łup obrońcy w `public.castle_loot_pending` (zmiana, której telefon jeszcze
-- nie zna). Wyzwalacz zapisu zamku scala ją z `economy.amounts` (drewno, kamień i żywność w 0..pojemność,
-- złoto od 0), kasuje wiersz i zwraca faktycznie dodaną zmianę w `castles.loot_applied`, którą telefon
-- dolicza u siebie (CastleSync.loot_from_rows). Nie zmieniamy `castles.data` od razu w `end_attack`, bo nowa
-- rewizja zamku przegrałaby z zapisem z telefonu (konflikt i przywrócenie starszego zamku z serwera, #23).
-- Ponowienie `finish_attack` łupu nie dubluje (zakończony atak wraca od razu), a zgubiona odpowiedź na zapis
-- kończy się konfliktem rewizji i przywróceniem zamku z serwera, który ma już scalony łup.
-- Kopia obrońcy do bitwy (`begin_attack`) bierze zapasy razem z czekającym łupem, więc tych samych zapasów
-- nie da się złupić dwa razy, zanim telefon obrońcy je scali.
-- Wyprawy na zamki-boty zostają po staremu: drewno, kamień i żywność dolicza gra (limit to pojemność),
-- a złoto tylko z odpowiedzi serwera.
--
-- Zamki zapisane przed migracją, które łamią limity, dostają raz zapasy przycięte do pojemności i do złota
-- z pokryciem (jedyny wyjątek od zasady „bez przycinania”; dotyczy stanu sprzed reguł).
-- Liczby pilnuje test gry (`tests/test_resource_sanity.gd`) po znacznikach w komentarzach.

-- ---------------------------------------------------------------------------------------------
-- Kolumny i tabela łupu czekającego
-- ---------------------------------------------------------------------------------------------

-- Klient ma uprawnienia do zapisu wyłącznie `save_version` i `data` (migracja init), więc nowych kolumn
-- nie ustawi; czyta je razem z własnym wierszem (`loot_applied` w odpowiedzi na zapis).
alter table public.castles
  add column loot_applied integer[] not null default '{0, 0, 0, 0}'
    check (cardinality(loot_applied) = 4),
  add column push_window_at timestamptz,
  add column push_count integer not null default 0 check (push_count >= 0);

comment on column public.castles.loot_applied is
  'Łup PvP scalony z economy.amounts w ostatnim zapisie zamku (#274): telefon dolicza tę zmianę u siebie. Zmienia tylko wyzwalacz.';
comment on column public.castles.push_window_at is
  'Początek okna rate limitu zapisów zamku (#274), zegar serwera. Zmienia tylko wyzwalacz.';
comment on column public.castles.push_count is
  'Liczba zapisów zamku w bieżącym oknie rate limitu (#274). Zmienia tylko wyzwalacz.';

create table public.castle_loot_pending (
  player_id uuid primary key references public.players (id) on delete cascade,
  -- zmiana zapasów w kolejności EconomyConfig.Res: dodatnia u atakującego, ujemna u obrońcy
  amounts bigint[] not null check (cardinality(amounts) = 4),
  updated_at timestamptz not null default now()
);
comment on table public.castle_loot_pending is
  'Łup PvP, który telefon gracza jeszcze nie scalił (#274). Zapisuje end_attack, scala wyzwalacz zapisu zamku; klient nie ma dostępu.';

alter table public.castle_loot_pending enable row level security;
revoke all on public.castle_loot_pending from anon, authenticated;
grant select, insert, update, delete on public.castle_loot_pending to service_role;
-- bez polityk dla anon i authenticated: klient nie czyta ani nie pisze tej tabeli

-- ---------------------------------------------------------------------------------------------
-- Funkcje pomocnicze (schemat private)
-- ---------------------------------------------------------------------------------------------

-- Pojemność drewna, kamienia i żywności z zapisu zamku (Economy.capacities_for).
create function private.castle_capacity(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (1000 + coalesce((select sum((array[500, 750, 1000, 1500, 2000])[b.level])
      from private.castle_buildings(p_castle) b where b.kind = 25 and b.level >= 1), 0))::integer
$$;

-- Kod problemu z surowcami w zapisie zamku albo null (zapis w granicach albo bez `economy`).
-- `p_paid`: płatne zmiany perka władcy (`castles.ruler_perk_paid`) do budżetu złota.
create function private.castle_resources_problem(p_player uuid, p_castle jsonb, p_paid integer)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_economy jsonb := p_castle -> 'economy';
  v_amounts jsonb;
  v_cap integer;
  x bigint;
begin
  if v_economy is null then
    return null;
  end if;
  v_amounts := v_economy -> 'amounts';
  if jsonb_typeof(v_economy) <> 'object' or jsonb_typeof(v_amounts) is distinct from 'array'
      or jsonb_array_length(v_amounts) <> 4 then
    return 'bad_economy';
  end if;
  v_cap := private.castle_capacity(p_castle);
  for i in 0 .. 3 loop
    x := private.json_int(v_amounts -> i, 0, 10000000);
    if x is null then
      return 'bad_economy';
    end if;
    if i < 3 and x > v_cap then
      return 'over_capacity';
    end if;
    if i = 3 and x > private.ruler_gold_left(p_player, p_castle -> 'generals', p_paid) then
      return 'gold_unbacked';
    end if;
  end loop;
  return null;
end;
$$;

-- Zapasy z czekającym łupem gracza (bez kasowania wiersza): drewno, kamień i żywność w 0..pojemność,
-- złoto od 0. Zapis bez poprawnego `economy.amounts` zostaje bez zmian.
create function private.amounts_with_delta(p_castle jsonb, p_delta bigint[])
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_amounts jsonb := p_castle -> 'economy' -> 'amounts';
  v_cap integer;
  v_out jsonb := '[]'::jsonb;
  x bigint;
begin
  if p_delta is null or jsonb_typeof(v_amounts) is distinct from 'array' or jsonb_array_length(v_amounts) <> 4 then
    return v_amounts;
  end if;
  v_cap := private.castle_capacity(p_castle);
  for i in 0 .. 3 loop
    x := private.json_int(v_amounts -> i, 0, 10000000);
    if x is null then
      return v_amounts;
    end if;
    x := greatest(x + coalesce(p_delta[i + 1], 0), 0);
    if i < 3 then
      x := least(x, v_cap);
    end if;
    v_out := v_out || to_jsonb(least(x, 10000000));
  end loop;
  return v_out;
end;
$$;

-- Kopia zamku do bitwy z łupem, którego telefon jeszcze nie scalił.
create function private.castle_with_pending(p_player uuid, p_castle jsonb)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select case when p.amounts is null or jsonb_typeof(p_castle -> 'economy') is distinct from 'object' then p_castle
    else jsonb_set(p_castle, '{economy,amounts}', private.amounts_with_delta(p_castle, p.amounts)) end
  from (select (select l.amounts from public.castle_loot_pending l where l.player_id = p_player) as amounts) p
$$;

-- Dopisuje zmianę zapasów do łupu czekającego gracza (wołane z end_attack).
create function private.add_loot_pending(p_player uuid, p_delta bigint[])
returns void
language sql
volatile
set search_path = ''
as $$
  insert into public.castle_loot_pending as l (player_id, amounts) values (p_player, p_delta)
  on conflict (player_id) do update set
    amounts = array[l.amounts[1] + excluded.amounts[1], l.amounts[2] + excluded.amounts[2],
      l.amounts[3] + excluded.amounts[3], l.amounts[4] + excluded.amounts[4]],
    updated_at = now()
$$;

revoke all on function private.castle_capacity(jsonb) from public, anon, authenticated;
revoke all on function private.castle_resources_problem(uuid, jsonb, integer) from public, anon, authenticated;
revoke all on function private.amounts_with_delta(jsonb, bigint[]) from public, anon, authenticated;
revoke all on function private.castle_with_pending(uuid, jsonb) from public, anon, authenticated;
revoke all on function private.add_loot_pending(uuid, bigint[]) from public, anon, authenticated;
-- begin_attack i end_attack wołają je jako service_role (Edge Functions)
grant execute on function private.castle_capacity(jsonb) to service_role;
grant execute on function private.castle_resources_problem(uuid, jsonb, integer) to service_role;
grant execute on function private.amounts_with_delta(jsonb, bigint[]) to service_role;
grant execute on function private.castle_with_pending(uuid, jsonb) to service_role;
grant execute on function private.add_loot_pending(uuid, bigint[]) to service_role;
grant execute on function private.ruler_gold_left(uuid, jsonb, integer) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Zamki sprzed migracji
-- ---------------------------------------------------------------------------------------------

-- Jednorazowo: zapasy ponad pojemność i złoto bez pokrycia przycięte do granic (przed wyzwalaczem,
-- żeby te zamki dało się potem zapisywać i atakować). Zły kształt `economy` zostaje: taki zamek nie
-- wejdzie do PvP, dopóki gra nie zapisze go od nowa.
update public.castles c
set data = jsonb_set(c.data, '{economy,amounts}', (
    select jsonb_agg(case when i < 3 then least(private.json_int(c.data -> 'economy' -> 'amounts' -> i, 0, 10000000),
        private.castle_capacity(c.data))
      else least(private.json_int(c.data -> 'economy' -> 'amounts' -> i, 0, 10000000),
        greatest(private.ruler_gold_left(c.player_id, c.data -> 'generals', c.ruler_perk_paid), 0)) end
      order by i)
    from generate_series(0, 3) as i))
where private.castle_resources_problem(c.player_id, c.data, c.ruler_perk_paid) in ('over_capacity', 'gold_unbacked');

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacz zapisu zamku
-- ---------------------------------------------------------------------------------------------

-- Przed zapisem zamku: rate limit, sanity zapasów z telefonu, scalenie łupu PvP i sanity złota po scaleniu.
-- SECURITY DEFINER, bo gracz zapisuje jako `authenticated`, a ta rola nie ma dostępu do castle_loot_pending
-- ani do wszystkich kolumn `attacks` (budżet złota); dotyczy tylko właściciela zapisywanego zamku
-- (new.player_id, którego RLS i bump_revision nie pozwalają zmienić). Nazwa `castles_resources` sortuje się
-- po `castles_check_generals` i `castles_check_ruler_perk`, więc wyzwalacz widzi już przyciętych generałów
-- i płatne zmiany perka z tego zapisu.
create function private.check_castle_resources()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem text;
  v_pending bigint[];
  v_before jsonb;
  v_after jsonb;
  v_applied integer[] := array[0, 0, 0, 0];
begin
  -- PUSH_LIMIT = 90 zapisów w 10 minut; odrzucony zapis cofa też licznik
  if tg_op = 'UPDATE' then
    if old.push_window_at is null or old.push_window_at <= now() - interval '10 minutes' then
      new.push_window_at := now();
      new.push_count := 1;
    else
      new.push_window_at := old.push_window_at;
      new.push_count := old.push_count + 1;
      if new.push_count > 90 then
        raise exception 'castle_rate_limited' using errcode = 'PT429';
      end if;
    end if;
  end if;

  -- zapasy z telefonu: kształt i pojemność; złoto sprawdzamy dopiero po scaleniu łupu
  v_problem := private.castle_resources_problem(new.player_id, new.data, new.ruler_perk_paid);
  if v_problem in ('bad_economy', 'over_capacity') then
    raise exception '%', v_problem using errcode = 'PT422';
  end if;

  if new.data ? 'economy' then
    delete from public.castle_loot_pending l where l.player_id = new.player_id returning l.amounts into v_pending;
    if v_pending is not null then
      v_before := new.data -> 'economy' -> 'amounts';
      v_after := private.amounts_with_delta(new.data, v_pending);
      new.data := jsonb_set(new.data, '{economy,amounts}', v_after);
      for i in 0 .. 3 loop
        v_applied[i + 1] := ((v_after ->> i)::numeric - (v_before ->> i)::numeric)::integer;
      end loop;
    end if;
    v_problem := private.castle_resources_problem(new.player_id, new.data, new.ruler_perk_paid);
    if v_problem is not null then
      raise exception '%', v_problem using errcode = 'PT422';
    end if;
  end if;
  new.loot_applied := v_applied;
  return new;
end;
$$;

revoke all on function private.check_castle_resources() from public, anon, authenticated;

create trigger castles_resources
  before insert or update of data on public.castles
  for each row execute function private.check_castle_resources();

-- ---------------------------------------------------------------------------------------------
-- Start ataku (#25, #249, #81) z sanity zamków i kopią obrońcy z czekającym łupem. Reszta bez zmian
-- względem `*_garrison.sql`.
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
  'Start ataku (#25, #249, #81, #274): limit 10 startów na 10 minut, zamek atakującego i obrońcy w limitach surowców (#274), armia z zamku atakującego bez garnizonu Dworu w limicie miejsc i utrzymania żywności, cel bez tarczy i bez innego ataku w toku; zwraca seedy, kopię zamku z czekającym łupem i obronę. Tylko dla service_role (Edge Function start_attack).';

revoke all on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) from public, anon, authenticated;
grant execute on function public.begin_attack(uuid, uuid, smallint, jsonb, bigint) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Koniec ataku (#25, #32) z łupem PvP przeniesionym przez serwer. Reszta bez zmian względem
-- `*_ruler_perk.sql`.
-- ---------------------------------------------------------------------------------------------

create or replace function public.end_attack(p_attacker uuid, p_attack uuid, p_result jsonb, p_loot jsonb,
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
    -- Łupieżca (#32): LOOTER_LOOT_PERCENT = 115 tylko przy ataku na gracza, z perkiem zapisanym przy
    -- zatwierdzeniu planu (attacks.attacker_ruler_perk); dzielenie całkowite jak RulerPerks.pvp_loot
    if a.defender_id is not null and a.attacker_ruler_perk = 1 then
      v_cap := v_cap * 115 / 100;
    end if;
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

  -- #274: łup z ataku na gracza przenosi serwer w tej samej transakcji: obrońca traci, atakujący zyskuje.
  -- Zmiana czeka w castle_loot_pending i wchodzi do `castles.data` przy najbliższym zapisie zamku każdego
  -- z nich (wyzwalacz castles_resources). Ponowienie wraca wyżej (status 'finished'), więc łup liczy się raz.
  if a.defender_id is not null and v_sum > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
    perform private.add_loot_pending(a.defender_id,
      array[-v_loot[1], -v_loot[2], -v_loot[3], -v_loot[4]]::bigint[]);
  end if;

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
  'Koniec ataku (#25): wynik i łup w limitach (zapasy obrońcy, capacity ocalałych, Łupieżca #32), łup PvP przeniesiony między zamkami przez castle_loot_pending (#274), tarcza 8 h od 30 procent zniszczeń; ponowienie zwraca zapisany wynik. Tylko dla service_role (Edge Function finish_attack).';
revoke all on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) to service_role;
