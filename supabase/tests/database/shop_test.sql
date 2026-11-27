-- Testy sklepu w Targu (#408, ADR 0014, migracja `*_shop.sql`), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: zapis grup i ofert tylko admin (app_metadata.role = admin), bez DELETE; gracz widzi tylko aktywne
-- grupy w oknie i ich aktywne oferty, a z odbiorów tylko swoje; anon nic. CHECK: najwyżej 3 oferty na grupę,
-- złoto do 100, inne do 2000, odnowienie od 60 minut. Archiwum grupy zabiera oferty, przywrócenie oddaje je
-- nieaktywne (grupa też nieaktywna). Odbiór tylko przez service_role: odnowienie (cooldown), pełny magazyn
-- (storage_full), nagroda w castle_loot_pending i złoto w private.ruler_gold_left.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(72);

insert into auth.users (id) values
  ('00000000-0000-0000-0000-0000000408f1'),  -- admin
  ('00000000-0000-0000-0000-0000000408a2'),  -- gracz A
  ('00000000-0000-0000-0000-0000000408b2');  -- gracz B

create function pg_temp.as_admin() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000408f1", "role": "authenticated",
    "app_metadata": {"role": "admin"}}', true)
$$;
create function pg_temp.as_a() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000408a2", "role": "authenticated"}', true)
$$;
create function pg_temp.as_b() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000408b2", "role": "authenticated",
    "user_metadata": {"role": "admin"}}', true)
$$;
create function pg_temp.as_server() returns void language sql as $$
  select set_config('request.jwt.claims', '', true)
$$;

-- Zamek: Dwór 1, donżon, Chata drwala 1 (pojemność 1000), zapasy `p_amounts`.
create function pg_temp.castle(p_amounts jsonb) returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings', '[[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2], [3, 4, 1, 10, 10, 2, 2]]'::jsonb),
    'economy', jsonb_build_object('amounts', p_amounts),
    'research', jsonb_build_object('done', '[]'::jsonb))
$$;
grant execute on function pg_temp.castle(jsonb) to authenticated;
create temp table ids (name text primary key, id bigint);
grant select, insert on ids to authenticated, service_role;

-- ---- RLS i admin ----
select ok((select bool_and(c.relrowsecurity) from pg_class c
    where c.oid in ('public.shop_groups'::regclass, 'public.shop_offers'::regclass, 'public.shop_claims'::regclass)),
  'RLS na wszystkich tabelach sklepu');
select pg_temp.as_admin();
select ok(public.is_admin(), 'admin z app_metadata');
select pg_temp.as_b();
select ok(not public.is_admin(), 'user_metadata nie daje admina');

-- ---- admin zapisuje ----
select pg_temp.as_admin();
set local role authenticated;
select lives_ok($$with x as (insert into public.shop_groups (name, sort_order, active, updated_by)
    values ('Na start', 1, true, '00000000-0000-0000-0000-0000000408a2') returning id) insert into ids select 'g1', id from x$$, 'admin dodaje grupę');
reset role;
select is((select updated_by from public.shop_groups where id = (select id from ids where name = 'g1')),
  '00000000-0000-0000-0000-0000000408f1'::uuid, 'updated_by z tokenu, nie z żądania');
select pg_temp.as_admin();
set local role authenticated;
select lives_ok($$
  with x as (insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes, active)
    values ((select id from ids where name = 'g1'), 1, 'Drewno', 0, 200, 60, true) returning id) insert into ids select 'o_wood', id from x;
  with x as (insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes, active)
    values ((select id from ids where name = 'g1'), 2, 'Złoto', 3, 100, 120, true) returning id) insert into ids select 'o_gold', id from x;
  with x as (insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes, active)
    values ((select id from ids where name = 'g1'), 3, 'Kamień', 1, 2000, 60, true) returning id) insert into ids select 'o_big', id from x$$,
  'admin dodaje 3 oferty');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 4, 'Czwarta', 0, 10, 60)$$, '23514', null, 'slot 4 odrzucony (maks. 3)');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Druga w slocie', 0, 10, 60)$$, '23505', null,
  'druga żywa oferta w slocie odrzucona');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Za dużo złota', 3, 101, 60)$$, '23514', null, 'złoto ponad 100 odrzucone');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Za dużo drewna', 0, 2001, 60)$$, '23514', null, 'drewno ponad 2000 odrzucone');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Za szybko', 0, 10, 59)$$, '23514', null, 'odnowienie poniżej 60 minut odrzucone');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Zero', 0, 0, 60)$$, '23514', null, 'ilość 0 odrzucona');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Nieznany', 4, 10, 60)$$, '23514', null, 'nieznany surowiec odrzucony');
select throws_ok($$insert into public.shop_groups (name, starts_at, ends_at) values ('Okno', now(), now())$$,
  '23514', null, 'okno z końcem nie po początku odrzucone');
select throws_ok($$insert into public.shop_groups (name) values ('')$$, '23514', null, 'pusta nazwa odrzucona');
select throws_ok($$insert into public.shop_groups (name) values ('Nazwa dłuższa niż dwadzieścia cztery')$$, '23514', null,
  'nazwa ponad 24 znaki odrzucona');
select throws_ok($$insert into public.shop_groups (name, updated_at) values ('Data', now() - interval '1 day')$$, '42501', null,
  'updated_at ustawia tylko wyzwalacz');
select throws_ok($$delete from public.shop_offers where id = (select id from ids where name = 'o_big')$$, '42501', null,
  'admin nie usuwa (archiwum zamiast DELETE)');
select throws_ok($$delete from public.shop_groups where id = (select id from ids where name = 'g1')$$, '42501', null,
  'admin nie usuwa grup');
-- grupy niewidoczne dla gracza: nieaktywna, przyszłe okno, minione okno
select lives_ok($$
  with x as (insert into public.shop_groups (name, active) values ('Wyłączona', false) returning id) insert into ids select 'g_off', id from x;
  with x as (insert into public.shop_groups (name, active, starts_at)
    values ('Jutro', true, now() + interval '1 day') returning id) insert into ids select 'g_future', id from x;
  with x as (insert into public.shop_groups (name, active, starts_at, ends_at)
    values ('Wczoraj', true, now() - interval '2 days', now() - interval '1 day') returning id) insert into ids select 'g_past', id from x;
  insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes, active)
    select id, 1, 'Ukryta', 0, 10, 60, true from ids where name in ('g_off', 'g_future', 'g_past');
  with x as (insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes, active)
    values ((select id from ids where name = 'g_off'), 2, 'Nieaktywna', 0, 10, 60, false) returning id) insert into ids select 'o_inactive', id from x$$,
  'admin dodaje grupy poza oknem');
select throws_ok($$select updated_by from public.shop_offers$$, '42501', null, 'admin też nie czyta updated_by przez API');
select is((select count(*)::integer from public.shop_groups), 4, 'admin widzi wszystkie grupy');
select is((select count(*)::integer from public.shop_offers), 7, 'admin widzi wszystkie oferty');
reset role;

-- ---- gracz i anon ----
select pg_temp.as_a();
set local role authenticated;
select is((select array_agg(name order by id) from public.shop_groups), array['Na start'], 'gracz widzi tylko widoczną grupę');
select is((select count(*)::integer from public.shop_offers), 3, 'gracz widzi tylko oferty widocznej grupy');
select throws_ok($$insert into public.shop_groups (name, active) values ('Moja', true)$$, '42501', null,
  'gracz nie doda grupy');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g_off'), 3, 'Moja', 3, 100, 60)$$, '42501', null, 'gracz nie doda oferty');
select is_empty($$update public.shop_offers set amount = 2000
    where id = (select id from ids where name = 'o_wood') returning 1$$, 'gracz nie zmieni oferty');
select is_empty($$update public.shop_groups set active = true
    where id = (select id from ids where name = 'g_off') returning 1$$, 'gracz nie włączy grupy');
select throws_ok($$delete from public.shop_offers$$, '42501', null, 'gracz nie usuwa ofert');
select throws_ok($$insert into public.shop_claims (player_id, offer_id, resource, amount)
    values ('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_wood'), 0, 300)$$, '42501', null,
  'gracz nie wpisze odbioru');
select throws_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408a2', 1)$$, '42501', null,
  'gracz nie woła claim_offer');
select throws_ok($$select updated_by from public.shop_groups$$, '42501', null, 'gracz nie czyta updated_by grup (uuid admina)');
select throws_ok($$select updated_by from public.shop_offers$$, '42501', null, 'gracz nie czyta updated_by ofert');
select throws_ok($$select * from public.shop_groups$$, '42501', null, 'select * zawiera updated_by, więc też odmowa');
select is((select count(*)::integer from public.shop_catalog()), 3, 'katalog gracza: 3 oferty widocznej grupy');
select ok((select bool_and(next_available_at is null) from public.shop_catalog()), 'nowy gracz: wszystko do odbioru');
reset role;
select pg_temp.as_b();
set local role authenticated;
select is_empty($$update public.shop_offers set amount = 2000 returning 1$$,
  'user_metadata.role = admin nie daje zapisu');
reset role;
select is((select amount from public.shop_offers where id = (select id from ids where name = 'o_wood')), 200,
  'oferta nietknięta');
set local role anon;
select throws_ok($$select * from public.shop_groups$$, '42501', null, 'anon nie czyta grup');
select throws_ok($$select * from public.shop_offers$$, '42501', null, 'anon nie czyta ofert');
select throws_ok($$select * from public.shop_claims$$, '42501', null, 'anon nie czyta odbiorów');
select throws_ok($$select * from public.shop_catalog()$$, '42501', null, 'anon nie woła katalogu');
reset role;

-- ---- odbiór ----
select pg_temp.as_a();
set local role authenticated;
insert into public.castles (player_id, map_seed, save_version, data)
values ('00000000-0000-0000-0000-0000000408a2', 1, 12, pg_temp.castle('[480, 300, 280, 50]'));
reset role;
select pg_temp.as_server();
set local role service_role;
select is(private.ruler_gold_left('00000000-0000-0000-0000-0000000408a2', '{}', 0), 175::bigint, 'złoto z pokryciem przed sklepem');
select is((select amount from public.claim_offer('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_wood'))),
  200, 'odbiór drewna');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000408a2'),
  '{200, 0, 0, 0}'::bigint[], 'nagroda czeka na zapis zamku');
select throws_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_wood'))$$,
  'P0001', 'cooldown', 'drugi odbiór przed końcem odnowienia odrzucony');
select is((select count(*)::integer from public.shop_claims), 1, 'jeden odbiór mimo ponowienia');
select throws_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_big'))$$,
  'P0001', 'storage_full', 'kamień 300 + 2000 ponad magazyn 1000 odrzucony');
select is((select amount from public.claim_offer('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_gold'))),
  100, 'odbiór złota (bez magazynu)');
select is(private.ruler_gold_left('00000000-0000-0000-0000-0000000408a2', '{}', 0), 275::bigint,
  'złoto z ofert w private.ruler_gold_left');
select throws_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_inactive'))$$,
  'P0001', 'offer_unavailable', 'nieaktywna oferta niedostępna');
select throws_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408b2', (select id from ids where name = 'o_wood'))$$,
  'P0001', 'no_castle', 'gracz bez zamku nie odbiera');
select throws_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408a2', -1)$$,
  'P0001', 'offer_unavailable', 'nieznana oferta');
reset role;
-- odnowienie liczy się od ostatniego odbioru: po 60 minutach drewno znowu do odbioru
update public.shop_claims set claimed_at = claimed_at - interval '61 minutes'
where offer_id = (select id from ids where name = 'o_wood');
set local role service_role;
select lives_ok($$select * from public.claim_offer('00000000-0000-0000-0000-0000000408a2', (select id from ids where name = 'o_wood'))$$,
  'po odnowieniu odbiór znowu przechodzi');
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000408a2'),
  '{400, 0, 0, 100}'::bigint[], 'nagrody sumują się w łupie czekającym');
reset role;

-- zapis zamku scala nagrody (drewno do pojemności, złoto z pokryciem)
select pg_temp.as_a();
set local role authenticated;
select lives_ok($$update public.castles set data = pg_temp.castle('[480, 300, 280, 50]')
    where player_id = '00000000-0000-0000-0000-0000000408a2'$$, 'zapis zamku po odbiorze złota bez gold_unbacked');
select is((select loot_applied from public.castles where player_id = '00000000-0000-0000-0000-0000000408a2'),
  '{400, 0, 0, 100}'::integer[], 'telefon dostaje nagrody w loot_applied');
select is((select count(*)::integer from public.shop_claims), 3, 'gracz widzi swoje odbiory');
select ok((select next_available_at > now() from public.shop_catalog() where offer_id = (select id from ids where name = 'o_wood')),
  'katalog: drewno w odnowieniu');
select ok((select next_available_at is null from public.shop_catalog() where offer_id = (select id from ids where name = 'o_big')),
  'katalog: kamień do odbioru');
reset role;
select pg_temp.as_b();
set local role authenticated;
select is((select count(*)::integer from public.shop_claims), 0, 'obcy gracz nie widzi cudzych odbiorów');
select ok((select bool_and(next_available_at is null) from public.shop_catalog()), 'obcy gracz ma własne odnowienia');
reset role;

-- ---- archiwum ----
select pg_temp.as_admin();
set local role authenticated;
select lives_ok($$update public.shop_groups set archived_at = now() where id = (select id from ids where name = 'g1')$$,
  'admin archiwizuje grupę');
select is((select count(*)::integer from public.shop_offers where group_id = (select id from ids where name = 'g1')
    and archived_at is null), 0, 'archiwizacja grupy zabiera jej oferty');
select throws_ok($$insert into public.shop_offers (group_id, slot, name, resource, amount, cooldown_minutes)
    values ((select id from ids where name = 'g1'), 1, 'Nowa', 0, 10, 60)$$, 'P0001', 'group_archived',
  'nie da się dodać oferty do zarchiwizowanej grupy');
select lives_ok($$update public.shop_groups set archived_at = null where id = (select id from ids where name = 'g1')$$,
  'admin przywraca grupę');
select is((select active from public.shop_groups where id = (select id from ids where name = 'g1')), false,
  'przywrócona grupa jest nieaktywna');
select is((select count(*)::integer from public.shop_offers where group_id = (select id from ids where name = 'g1')
    and archived_at is null and not active), 3, 'oferty wracają z grupą, nieaktywne');
select lives_ok($$update public.shop_offers set archived_at = now() where id = (select id from ids where name = 'o_gold');
  update public.shop_offers set active = true where id = (select id from ids where name = 'o_gold')$$,
  'admin archiwizuje ofertę');
select lives_ok($$update public.shop_offers set archived_at = null where id = (select id from ids where name = 'o_gold')$$,
  'admin przywraca ofertę');
select is((select active from public.shop_offers where id = (select id from ids where name = 'o_gold')), false,
  'przywrócona oferta jest nieaktywna');
reset role;

select * from finish();
rollback;
