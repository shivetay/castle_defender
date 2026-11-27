-- Testy odcinków wału i palisady (#371, migracja `*_wall_segments.sql`), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: kratki z `extra_ids` są opłacone jak zlecenie z kolejki, odcinek 3 kratek kosztuje materiały ×3 i 5 zł,
-- zapis bez tego kosztu jest odrzucony, anulowanie zwraca całość ze złotem, ukończenie niczego nie dolicza,
-- zlecenie w toku trwa czas ×N, a `extra_ids` spoza zasad gry (obcy rodzaj, brak budynku, powtórka, ponad 2,
-- inny budynek niż wał i palisada) się nie liczą. Ulepszenie odcinka (`*_wall_segment_upgrades.sql`) to suma
-- kratek ×N w koszcie i czasie, bez złota. Te same liczby liczy `tests/test_wall_segments.gd`.
-- Gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(24);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000371a1');
update public.players set rating = 63710, age = 0 where id = '00000000-0000-0000-0000-0000000371a1';

-- Zamek jak w `economy_growth_test.sql` (Dwór 1, donżon, Chata drwala 1, Koszary 1) z budynkami `p_more`
-- (dopisane do siatki), zapasami `p_amounts` i kolejką `p_queue`.
create function pg_temp.castle(p_amounts jsonb, p_more jsonb default '[]', p_queue jsonb default '[]') returns jsonb
language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings',
      '[[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2], [3, 4, 1, 10, 10, 2, 2], [4, 18, 1, 50, 50, 3, 3]]'::jsonb
        || p_more),
    'economy', jsonb_build_object('amounts', p_amounts),
    'queue', jsonb_build_object('orders', p_queue),
    'research', jsonb_build_object('done', '[]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[]'::jsonb, 'orders', '[]'::jsonb))
$$;
grant execute on function pg_temp.castle(jsonb, jsonb, jsonb) to authenticated;

create function pg_temp.push(p_castle jsonb) returns void language sql as $$
  update public.castles set data = p_castle where player_id = '00000000-0000-0000-0000-0000000371a1'
$$;
grant execute on function pg_temp.push(jsonb) to authenticated;

create function pg_temp.as_a() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000371a1", "role": "authenticated"}', true)
$$;

-- Trzy place budowy palisady (rodzaj 1) i zlecenie odcinka: główna kratka 10, dodatkowe 11 i 12.
create function pg_temp.sites() returns jsonb language sql as $$
  select '[[10, 1, 0, 20, 20, 1, 1], [11, 1, 0, 21, 20, 1, 1], [12, 1, 0, 22, 20, 1, 1]]'::jsonb
$$;
create function pg_temp.segment() returns jsonb language sql as $$
  select '[{"building_id": 10, "extra_ids": [11, 12], "kind": 1, "level": 1, "cost": [60, 0, 15, 5],
    "duration_ms": 30000, "start_ms": 0}]'::jsonb
$$;
grant execute on function pg_temp.sites() to authenticated;
grant execute on function pg_temp.segment() to authenticated;

-- ---- funkcje ----
select is((select s.extra_ids from private.segment_orders(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment())) s),
  '{11, 12}'::bigint[], 'odcinek: kratki 11 i 12');
select is((select s.gold from private.segment_orders(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment())) s),
  5::bigint, 'SEGMENT_GOLD: 3 kratki to 5 zł');
select is((select s.gold from private.segment_orders(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(),
    '[{"building_id": 10, "extra_ids": [11], "level": 1}]'::jsonb)) s), 2::bigint, '2 kratki to 2 zł');
select is((select count(*) from private.build_paid(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment())) p
    where p.queued), 3::bigint, 'trzy kratki opłacone jak zlecenie');
select is((select s.extra_ids from private.segment_orders(pg_temp.castle('[0, 0, 0, 0]',
    pg_temp.sites() || '[[13, 0, 0, 23, 20, 1, 1], [14, 1, 0, 24, 20, 1, 1]]'::jsonb,
    '[{"building_id": 10, "extra_ids": [10, 13, 99, 11, 11, 12, 14], "level": 1}]'::jsonb)) s),
  '{11, 12}'::bigint[], 'bez głównej, obcego rodzaju, brakującej i powtórki; najwyżej 2');
select is((select count(*) from private.segment_orders(pg_temp.castle('[0, 0, 0, 0]',
    '[[20, 3, 1, 20, 20, 2, 2], [21, 3, 1, 23, 20, 2, 2]]'::jsonb,
    '[{"building_id": 20, "extra_ids": [21], "level": 2}]'::jsonb)) s), 0::bigint, 'wieża nie jest odcinkiem');
select is(private.queue_head_ms(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment())), 30000::bigint,
  'zlecenie w toku: 10 s × 3 kratki');
select is(private.queue_head_ms(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(),
    '[{"building_id": 10, "level": 1}]'::jsonb)), 10000::bigint, 'zwykłe zlecenie: czas jednej kratki');
select is((select f.spend from private.build_flow(pg_temp.castle('[0, 0, 0, 0]'),
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment())) f), '{60, 0, 15, 5}'::bigint[],
  'wydatek odcinka: materiały ×3 i 5 zł');
select is((select f.refund from private.build_flow(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment()),
    pg_temp.castle('[0, 0, 0, 0]')) f), '{60, 0, 15, 5}'::bigint[], 'zwrot za anulowany odcinek: całość ze złotem');
select is((select f.refund from private.build_flow(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment()),
    pg_temp.castle('[0, 0, 0, 0]', '[[10, 1, 1, 20, 20, 1, 1], [11, 1, 1, 21, 20, 1, 1], [12, 1, 1, 22, 20, 1, 1]]')) f),
  '{0, 0, 0, 0}'::bigint[], 'ukończony odcinek: bez zwrotu');
select is((select f.spend from private.build_flow(pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment()),
    pg_temp.castle('[0, 0, 0, 0]', '[[10, 1, 1, 20, 20, 1, 1], [11, 1, 1, 21, 20, 1, 1], [12, 1, 1, 22, 20, 1, 1]]')) f),
  '{0, 0, 0, 0}'::bigint[], 'ukończony odcinek: bez nowego wydatku');
select is((select array[f.spend[4], f.refund[4]] from private.build_flow(
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), '[{"building_id": 10, "level": 1}]'::jsonb),
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.sites(), pg_temp.segment())) f), '{5, 0}'::bigint[],
  'dopisane kratki do zlecenia: dopłata jak za nowy odcinek');

-- ---- ulepszenie odcinka (*_wall_segment_upgrades.sql) ----
create function pg_temp.built() returns jsonb language sql as $$
  select '[[10, 1, 1, 20, 20, 1, 1], [11, 1, 1, 21, 20, 1, 1], [12, 1, 1, 22, 20, 1, 1]]'::jsonb
$$;
create function pg_temp.upgrade() returns jsonb language sql as $$
  select '[{"building_id": 10, "extra_ids": [11, 12], "kind": 1, "level": 2}]'::jsonb
$$;
select is((select array[cardinality(s.extra_ids), s.gold] from private.segment_orders(
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.built(), pg_temp.upgrade())) s), '{2, 0}'::bigint[],
  'ulepszenie odcinka: dwie dodatkowe kratki, bez złota');
select is((select f.spend from private.build_flow(pg_temp.castle('[0, 0, 0, 0]', pg_temp.built()),
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.built(), pg_temp.upgrade())) f), '{90, 0, 21, 0}'::bigint[],
  'wydatek ulepszenia: poziom 2 ×3 kratki');
select is((select f.refund from private.build_flow(pg_temp.castle('[0, 0, 0, 0]', pg_temp.built(), pg_temp.upgrade()),
    pg_temp.castle('[0, 0, 0, 0]', pg_temp.built())) f), '{90, 0, 21, 0}'::bigint[], 'anulowane ulepszenie: zwrot ×3');
select is((select f.spend from private.build_flow(pg_temp.castle('[0, 0, 0, 0]', pg_temp.built(), pg_temp.upgrade()),
    pg_temp.castle('[0, 0, 0, 0]', '[[10, 1, 2, 20, 20, 1, 1], [11, 1, 2, 21, 20, 1, 1], [12, 1, 2, 22, 20, 1, 1]]')) f),
  '{0, 0, 0, 0}'::bigint[], 'ukończone ulepszenie: bez nowego wydatku');
select is(private.queue_head_ms(pg_temp.castle('[0, 0, 0, 0]', pg_temp.built(), pg_temp.upgrade())), 90000::bigint,
  'ulepszenie w toku: 30 s × 3 kratki');

-- ---- zapis gracza ----
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000371a1', 3711, 12, pg_temp.castle('[500, 300, 300, 50]'));

set local role authenticated;
select pg_temp.as_a();
select throws_ok($$select pg_temp.push(pg_temp.castle('[500, 300, 300, 50]', pg_temp.sites(), pg_temp.segment()))$$,
  'PT422', 'economy_too_fast', 'odcinek bez pobranego kosztu odrzucony');
select throws_ok($$select pg_temp.push(pg_temp.castle('[480, 300, 295, 50]', pg_temp.sites(), pg_temp.segment()))$$,
  'PT422', 'economy_too_fast', 'odcinek z kosztem jednej kratki odrzucony');
select throws_ok($$select pg_temp.push(pg_temp.castle('[440, 300, 285, 50]', pg_temp.sites(), pg_temp.segment()))$$,
  'PT422', 'economy_too_fast', 'odcinek bez dopłaty w złocie odrzucony');
select lives_ok($$select pg_temp.push(pg_temp.castle('[440, 300, 285, 45]', pg_temp.sites(), pg_temp.segment()))$$,
  'odcinek 3 kratek: materiały ×3 i 5 zł');
select lives_ok($$select pg_temp.push(pg_temp.castle('[500, 300, 300, 50]'))$$,
  'anulowanie: pełny zwrot ze złotem');
reset role;
select is((select c.data -> 'economy' -> 'amounts' from public.castles c
    where c.player_id = '00000000-0000-0000-0000-0000000371a1'), '[500, 300, 300, 50]'::jsonb, 'zapasy po zwrocie');

select * from finish();
rollback;
