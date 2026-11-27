-- #387: szkolenie w epoce II (ADR 0013). Serwer powtarza tempo szkolenia gry dla poziomów 6–10.
--
-- Do tej pory `private.train_ms` (z `*_army_research_goods_sanity.sql`) liczył poziomy 6–10 jak poziom 5:
-- tablica tempa miała 5 wartości, a poziom był przycinany przez least(..., 5). Teraz (decyzja właścicielki,
-- #387) tempo szkolenia rośnie dalej przez epokę II (RecruitmentConfig.train_ms):
--   TRAIN_TIME_S = [20, 20, 25, 40, 30, 30, 45, 25, 50, 35, 60, 90, 15, 10, 40, 45] sekund na poziomie 1,
--   TRAINING_SPEED_PERCENT = [100, 120, 140, 170, 200, 230, 260, 300, 340, 400] dla poziomów 1–10
--   (wyższe jak 10, MAX_TOTAL_LEVEL = 10).
-- `private.castle_army_problem` woła tę funkcję z najwyższym poziomem budynku (`private.castle_buildings`
-- przycina poziom do 0..10), więc wystarczy nowa wersja funkcji. Liczba miejsc w kolejce
-- (RecruitmentConfig.TRAINING_SLOTS) i premie bitwy (kolce w fosie, zasięg z Kopca) serwer nie liczy.
--
-- Zgodność ze starszym klientem: nowy serwer pozwala szkolić szybciej niż stary, więc zapis starszego klienta
-- (wolniejsze szkolenie) zawsze przechodzi. Nowy klient na starym serwerze dostałby `train_too_fast` przy
-- szkoleniu w budynku epoki II, więc migrację wgrywa się razem z wydaniem klienta z #387 (docs/PO-WYDANIU.md).
-- Nowych danych o graczu nie ma, a funkcja zostaje w schemacie `private` (tylko service_role).
-- Liczby pilnuje test gry `tests/test_age_two_bonuses.gd` po znacznikach w komentarzu i w funkcji,
-- a pgTAP `supabase/tests/database/training_age_two_test.sql`.

-- Czas szkolenia jednostki `p_unit` w budynku na poziomie `p_level` w ms (RecruitmentConfig.train_ms).
create or replace function private.train_ms(p_unit integer, p_level bigint)
returns bigint
language sql
immutable
set search_path = ''
as $$
  select coalesce((array[20, 20, 25, 40, 30, 30, 45, 25, 50, 35, 60, 90, 15, 10, 40, 45])[p_unit + 1], 0)::bigint
    * 1000 * 100 / (array[100, 120, 140, 170, 200, 230, 260, 300, 340, 400])[least(greatest(p_level, 1), 10)]
$$;

revoke all on function private.train_ms(integer, bigint) from public, anon, authenticated;
