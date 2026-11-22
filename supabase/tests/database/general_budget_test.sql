-- Testy budżetu generałów (#31), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: przy zapisie zamku serwer zostawia generałów tylko w granicach złota (start + fale PvE + łupy
-- z zakończonych ataków) i PD (40 za bitwę); boty i fale PvE wystarczą najwyżej na poziom 2, a poziom 3
-- wymaga złota i PD z PvP; generał bez pokrycia traci poziomy albo znika; uczciwy zapis przechodzi bez
-- zmian; generał ataku w PvP pochodzi z przyciętego zapisu; gracz nie woła funkcji sam.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(12);

create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000031d1'), ('00000000-0000-0000-0000-0000000031e1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 63200, age = 0 where id in (select id from test_ids);

create function pg_temp.save(p_generals jsonb) returns jsonb language sql as $$
  insert into public.castles as c (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000031d1', 3131, 11, jsonb_build_object('generals', p_generals))
  on conflict (player_id) do update set data = excluded.data
  returning c.data -> 'generals'
$$;

-- bez ataków: 175 złota i 200 PD (fale PvE) wystarczą na rekrutację i poziom 2, ale nie na poziom 3
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 2, "xp": 0, "perk": -1}], "attack": 0, "pvp_gold": 0}'),
  '{"roster": [{"kind": 0, "level": 2, "xp": 0, "perk": -1}], "attack": 0, "pvp_gold": 0}'::jsonb,
  'uczciwy zapis z PvE bez zmian');
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 3, "xp": 0, "perk": 0}]}') -> 'roster' -> 0,
  '{"kind": 0, "level": 2, "xp": 0, "perk": -1}'::jsonb, 'bez PvP poziom 3 spada do 2');
select is(jsonb_array_length(pg_temp.save('{"roster": [{"kind": 0, "level": 2}, {"kind": 1, "level": 1},
  {"kind": 2, "level": 1}]}') -> 'roster'), 1, 'na drugiego generała brakuje złota: znika z kolejnymi');

-- 20 wygranych z botem z łupem 100 złota: złoto ogółem rośnie, ale PvP nadal zero
insert into public.attacks (attacker_id, bot_idx, battle_seed, status, result, loot, finished_at)
select '00000000-0000-0000-0000-0000000031d1', 0, g, 'finished',
  '{"won": true, "percent": 60, "stars": [false, true, true]}', array[0, 0, 0, 100], now()
from generate_series(1, 20) g;
select is(pg_temp.save('{"roster": [{"kind": 1, "level": 3, "xp": 0, "perk": 0}], "pvp_gold": 500}'),
  '{"roster": [{"kind": 1, "level": 2, "xp": 0, "perk": -1}], "attack": -1, "pvp_gold": 0}'::jsonb,
  'złoto z botów nie daje poziomu 3, a pula PvP z telefonu jest przycięta');
select is(jsonb_array_length(pg_temp.save('{"roster": [{"kind": 0, "level": 2}, {"kind": 1, "level": 2},
  {"kind": 2, "level": 2}]}') -> 'roster'), 3, 'złoto z botów starcza na trzech generałów poziomu 2');
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 2, "xp": 120}]}') -> 'roster' -> 0 -> 'xp',
  '0'::jsonb, 'od poziomu 2 boty nie dają PD');

-- 8 ataków na gracza z łupem 30 złota: 240 złota i 320 PD z PvP
insert into public.attacks (attacker_id, defender_id, battle_seed, status, result, loot, finished_at)
select '00000000-0000-0000-0000-0000000031d1', '00000000-0000-0000-0000-0000000031e1', 100 + g, 'finished',
  '{"won": true, "percent": 60, "stars": [false, true, true]}', array[0, 0, 0, 30], now()
from generate_series(1, 8) g;
-- atak w toku i porzucony się nie liczą
insert into public.attacks (attacker_id, defender_id, battle_seed, status, loot)
values ('00000000-0000-0000-0000-0000000031d1', '00000000-0000-0000-0000-0000000031e1', 99, 'abandoned',
  array[0, 0, 0, 5000]);
select is(pg_temp.save('{"roster": [{"kind": 1, "level": 3, "xp": 10, "perk": 0}], "attack": 1, "pvp_gold": 90}'),
  '{"roster": [{"kind": 1, "level": 3, "xp": 10, "perk": 0}], "attack": 1, "pvp_gold": 90}'::jsonb,
  'poziom 3 z PvP bez zmian');
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 3}, {"kind": 1, "level": 3}]}') -> 'roster' -> 1 -> 'level',
  '2'::jsonb, 'złota z PvP starcza tylko na jeden poziom 3');
select is(pg_temp.save('{"roster": [{"kind": 0}, {"kind": 0}, {"kind": 7}, "x"], "attack": 2}') -> 'attack',
  '-1'::jsonb, 'generał ataku tylko spośród zostawionych');

-- generał ataku w PvP z przyciętego zapisu
select lives_ok($$select pg_temp.save('{"roster": [{"kind": 1, "level": 3, "perk": 1}, {"kind": 0, "level": 3}]}')$$,
  'zapis dwóch generałów poziomu 3');
select is(private.castle_general((select data from public.castles where player_id = '00000000-0000-0000-0000-0000000031d1'), 0),
  '{"kind": 0, "level": 2, "perk": -1}'::jsonb, 'launch_attack widzi tylko generała z pokryciem');

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000031d1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select private.checked_generals('00000000-0000-0000-0000-0000000031d1', '{}')$$, '42501', null,
  'gracz nie woła checked_generals');

select * from finish();
rollback;
