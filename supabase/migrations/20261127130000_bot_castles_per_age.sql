-- #230: 20 zamków-botów na każdą epokę (MVP: I–II, razem 40).
--
-- Numeracja jak `BotRoster` w grze: idx 0–19 to epoka I, idx 20–39 epoka II (age = idx / 20).
-- Seed `BotRoster.seed_of(i)` się nie zmienia, więc wiersze 0–19 zachowują `map_seed`; zamki 15–19
-- przechodzą z epoki II do epoki I (najsilniejsze zamki epoki I). Nowe wiersze 20–39 mają seed
-- i nazwę z `BotRoster.NAMES`; zgodność z grą pilnuje `tests/test_attack_start.gd` po wierszach tego pliku.
-- Łup (`end_attack`) i punkty PvE (`attacks_pve_points`) dalej rosną z `bot_idx`, wzory bez zmian.
-- Tabela zostaje tylko do odczytu dla klientów (RLS i uprawnienia z `*_init_pvp_schema.sql`).

alter table public.bot_castles drop constraint bot_castles_idx_check;
alter table public.bot_castles add constraint bot_castles_idx_check check (idx between 0 and 39);

update public.bot_castles set age = 0 where idx between 15 and 19;

insert into public.bot_castles (idx, name, map_seed, age) values
  (20, 'Brzozowy Gród', 1673621543, 1),
  (21, 'Kozi Gród', 984361351, 1),
  (22, 'Sowia Góra', 1864033473, 1),
  (23, 'Głęboki Rów', 301151539, 1),
  (24, 'Jelenia Struga', 1446342387, 1),
  (25, 'Grodzisko Nowe', 1038056881, 1),
  (26, 'Mglisty Bród', 1406884201, 1),
  (27, 'Bursztynowa Wola', 1381573529, 1),
  (28, 'Kamienica', 2140396142, 1),
  (29, 'Ognisty Wał', 1864522405, 1),
  (30, 'Rogaty Gród', 1502820985, 1),
  (31, 'Srebrny Potok', 1135080201, 1),
  (32, 'Dzicza Skała', 2057058519, 1),
  (33, 'Strażnica Graniczna', 1086145739, 1),
  (34, 'Książęcy Gród', 1729057336, 1),
  (35, 'Wysoki Wał', 84480853, 1),
  (36, 'Gród nad Wisłą', 235166858, 1),
  (37, 'Biały Gród', 1193430381, 1),
  (38, 'Złota Brama', 561947788, 1),
  (39, 'Stołeczny Gród', 334360490, 1)
on conflict (idx) do nothing;

comment on table public.bot_castles is 'Zamki-boty: 20 na epokę (idx / 20 = epoka); seed musi zgadzać się z BotRoster.seed_of w grze.';
