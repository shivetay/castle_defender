-- #282 (etap 3 z #274): przyrost i spadek surowców między zapisami zamku liczy serwer.
--
-- Po #278 serwer pilnował tylko granic zapasów (pojemność magazynów, złoto z pokryciem). Zmodyfikowany klient
-- mógł w nich ustawić dowolny stan: pełny magazyn w każdej chwili, budowa i badania bez płacenia albo zera
-- tuż przed najazdem (obrońca chowa łup). Teraz każdy zapis zamku z tokenem gracza (rola `authenticated`
-- albo `anon`, jak w #279) przechodzi przez bilans każdego surowca od poprzedniego zapisu na zegarze
-- serwera. Zapis spoza bilansu jest odrzucany w całości kodem HTTP 422 (SQLSTATE PT422), bez przycinania
-- (decyzja właścicielki, #282); telefon przywraca wtedy zamek z serwera (SupabaseClient, #274 etap 1).
--
-- Limit przyrostu (kod economy_too_fast): przyrost zapasu plus wydatki widoczne w zapisie nie może być
-- większy niż produkcja w tym czasie, nagrody fal PvE i zwroty za anulowane zlecenia budowy.
-- - Produkcja to górna granica Economy.rates z budynków obu zapisów (każdy budynek na wyższym z dwóch
--   poziomów, poziomy 1..5, ruiny po ataku bez kary): gród BASE_PER_HOUR = [20, 20, 20, 0], Chata drwala
--   LUMBER_HUT = 4 drewno, Rybak FISHER = 16 żywność, Pole FARM = 28 żywność, Kamieniołom QUARRY = 30 kamień
--   ze stawkami PRODUCTION = {"4": [0, [60, 90, 120, 160, 200]], "16": [2, [40, 60, 80, 110, 140]], "28": [2, [60, 90, 120, 160, 200]], "30": [1, [40, 60, 80, 110, 140]]},
--   razy premie technologii PRODUCTION_BONUS = {"G1": [0, 20], "G2": [2, 15]} i perka Gospodarny
--   (THRIFTY = 3, +10 punktów procentowych), gdy są w którymkolwiek z dwóch zapisów, z dzieleniem całkowitym.
--   Do tego żywność z Chaty myśliwego (HUNTER = 6, przepis GoodsConfig.RECIPES[0]: HUNTER_FOOD = 2 na cykl,
--   6 cykli na godzinę razy LEVEL_PERCENT). Stawka razy czas od poprzedniego zapisu.
-- - Wydatki (dolna granica, liczy je serwer z zapisu, nie z kosztów wpisanych przez telefon):
--   - budowa: każdy poziom budynku albo zlecenie w kolejce (`queue.orders`, id i poziom), których nie było
--     w poprzednim zapisie, po BuildConfig.cost: BUILD_COST = {"0": [10, 0, 10, 0], "1": [20, 0, 5, 0], "2": [60, 20, 20, 0], "3": [120, 40, 40, 0], "4": [80, 0, 30, 0], "6": [60, 0, 20, 0], "7": [80, 20, 20, 0], "8": [100, 20, 30, 0], "9": [80, 20, 20, 0], "10": [60, 0, 20, 0], "11": [100, 0, 30, 0], "12": [80, 10, 20, 0], "13": [90, 0, 30, 0], "14": [60, 40, 10, 0], "15": [30, 0, 20, 0], "16": [70, 0, 10, 0], "17": [100, 20, 40, 0], "18": [100, 20, 40, 0], "19": [140, 30, 40, 0], "20": [120, 10, 40, 0], "21": [150, 60, 40, 0], "22": [120, 20, 40, 10], "24": [100, 40, 30, 0], "25": [100, 40, 0, 0], "26": [5, 0, 15, 0], "27": [60, 40, 40, 0], "28": [60, 0, 20, 0], "29": [40, 30, 10, 0], "30": [100, 0, 30, 0], "31": [100, 20, 30, 0]}
--     z COST_PERCENT = [100, 150, 250, 400, 600] i AGE_COST_PERCENT = [100, 200],
--     a Dwór MANOR_COST = [[0, 0, 0, 0], [300, 200, 200, 0], [500, 350, 350, 0], [750, 550, 550, 0], [1000, 800, 800, 0], [1000, 1000, 1000, 0], [600, 400, 400, 0], [1000, 700, 700, 0], [1500, 1100, 1100, 0], [2000, 1600, 1600, 0]];
--   - badania: technologie zbadane albo w toku (`research.active`), których nie było, po ResearchConfig.cost:
--     RESEARCH_BASE_COST = [[100, 50, 50, 0], [400, 300, 200, 0]] razy COST_STEP_PERCENT = 160 procent (dzielenie
--     całkowite) za każdą wcześniej rozpoczętą technologię tej samej epoki;
--   - rekrutacja: jednostki wyszkolone, na zwiadzie i w szkoleniu ponad poprzedni zapis, po UnitTypes.resource_cost:
--     UNIT_COST = [[0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 15, 0], [0, 0, 15, 0], [0, 0, 10, 0], [0, 0, 15, 0], [0, 0, 10, 0], [0, 0, 20, 0], [60, 0, 0, 0], [0, 0, 10, 0], [0, 0, 5, 0], [0, 0, 15, 0], [40, 0, 0, 0]];
--   - pułapki: ponad poprzedni zapis każdego rodzaju (`defense.traps`), po TRAP_COST = [[30, 0, 10, 0], [20, 20, 0, 0], [50, 0, 0, 0], [20, 0, 0, 0], [40, 0, 0, 0]];
--   - zwiad: nowa misja (poprzedni zapis bez misji) po SCOUT_COST = [0, 0, 10, 10] za zwiadowcę;
--   - złoto: generałowie ponad poprzedni zapis (50, awans 80 i 150, jak `private.ruler_gold_left`)
--     i płatne zmiany perka władcy (50 za każdą, `castles.ruler_perk_paid`).
-- - Nagrody fal PvE (PveWaves.REWARDS = [[100, 50, 100, 10], [150, 100, 150, 15], [200, 150, 200, 20], [300, 200, 300, 30], [500, 300, 500, 50]])
--   tylko za fale, których serwer jeszcze nie nagrodził (`castles.pve_rewarded`, najwyższe `pve.cleared`
--   z przyjętych zapisów), więc cofnięcie licznika fal nie daje nagrody drugi raz.
-- - Zwroty: koszt zleceń z poprzedniej kolejki, które zniknęły bez nowego poziomu (anulowanie oddaje całość).
--
-- Limit spadku (kod economy_hidden): zapas nie może spaść bardziej, niż wyjaśniają wydatki (te same co wyżej),
-- zużycie w tym czasie i mniejszy magazyn. Zużycie to górna granica: utrzymanie wojska (wyszkoleni, zwiad
-- i szkolenie, wyższa z dwóch zapisów armia, `private.unit_upkeep`) i wejścia surowców wytwórców
-- (GoodsConfig.RECIPES, budynki na wyższym z dwóch poziomów):
--   GOODS_INPUTS = [[9, 1, 3, {"0": 3, "1": 1}], [9, 1, 3, {"0": 2, "1": 1}], [9, 1, 2, {"0": 2, "1": 2}], [9, 1, 2, {"0": 5, "1": 1}], [11, 1, 2, {"0": 3}], [11, 3, 1, {"0": 4}], [12, 1, 3, {"0": 1}], [8, 1, 2, {"0": 1}], [8, 1, 2, {"0": 2}], [13, 1, 2, {"0": 1}], [14, 1, 3, {"0": 4}], [17, 1, 1, {"2": 10}]]
--   ([budynek, od poziomu, cykle na godzinę, {surowiec: ilość}]). Głód (#214) mieści się w utrzymaniu,
--   a strata z najazdu (#274) wchodzi przez `castle_loot_pending` dopiero po tym bilansie. Mniejszy magazyn:
--   zapas z poprzedniego zapisu liczy się najwyżej do pojemności z bieżącego (rozebrany Magazyn).
--   Wydatki, których zapis nie pokazuje (pułapka postawiona i zdjęta, jednostka wyszkolona i polegla między
--   zapisami), mieszczą się w zapasie HIDE_SLACK = [100, 100, 100, 20] plus 5 minut produkcji i zużycia.
--   Ten zapas odnawia się w godzinę (`castles.hide_credit`), więc chowanie po trochu co zapis też jest limitowane.
--   Zapis gracza bez `economy`, gdy poprzedni ją miał, to economy_missing: inaczej zamek bez zapasów nie dałby łupu.
--
-- Czas i tolerancja jak w #279 i #281: czas od poprzedniego zapisu na zegarze serwera (`old.updated_at`) plus
-- kredyt z poprzedniego zapisu (`castles.economy_credit`, zmienia go tylko wyzwalacz). Kredyt może zejść do
-- -TOLERANCE = 5 minut produkcji danego surowca plus ROUND_SLACK = 2 sztuki (zaokrąglenia) łącznie, nie na każdy
-- zapis (decyzja właścicielki, #282); niewykorzystana produkcja przechodzi najwyżej w tej samej wysokości, bo
-- pełny magazyn nie gromadzi zapasu. Pierwszy zapis zamku (INSERT) liczy od zapasów nowej gry
-- EconomyConfig.START = [500, 300, 300, 50] i czasu od założenia konta z zapasem INSERT_GRACE = 6 godzin.
--
-- Łup z zamków-botów (drewno, kamień, żywność i złoto) przenosi teraz serwer, jak łup PvP (decyzja właścicielki,
-- #282): `end_attack` dopisuje go do `castle_loot_pending` atakującego, a zapis zamku scala go po bilansie
-- i zwraca w `loot_applied`. Wyprawa bez sieci nic nie daje. Złoto ma ten sam bilans (produkcja 0), więc
-- obrońca po najeździe nie wypchnie złota z powrotem (review #278).
-- Liczby pilnuje test gry (`tests/test_economy_growth.gd`) po znacznikach w komentarzach.

-- ---------------------------------------------------------------------------------------------
-- Kolumny serwera
-- ---------------------------------------------------------------------------------------------

-- Klient ma uprawnienia do zapisu wyłącznie `save_version` i `data` (migracja init), więc ich nie ustawi.
alter table public.castles
  add column economy_credit bigint[] not null default '{0, 0, 0, 0}' check (cardinality(economy_credit) = 4),
  add column hide_credit bigint[] not null default '{0, 0, 0, 0}' check (cardinality(hide_credit) = 4),
  add column pve_rewarded smallint not null default 0 check (pve_rewarded between 0 and 5);

comment on column public.castles.economy_credit is
  'Kredyt produkcji (#282) dla każdego surowca: niewykorzystana produkcja najwyżej 5 minut, ujemny do -5 minut. Zmienia tylko wyzwalacz.';
comment on column public.castles.hide_credit is
  'Zapas na wydatki niewidoczne w zapisie (#282) dla każdego surowca, od 0 w dół, odnawia się w godzinę. Zmienia tylko wyzwalacz.';
comment on column public.castles.pve_rewarded is
  'Ile fal PvE serwer już wliczył do bilansu surowców (#282), najwyżej PveWaves.COUNT = 5. Zmienia tylko wyzwalacz.';

-- Zamki sprzed migracji: fale już wygrane mają nagrodę w zapasach. Bez bump_revision, żeby telefony nie dostały
-- konfliktu rewizji.
alter table public.castles disable trigger castles_bump_revision;
update public.castles c set pve_rewarded = coalesce(private.json_int(c.data -> 'pve' -> 'cleared', 0, 5), 0)
where coalesce(private.json_int(c.data -> 'pve' -> 'cleared', 0, 5), 0) > 0;
alter table public.castles enable trigger castles_bump_revision;

-- ---------------------------------------------------------------------------------------------
-- Funkcje pomocnicze (schemat private, tylko dla wyzwalacza)
-- ---------------------------------------------------------------------------------------------

-- Zapasy z zapisu (4 liczby 0..10000000) albo null przy braku albo złym kształcie `economy.amounts`.
create function private.economy_amounts(p_castle jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  select case when jsonb_typeof(p_castle -> 'economy' -> 'amounts') = 'array'
      and jsonb_array_length(p_castle -> 'economy' -> 'amounts') = 4
      and (select bool_and(private.json_int(p_castle -> 'economy' -> 'amounts' -> i, 0, 10000000) is not null)
        from generate_series(0, 3) i)
    then (select array_agg(private.json_int(p_castle -> 'economy' -> 'amounts' -> i, 0, 10000000) order by i)
      from generate_series(0, 3) i)
  end
$$;

-- Koszt poziomu `p_level` (narastająco, 1..10) budynku `p_kind` (BuildConfig.cost), w kolejności EconomyConfig.Res.
create function private.build_cost(p_kind bigint, p_level bigint)
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_lv integer := least(greatest(p_level, 1), 10)::integer;
  v_base jsonb;
  v_percent bigint;
begin
  if p_kind = 5 then
    return array(select (e #>> '{}')::bigint from jsonb_array_elements(
      ('[[0, 0, 0, 0], [300, 200, 200, 0], [500, 350, 350, 0], [750, 550, 550, 0], [1000, 800, 800, 0], [1000, 1000, 1000, 0], [600, 400, 400, 0], [1000, 700, 700, 0], [1500, 1100, 1100, 0], [2000, 1600, 1600, 0]]'::jsonb
        -> (v_lv - 1))) e);
  end if;
  v_base := '{"0": [10, 0, 10, 0], "1": [20, 0, 5, 0], "2": [60, 20, 20, 0], "3": [120, 40, 40, 0], "4": [80, 0, 30, 0], "6": [60, 0, 20, 0], "7": [80, 20, 20, 0], "8": [100, 20, 30, 0], "9": [80, 20, 20, 0], "10": [60, 0, 20, 0], "11": [100, 0, 30, 0], "12": [80, 10, 20, 0], "13": [90, 0, 30, 0], "14": [60, 40, 10, 0], "15": [30, 0, 20, 0], "16": [70, 0, 10, 0], "17": [100, 20, 40, 0], "18": [100, 20, 40, 0], "19": [140, 30, 40, 0], "20": [120, 10, 40, 0], "21": [150, 60, 40, 0], "22": [120, 20, 40, 10], "24": [100, 40, 30, 0], "25": [100, 40, 0, 0], "26": [5, 0, 15, 0], "27": [60, 40, 40, 0], "28": [60, 0, 20, 0], "29": [40, 30, 10, 0], "30": [100, 0, 30, 0], "31": [100, 20, 30, 0]}'::jsonb
    -> p_kind::text;
  if v_base is null then
    return array[0, 0, 0, 0]::bigint[];
  end if;
  v_percent := (array[100, 150, 250, 400, 600])[(v_lv - 1) % 5 + 1] * (array[100, 200])[(v_lv - 1) / 5 + 1];
  return array(select (v_base ->> i)::bigint * v_percent / 10000 from generate_series(0, 3) i order by i);
end;
$$;

-- Poziomy opłacone w zapisie: każdy poziom 1..poziom budynku i zlecenie z kolejki (id budynku z siatki i poziom).
create function private.build_paid(p_castle jsonb)
returns table (id bigint, kind bigint, level bigint, queued boolean)
language sql
immutable
set search_path = ''
as $$
  select b.id, b.kind, l::bigint, false
  from private.castle_levels(p_castle) b
  cross join lateral generate_series(1, least(greatest(b.level, 0), 10)) as l
  union
  select b.id, b.kind, q.level, true
  from (
    select private.json_int(o -> 'building_id', 1, 2147483647) as id, private.json_int(o -> 'level', 1, 10) as level
    from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'queue' -> 'orders') = 'array'
        then p_castle -> 'queue' -> 'orders' else '[]'::jsonb end) o
    where jsonb_typeof(o) = 'object'
  ) q
  join private.castle_levels(p_castle) b on b.id = q.id
  where q.level is not null
$$;

-- Suma kosztów budowy w zapisie `p_new` ponad `p_old` (wydatek) i zleceń z `p_old`, które zniknęły bez poziomu (zwrot).
create function private.build_flow(p_old jsonb, p_new jsonb)
returns table (spend bigint[], refund bigint[])
language sql
immutable
set search_path = ''
as $$
  with n as (select distinct x.id, x.kind, x.level from private.build_paid(p_new) x),
  o as (select distinct x.id, x.kind, x.level from private.build_paid(p_old) x),
  oq as (select distinct x.id, x.kind, x.level from private.build_paid(p_old) x where x.queued
    and not exists (select 1 from private.build_paid(p_old) y
      where not y.queued and y.id = x.id and y.kind = x.kind and y.level = x.level)),
  s as (select private.build_cost(n.kind, n.level) c from n
    where not exists (select 1 from o where o.id = n.id and o.kind = n.kind and o.level = n.level)),
  r as (select private.build_cost(oq.kind, oq.level) c from oq
    where not exists (select 1 from n where n.id = oq.id and n.kind = oq.kind and n.level = oq.level))
  select
    array(select coalesce((select sum(s.c[i]) from s), 0)::bigint from generate_series(1, 4) i order by i),
    array(select coalesce((select sum(r.c[i]) from r), 0)::bigint from generate_series(1, 4) i order by i)
$$;

-- Koszt technologii epoki `p_age`, gdy rozpoczęto już `p_step` technologii tej epoki (ResearchConfig.cost).
create function private.research_cost(p_age integer, p_step bigint)
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_out bigint[] := case when p_age >= 1 then array[400, 300, 200, 0] else array[100, 50, 50, 0] end;
begin
  for s in 1 .. greatest(p_step, 0) loop
    for i in 1 .. 4 loop
      v_out[i] := v_out[i] * 160 / 100;
    end loop;
  end loop;
  return v_out;
end;
$$;

-- Technologie zbadane i w toku (opłacone przy starcie badania).
create function private.research_paid(p_castle jsonb)
returns text[]
language sql
immutable
set search_path = ''
as $$
  select coalesce(private.research_codes(p_castle), '{}')
    || case when jsonb_typeof(p_castle -> 'research' -> 'active' -> 'code') = 'string'
        and private.tech_tree() ? (p_castle -> 'research' -> 'active' ->> 'code')
        and (p_castle -> 'research' -> 'active' ->> 'code') <> all (coalesce(private.research_codes(p_castle), '{}'))
      then array[p_castle -> 'research' -> 'active' ->> 'code'] else '{}'::text[] end
$$;

-- Koszt badań w `p_new` ponad `p_old`: k nowych po m starych w każdej epoce to koszty kroków m..m+k-1.
create function private.research_spend(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with a as (
    select (t.value ->> 0)::integer as age,
      count(*) filter (where t.key = any (private.research_paid(p_old))) as m,
      count(*) filter (where t.key = any (private.research_paid(p_new))
        and t.key <> all (private.research_paid(p_old))) as k
    from jsonb_each(private.tech_tree()) t
    group by 1
  ), c as (
    select private.research_cost(a.age, s) as c
    from a cross join lateral generate_series(a.m, a.m + a.k - 1) s
  )
  select array(select coalesce((select sum(c.c[i]) from c), 0)::bigint from generate_series(1, 4) i order by i)
$$;

-- Koszt jednostki `p_unit` w surowcach (UnitTypes.resource_cost).
create function private.unit_res_cost(p_unit integer)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  select array(select (e #>> '{}')::bigint from jsonb_array_elements(coalesce(
    '[[0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 10, 0], [0, 0, 15, 0], [0, 0, 15, 0], [0, 0, 10, 0], [0, 0, 15, 0], [0, 0, 10, 0], [0, 0, 20, 0], [60, 0, 0, 0], [0, 0, 10, 0], [0, 0, 5, 0], [0, 0, 15, 0], [40, 0, 0, 0]]'::jsonb
      -> p_unit, '[0, 0, 0, 0]'::jsonb)) e)
$$;

-- Jednostki opłacone w zapisie dla każdego rodzaju (indeks = rodzaj + 1): wyszkoleni, na zwiadzie i w szkoleniu.
create function private.army_paid(p_castle jsonb)
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_out bigint[] := private.army_owned(p_castle);
  u bigint;
  e jsonb;
begin
  for e in select x from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'recruitment' -> 'orders') = 'array'
      then p_castle -> 'recruitment' -> 'orders' else '[]' end) x loop
    u := private.json_int(e -> 'unit', 0, private.unit_count() - 1);
    if u is not null then
      v_out[u + 1] := v_out[u + 1] + 1;
    end if;
  end loop;
  return v_out;
end;
$$;

-- Pułapki każdego rodzaju (TrapConfig.Kind, indeks = rodzaj + 1) w `defense.traps` = [[rodzaj, x, y, odkryta], ...].
create function private.trap_counts(p_castle jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  select array(select (select count(*) from jsonb_array_elements(
        case when jsonb_typeof(p_castle -> 'defense' -> 'traps') = 'array' then p_castle -> 'defense' -> 'traps'
          else '[]'::jsonb end) t
      where case when jsonb_typeof(t) = 'array' then jsonb_array_length(t) >= 3 else false end
        and private.json_int(t -> 0, 0, 4) = k)::bigint
    from generate_series(0, 4) k order by k)
$$;

-- Zwiadowcy na misji w zapisie (0 bez misji).
create function private.scouts_out(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(private.json_int(u -> 1, 0, 10000)), 0)::bigint
  from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'scout' -> 'mission' -> 'units') = 'array'
      then p_castle -> 'scout' -> 'mission' -> 'units' else '[]'::jsonb end) u
  where jsonb_typeof(u) = 'array'
$$;

-- Złoto wydane na generałów w zapisie (werbunek 50, awans na 2 za 80 i na 3 za 150, jak `ruler_gold_left`).
create function private.generals_gold(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(50
      + case when private.json_int(g -> 'level', 1, 3) >= 2 then 80 else 0 end
      + case when private.json_int(g -> 'level', 1, 3) >= 3 then 150 else 0 end), 0)::bigint
  from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'generals' -> 'roster') = 'array'
    then p_castle -> 'generals' -> 'roster' else '[]'::jsonb end) g
$$;

-- Wydatki widoczne w `p_new` względem `p_old` (bez budowy, którą liczy build_flow) i bez perka władcy.
create function private.other_spend(p_old jsonb, p_new jsonb)
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_out bigint[] := private.research_spend(p_old, p_new);
  v_old bigint[] := private.army_paid(p_old);
  v_new bigint[] := private.army_paid(p_new);
  v_ot bigint[] := private.trap_counts(p_old);
  v_nt bigint[] := private.trap_counts(p_new);
  v_cost bigint[];
  v_scouts bigint;
begin
  for u in 0 .. private.unit_count() - 1 loop
    if v_new[u + 1] > v_old[u + 1] then
      v_cost := private.unit_res_cost(u);
      for i in 1 .. 4 loop
        v_out[i] := v_out[i] + (v_new[u + 1] - v_old[u + 1]) * v_cost[i];
      end loop;
    end if;
  end loop;
  for k in 0 .. 4 loop
    if v_nt[k + 1] > v_ot[k + 1] then
      v_cost := array(select (e #>> '{}')::bigint from jsonb_array_elements(
        '[[30, 0, 10, 0], [20, 20, 0, 0], [50, 0, 0, 0], [20, 0, 0, 0], [40, 0, 0, 0]]'::jsonb -> k) e);
      for i in 1 .. 4 loop
        v_out[i] := v_out[i] + (v_nt[k + 1] - v_ot[k + 1]) * v_cost[i];
      end loop;
    end if;
  end loop;
  -- nowa misja zwiadu: tylko gdy poprzedni zapis był bez misji (inna misja w miejscu starej to niepewny wydatek)
  if private.scouts_out(p_old) = 0 then
    v_scouts := private.scouts_out(p_new);
    v_out[3] := v_out[3] + 10 * v_scouts;
    v_out[4] := v_out[4] + 10 * v_scouts;
  end if;
  v_out[4] := v_out[4] + greatest(private.generals_gold(p_new) - private.generals_gold(p_old), 0);
  return v_out;
end;
$$;

-- Budynki obu zapisów: każdy id i rodzaj na wyższym z dwóch poziomów (1..5, jak premie i produkcja).
create function private.buildings_max(p_old jsonb, p_new jsonb)
returns table (id bigint, kind bigint, level integer)
language sql
immutable
set search_path = ''
as $$
  select x.id, x.kind, max(x.level)::integer
  from (select * from private.castle_buildings(p_old) union all select * from private.castle_buildings(p_new)) x
  where x.level >= 1
  group by x.id, x.kind
$$;

-- Górna granica produkcji na godzinę między zapisami (Economy.rates plus żywność Chaty myśliwego).
create function private.production_max(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with b as (select * from private.buildings_max(p_old, p_new)),
  raw as (
    select r, (array[20, 20, 20, 0])[r + 1] + coalesce((select sum((p.v -> 1 ->> (b.level - 1))::bigint)
        from b join jsonb_each('{"4": [0, [60, 90, 120, 160, 200]], "16": [2, [40, 60, 80, 110, 140]], "28": [2, [60, 90, 120, 160, 200]], "30": [1, [40, 60, 80, 110, 140]]}'::jsonb) p(k, v)
          on p.k = b.kind::text and (p.v ->> 0)::integer = r), 0) as amount
    from generate_series(0, 3) r
  ), bonus as (
    select r, coalesce((select sum((t.v ->> 1)::integer) from jsonb_each('{"G1": [0, 20], "G2": [2, 15]}'::jsonb) t(k, v)
        where (t.v ->> 0)::integer = r
          and (t.k = any (coalesce(private.research_codes(p_old), '{}'))
            or t.k = any (coalesce(private.research_codes(p_new), '{}')))), 0)
      + case when private.castle_ruler_perk(p_old) = 3 or private.castle_ruler_perk(p_new) = 3 then 10 else 0 end as percent
    from generate_series(0, 3) r
  )
  select array(
    select raw.amount * (100 + bonus.percent) / 100
      -- HUNTER_FOOD = 2 na cykl, 6 cykli na godzinę na poziomie 1 razy LEVEL_PERCENT = [100, 150, 200, 275, 350]
      + case when raw.r = 2 then coalesce((select sum(2 * (6 * (array[100, 150, 200, 275, 350])[b.level] / 100))
          from b where b.kind = 6), 0) else 0 end
    from raw join bonus on bonus.r = raw.r
    order by raw.r)::bigint[]
$$;

-- Utrzymanie wojska z zapisu na godzinę: wyszkoleni, zwiad i szkolenie (górna granica Recruitment.army_upkeep).
create function private.upkeep_all(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum(n * private.unit_upkeep((i - 1)::integer)), 0)::bigint
  from unnest(private.army_paid(p_castle)) with ordinality as a(n, i)
$$;

-- Górna granica zużycia na godzinę między zapisami: utrzymanie (wyższa armia) i wejścia surowców wytwórców.
create function private.consumption_max(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with b as (select * from private.buildings_max(p_old, p_new)),
  rec as (
    select (e ->> 0)::bigint as kind, (e ->> 1)::integer as min_level, (e ->> 2)::bigint as cph, e -> 3 as ins
    from jsonb_array_elements('[[9, 1, 3, {"0": 3, "1": 1}], [9, 1, 3, {"0": 2, "1": 1}], [9, 1, 2, {"0": 2, "1": 2}], [9, 1, 2, {"0": 5, "1": 1}], [11, 1, 2, {"0": 3}], [11, 3, 1, {"0": 4}], [12, 1, 3, {"0": 1}], [8, 1, 2, {"0": 1}], [8, 1, 2, {"0": 2}], [13, 1, 2, {"0": 1}], [14, 1, 3, {"0": 4}], [17, 1, 1, {"2": 10}]]'::jsonb) e
  )
  select array(
    select coalesce((select sum(rec.cph * (array[100, 150, 200, 275, 350])[b.level] / 100 * (rec.ins ->> r::text)::bigint)
        from rec join b on b.kind = rec.kind and b.level >= rec.min_level
        where rec.ins ? r::text), 0)
      + case when r = 2 then greatest(private.upkeep_all(p_old), private.upkeep_all(p_new)) else 0 end
    from generate_series(0, 3) r order by r)::bigint[]
$$;

-- Nagrody fal PvE z przedziału [p_from, p_to) (PveWaves.REWARDS).
create function private.pve_reward(p_from integer, p_to integer)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  select array(select (select coalesce(sum((('[[100, 50, 100, 10], [150, 100, 150, 15], [200, 150, 200, 20], [300, 200, 300, 30], [500, 300, 500, 50]]'::jsonb
        -> w) ->> r)::bigint), 0)
      from generate_series(greatest(p_from, 0), least(p_to, 5) - 1) w)::bigint
    from generate_series(0, 3) r order by r)
$$;

revoke all on function private.economy_amounts(jsonb) from public, anon, authenticated;
revoke all on function private.build_cost(bigint, bigint) from public, anon, authenticated;
revoke all on function private.build_paid(jsonb) from public, anon, authenticated;
revoke all on function private.build_flow(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.research_cost(integer, bigint) from public, anon, authenticated;
revoke all on function private.research_paid(jsonb) from public, anon, authenticated;
revoke all on function private.research_spend(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.unit_res_cost(integer) from public, anon, authenticated;
revoke all on function private.army_paid(jsonb) from public, anon, authenticated;
revoke all on function private.trap_counts(jsonb) from public, anon, authenticated;
revoke all on function private.scouts_out(jsonb) from public, anon, authenticated;
revoke all on function private.generals_gold(jsonb) from public, anon, authenticated;
revoke all on function private.other_spend(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.buildings_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.production_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.upkeep_all(jsonb) from public, anon, authenticated;
revoke all on function private.consumption_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.pve_reward(integer, integer) from public, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacz zapisu zamku
-- ---------------------------------------------------------------------------------------------

-- Jak w `*_resource_sanity.sql`, z bilansem surowców (#282) przed scaleniem łupu: bilans liczy zapasy z telefonu,
-- a łup i strata z `castle_loot_pending` wchodzą po nim. Nazwa `castles_resources` sortuje się po wszystkich
-- `castles_check_*`, więc wyzwalacz widzi już przyciętych generałów i płatne zmiany perka z tego zapisu.
-- SECURITY DEFINER jak wcześniej; czyta tylko wiersze właściciela zapisywanego zamku (new.player_id).
create or replace function private.check_castle_resources()
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
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_old jsonb;
  v_elapsed numeric;
  v_new_amounts bigint[];
  v_old_amounts bigint[];
  v_credit bigint[] := array[0, 0, 0, 0];
  v_hide bigint[] := array[0, 0, 0, 0];
  v_rewarded integer := 0;
  v_cleared integer;
  v_prod bigint[];
  v_use bigint[];
  v_build record;
  v_other bigint[];
  v_reward bigint[];
  v_cap bigint;
  v_spend numeric;
  v_tol numeric;
  v_slack numeric;
  v_hide_tol numeric;
  v_base numeric;
  v_out_credit bigint[] := array[0, 0, 0, 0];
  v_out_hide bigint[] := array[0, 0, 0, 0];
  v_has_old boolean := false;
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

  -- #282: bilans surowców od poprzedniego zapisu, tylko zapisy gracza (serwer pisze stan zaufany)
  if v_role in ('authenticated', 'anon') then
    v_new_amounts := private.economy_amounts(new.data);
    -- INSERT: kredyt z nowego wiersza, czyli domyślne 0 (klient wstawia tylko player_id, map_seed, save_version i data)
    v_credit := new.economy_credit;
    if tg_op = 'UPDATE' then
      v_old_amounts := private.economy_amounts(old.data);
      v_credit := old.economy_credit;
      v_hide := old.hide_credit;
      v_rewarded := old.pve_rewarded;
    end if;
    -- gra zawsze zapisuje `economy`; zamek gracza, który traci zapasy w kolejnym zapisie, nie dałby łupu w PvP.
    -- Pierwszy zapis (INSERT) bez `economy` przechodzi bez bilansu: liczy się od pierwszego zapisu z zapasami.
    if v_new_amounts is null and tg_op = 'UPDATE' then
      raise exception 'economy_missing' using errcode = 'PT422';
    end if;
    v_cleared := coalesce(private.json_int(new.data -> 'pve' -> 'cleared', 0, 5), 0)::integer;
    if v_new_amounts is not null then
      if v_old_amounts is null then
        -- pierwszy zapis z zapasami: od nowej gry (EconomyConfig.START) i czasu od założenia konta; INSERT_GRACE = 6 godzin
        v_old := private.start_buildings(new.data);
        v_old_amounts := array[500, 300, 300, 50];
        select extract(epoch from now() - p.created_at) * 1000 + 6 * 3600 * 1000 into v_elapsed
        from public.players p where p.id = new.player_id;
        v_elapsed := coalesce(v_elapsed, 6 * 3600 * 1000);
      else
        v_has_old := true;
        v_old := old.data;
        v_elapsed := greatest(extract(epoch from now() - old.updated_at) * 1000, 0);
      end if;
      v_prod := private.production_max(v_old, new.data);
      v_use := private.consumption_max(v_old, new.data);
      select * into v_build from private.build_flow(v_old, new.data);
      v_other := private.other_spend(v_old, new.data);
      v_reward := private.pve_reward(v_rewarded, v_cleared);
      v_cap := private.castle_capacity(new.data);
      for i in 1 .. 4 loop
        v_spend := v_build.spend[i] + v_other[i] + case when i = 4 and tg_op = 'UPDATE'
          then 50 * greatest(new.ruler_perk_paid - old.ruler_perk_paid, 0) else 0 end;
        -- przyrost: TOLERANCE = 5 minut produkcji plus ROUND_SLACK = 2 łącznie
        v_tol := v_prod[i] * 5 * 60 * 1000 / 3600000.0 + 2;
        v_slack := v_credit[i] + v_prod[i] * v_elapsed / 3600000.0 + v_reward[i] + v_build.refund[i]
          - (v_new_amounts[i] - v_old_amounts[i]) - v_spend;
        if v_slack < -v_tol then
          raise exception 'economy_too_fast' using errcode = 'PT422';
        end if;
        v_out_credit[i] := floor(least(v_slack, v_tol))::bigint;
        -- spadek (bez pierwszego zapisu): HIDE_SLACK = [100, 100, 100, 20] plus 5 minut produkcji i zużycia,
        -- odnawiane w godzinę
        if v_has_old then
          v_hide_tol := (v_prod[i] + v_use[i]) * 5 * 60 * 1000 / 3600000.0 + (array[100, 100, 100, 20])[i];
          v_base := case when i < 4 then least(v_old_amounts[i], v_cap) else v_old_amounts[i] end;
          v_slack := v_hide[i] + least(v_hide_tol * v_elapsed / 3600000.0, v_hide_tol)
            + v_new_amounts[i] - (v_base - v_spend - v_use[i] * v_elapsed / 3600000.0);
          if v_slack < -v_hide_tol then
            raise exception 'economy_hidden' using errcode = 'PT422';
          end if;
          v_out_hide[i] := ceil(least(v_slack, 0))::bigint;
        end if;
      end loop;
      new.economy_credit := v_out_credit;
      new.hide_credit := v_out_hide;
    end if;
    new.pve_rewarded := greatest(v_rewarded, v_cleared)::smallint;
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

-- ---------------------------------------------------------------------------------------------
-- Koniec ataku (#25, #32, #274) z łupem z zamku-bota przeniesionym przez serwer (#282). Reszta bez zmian
-- względem `*_resource_sanity.sql`.
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

  -- #274: łup przenosi serwer w tej samej transakcji: atakujący zyskuje, a obrońca-gracz traci. Od #282 także
  -- łup z zamku-bota (bez obrońcy). Zmiana czeka w castle_loot_pending i wchodzi do `castles.data` przy
  -- najbliższym zapisie zamku każdego z nich (wyzwalacz castles_resources, po bilansie surowców). Ponowienie
  -- wraca wyżej (status 'finished'), więc łup liczy się raz.
  if v_sum > 0 then
    perform private.add_loot_pending(a.attacker_id,
      array[v_loot[1], v_loot[2], v_loot[3], v_loot[4]]::bigint[]);
  end if;
  if a.defender_id is not null and v_sum > 0 then
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
  'Koniec ataku (#25): wynik i łup w limitach (zapasy obrońcy, capacity ocalałych, Łupieżca #32), łup PvP i z zamku-bota przeniesiony przez castle_loot_pending (#274, #282), tarcza 8 h od 30 procent zniszczeń; ponowienie zwraca zapisany wynik. Tylko dla service_role (Edge Function finish_attack).';
revoke all on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.end_attack(uuid, uuid, jsonb, jsonb, jsonb) to service_role;
