-- Testy bilansu surowców w zapisie zamku (#282), uruchamiane przez `supabase test db` (pgTAP).
-- Kryteria: zapasy nie rosną szybciej niż produkcja od poprzedniego zapisu (z tolerancją 5 minut produkcji
-- łącznie), budowa, badania i rekrutacja mają pokrycie w surowcach, zwrot za anulowane zlecenie liczy się raz,
-- nagroda fali PvE wchodzi tylko z wyniku przyjętego przez serwer (#288), zapasy nie spadają bez wydatku
-- (obrońca nie schowa łupu), mniejszy magazyn i scalony łup przechodzą, łup z zamku-bota przenosi serwer,
-- złoto po najeździe nie wraca, serwer pisze bez bilansu, a gracz nie ustawi kolumn bilansu.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(44);

insert into auth.users (id) values ('00000000-0000-0000-0000-0000000282a1');
update public.players set rating = 62820, age = 0 where id = '00000000-0000-0000-0000-0000000282a1';

-- Zamek: Dwór 1, donżon, Chata drwala 1 i Koszary 1 (produkcja 80 drewna, 20 kamienia, 20 żywności na godzinę),
-- zapasy `p_amounts`; `p_extra` nadpisuje części zapisu.
create function pg_temp.castle(p_amounts jsonb, p_extra jsonb default '{}') returns jsonb language sql as $$
  select jsonb_build_object(
    'profile', jsonb_build_object('castle_name', 'Gród'),
    'grid', jsonb_build_object('buildings',
      '[[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2], [3, 4, 1, 10, 10, 2, 2], [4, 18, 1, 50, 50, 3, 3]]'::jsonb),
    'economy', jsonb_build_object('amounts', p_amounts),
    'research', jsonb_build_object('done', '[]'::jsonb),
    'recruitment', jsonb_build_object('squads', '[]'::jsonb, 'orders', '[]'::jsonb)) || p_extra
$$;
grant execute on function pg_temp.castle(jsonb, jsonb) to authenticated;

-- Zapis jak z telefonu (PATCH).
create function pg_temp.push(p_amounts jsonb, p_extra jsonb default '{}') returns void language sql as $$
  update public.castles set data = pg_temp.castle(p_amounts, p_extra) where player_id = '00000000-0000-0000-0000-0000000282a1'
$$;
grant execute on function pg_temp.push(jsonb, jsonb) to authenticated;

-- Poprzedni zapis zamku sprzed `p_ago` (zegar serwera): bump_revision ustawia updated_at na teraz.
create function pg_temp.age_castle(p_ago interval) returns void language plpgsql as $$
begin
  alter table public.castles disable trigger castles_bump_revision;
  update public.castles set updated_at = now() - p_ago where player_id = '00000000-0000-0000-0000-0000000282a1';
  alter table public.castles enable trigger castles_bump_revision;
end;
$$;

create function pg_temp.as_a() returns void language sql as $$
  select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000282a1", "role": "authenticated"}', true)
$$;

-- ---- funkcje bilansu ----
select is(private.production_max(pg_temp.castle('[0, 0, 0, 0]'), pg_temp.castle('[0, 0, 0, 0]')), '{80, 20, 20, 0}'::bigint[],
  'produkcja: gród i Chata drwala 1');
select is(private.production_max(pg_temp.castle('[0, 0, 0, 0]'),
    pg_temp.castle('[0, 0, 0, 0]', '{"research": {"done": ["G1", "G25"]}}')),
  '{104, 22, 22, 0}'::bigint[], 'produkcja z G1 i Gospodarnym z któregokolwiek zapisu');
select is(private.production_max(pg_temp.castle('[0, 0, 0, 0]'), pg_temp.castle('[0, 0, 0, 0]',
    '{"grid": {"buildings": [[1, 5, 2, 30, 30, 4, 4], [5, 6, 2, 10, 20, 2, 2]]}}')),
  '{80, 20, 38, 0}'::bigint[], 'Chata myśliwego 2: żywność z przepisu (2 × 9 cykli), budynek z wyższego zapisu');
select is(private.consumption_max(pg_temp.castle('[0, 0, 0, 0]'), pg_temp.castle('[0, 0, 0, 0]',
    '{"grid": {"buildings": [[1, 5, 1, 30, 30, 4, 4], [6, 17, 1, 10, 20, 3, 3]]}, "recruitment": {"squads": [[1, 0, 7]]}}')),
  '{0, 0, 17, 0}'::bigint[], 'zużycie: Stajnia (10 żywności na konia) i utrzymanie 7 toporników');
select is(private.build_cost(5, 2), '{300, 200, 200, 0}'::bigint[], 'koszt Dworu 2');
select is(private.build_cost(4, 6), '{680, 0, 255, 0}'::bigint[], 'Chata drwala na poziomie 1 epoki II: 850 procent (#262)');
select is(private.research_cost(0, 2), '{256, 128, 128, 0}'::bigint[], 'trzecia technologia epoki I: ×1,6 dwa razy');
select is(private.pve_reward(0, 5), '{1250, 800, 1250, 125}'::bigint[], 'nagrody wszystkich fal PvE');

-- ---- pierwszy zapis: od zapasów nowej gry ----
set local role authenticated;
select pg_temp.as_a();
select throws_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000282a1', 2821, 12, pg_temp.castle('[1000, 280, 230, 50]'))$$,
  'PT422', 'economy_too_fast', 'nowe konto: drewno ponad start i 6 godzin produkcji odrzucone');
select lives_ok(
  $$insert into public.castles (player_id, map_seed, save_version, data)
    values ('00000000-0000-0000-0000-0000000282a1', 2821, 12, pg_temp.castle('[320, 280, 230, 50]'))$$,
  'nowe konto: start minus Chata drwala i Koszary');
select throws_ok($$select pg_temp.push('[340, 280, 230, 50]')$$, 'PT422', 'economy_too_fast',
  'przyrost bez upływu czasu odrzucony');
reset role;

-- ---- produkcja w czasie ----
select pg_temp.age_castle(interval '1 hour');
set local role authenticated;
select lives_ok($$select pg_temp.push('[400, 300, 250, 50]')$$, 'godzina produkcji przechodzi');
reset role;
select pg_temp.age_castle(interval '1 hour');
set local role authenticated;
select throws_ok($$select pg_temp.push('[520, 320, 270, 50]')$$, 'PT422', 'economy_too_fast',
  'drewno ponad godzinę produkcji odrzucone');

-- ---- budowa: koszt przy zleceniu, zwrot przy anulowaniu ----
select throws_ok($$select pg_temp.push('[480, 320, 270, 50]', '{"queue": {"orders": [{"building_id": 1, "level": 2}]}}')$$,
  'PT422', 'economy_too_fast', 'zlecenie Dworu 2 bez kosztu odrzucone');
select lives_ok($$select pg_temp.push('[180, 120, 70, 50]', '{"queue": {"orders": [{"building_id": 1, "level": 2}]}}')$$,
  'zlecenie Dworu 2 z kosztem przechodzi');
select lives_ok($$select pg_temp.push('[480, 320, 270, 50]')$$, 'anulowane zlecenie oddaje koszt');
select throws_ok($$select pg_temp.push('[780, 320, 270, 50]')$$, 'PT422', 'economy_too_fast',
  'zwrot za anulowane zlecenie liczy się raz');
reset role;

-- ---- badania i rekrutacja ----
select pg_temp.age_castle(interval '2 minutes');
set local role authenticated;
select throws_ok($$select pg_temp.push('[480, 320, 270, 50]', '{"research": {"done": ["A1"]}}')$$,
  'PT422', 'economy_too_fast', 'A1 bez kosztu odrzucone');
select lives_ok($$select pg_temp.push('[380, 270, 220, 50]', '{"research": {"done": ["A1"]}}')$$, 'A1 z kosztem przechodzi');
reset role;
select pg_temp.age_castle(interval '10 minutes');
set local role authenticated;
select throws_ok($$select pg_temp.push('[380, 270, 220, 50]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}}')$$,
  'PT422', 'economy_too_fast', 'czterech chłopów bez żywności odrzuconych');
select lives_ok($$select pg_temp.push('[380, 270, 203, 50]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}}')$$,
  'czterech chłopów za 20 żywności przechodzi');

-- ---- nagrody fal PvE (#288: tylko z wyniku fali przyjętego przez serwer) ----
select throws_ok($$select pg_temp.push('[480, 320, 303, 60]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'PT422', 'economy_too_fast', 'skok pve.cleared bez wyniku fali nie daje nagrody (#288)');
reset role;
select set_config('request.jwt.claims', '', true);
set local role service_role;
create temp table wave_run as select * from public.begin_wave('00000000-0000-0000-0000-0000000282a1', 0);
update public.pve_wave_runs set started_at = now() - interval '1 minute' where id = (select run_id from wave_run);
select is((select status from public.end_wave('00000000-0000-0000-0000-0000000282a1', (select run_id from wave_run), true)),
  'won', 'serwer przyjął wygraną pierwszą falę');
reset role;
select pg_temp.as_a();
set local role authenticated;
select lives_ok($$select pg_temp.push('[380, 270, 203, 50]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'zapis po fali przechodzi bez nagrody z telefonu');
select is((select data -> 'economy' -> 'amounts' from public.castles where player_id = '00000000-0000-0000-0000-0000000282a1'),
  '[480, 320, 303, 60]'::jsonb, 'nagrodę za pierwszą falę dopisał serwer po bilansie');
select lives_ok($$select pg_temp.push('[480, 320, 303, 60]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 0}}')$$,
  'zapis z cofniętym licznikiem fal przechodzi');
select throws_ok($$select pg_temp.push('[580, 320, 303, 60]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'PT422', 'economy_too_fast', 'ta sama fala drugi raz nic nie daje');
select throws_ok($$select pg_temp.push('[480, 320, 303, 65]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'PT422', 'economy_too_fast', 'złoto bez źródła odrzucone');

-- ---- chowanie zapasów ----
select throws_ok($$select pg_temp.push('[0, 0, 0, 0]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'PT422', 'economy_hidden', 'zera bez wydatku odrzucone (obrońca nie schowa łupu)');
select lives_ok($$select pg_temp.push('[430, 320, 303, 60]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'mały spadek bez widocznego wydatku mieści się w zapasie');
select throws_ok($$select pg_temp.push('[370, 320, 303, 60]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'PT422', 'economy_hidden', 'zapas na niewidoczne wydatki jest łączny, nie na zapis');
select throws_ok($$update public.castles set data = '{"profile": {"castle_name": "Gród"}}'
    where player_id = '00000000-0000-0000-0000-0000000282a1'$$,
  'PT422', 'economy_missing', 'zapis bez economy odrzucony');

-- ---- gracz nie ustawia kolumn bilansu ----
select throws_ok($$update public.castles set economy_credit = '{999999, 0, 0, 0}'
    where player_id = '00000000-0000-0000-0000-0000000282a1'$$, '42501', null, 'gracz nie ustawi kredytu produkcji');
select throws_ok($$update public.castles set hide_credit = '{999999, 0, 0, 0}'
    where player_id = '00000000-0000-0000-0000-0000000282a1'$$, '42501', null, 'gracz nie ustawi zapasu na wydatki');
select throws_ok($$update public.castles set pve_rewarded = 0
    where player_id = '00000000-0000-0000-0000-0000000282a1'$$, '42501', null, 'gracz nie cofnie nagrodzonych fal');
reset role;

-- ---- łup z zamku-bota przenosi serwer ----
select set_config('request.jwt.claims', '', true);
set local role service_role;
create temp table bot_attack as
  select * from public.begin_attack('00000000-0000-0000-0000-0000000282a1', null, 0::smallint, '[[13, 4]]', 7);
select is((select status from public.end_attack('00000000-0000-0000-0000-0000000282a1', (select attack_id from bot_attack),
    '{"won": true, "percent": 100, "stars": [true, true, true]}', '[15, 0, 0, 2]', '[4]')), 'finished',
  'wynik wyprawy przyjęty');
reset role;
select is((select amounts from public.castle_loot_pending where player_id = '00000000-0000-0000-0000-0000000282a1'),
  '{15, 0, 0, 2}'::bigint[], 'łup z bota czeka na zapis zamku');
select pg_temp.as_a();
set local role authenticated;
select lives_ok($$select pg_temp.push('[430, 320, 303, 60]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'zapis zamku po wyprawie');
select is((select loot_applied from public.castles where player_id = '00000000-0000-0000-0000-0000000282a1'),
  '{15, 0, 0, 2}'::integer[], 'telefon dostaje łup z bota w loot_applied');
select lives_ok($$select pg_temp.push('[445, 320, 303, 62]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'zapis z doliczonym łupem przechodzi');
reset role;

-- ---- złoto po najeździe nie wraca ----
select private.add_loot_pending('00000000-0000-0000-0000-0000000282a1', '{0, 0, 0, -30}');
set local role authenticated;
select lives_ok($$select pg_temp.push('[445, 320, 303, 62]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'zapis scala stratę z najazdu');
select throws_ok($$select pg_temp.push('[445, 320, 303, 62]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'PT422', 'economy_too_fast', 'złoto stracone w najeździe nie wraca z telefonu');
reset role;

-- ---- serwer pisze bez bilansu; mniejszy magazyn obniża zapas ----
select set_config('request.jwt.claims', '', true);
select lives_ok($$update public.castles set data = pg_temp.castle('[1500, 320, 303, 32]',
    '{"grid": {"buildings": [[1, 5, 1, 30, 30, 4, 4], [2, 21, 1, 40, 40, 2, 2], [3, 4, 1, 10, 10, 2, 2], [4, 18, 1, 50, 50, 3, 3], [5, 25, 1, 20, 20, 2, 2]]}, "research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')
    where player_id = '00000000-0000-0000-0000-0000000282a1'$$, 'serwer zapisuje zamek z Magazynem bez bilansu');
select pg_temp.as_a();
set local role authenticated;
select lives_ok($$select pg_temp.push('[1000, 320, 303, 32]',
    '{"research": {"done": ["A1"]}, "recruitment": {"squads": [[1, 13, 4]], "orders": []}, "pve": {"cleared": 1}}')$$,
  'rozebrany Magazyn: nadmiar przepada bez odrzutu');
reset role;

select * from finish();
rollback;
