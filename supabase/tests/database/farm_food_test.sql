-- Testy żywności z Pola i spichlerza w limicie utrzymania (#35), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `private.food_production` liczy Pola (rodzaj 28) obok Rybaków (16) jak Economy.rates,
-- `begin_attack` przepuszcza armię, którą wyżywią Pola, a klient dalej nie woła funkcji pomocniczej.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(8);

-- P = b1: Dwór 2 i Pole 1 (20 + 60 = 80 Ży/h), 20 jeźdźców je 40. Ranking w paśmie 80 000 (bez
-- prawdziwych graczy), bo testy biegną też na projekcie w chmurze, w transakcji, która się cofa.
insert into auth.users (id) values ('00000000-0000-0000-0000-0000000000b1');
update public.players set rating = 80000, age = 0 where id = '00000000-0000-0000-0000-0000000000b1';
insert into public.castles (player_id, map_seed, save_version, data) values
  ('00000000-0000-0000-0000-0000000000b1', 31, 8, jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Rolniczy'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 2, 30, 30, 4, 4], [2, 28, 1, 40, 30, 2, 2]]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[[1, 6, 10], [2, 6, 10]]'::jsonb)));

-- ---- klient nie woła funkcji pomocniczej ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000000b1", "role": "authenticated"}', true);
select throws_ok($$select private.food_production('{}'::jsonb)$$, '42501', null, 'gracz nie woła food_production');
reset role;

set local role service_role;

-- ---- produkcja żywności z Pól (Economy.rates) ----
select is(private.food_production('{}'::jsonb), 20, 'sam gród: 20 Ży/h');
select is(private.food_production('{"grid": {"buildings": [[1, 28, 1, 0, 0, 2, 2], [2, 28, 3, 0, 0, 2, 2], [3, 28, 0, 0, 0, 2, 2]]}}'),
  200, 'Pola 1 i 3: 20 + 60 + 120, plac budowy nic nie daje');
select is(private.food_production('{"grid": {"buildings": [[1, 16, 1, 0, 0, 2, 2], [2, 28, 5, 0, 0, 2, 2]]}}'),
  260, 'Rybak 1 i Pole 5: 20 + 40 + 200');
select is(private.food_production('{"grid": {"buildings": [[1, 28, 2, 0, 0, 2, 2]]}, "research": {"done": ["G2"]}}'),
  126, 'G2: (20 + 90) × 115%, w dół');
select is(private.food_production('{"grid": {"buildings": [[1, 28, 9, 0, 0, 2, 2]]}}'), 220, 'poziom Pola przycięty do 5');
select is(private.food_production('{"grid": {"buildings": [[1, 30, 5, 0, 0, 2, 2]]}}'), 20, 'Kamieniołom nie daje żywności');

-- ---- start ataku: Pole wyżywi 20 jeźdźców (40 Ży/h przy 80 Ży/h) ----
select lives_ok(
  $$select * from public.begin_attack('00000000-0000-0000-0000-0000000000b1', null, 0::smallint, '[[6, 10], [6, 10]]', 1)$$,
  'armia wyżywiona z Pola idzie do ataku');

select * from finish();
rollback;
