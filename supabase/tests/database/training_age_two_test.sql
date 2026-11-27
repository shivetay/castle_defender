-- Testy szkolenia w epoce II (#387, ADR 0012, migracja `*_training_age_two.sql`), uruchamiane przez
-- `supabase test db` (pgTAP). Kryteria: `private.train_ms` liczy poziomy 6–10 z tempem
-- TRAINING_SPEED_PERCENT = [100, 120, 140, 170, 200, 230, 260, 300, 340, 400] jak gra
-- (RecruitmentConfig.train_ms, `tests/test_army_research_goods_sanity.gd`), epoka I się nie zmienia,
-- poziom ponad 10 liczy się jak 10, a gracz nie woła funkcji serwera.
begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;

select plan(11);

-- ---- epoka I bez zmian ----
select is(private.train_ms(0, 1), 20000::bigint, 'topornik w Koszarach 1: 20 s');
select is(private.train_ms(0, 5), 10000::bigint, 'Koszary 5: 200 procent');

-- ---- poziomy 6–10 ----
select is(private.train_ms(0, 6), 8695::bigint, 'Koszary II.1: 230 procent, szybciej niż poziom 5');
select is(private.train_ms(0, 7), 7692::bigint, 'Koszary II.2: 260 procent');
select is(private.train_ms(0, 8), 6666::bigint, 'Koszary II.3: 300 procent');
select is(private.train_ms(0, 9), 5882::bigint, 'Koszary II.4: 340 procent');
select is(private.train_ms(0, 10), 5000::bigint, 'Koszary II.5: 400 procent');
select is(private.train_ms(11, 10), 22500::bigint, 'jednostka 90 s na poziomie II.5');
select is(private.train_ms(0, 99), 5000::bigint, 'poziom ponad 10 jak 10');

-- ---- gracz nie woła funkcji serwera ----
select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-0000000387a1", "role": "authenticated"}', true);
set local role authenticated;
select throws_ok($$select private.train_ms(0, 6)$$, '42501', null, 'gracz nie wywoła train_ms');
reset role;
set local role anon;
select throws_ok($$select private.train_ms(0, 6)$$, '42501', null, 'anon nie wywoła train_ms');
reset role;

select * from finish();
rollback;
