-- Testy budżetu generałów (#31), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: przy zapisie zamku serwer zostawia generałów tylko w granicach złota (start + fale PvE + łupy
-- z zakończonych ataków) i PD (40 za bitwę); generał bez pokrycia traci poziomy albo znika; uczciwy zapis
-- przechodzi bez zmian; generał ataku w PvP pochodzi z przyciętego zapisu; gracz nie woła funkcji sam.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

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

-- bez ataków: 175 złota, 200 PD, więc nawet jeden generał (300 złota) nie ma pokrycia
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 1, "xp": 20, "perk": -1}], "attack": 0}'),
  '{"roster": [], "attack": -1}'::jsonb, 'bez złota z łupów generał znika');

-- 10 zakończonych ataków z łupem 100 złota: 1175 złota, 600 PD
insert into public.attacks (attacker_id, defender_id, battle_seed, status, result, loot, finished_at)
select '00000000-0000-0000-0000-0000000031d1', '00000000-0000-0000-0000-0000000031e1', g, 'finished',
  '{"won": true, "percent": 60, "stars": [false, true, true]}', array[0, 0, 0, 100], now()
from generate_series(1, 10) g;
-- atak w toku i porzucony się nie liczą
insert into public.attacks (attacker_id, defender_id, battle_seed, status, loot)
values ('00000000-0000-0000-0000-0000000031d1', '00000000-0000-0000-0000-0000000031e1', 99, 'abandoned',
  array[0, 0, 0, 5000]);

select is(pg_temp.save('{"roster": [{"kind": 0, "level": 2, "xp": 40, "perk": -1}], "attack": 0}'),
  '{"roster": [{"kind": 0, "level": 2, "xp": 40, "perk": -1}], "attack": 0}'::jsonb, 'uczciwy zapis bez zmian');
select is(pg_temp.save('{"roster": [{"kind": 1, "level": 3, "xp": 0, "perk": 0}], "attack": 1}') -> 'roster' -> 0,
  '{"kind": 1, "level": 2, "xp": 0, "perk": -1}'::jsonb, 'na poziom 3 brakuje złota: poziom 2, bez perka');
select is(jsonb_array_length(pg_temp.save('{"roster": [{"kind": 0, "level": 2, "xp": 0}, {"kind": 1, "level": 2, "xp": 0},
  {"kind": 2, "level": 1, "xp": 0}]}') -> 'roster'), 2, 'trzeci generał bez złota znika');
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 2, "xp": 0}, {"kind": 1, "level": 2, "xp": 0}]}') -> 'roster' -> 1 -> 'level',
  '1'::jsonb, 'drugiemu starcza tylko na rekrutację');
select is(pg_temp.save('{"roster": [{"kind": 0, "level": 1, "xp": 300}]}') -> 'roster' -> 0 -> 'xp',
  '300'::jsonb, 'PD w limicie bitew');
select is(pg_temp.save('{"roster": [{"kind": 0}, {"kind": 0}, {"kind": 7}, "x"], "attack": 2}'),
  '{"roster": [{"kind": 0, "level": 1, "xp": 0, "perk": -1}], "attack": -1}'::jsonb,
  'powtórzony, nieznany i zły wpis odpadają, generał ataku tylko spośród zostawionych');

-- PD: bez bitew (tylko fale PvE) 200 PD nie starczy na poziom 3 (100 + 300)
reset role;
delete from public.attacks where attacker_id = '00000000-0000-0000-0000-0000000031d1' and status = 'finished'
  and battle_seed > 2;
update public.attacks set loot = array[0, 0, 0, 1000] where attacker_id = '00000000-0000-0000-0000-0000000031d1'
  and status = 'finished';
-- 2175 złota, ale tylko (2 + 5) × 40 = 280 PD
select is(pg_temp.save('{"roster": [{"kind": 1, "level": 3, "xp": 250, "perk": 1}]}') -> 'roster' -> 0,
  '{"kind": 1, "level": 2, "xp": 180, "perk": -1}'::jsonb, 'poziom bez pokrycia w PD spada, PD przycięte');

-- generał ataku w PvP z przyciętego zapisu
select is(private.castle_general((select data from public.castles where player_id = '00000000-0000-0000-0000-0000000031d1'), 1),
  '{"kind": 1, "level": 2, "perk": -1}'::jsonb, 'launch_attack widzi tylko generała z pokryciem');

-- zapis zamku bez generałów zostaje bez nich
update public.castles set data = '{"grid": {}}' where player_id = '00000000-0000-0000-0000-0000000031d1';
select ok(not ((select data from public.castles where player_id = '00000000-0000-0000-0000-0000000031d1') ? 'generals'),
  'zapis bez generałów bez zmian');

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000031d1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select private.checked_generals('00000000-0000-0000-0000-0000000031d1', '{}')$$, '42501', null,
  'gracz nie woła checked_generals');

select * from finish();
rollback;
