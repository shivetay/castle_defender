-- Testy wymuszenia aktualizacji (#336, ADR 0006), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: klient czyta progi wersji tylko przez `client_version_policy()` i nie zmieni ich; zapis
-- zamku, obrony i gracza z wersją klienta (nagłówek `x-client-version`) poniżej `min_code` albo bez
-- nagłówka kończy się błędem `update_required` (HTTP 426 w PostgREST), a serwer (service_role,
-- połączenie bez tokenu) zapisuje bez nagłówka.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(25);

-- Zamki w tym teście nie mają zgodnego bilansu (jak w rls_test.sql): kredyt bez limitu.
create function pg_temp.economy_free() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' and tg_when = 'BEFORE' then
    new.economy_credit := '{1000000000, 1000000000, 1000000000, 1000000000}';
    return new;
  end if;
  perform set_config('session_replication_role', 'replica', true);
  update public.castles set economy_credit = '{1000000000, 1000000000, 1000000000, 1000000000}',
    hide_credit = '{1000000000, 1000000000, 1000000000, 1000000000}' where player_id = new.player_id;
  perform set_config('session_replication_role', 'origin', true);
  return null;
end;
$$;
create trigger castles_economy_free before insert on public.castles
  for each row execute function pg_temp.economy_free();
create trigger castles_economy_free_after after insert or update of data on public.castles
  for each row execute function pg_temp.economy_free();

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000336a1');
insert into public.castles (player_id, map_seed, save_version, data)
  values ('00000000-0000-0000-0000-0000000336a1', 3361, 8, '{"grid": "a"}');
insert into public.defense_layouts (player_id, save_version, data)
  values ('00000000-0000-0000-0000-0000000336a1', 8, '{"traps": []}');

-- ---- polityka ----
select is(public.client_version_policy() ->> 'min_code', '0', 'startowe minimum nikogo nie blokuje');
select is(public.client_version_policy() ->> 'recommended_code', '0', 'startowa rekomendacja nikogo nie nęka');
select is(public.client_version_policy() ->> 'store_url', 'market://details?id=com.shivetay.dunhold',
  'domyślny link do sklepu');
select throws_ok($$insert into public.client_versions (id) values (false)$$, '23514', null,
  'polityka ma tylko jeden wiersz');
select throws_ok($$update public.client_versions set min_code = 700, recommended_code = 600$$, '23514', null,
  'rekomendowana wersja nie jest niższa niż minimum');

set local role anon;
select lives_ok($$select public.client_version_policy()$$, 'anon czyta politykę przed założeniem konta');
select is((select count(*)::int from public.client_versions), 1, 'anon czyta progi (publiczne z założenia)');
select throws_ok($$select updated_at from public.client_versions$$, '42501', null, 'anon czyta tylko kolumny progów');
select throws_ok($$update public.client_versions set min_code = 0$$, '42501', null, 'anon nie zmieni progów');
reset role;

-- ---- minimum 0: stary klient bez nagłówka nadal zapisuje ----
set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000336a1", "role": "authenticated"}', true);
select set_config('request.headers', '{}', true);
select lives_ok($$update public.players set nickname = 'Bolko' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'przy minimum 0 zapis bez nagłówka przechodzi');
select throws_ok($$update public.client_versions set min_code = 0$$, '42501', null,
  'gracz nie zmieni progów');
select throws_ok($$select private.require_client_version()$$, '42501', null,
  'gracz nie woła funkcji wyzwalacza');
select throws_ok($$insert into public.client_versions (id) values (false)$$, '42501', null,
  'gracz nie doda progów');
reset role;

-- ---- właścicielka podnosi minimum do 0.7.0 ----
update public.client_versions set min_code = 700, recommended_code = 701;
select is((public.client_version_policy() ->> 'min_code')::int, 700, 'polityka oddaje nowe minimum');

set local role authenticated;
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000336a1", "role": "authenticated"}', true);

select set_config('request.headers', '{"x-client-version": "600"}', true);
select throws_ok($$update public.players set nickname = 'Stary' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'PT426', 'update_required', 'stara wersja nie zmieni nicku');
select throws_ok($$update public.defense_layouts set data = '{"traps": [1]}'
    where player_id = '00000000-0000-0000-0000-0000000336a1'$$,
  'PT426', 'update_required', 'stara wersja nie zapisze obrony');
select throws_ok($$update public.castles set data = '{"grid": "stary"}'
    where player_id = '00000000-0000-0000-0000-0000000336a1'$$,
  'PT426', 'update_required', 'stara wersja nie zapisze zamku');

select set_config('request.headers', '{}', true);
select throws_ok($$update public.players set nickname = 'Brak' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'PT426', 'update_required', 'brak nagłówka to wersja sprzed #336');
select set_config('request.headers', '{"x-client-version": "7OO"}', true);
select throws_ok($$update public.players set nickname = 'Zly' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'PT426', 'update_required', 'nagłówek, który nie jest liczbą, to wersja 0');

select set_config('request.headers', '{"x-client-version": "700"}', true);
select lives_ok($$update public.players set nickname = 'Nowy' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'wersja równa minimum zmienia nick');
select lives_ok($$update public.defense_layouts set data = '{"traps": [2]}'
    where player_id = '00000000-0000-0000-0000-0000000336a1'$$,
  'wersja równa minimum zapisuje obronę');
select set_config('request.headers', '{"x-client-version": "10203"}', true);
select lives_ok($$update public.castles set data = '{"grid": "nowy", "economy": {"amounts": [0, 0, 0, 0]}}'
    where player_id = '00000000-0000-0000-0000-0000000336a1'$$,
  'nowsza wersja zapisuje zamek');
reset role;

-- ---- serwer zapisuje bez nagłówka ----
set local role service_role;
select set_config('request.jwt.claims', '{"role": "service_role"}', true);
select set_config('request.headers', '{}', true);
select lives_ok($$update public.players set nickname = 'Serwer' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'service_role (Edge Function) zapisuje bez nagłówka');
reset role;
select set_config('request.jwt.claims', '', true);
select lives_ok($$update public.players set nickname = 'Worker' where id = '00000000-0000-0000-0000-0000000336a1'$$,
  'połączenie bez tokenu (worker, SQL Editor) zapisuje bez nagłówka');

select is((select nickname from public.players where id = '00000000-0000-0000-0000-0000000336a1'), 'Worker',
  'odrzucone zapisy niczego nie zmieniły po drodze');

select * from finish();
rollback;
