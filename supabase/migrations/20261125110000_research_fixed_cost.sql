-- Stały koszt technologii w epoce, drożeją tylko doktryny.
--
-- Do tej pory serwer liczył koszt badań jak gra: RESEARCH_BASE_COST epoki razy 160 procent za każdą
-- wcześniej rozpoczętą technologię tej samej epoki. Teraz gra (ResearchConfig.cost, Research.cost_of)
-- bierze stały koszt epoki, a ×1,6 dostają tylko doktryny, czyli technologie z samą procentową premią:
--   DOCTRINES = ["A1", "A2", "G1", "G2"] (TechTree.DOCTRINES),
-- liczone za każdą wcześniej rozpoczętą doktrynę tej samej epoki. Bez tej zmiany serwer zawyżałby
-- wydatki na badania i odrzucałby uczciwe zapisy jako economy_too_fast.
--
-- `private.research_cost(age, step)` się nie zmienia (baza epoki × 1,6^step); zmienia się tylko to,
-- jakie kroki liczy `private.research_spend`. Czas badań (`research_need_ms`, `research_head_ms`) nadal
-- rośnie ×2 z każdą technologią epoki, jak w grze.
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

revoke all on function private.research_doctrines() from public, anon, authenticated;
revoke all on function private.research_spend(jsonb, jsonb) from public, anon, authenticated;
