-- Poziomy doktryn.
--
-- Doktryny z poziomami (TechTree.LEVELED_DOCTRINES) bada się ponownie: LEVELED = ["G1", "G2"].
-- Poziom 1 to zbadana technologia (`research.done`), wyższe są w `research.levels` jako {kod: poziom},
-- tylko od 2, najwyżej DOCTRINE_MAX_LEVEL = [3, 5] w epoce zamku (`private.castle_age`). Badanie w toku
-- (`research.active.code`) zbadanej doktryny to jej kolejny poziom. Każdy poziom ponad pierwszy dodaje
-- DOCTRINE_LEVEL_PERCENT = 5 punktów procentowych do premii doktryny.
--
-- Serwer liczy poziomy wszędzie tam, gdzie liczył samo zbadanie:
-- - walidacja zapisu (`castle_research_problem`): kod `bad_research_level` przy złym kształcie `levels`,
--   poziomie dla technologii bez poziomów albo niezbadanej, poza 2..limit epoki, albo przy badaniu w toku
--   doktryny, która ma już najwyższy poziom epoki;
-- - wydatki (`research_spend`): każdy poziom to krok doktryny jak kolejna doktryna epoki
--   (ResearchConfig.cost: baza epoki × 1,6^liczba wcześniej rozpoczętych poziomów doktryn epoki);
-- - czas (`research_level_need_ms` w wyzwalaczu `check_castle_army`, `research_head_ms`): poziom trwa
--   stały czas epoki;
-- - produkcja (`production_max`) i limit utrzymania (`food_production`): premia G1 i G2 rośnie z poziomem,
--   wyższy poziom z dwóch zapisów, jak dotąd samo zbadanie.
-- Liczby pilnuje test gry (`tests/test_doctrine_levels_server.gd`) po znacznikach w komentarzach.

-- Doktryny z poziomami (TechTree.LEVELED_DOCTRINES).
create function private.research_leveled()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['G1', 'G2']::text[]
$$;

-- Najwyższy poziom doktryny w epoce zamku `p_age` (TechTree.DOCTRINE_MAX_LEVEL).
create function private.doctrine_max_level(p_age integer)
returns integer
language sql
immutable
set search_path = ''
as $$
  select (array[3, 5])[least(greatest(coalesce(p_age, 0), 0), 1) + 1]
$$;

-- Poziom technologii w zapisie (Research.level): 0 niezbadana, 1 zbadana, dla doktryny z poziomami
-- `research.levels` (liczba całkowita 2..5), inaczej 1.
create function private.tech_level(p_castle jsonb, p_code text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select case
    when not p_code = any (coalesce(private.research_codes(p_castle), '{}')) then 0
    when p_code = any (private.research_leveled())
        and jsonb_typeof(p_castle -> 'research' -> 'levels' -> p_code) = 'number'
        and (p_castle -> 'research' -> 'levels' ->> p_code) ~ '^[0-9]+(\.0+)?$'
      then least(greatest((p_castle -> 'research' -> 'levels' ->> p_code)::numeric::integer, 1), 5)
    else 1 end
$$;

-- Opłacone poziomy technologii: zbadane poziomy plus badanie w toku (niezbadanej technologii albo
-- kolejnego poziomu doktryny z poziomami).
create function private.research_paid_level(p_castle jsonb, p_code text)
returns integer
language sql
immutable
set search_path = ''
as $$
  select private.tech_level(p_castle, p_code)
    + case when jsonb_typeof(p_castle -> 'research' -> 'active' -> 'code') = 'string'
        and (p_castle -> 'research' -> 'active' ->> 'code') = p_code
        and private.tech_tree() ? p_code
        and (private.tech_level(p_castle, p_code) = 0 or p_code = any (private.research_leveled()))
      then 1 else 0 end
$$;

-- Kod problemu z listą badań w zapisie albo null (jak w `*_army_research_goods_sanity.sql`, z poziomami).
create or replace function private.castle_research_problem(p_castle jsonb)
returns text
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_done text[] := private.research_codes(p_castle);
  v_levels jsonb := p_castle -> 'research' -> 'levels';
  v_max integer := private.doctrine_max_level(private.castle_age(p_castle));
  v_active text;
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
  if v_levels is not null then
    if jsonb_typeof(v_levels) <> 'object' then
      return 'bad_research_level';
    end if;
    if exists (select 1 from jsonb_each(v_levels) l
        where l.key <> all (private.research_leveled()) or l.key <> all (v_done)
          or jsonb_typeof(l.value) <> 'number' or (l.value #>> '{}') !~ '^[0-9]+(\.0+)?$'
          or (l.value #>> '{}')::numeric < 2 or (l.value #>> '{}')::numeric > v_max) then
      return 'bad_research_level';
    end if;
  end if;
  if jsonb_typeof(p_castle -> 'research' -> 'active' -> 'code') = 'string' then
    v_active := p_castle -> 'research' -> 'active' ->> 'code';
    if v_active = any (private.research_leveled()) and private.tech_level(p_castle, v_active) >= v_max then
      return 'bad_research_level';
    end if;
  end if;
  return null;
end;
$$;

-- Koszt badań w `p_new` ponad `p_old`: w każdej epoce zwykła technologia kosztuje krok 0, a k nowych
-- poziomów doktryn po m starych poziomach doktryn tej epoki to koszty kroków m..m+k-1.
create or replace function private.research_spend(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with t as (
    select (t.value ->> 0)::integer as age,
      t.key = any (private.research_doctrines()) as doctrine,
      private.research_paid_level(p_old, t.key) as was,
      private.research_paid_level(p_new, t.key) as now
    from jsonb_each(private.tech_tree()) t
  ), a as (
    select age,
      coalesce(sum(was) filter (where doctrine), 0)::bigint as m,
      coalesce(sum(greatest(now - was, 0)) filter (where doctrine), 0)::bigint as k,
      coalesce(sum(greatest(now - was, 0)) filter (where not doctrine), 0)::bigint as n
    from t
    group by 1
  ), c as (
    select private.research_cost(a.age, s) as c
    from a cross join lateral generate_series(a.m, a.m + a.k - 1) s
    union all
    select private.research_cost(a.age, 0) as c
    from a cross join lateral generate_series(1, a.n) s
  )
  select array(select coalesce((select sum(c.c[i]) from c), 0)::bigint from generate_series(1, 4) i order by i)
$$;

-- Czas (ms) kolejnych poziomów doktryn w `p_new` ponad `p_old` (pierwszy poziom liczy research_need_ms):
-- stały czas epoki BASE_TIME_S = [60, 1800] za każdy nowy poziom ponad pierwszy.
create function private.research_level_need_ms(p_old jsonb, p_new jsonb)
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum((array[60000, 1800000])[(private.tech_tree() -> c ->> 0)::integer + 1]
      * greatest(private.tech_level(p_new, c) - greatest(private.tech_level(p_old, c), 1), 0)), 0)
  from unnest(private.research_leveled()) c
$$;

-- Pełny czas (ms) badania w toku w zapisie według drzewka, gdy da się je zacząć: niezbadana technologia
-- z wymaganiami albo kolejny poziom doktryny z poziomami.
create or replace function private.research_head_ms(p_castle jsonb)
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
  if not private.tech_tree() ? v_code
      or (v_code = any (v_done) and v_code <> all (private.research_leveled()))
      or exists (select 1 from jsonb_array_elements_text(private.tech_tree() -> v_code -> 1) r where r <> all (v_done)) then
    return 0;
  end if;
  v_age := (private.tech_tree() -> v_code ->> 0)::integer;
  return (array[60000, 1800000])[v_age + 1];
end;
$$;

-- Górna granica produkcji na godzinę między zapisami (Economy.rates plus żywność Chaty myśliwego),
-- z premią G1 i G2 według wyższego poziomu doktryny z dwóch zapisów.
create or replace function private.production_max(p_old jsonb, p_new jsonb)
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
    select r, coalesce((select sum((t.v ->> 1)::integer
          + 5 * (greatest(private.tech_level(p_old, t.k), private.tech_level(p_new, t.k)) - 1))
        from jsonb_each('{"G1": [0, 20], "G2": [2, 15]}'::jsonb) t(k, v)
        where (t.v ->> 0)::integer = r
          and greatest(private.tech_level(p_old, t.k), private.tech_level(p_new, t.k)) >= 1), 0)
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

-- Limit utrzymania jak w `*_ruler_perk.sql`, z premią G2 według poziomu doktryny (15 + 5 za poziom ponad 1).
create or replace function private.food_production(p_castle jsonb)
returns integer
language sql
immutable
set search_path = ''
as $$
  select ((20 + coalesce((select sum(case b.kind
          when 16 then (array[40, 60, 80, 110, 140])[b.level]
          when 28 then (array[60, 90, 120, 160, 200])[b.level]
          else 0 end)
        from private.castle_buildings(p_castle) b where b.kind in (16, 28) and b.level >= 1), 0))
      * (100 + case when private.tech_level(p_castle, 'G2') >= 1
          then 15 + 5 * (private.tech_level(p_castle, 'G2') - 1) else 0 end
        + case when private.castle_ruler_perk(p_castle) = 3 then 10 else 0 end)
      / 100)::integer
$$;

-- Wyzwalacz zapisu zamku jak w `*_army_research_goods_sanity.sql`, z czasem kolejnych poziomów doktryn.
create or replace function private.check_castle_army()
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

  -- badania: jeden badacz, także kolejne poziomy doktryn; TOLERANCE = 5 minut łącznie (kredyt najwyżej -5 minut)
  v_avail := v_elapsed + v_research_credit;
  v_need := private.research_need_ms(coalesce(private.research_codes(v_old), '{}'), private.research_codes(new.data))
    + private.research_level_need_ms(v_old, new.data);
  if v_avail - v_need < -5 * 60 * 1000 then
    raise exception 'research_too_fast' using errcode = 'PT422';
  end if;
  new.research_credit_ms := least(v_avail - v_need, private.research_head_ms(new.data))::bigint;

  -- wojsko: limit miejsc, gdy armia urosła, i czas szkolenia w każdym rodzaju budynku
  if private.army_total(new.data - 'scout') > private.army_limit(new.data)
      and private.army_total(new.data) > private.army_total(v_old) then
    raise exception 'army_over_limit' using errcode = 'PT422';
  end if;
  if private.castle_age(v_old) > 0 and private.era_i_units(new.data) > private.era_i_units(v_old) then
    raise exception 'unit_era_passed' using errcode = 'PT422';
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

revoke all on function private.research_leveled() from public, anon, authenticated;
revoke all on function private.doctrine_max_level(integer) from public, anon, authenticated;
revoke all on function private.tech_level(jsonb, text) from public, anon, authenticated;
revoke all on function private.research_paid_level(jsonb, text) from public, anon, authenticated;
revoke all on function private.castle_research_problem(jsonb) from public, anon, authenticated;
revoke all on function private.research_spend(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.research_level_need_ms(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.research_head_ms(jsonb) from public, anon, authenticated;
revoke all on function private.production_max(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.food_production(jsonb) from public, anon, authenticated;
grant execute on function private.food_production(jsonb) to service_role;
grant execute on function private.castle_research_problem(jsonb) to service_role;
revoke all on function private.check_castle_army() from public, anon, authenticated;
-- Funkcje serwera (service_role: Edge Functions, begin_attack, limity) wołają limit utrzymania i walidację
-- badań, a te czytają poziomy, jak `research_codes` i `castle_age` w poprzednich migracjach.
grant execute on function private.research_leveled() to service_role;
grant execute on function private.doctrine_max_level(integer) to service_role;
grant execute on function private.tech_level(jsonb, text) to service_role;
grant execute on function private.research_paid_level(jsonb, text) to service_role;
