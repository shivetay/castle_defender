-- Testy historii obron (#328), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: `defense_history` oddaje tylko zakończone ataki na zamek wołającego, od najnowszego,
-- najwyżej 10, z nickiem napastnika, jego armią i znacznikiem powtórki; bez ataków w toku, ataków
-- gracza na innych i cudzych obron; gracz nie woła funkcji sam (tylko service_role przez Edge Function).
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(15);

-- A i C atakują B, O to obcy gracz. Ranking w paśmie 63 280 (bez prawdziwych graczy), bo testy biegną
-- też na projekcie w chmurze, w transakcji, która się cofa.
create temp table test_ids (id uuid primary key) on commit drop;
insert into test_ids values
  ('00000000-0000-0000-0000-0000000328a1'), ('00000000-0000-0000-0000-0000000328b1'),
  ('00000000-0000-0000-0000-0000000328c1'), ('00000000-0000-0000-0000-0000000328d1');
insert into auth.users (id) select id from test_ids;
update public.players set rating = 63280, age = 0 where id in (select id from test_ids);
update public.players set nickname = 'Mieszko' where id = '00000000-0000-0000-0000-0000000328a1';
update public.players set nickname = 'Dobrawa' where id = '00000000-0000-0000-0000-0000000328c1';

-- 11 zakończonych obron B (co godzinę; najnowsza od C bez planu), atak w toku na B i atak B na O
insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot,
  attacker_army, orders, status, result, loot, started_at, finished_at)
select
  case when i = 11 then '00000000-0000-0000-0000-0000000328c1'::uuid else '00000000-0000-0000-0000-0000000328a1'::uuid end,
  '00000000-0000-0000-0000-0000000328b1', 1, i, '{}', '{}', jsonb_build_array(jsonb_build_array(0, i)),
  case when i = 11 then '[]'::jsonb else '[{"squad": 1}]'::jsonb end,
  'finished', jsonb_build_object('won', i % 2 = 0, 'percent', i * 5, 'stars', jsonb_build_array(true, false, false)),
  array[0, 0, 0, 0], now() - make_interval(hours => 20 - i), now() - make_interval(hours => 20 - i)
from generate_series(1, 11) as i;
insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot, status)
values ('00000000-0000-0000-0000-0000000328a1', '00000000-0000-0000-0000-0000000328b1', 1, 99, '{}', '{}', 'started');
insert into public.attacks (attacker_id, defender_id, map_seed, battle_seed, defense_snapshot, castle_snapshot,
  status, result, loot, finished_at)
values ('00000000-0000-0000-0000-0000000328b1', '00000000-0000-0000-0000-0000000328d1', 1, 98, '{}', '{}',
  'finished', '{"won": true, "percent": 50, "stars": [true, true, false]}', array[0, 0, 0, 0], now());

set local role service_role;
create temp table h on commit drop as
  select row_number() over () as n, * from public.defense_history('00000000-0000-0000-0000-0000000328b1');

select is((select count(*)::int from h), 10, 'najwyżej 10 obron');
select is((select battle_seed::int from public.attacks a join h on h.id = a.id where h.n = 1), 11,
  'najnowsza obrona pierwsza');
select ok((select bool_and(h.finished_at >= h2.finished_at) from h join h h2 on h2.n = h.n + 1),
  'od najnowszej');
select is((select nickname from h where n = 1), 'Dobrawa', 'nick napastnika');
select is((select nickname from h where n = 2), 'Mieszko', 'nick innego napastnika');
select is((select has_replay from h where n = 1), false, 'obrona bez planu nie ma powtórki');
select is((select has_replay from h where n = 2), true, 'obrona z planem ma powtórkę');
select is((select attacker_army from h where n = 1), '[[0, 11]]'::jsonb, 'armia napastnika ze startu');
select is((select (result ->> 'percent')::int from h where n = 1), 55, 'wynik z serwera');
select ok(not exists (select 1 from h join public.attacks a on a.id = h.id where a.status <> 'finished'),
  'bez ataku w toku');
select is((select count(*)::int from public.defense_history('00000000-0000-0000-0000-0000000328a1')), 0,
  'atakujący nie widzi swoich ataków jako obron');
select is((select count(*)::int from public.defense_history('00000000-0000-0000-0000-0000000328d1')), 1,
  'obcy gracz widzi tylko obronę na swoim zamku');
select is((select count(*)::int from public.defense_history(null)), 0, 'bez gracza nic');

-- ---- gracz nie woła funkcji sam ----
reset role;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000328b1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select * from public.defense_history('00000000-0000-0000-0000-0000000328b1')$$,
  '42501', null, 'gracz nie wywoła defense_history');
reset role;
set local role anon;
select throws_ok($$select * from public.defense_history('00000000-0000-0000-0000-0000000328b1')$$,
  '42501', null, 'anon nie wywoła defense_history');

select * from finish();
rollback;
