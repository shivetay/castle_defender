-- Stały koszt i czas technologii w epoce, drożeją tylko doktryny.
--
-- Do tej pory serwer liczył koszt badań jak gra: RESEARCH_BASE_COST epoki razy 160 procent za każdą
-- wcześniej rozpoczętą technologię tej samej epoki. Teraz gra (ResearchConfig.cost, Research.cost_of)
-- bierze stały koszt epoki, a ×1,6 dostają tylko doktryny, czyli technologie z samą procentową premią:
--   DOCTRINES = ["A1", "A2", "G1", "G2"] (TechTree.DOCTRINES),
-- liczone za każdą wcześniej rozpoczętą doktrynę tej samej epoki. Bez tej zmiany serwer zawyżałby
-- wydatki na badania i odrzucałby uczciwe zapisy jako economy_too_fast.
--
-- `private.research_cost(age, step)` się nie zmienia (baza epoki × 1,6^step); zmienia się tylko to,
-- jakie kroki liczy `private.research_spend`.
--
-- Czas badań (ResearchConfig.time_ms) jest teraz stały w epoce: BASE_TIME_S = [60, 1800], bez ×2 za
-- każdą wcześniejszą technologię. `private.research_need_ms` (reguła research_too_fast) i
-- `private.research_head_ms` (kredyt badania w toku) liczą go tak samo; bez tego serwer odrzucałby
-- uczciwe zapisy jako research_too_fast.
-- Liczby pilnuje test gry (`tests/test_research_fixed_cost.gd`) po znacznikach w komentarzach.

-- Kody doktryn (TechTree.DOCTRINES).
create function private.research_doctrines()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['A1', 'A2', 'G1', 'G2']::text[]
$$;

-- Koszt badań w `p_new` ponad `p_old`: w każdej epoce zwykła technologia kosztuje krok 0, a k nowych
-- doktryn po m starych doktrynach tej epoki to koszty kroków m..m+k-1.
create or replace function private.research_spend(p_old jsonb, p_new jsonb)
returns bigint[]
language sql
immutable
set search_path = ''
as $$
  with t as (
    select (t.value ->> 0)::integer as age,
      t.key = any (private.research_doctrines()) as doctrine,
      t.key = any (private.research_paid(p_old)) as was_paid,
      t.key = any (private.research_paid(p_new)) as is_paid
    from jsonb_each(private.tech_tree()) t
  ), a as (
    select age,
      count(*) filter (where doctrine and was_paid) as m,
      count(*) filter (where doctrine and is_paid and not was_paid) as k,
      count(*) filter (where not doctrine and is_paid and not was_paid) as n
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

-- Czas (ms) badania technologii z `p_new`, których nie ma w `p_old`: stały czas epoki razy ich liczba.
create or replace function private.research_need_ms(p_old text[], p_new text[])
returns numeric
language sql
immutable
set search_path = ''
as $$
  select coalesce(sum((array[60000, 1800000])[a.age + 1] * a.k), 0)
  from (
    select (t.value ->> 0)::integer as age,
      count(*) filter (where t.key = any (p_new) and t.key <> all (p_old)) as k
    from jsonb_each(private.tech_tree()) t
    group by 1
  ) a
$$;

-- Pełny czas (ms) badania w toku w zapisie (`research.active.code`) według drzewka, gdy da się je zacząć.
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
  if not private.tech_tree() ? v_code or v_code = any (v_done)
      or exists (select 1 from jsonb_array_elements_text(private.tech_tree() -> v_code -> 1) r where r <> all (v_done)) then
    return 0;
  end if;
  v_age := (private.tech_tree() -> v_code ->> 0)::integer;
  return (array[60000, 1800000])[v_age + 1];
end;
$$;

revoke all on function private.research_doctrines() from public, anon, authenticated;
revoke all on function private.research_spend(jsonb, jsonb) from public, anon, authenticated;
revoke all on function private.research_need_ms(text[], text[]) from public, anon, authenticated;
revoke all on function private.research_head_ms(jsonb) from public, anon, authenticated;
