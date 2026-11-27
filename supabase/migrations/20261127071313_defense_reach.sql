-- #342: technologia O25 Wysunięte straże poszerza strefę obrony (ADR 0006).
--
-- Strefa obrony (DefensePlan.zone: posterunki załogi, pułapki, zadania domyślne) ma promień
-- 10 + 2 × (poziom Dworu w epoce − 1) + poziom O25. O25 (Obrona, epoka I, bez wymagań) to doktryna
-- z poziomami jak A1, A2, G1 i G2: 3 poziomy w epoce I, 5 w epoce II, każdy kolejny poziom drożeje jak
-- kolejna doktryna epoki. Serwer musi ją znać, bo odrzuca zapis zamku z nieznaną technologią
-- (`private.castle_research_problem`) i liczy koszt, czas i poziomy doktryn z list:
-- - drzewko `private.tech_tree` jak w `*_quarry_age_one.sql`, z O25:
--   TECH_TREE = {"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "A60": [0, []], "A61": [1, ["A60"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "O25": [0, []], "O23": [0, []], "O24": [1, ["O23"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [0, ["G1"]], "G6": [1, ["G4"]], "G25": [0, []], "G26": [1, ["G25"]], "U1": [0, []], "U14": [0, []], "U15": [1, ["U14"]], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}
-- - doktryny (`private.research_doctrines`, koszt jak w `*_research_fixed_cost.sql`):
--   DOCTRINES = ["A1", "A2", "G1", "G2", "O25"]
-- - doktryny z poziomami (`private.research_leveled`, walidacja i czas jak w `*_doctrine_levels.sql`):
--   LEVELED = ["A1", "A2", "G1", "G2", "O25"]
-- Strefę obrony liczy tylko symulacja bitwy (gra i worker weryfikacji) z kopii zamku, więc poza listami
-- nic się nie zmienia: `attacks.attacker_techs` nadal niesie tylko badania ataku.
-- Liczby pilnują testy gry (`tests/test_army_research_goods_sanity.gd`, `tests/test_research_fixed_cost.gd`,
-- `tests/test_doctrine_levels_server.gd`) po znacznikach w komentarzach.

create or replace function private.tech_tree()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select '{"A1": [0, []], "A2": [0, []], "A3": [0, ["G24"]], "A4": [0, ["A1"]], "A7": [0, ["A2", "A43"]], "A21": [0, ["A38"]], "A38": [0, ["G19"]], "A39": [0, []], "A40": [0, ["G18"]], "A41": [0, ["A40"]], "A42": [0, ["G18"]], "A43": [0, ["G19"]], "A44": [0, ["A41"]], "A45": [0, ["A38"]], "A5": [1, ["A4"]], "A6": [1, ["A1"]], "A22": [1, ["A7"]], "A46": [1, ["A45"]], "A47": [1, ["A2"]], "A60": [0, []], "A61": [1, ["A60"]], "O1": [0, []], "O2": [0, []], "O3": [0, ["O2"]], "O25": [0, []], "O23": [0, []], "O24": [1, ["O23"]], "G1": [0, []], "G2": [0, []], "G18": [0, []], "G19": [0, ["G18"]], "G20": [0, ["G2"]], "G21": [0, []], "G24": [0, ["G1"]], "G4": [0, ["G1"]], "G6": [1, ["G4"]], "G25": [0, []], "G26": [1, ["G25"]], "U1": [0, []], "U14": [0, []], "U15": [1, ["U14"]], "S1": [0, []], "S2": [0, []], "S3": [1, ["S1"]]}'::jsonb
$$;

-- Kody doktryn (TechTree.DOCTRINES).
create or replace function private.research_doctrines()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['A1', 'A2', 'G1', 'G2', 'O25']::text[]
$$;

-- Doktryny z poziomami (TechTree.LEVELED_DOCTRINES).
create or replace function private.research_leveled()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array['A1', 'A2', 'G1', 'G2', 'O25']::text[]
$$;
