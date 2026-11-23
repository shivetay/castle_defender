-- #281: badania, wojsko i towary w `castles.data` bez zaufanej edycji lokalnej.
--
-- Serwer czyta z zapisu zamku zbadane technologie (premie G1/G2, epoka II przez O1, G1, A7, budynki
-- i jednostki wymagające badań), oddziały (armia ataku w `begin_attack`, garnizon) i zapasy zbrojowni.
-- Klient nie jest zaufany, a powtórka bitwy na serwerze (#52) liczy z tej samej kopii zamku, więc przy
-- każdym zapisie zamku (wyzwalacz `castles_check_army`, INSERT i UPDATE `data`) te trzy części muszą dać
-- się zdobyć w grze. Zapis spoza reguł jest odrzucany w całości kodem HTTP 422 (SQLSTATE PT422), bez cichego
-- przycinania; telefon przywraca wtedy zamek z serwera (SupabaseClient, #274 etap 1). Kod w treści błędu:
--
-- Reguły stanu (każdy zapis, także serwera; `begin_attack` nie wpuszcza takiego zamku do PvP):
-- - bad_research: `research.done` to nie lista znanych kodów TechTree bez powtórzeń;
-- - research_locked: technologia bez zbadanych technologii, których wymaga (TechTree.requires);
-- - research_age: technologia z epoki późniejszej niż epoka zamku (`private.castle_age`, Research.check);
-- - bad_army: zły kształt `recruitment` (oddział [id > 0, rodzaj 0..15, liczba 0..SQUAD_SIZE = 10], id bez
--   powtórzeń, `orders` jako lista) albo misji zwiadu (`scout.mission.units` = [[rodzaj, liczba], ...]);
-- - unit_locked: wyszkolona jednostka (w oddziale albo na zwiadzie) bez technologii z UnitTypes.required_tech;
-- - unit_age: jednostka z epoki późniejszej niż epoka zamku (UnitTypes.age);
-- - bad_goods: `goods.amounts` to nie GOODS_COUNT = 22 liczb całkowitych od 0;
-- - goods_over_capacity: towar ponad pojemność zbrojowni ARMORY_CAPACITY = 1000 (GoodsConfig.capacity).
--
-- Reguły przyrostu (tylko zapisy z tokenem gracza, rola `authenticated` albo `anon`, jak w #279):
-- - research_too_fast: nowe technologie (kody, których nie było w poprzednim zapisie) zajmują jednemu
--   badaczowi (ResearchConfig.RESEARCHERS = 1) więcej czasu, niż upłynęło. Czas technologii epoki a to
--   ResearchConfig.time_ms: BASE_TIME_S = [60, 1800] razy TIME_STEP = 2 do potęgi liczby technologii tej
--   epoki zbadanych wcześniej, więc k nowych po m starych kosztuje BASE × (2^(m+k) − 2^m);
-- - train_too_fast: wyszkolonych jednostek (oddziały i zwiad) przybyło więcej, niż zdążyłyby wyszkolić
--   budynki rekrutacji. Każdy rodzaj budynku (UnitTypes.building) liczy się osobno, bo budynki szkolą
--   równolegle: czas to suma RecruitmentConfig.train_ms nowych jednostek na najwyższym poziomie budynku
--   tego rodzaju, podzielona przez liczbę takich budynków (dolna granica prawdziwego czasu);
--   TRAIN_TIME_S = [20, 20, 25, 40, 30, 30, 45, 25, 50, 35, 60, 90, 15, 10, 40, 45],
--   TRAINING_SPEED_PERCENT = [100, 120, 140, 170, 200] dla poziomów 1–5 (wyższe jak 5);
-- - unit_no_building: przybyła jednostka, a w zamku nie ma gotowego budynku, który ją szkoli;
-- - army_over_limit: oddziały i zlecenia szkolenia ponad limit miejsc (`private.army_limit`), gdy armia
--   (z jednostkami na zwiadzie) urosła. Mniejsza albo ta sama armia ponad limit przechodzi: po rozbiórce
--   Koszar albo powrocie zwiadu zamek może legalnie mieć chwilowo za dużo wojska (#249);
-- - goods_too_fast: towaru przybyło więcej, niż wyprodukowaliby wytwórcy (GoodsConfig.RECIPES) od
--   poprzedniego zapisu, bez wejść i zużycia (górna granica produkcji). Tempo przepisu to suma
--   GoodsConfig.cycles_per_hour po budynkach wytwórcy (LEVEL_PERCENT = [100, 150, 200, 275, 350]),
--   na najwyższym poziomie budynku z poprzedniego i bieżącego zapisu.
--
-- Czas liczy się jak przy budowie (#279): czas od poprzedniego zapisu na zegarze serwera (`old.updated_at`)
-- plus kredyt z poprzedniego zapisu, który zmienia tylko wyzwalacz (`research_credit_ms`, `train_credit_ms`
-- dla każdego rodzaju budynku, `goods_credit` dla każdego towaru w ilości × ms na godzinę). Kredyt to
-- niewykorzystany, naprawdę upłynięty czas, najwyżej tyle, ile trwa zlecenie w toku: badanie
-- `research.active` (czas liczy serwer z drzewka, nie z zapisu), pierwsze zlecenie szkolenia w każdym budynku,
-- jeden cykl przepisu u wytwórcy (ułamek cyklu z Goods._progress). Kredyt może zejść do -TOLERANCE = 5 minut
-- łącznie (dla towarów: 5 minut produkcji), nie na każdy zapis. Stałe przesunięcie zegara telefonu nie
-- przeszkadza; przestawienie zegara do przodu jest tym, co ten limit łapie.
-- Pierwszy zapis zamku (INSERT) liczy od założenia konta (`players.created_at`) z zapasem INSERT_GRACE = 6 godzin
-- na grę bez sieci, od nowej gry: bez badań, wojska i towarów.
--
-- Nie ma tu pokrycia kosztów (surowce za badania, żywność i towary za rekrutację): to wymaga limitu przyrostu
-- ekonomii (#282). Budynek badań gałęzi (#165) też nie jest sprawdzany.
-- Zamki zapisane przed migracją, które łamią reguły stanu, dostają raz poprawkę (jedyny wyjątek od zasady
-- „bez przycinania”): technologie spoza drzewka, bez wymagań i z późniejszej epoki znikają (a Dwór epoki II,
-- który przez to traci technologie przejścia, schodzi z zabudową do poziomu 5), złe oddziały i jednostki
-- bez technologii znikają, zła misja zwiadu znika, a towary są przycięte do zbrojowni.
-- Liczby pilnuje test gry (`tests/test_army_research_goods_sanity.gd`) po znacznikach w komentarzach.

-- ---------------------------------------------------------------------------------------------
-- Kredyty czasu
-- ---------------------------------------------------------------------------------------------

-- Klient ma uprawnienia do zapisu wyłącznie `save_version` i `data` (migracja init), więc kredytów nie ustawi.
alter table public.castles
  add column research_credit_ms bigint not null default 0,
  add column train_credit_ms jsonb not null default '{}'::jsonb,
  add column goods_credit jsonb not null default '[]'::jsonb;

comment on column public.castles.research_credit_ms is
  'Kredyt czasu badań (#281): niewykorzystany czas, najwyżej czas badania w toku, ujemny do -5 minut. Zmienia tylko wyzwalacz.';
comment on column public.castles.train_credit_ms is
  'Kredyt czasu szkolenia (#281) dla każdego rodzaju budynku rekrutacji, w ms. Zmienia tylko wyzwalacz.';
comment on column public.castles.goods_credit is
  'Kredyt produkcji towarów (#281) dla każdego towaru, w ilości × ms na godzinę, najwyżej jeden cykl. Zmienia tylko wyzwalacz.';

-- ---------------------------------------------------------------------------------------------
-- Tabele gry
-- ---------------------------------------------------------------------------------------------

-- Drzewko technologii: kod → [epoka (0 = I), wymagane kody] (TechTree.TECHS):
--   TECH_TREE = {"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [1, ["G1"]], "G6": [1, ["G4"]], "U1": [0, []], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}
create function private.tech_tree()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [1, ["G1"]], "G6": [1, ["G4"]], "U1": [0, []], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}'::jsonb
$$;

-- Jednostki: [epoka, technologia ("" = bez), budynek rekrutacji (BuildingTypes.Kind)], indeks = UnitTypes.Unit:
--   UNIT_RULES = [[0, "", 18], [0, "", 18], [0, "", 20], [0, "A21", 19], [0, "A3", 14], [0, "S1", 22], [0, "A7", 17], [1, "", 18], [1, "A46", 19], [1, "A47", 20], [1, "A22", 17], [1, "A6", 18], [0, "", 18], [0, "", 18], [1, "S3", 22], [0, "", 17]]
create function private.unit_rules()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '[[0, "", 18], [0, "", 18], [0, "", 20], [0, "A21", 19], [0, "A3", 14], [0, "S1", 22], [0, "A7", 17], [1, "", 18], [1, "A46", 19], [1, "A47", 20], [1, "A22", 17], [1, "A6", 18], [0, "", 18], [0, "", 18], [1, "S3", 22], [0, "", 17]]'::jsonb
$$;

-- Przepisy wytwórców: [budynek wytwórcy (BuildingTypes.Kind z GoodsConfig.PRODUCER_KINDS), od poziomu,
-- cykle na godzinę na poziomie 1, wyjścia towarów {Good: ilość}] w kolejności GoodsConfig.RECIPES:
--   GOODS_RECIPES = [[6, 1, 6, {"0": 2, "2": 1, "3": 1, "4": 2}], [15, 1, 6, {"5": 3}], [7, 1, 4, {"1": 1}], [10, 1, 4, {"14": 1}], [10, 1, 4, {"14": 1}], [9, 1, 3, {"10": 1}], [9, 1, 3, {"11": 2}], [9, 1, 2, {"13": 1}], [9, 1, 2, {"12": 1}], [11, 1, 2, {"15": 1}], [11, 3, 1, {"16": 1}], [12, 1, 3, {"17": 10}], [8, 1, 2, {"6": 1}], [8, 1, 2, {"8": 1}], [8, 1, 1, {"7": 1}], [8, 1, 1, {"9": 1}], [13, 1, 2, {"18": 1}], [13, 1, 2, {"19": 1}], [14, 1, 3, {"20": 1}], [17, 1, 1, {"21": 1}]]
create function private.goods_recipes()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '[[6, 1, 6, {"0": 2, "2": 1, "3": 1, "4": 2}], [15, 1, 6, {"5": 3}], [7, 1, 4, {"1": 1}], [10, 1, 4, {"14": 1}], [10, 1, 4, {"14": 1}], [9, 1, 3, {"10": 1}], [9, 1, 3, {"11": 2}], [9, 1, 2, {"13": 1}], [9, 1, 2, {"12": 1}], [11, 1, 2, {"15": 1}], [11, 3, 1, {"16": 1}], [12, 1, 3, {"17": 10}], [8, 1, 2, {"6": 1}], [8, 1, 2, {"8": 1}], [8, 1, 1, {"7": 1}], [8, 1, 1, {"9": 1}], [13, 1, 2, {"18": 1}], [13, 1, 2, {"19": 1}], [14, 1, 3, {"20": 1}], [17, 1, 1, {"21": 1}]]'::jsonb
$$;

-- Czas szkolenia jednostki `p_unit` w budynku na poziomie `p_level` w ms (RecruitmentConfig.train_ms).
create function private.train_ms(p_unit integer, p_level bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce((array[20, 20, 25, 40, 30, 30, 45, 25, 50, 35, 60, 90, 15, 10, 40, 45])[p_unit + 1], 0)::bigint
    * 1000 * 100 / (array[100, 120, 140, 170, 200])[least(greatest(p_level, 1), 5)]
$$;

-- ---------------------------------------------------------------------------------------------
-- Badania
-- ---------------------------------------------------------------------------------------------

-- Zbadane kody z zapisu; pusta lista bez `research`, null przy złym kształcie, nieznanym kodzie albo powtórce.
create function private.research_codes(p_castle jsonb)
returns text[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_done jsonb := p_castle -> 'research' -> 'done';
  v_codes text[];
begin
  if p_castle -> 'research' is null then
    return '{}';
  end if;
  if jsonb_typeof(p_castle -> 'research') <> 'object' then
    return null;
  end if;
  if v_done is null then
    return '{}';
  end if;
  if jsonb_typeof(v_done) <> 'array' then
    return null;
  end if;
  if exists (select 1 from jsonb_array_elements(v_done) e
      where jsonb_typeof(e) <> 'string' or not private.tech_tree() ? (e #>> '{}')) then
    return null;
  end if;
  select coalesce(array_agg(e #>> '{}'), '{}') into v_codes from jsonb_array_elements(v_done) e;
  if cardinality(v_codes) <> (select count(distinct c) from unnest(v_codes) c) then
    return null;
  end if;
  return v_codes;
end;
$$;

-- Kod problemu z listą badań w zapisie albo null.
create function private.castle_research_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_done text[] := private.research_codes(p_castle);
begin
  if v_done is null then
    return 'bad_research';
  end if;
  if exists (select 1 from unnest(v_done) c
      cross join lateral jsonb_array_elements_text(private.tech_tree() -> c -> 1) r
      where r <> all (v_done)) then
    return 'research_locked';
  end if;
  if exists (select 1 from unnest(v_done) c
      where (private.tech_tree() -> c ->> 0)::integer > private.castle_age(p_castle)) then
    return 'research_age';
  end if;
  return null;
end;
$$;

-- Czas (ms) badania technologii z `p_new`, których nie ma w `p_old`: BASE × (2^(m+k) − 2^m) dla każdej epoki.
create function private.research_need_ms(p_old text[], p_new text[])
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum((array[60000, 1800000])[a.age + 1]
      * (power(2::numeric, a.m + a.k) - power(2::numeric, a.m))), 0)
  from (
    select (t.value ->> 0)::integer as age,
      count(*) filter (where t.key = any (p_old)) as m,
      count(*) filter (where t.key = any (p_new) and t.key <> all (p_old)) as k
    from jsonb_each(private.tech_tree()) t
    group by 1
  ) a
$$;

-- Pełny czas (ms) badania w toku w zapisie (`research.active.code`) według drzewka, gdy da się je zacząć.
create function private.research_head_ms(p_castle jsonb)
returns bigint
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_done text[] := coalesce(private.research_codes(p_castle), '{}');
  v_code text;
  v_age integer;
begin
  if jsonb_typeof(p_castle -> 'research' -> 'active' -> 'code') is distinct from 'string' then
    return 0;
  end if;
  v_code := p_castle -> 'research' -> 'active' ->> 'code';
  if not private.tech_tree() ? v_code or v_code = any (v_done)
      or exists (select 1 from jsonb_array_elements_text(private.tech_tree() -> v_code -> 1) r where r <> all (v_done)) then
    return 0;
  end if;
  v_age := (private.tech_tree() -> v_code ->> 0)::integer;
  return ((array[60000, 1800000])[v_age + 1] * power(2::numeric,
    (select count(*) from unnest(v_done) c where (private.tech_tree() -> c ->> 0)::integer = v_age)))::bigint;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Wojsko
-- ---------------------------------------------------------------------------------------------

-- Kod problemu z oddziałami i zwiadem w zapisie albo null.
create function private.castle_army_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rec jsonb := p_castle -> 'recruitment';
  v_mission jsonb := p_castle -> 'scout' -> 'mission';
  v_done text[] := coalesce(private.research_codes(p_castle), '{}');
  v_age smallint := private.castle_age(p_castle);
  v_ids bigint[] := '{}';
  v_tech text;
  e jsonb;
  v_id bigint;
  u bigint;
  n bigint;
begin
  if v_rec is not null then
    if jsonb_typeof(v_rec) <> 'object' or jsonb_typeof(coalesce(v_rec -> 'squads', '[]')) <> 'array'
        or jsonb_typeof(coalesce(v_rec -> 'orders', '[]')) <> 'array' then
      return 'bad_army';
    end if;
    for e in select x from jsonb_array_elements(coalesce(v_rec -> 'squads', '[]')) x loop
      if jsonb_typeof(e) <> 'array' then
        return 'bad_army';
      end if;
      if jsonb_array_length(e) < 3 then
        return 'bad_army';
      end if;
      v_id := private.json_int(e -> 0, 1, 2147483647);
      u := private.json_int(e -> 1, 0, private.unit_count() - 1);
      n := private.json_int(e -> 2, 0, 10);  -- SQUAD_SIZE
      if v_id is null or u is null or n is null or v_id = any (v_ids) then
        return 'bad_army';
      end if;
      v_ids := v_ids || v_id;
      if n > 0 then
        v_tech := private.unit_rules() -> u::integer ->> 1;
        if v_tech <> '' and v_tech <> all (v_done) then
          return 'unit_locked';
        end if;
        if (private.unit_rules() -> u::integer ->> 0)::integer > v_age then
          return 'unit_age';
        end if;
      end if;
    end loop;
  end if;
  -- zwiad: gra zapisuje misję tylko wtedy, gdy jest w toku (Scouting.save_data)
  if v_mission is not null and jsonb_typeof(v_mission) = 'object' and v_mission ? 'units' then
    if jsonb_typeof(v_mission -> 'units') <> 'array' then
      return 'bad_army';
    end if;
    for e in select x from jsonb_array_elements(v_mission -> 'units') x loop
      if jsonb_typeof(e) <> 'array' then
        return 'bad_army';
      end if;
      if jsonb_array_length(e) <> 2 then
        return 'bad_army';
      end if;
      u := private.json_int(e -> 0, 0, private.unit_count() - 1);
      n := private.json_int(e -> 1, 0, 10000);
      if u is null or n is null then
        return 'bad_army';
      end if;
      if n > 0 then
        v_tech := private.unit_rules() -> u::integer ->> 1;
        if v_tech <> '' and v_tech <> all (v_done) then
          return 'unit_locked';
        end if;
        if (private.unit_rules() -> u::integer ->> 0)::integer > v_age then
          return 'unit_age';
        end if;
      end if;
    end loop;
  end if;
  return null;
end;
$$;

-- Wyszkolone jednostki każdego rodzaju (indeks = rodzaj + 1): oddziały i zwiadowcy na misji. Złe wpisy się nie liczą.
create function private.army_owned(p_castle jsonb)
returns bigint[]
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_out bigint[] := array_fill(0::bigint, array[private.unit_count()]);
  e jsonb;
  u bigint;
  n bigint;
begin
  for e in select x from jsonb_array_elements(case when jsonb_typeof(p_castle -> 'recruitment' -> 'squads') = 'array'
      then p_castle -> 'recruitment' -> 'squads' else '[]' end) x loop
    if jsonb_typeof(e) = 'array' then
      u := private.json_int(e -> 1, 0, private.unit_count() - 1);
      n := private.json_int(e -> 2, 0, 10);
      if u is not null and n is not null then
        v_out[u + 1] := v_out[u + 1] + n;
      end if;
    end if;
  end loop;
  if jsonb_typeof(p_castle -> 'scout' -> 'mission' -> 'units') = 'array' then
    for e in select x from jsonb_array_elements(p_castle -> 'scout' -> 'mission' -> 'units') x loop
      if jsonb_typeof(e) = 'array' then
        u := private.json_int(e -> 0, 0, private.unit_count() - 1);
        n := private.json_int(e -> 1, 0, 10000);
        if u is not null and n is not null then
          v_out[u + 1] := v_out[u + 1] + n;
        end if;
      end if;
    end loop;
  end if;
  return v_out;
end;
$$;

-- Armia z zapisu: wyszkoleni (oddziały i zwiad) i zlecenia szkolenia. Bez `scout` to miejsca w armii
-- jak Recruitment.free_army (zwiadowcy na misji wyszli z armii).
create function private.army_total(p_castle jsonb)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select (select coalesce(sum(o.n), 0) from unnest(private.army_owned(p_castle)) o(n))::bigint
    + case when jsonb_typeof(p_castle -> 'recruitment' -> 'orders') = 'array'
        then jsonb_array_length(p_castle -> 'recruitment' -> 'orders') else 0 end
$$;

-- Plan szkolenia między zapisami dla każdego rodzaju budynku rekrutacji: czas (ms) potrzebny na nowe jednostki,
-- pełny czas zleceń w toku (pierwsze zlecenie każdego budynku), oba podzielone przez liczbę budynków, i czy
-- przybyła jednostka bez budynku. Budynki z obu zapisów, poziom najwyższy (lżejsza, dolna granica czasu).
create function private.train_plan(p_old jsonb, p_new jsonb)
returns table (kind bigint, need_ms numeric, head_ms numeric, missing boolean)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_rules jsonb := private.unit_rules();
  v_old bigint[] := private.army_owned(p_old);
  v_new bigint[] := private.army_owned(p_new);
  v_n bigint;
  v_best bigint;
  v_head numeric;
  k bigint;
begin
  for k in select distinct (r ->> 2)::bigint from jsonb_array_elements(v_rules) r order by 1 loop
    select greatest(
        (select count(*) from private.castle_levels(p_new) b where b.kind = k and b.level >= 1),
        (select count(*) from private.castle_levels(p_old) b where b.kind = k and b.level >= 1)),
      coalesce((select max(b.level) from (select * from private.castle_levels(p_new)
          union all select * from private.castle_levels(p_old)) b where b.kind = k), 1)
    into v_n, v_best;
    need_ms := 0;
    missing := false;
    for i in 0 .. private.unit_count() - 1 loop
      if (v_rules -> i ->> 2)::bigint = k and v_new[i + 1] > v_old[i + 1] then
        missing := missing or v_n = 0;
        need_ms := need_ms + (v_new[i + 1] - v_old[i + 1]) * private.train_ms(i, v_best);
      end if;
    end loop;
    select coalesce(sum(private.train_ms(f.unit::integer, v_best)), 0) into v_head
    from (
      select distinct on (o.bid) o.bid, o.unit
      from (
        select private.json_int(x.e -> 'building_id', 1, 2147483647) as bid,
          private.json_int(x.e -> 'unit', 0, private.unit_count() - 1) as unit, x.ord
        from jsonb_array_elements(case when jsonb_typeof(p_new -> 'recruitment' -> 'orders') = 'array'
            then p_new -> 'recruitment' -> 'orders' else '[]' end) with ordinality as x(e, ord)
        where jsonb_typeof(x.e) = 'object'
      ) o
      where o.bid is not null
      order by o.bid, o.ord
    ) f
    join private.castle_levels(p_new) b on b.id = f.bid and b.kind = k and b.level >= 1
    where f.unit is not null and (v_rules -> f.unit::integer ->> 2)::bigint = k;
    if v_n > 0 then
      need_ms := need_ms / v_n;
      head_ms := v_head / v_n;
    else
      head_ms := 0;
    end if;
    kind := k;
    return next;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------------------------
-- Towary
-- ---------------------------------------------------------------------------------------------

-- Kod problemu z zapasami zbrojowni w zapisie albo null.
create function private.castle_goods_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_amounts jsonb := p_castle -> 'goods' -> 'amounts';
  x bigint;
begin
  if p_castle -> 'goods' is null then
    return null;
  end if;
  if jsonb_typeof(p_castle -> 'goods') <> 'object' then
    return 'bad_goods';
  end if;
  if v_amounts is null then
    return null;
  end if;
  -- GOODS_COUNT = 22
  if jsonb_typeof(v_amounts) <> 'array' or jsonb_array_length(v_amounts) <> 22 then
    return 'bad_goods';
  end if;
  for i in 0 .. 21 loop
    x := private.json_int(v_amounts -> i, 0, 10000000);
    if x is null then
      return 'bad_goods';
    end if;
    -- ARMORY_CAPACITY = 1000
    if x > 1000 then
      return 'goods_over_capacity';
    end if;
  end loop;
  return null;
end;
$$;

-- Zapasy towarów z zapisu (22 liczby, złe i brakujące jako 0).
create function private.goods_amounts(p_castle jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  select array_agg(coalesce(case when jsonb_typeof(p_castle -> 'goods' -> 'amounts') = 'array'
      then private.json_int(p_castle -> 'goods' -> 'amounts' -> g, 0, 10000000) end, 0) order by g)
  from generate_series(0, 21) g
$$;

-- Plan produkcji między zapisami dla każdego towaru: przyrost zapasu, tempo wytwórców (ilość na godzinę) i jeden
-- cykl wszystkich przepisów, które go dają (w ilości × ms na godzinę).
create function private.goods_plan(p_old jsonb, p_new jsonb)
returns table (good integer, inc bigint, rate bigint, cap bigint)
language sql
immutable
set search_path = ''
as $$
  with b as (
    select x.id, x.kind, max(x.level) as lvl
    from (select * from private.castle_levels(p_old) union all select * from private.castle_levels(p_new)) x
    where x.level >= 1
    group by x.id, x.kind
  ), r as (
    select e.ord, (e.v ->> 0)::bigint as kind, (e.v ->> 1)::bigint as min_level, (e.v ->> 2)::bigint as cph, e.v -> 3 as outs
    from jsonb_array_elements(private.goods_recipes()) with ordinality as e(v, ord)
  ), p as (
    select r.ord, r.outs, sum(r.cph * (array[100, 150, 200, 275, 350])[least(b.lvl, 5)] / 100) as per_hour
    from r join b on b.kind = r.kind and b.lvl >= r.min_level
    group by r.ord, r.outs
  ), g as (
    select o.key::integer as good, sum(p.per_hour * (o.value #>> '{}')::bigint) as rate,
      sum((o.value #>> '{}')::bigint) * 3600000 as cap
    from p cross join lateral jsonb_each(p.outs) o
    where p.per_hour > 0
    group by 1
  )
  select s.g, (private.goods_amounts(p_new))[s.g + 1] - (private.goods_amounts(p_old))[s.g + 1],
    coalesce(g.rate, 0)::bigint, coalesce(g.cap, 0)::bigint
  from generate_series(0, 21) s(g)
  left join g on g.good = s.g
  order by s.g
$$;

revoke all on function private.tech_tree() from public, anon, authenticated;
revoke all on function private.unit_rules() from public, anon, authenticated;
revoke all on function private.goods_recipes() from public, anon, authenticated;
revoke all on function private.train_ms(integer, bigint) from public, anon, authenticated;
revoke all on function private.research_codes(jsonb) from public, anon, authenticated;
revoke all on function private.castle_research_problem(jsonb) from public, anon, authenticated;
revoke all on function private.research_need_ms(text[], text[]) from public, anon, authenticated;
revoke all on function private.research_head_ms(jsonb) from public, anon, authenticated;
revoke all on function private.castle_army_problem(jsonb) from public, anon, authenticated;
revoke all on function private.army_owned(jsonb) from public, anon, authenticated;
revoke all on function private.army_total(jsonb) from public, anon, authenticated;
revoke all on function private.train_plan(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.castle_goods_problem(jsonb) from public, anon, authenticated;
revoke all on function private.goods_amounts(jsonb) from public, anon, authenticated;
revoke all on function private.goods_plan(jsonb, jsonb) from public, anon, authenticated;
-- begin_attack woła problemy stanu (przez castle_resources_problem) jako service_role
grant execute on function private.tech_tree() to service_role;
grant execute on function private.unit_rules() to service_role;
grant execute on function private.research_codes(jsonb) to service_role;
grant execute on function private.castle_research_problem(jsonb) to service_role;
grant execute on function private.castle_army_problem(jsonb) to service_role;
grant execute on function private.castle_goods_problem(jsonb) to service_role;

-- ---------------------------------------------------------------------------------------------
-- Zamki sprzed migracji
-- ---------------------------------------------------------------------------------------------

-- Jednorazowo: poprawka stanu zamków, które łamią reguły stanu (opis na górze). Wyzwalacze surowców i zabudowy
-- są na ten czas wyłączone, żeby zamek z innym problemem (który i tak nie wejdzie do PvP) nie zatrzymał migracji;
-- bump_revision zostaje, więc telefon dostanie konflikt rewizji i wczyta poprawiony zamek z serwera.
alter table public.castles disable trigger castles_resources;
alter table public.castles disable trigger castles_check_buildings;
do $$
declare
  r record;
  v jsonb;
  d text[];
  keep text[];
begin
  for r in select c.player_id, c.data from public.castles c
      where coalesce(private.castle_research_problem(c.data), private.castle_army_problem(c.data),
        private.castle_goods_problem(c.data)) is not null loop
    v := r.data;
    -- badania: znane kody bez powtórzeń, potem bez technologii z brakującymi wymaganiami albo z późniejszej epoki
    if private.castle_research_problem(v) is not null then
      if jsonb_typeof(v -> 'research') is distinct from 'object' then
        v := jsonb_set(v, '{research}', '{}'::jsonb);
      end if;
      select coalesce(array_agg(t.key), '{}') into d from jsonb_each(private.tech_tree()) t
      where jsonb_typeof(v -> 'research' -> 'done') = 'array' and (v -> 'research' -> 'done') @> jsonb_build_array(t.key);
      loop
        v := jsonb_set(v, '{research,done}', to_jsonb(d));
        -- Dwór epoki II bez technologii przejścia: cała zabudowa do poziomu 5 (jak w *_building_sanity.sql)
        if private.castle_buildings_problem(v) = 'age_locked' then
          v := jsonb_set(v, '{grid,buildings}', (
            select jsonb_agg(case
                when case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 7 else false end
                  and private.json_int(x.e -> 2, -2147483648, 2147483647) is not null
                then jsonb_set(x.e, '{2}', to_jsonb(least(private.json_int(x.e -> 2, -2147483648, 2147483647), 5)))
                else x.e end order by x.ord)
            from jsonb_array_elements(v -> 'grid' -> 'buildings') with ordinality as x(e, ord)));
        end if;
        select coalesce(array_agg(c), '{}') into keep from unnest(d) c
        where (private.tech_tree() -> c ->> 0)::integer <= private.castle_age(v)
          and not exists (select 1 from jsonb_array_elements_text(private.tech_tree() -> c -> 1) q where q <> all (d));
        exit when cardinality(keep) = cardinality(d);
        d := keep;
      end loop;
    end if;
    -- wojsko: oddziały w dobrym kształcie (pierwszy wpis danego id), bez jednostek bez technologii albo epoki
    if private.castle_army_problem(v) is not null then
      if jsonb_typeof(v -> 'recruitment') is distinct from 'object' then
        v := jsonb_set(v, '{recruitment}', '{}'::jsonb);
      end if;
      if jsonb_typeof(coalesce(v -> 'recruitment' -> 'orders', '[]')) <> 'array' then
        v := jsonb_set(v, '{recruitment,orders}', '[]'::jsonb);
      end if;
      d := coalesce(private.research_codes(v), '{}');
      v := jsonb_set(v, '{recruitment,squads}', coalesce((
        select jsonb_agg(s.e order by s.ord)
        from (
          select distinct on (q.id) q.e, q.ord, q.unit, q.n
          from (
            select x.e, x.ord, private.json_int(x.e -> 0, 1, 2147483647) as id,
              private.json_int(x.e -> 1, 0, private.unit_count() - 1) as unit,
              private.json_int(x.e -> 2, 0, 10) as n
            from jsonb_array_elements(case when jsonb_typeof(v -> 'recruitment' -> 'squads') = 'array'
                then v -> 'recruitment' -> 'squads' else '[]' end) with ordinality as x(e, ord)
            where case when jsonb_typeof(x.e) = 'array' then jsonb_array_length(x.e) >= 3 else false end
          ) q
          where q.id is not null and q.unit is not null and q.n is not null
          order by q.id, q.ord
        ) s
        where s.n = 0 or ((private.unit_rules() -> s.unit::integer ->> 1 = ''
            or private.unit_rules() -> s.unit::integer ->> 1 = any (d))
          and (private.unit_rules() -> s.unit::integer ->> 0)::integer <= private.castle_age(v))), '[]'::jsonb));
      if private.castle_army_problem(v) is not null then
        v := v #- '{scout,mission}';
      end if;
    end if;
    -- towary: 22 liczby w 0..pojemność
    if private.castle_goods_problem(v) is not null then
      if jsonb_typeof(v -> 'goods') is distinct from 'object' then
        v := jsonb_set(v, '{goods}', '{}'::jsonb);
      end if;
      v := jsonb_set(v, '{goods,amounts}', (
        select jsonb_agg(least(greatest(coalesce(case when jsonb_typeof(v -> 'goods' -> 'amounts') = 'array'
            then private.json_int(v -> 'goods' -> 'amounts' -> g, -2147483648, 2147483647) end, 0), 0), 1000) order by g)
        from generate_series(0, 21) g));
    end if;
    update public.castles c set data = v where c.player_id = r.player_id;
  end loop;
end;
$$;
alter table public.castles enable trigger castles_check_buildings;
alter table public.castles enable trigger castles_resources;

-- Kredyt na start: zlecenia w toku w zapisie sprzed migracji dostają pełny czas, a towary jeden cykl.
-- Bez bump_revision, żeby telefony nie dostały konfliktu rewizji.
alter table public.castles disable trigger castles_bump_revision;
update public.castles c set
  research_credit_ms = private.research_head_ms(c.data),
  train_credit_ms = (select coalesce(jsonb_object_agg(t.kind::text, t.head_ms::bigint), '{}'::jsonb)
    from private.train_plan(c.data, c.data) t),
  goods_credit = (select jsonb_agg(g.cap order by g.good) from private.goods_plan(c.data, c.data) g);
alter table public.castles enable trigger castles_bump_revision;

-- ---------------------------------------------------------------------------------------------
-- Wyzwalacz zapisu zamku
-- ---------------------------------------------------------------------------------------------

-- Przed zapisem zamku: badania, wojsko i towary w regułach gry i przyrost w czasie od poprzedniego zapisu.
-- SECURITY DEFINER, bo funkcje pomocnicze są w schemacie private, a gracz zapisuje jako `authenticated`;
-- czyta tylko `players.created_at` właściciela zapisywanego zamku (new.player_id). Nazwa `castles_check_army`
-- sortuje się po `castles_bump_revision`, ale czas poprzedniego zapisu bierze z `old.updated_at`.
create function private.check_castle_army()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_problem text := coalesce(private.castle_research_problem(new.data), private.castle_army_problem(new.data),
    private.castle_goods_problem(new.data));
  v_role text := coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '');
  v_old jsonb;
  v_elapsed numeric;
  v_research_credit numeric := 0;
  v_train_credit jsonb := '{}';
  v_goods_credit jsonb := '[]';
  v_avail numeric;
  v_need numeric;
  v_train jsonb := '{}';
  v_goods jsonb := '[]';
  r record;
begin
  if v_problem is not null then
    raise exception '%', v_problem using errcode = 'PT422';
  end if;
  -- serwer (service_role, migracje) pisze stan zaufany; limity przyrostu dotyczą gracza
  if v_role not in ('authenticated', 'anon') then
    return new;
  end if;
  if tg_op = 'INSERT' then
    -- nowa gra: bez badań, wojska i towarów; INSERT_GRACE = 6 godzin
    v_old := '{}'::jsonb;
    select extract(epoch from now() - p.created_at) * 1000 + 6 * 3600 * 1000 into v_elapsed
    from public.players p where p.id = new.player_id;
    v_elapsed := coalesce(v_elapsed, 6 * 3600 * 1000);
  else
    v_old := old.data;
    v_elapsed := extract(epoch from now() - old.updated_at) * 1000;
    v_research_credit := old.research_credit_ms;
    v_train_credit := old.train_credit_ms;
    v_goods_credit := old.goods_credit;
  end if;

  -- badania: jeden badacz; TOLERANCE = 5 minut łącznie (kredyt najwyżej -5 minut)
  v_avail := v_elapsed + v_research_credit;
  v_need := private.research_need_ms(coalesce(private.research_codes(v_old), '{}'), private.research_codes(new.data));
  if v_avail - v_need < -5 * 60 * 1000 then
    raise exception 'research_too_fast' using errcode = 'PT422';
  end if;
  new.research_credit_ms := least(v_avail - v_need, private.research_head_ms(new.data))::bigint;

  -- wojsko: limit miejsc, gdy armia urosła, i czas szkolenia w każdym rodzaju budynku
  if private.army_total(new.data - 'scout') > private.army_limit(new.data)
      and private.army_total(new.data) > private.army_total(v_old) then
    raise exception 'army_over_limit' using errcode = 'PT422';
  end if;
  for r in select * from private.train_plan(v_old, new.data) loop
    if r.missing then
      raise exception 'unit_no_building' using errcode = 'PT422';
    end if;
    v_avail := v_elapsed + coalesce((v_train_credit ->> r.kind::text)::numeric, 0);
    if v_avail - r.need_ms < -5 * 60 * 1000 then
      raise exception 'train_too_fast' using errcode = 'PT422';
    end if;
    v_train := v_train || jsonb_build_object(r.kind::text, least(v_avail - r.need_ms, r.head_ms)::bigint);
  end loop;
  new.train_credit_ms := v_train;

  -- towary: przyrost najwyżej z produkcji wytwórców; tolerancja 5 minut produkcji łącznie
  for r in select * from private.goods_plan(v_old, new.data) loop
    v_avail := coalesce((v_goods_credit ->> r.good)::numeric, 0) + r.rate * v_elapsed;
    v_need := greatest(r.inc, 0)::numeric * 3600000;
    if v_avail - v_need < -r.rate * 5 * 60 * 1000 then
      raise exception 'goods_too_fast' using errcode = 'PT422';
    end if;
    v_goods := v_goods || to_jsonb(least(v_avail - v_need, r.cap)::bigint);
  end loop;
  new.goods_credit := v_goods;
  return new;
end;
$$;

revoke all on function private.check_castle_army() from public, anon, authenticated;

create trigger castles_check_army
  before insert or update of data on public.castles
  for each row execute function private.check_castle_army();

-- ---------------------------------------------------------------------------------------------
-- Zamek spoza reguł nie wchodzi do PvP (begin_attack przez castle_resources_problem)
-- ---------------------------------------------------------------------------------------------

-- Jak w `*_building_sanity.sql`, z kodami badań, wojska i towarów po zabudowie, a przed surowcami.
create or replace function private.castle_resources_problem(p_player uuid, p_castle jsonb, p_paid integer)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_economy jsonb := p_castle -> 'economy';
  v_amounts jsonb;
  v_cap integer;
  v_state text := coalesce(private.castle_buildings_problem(p_castle), private.castle_research_problem(p_castle),
    private.castle_army_problem(p_castle), private.castle_goods_problem(p_castle));
  x bigint;
begin
  if v_state is not null then
    return v_state;
  end if;
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

revoke all on function private.castle_resources_problem(uuid, jsonb, integer) from public, anon, authenticated;
grant execute on function private.castle_resources_problem(uuid, jsonb, integer) to service_role;
