# ADR 0013: Premie szkolenia, kolców w fosie i Kopca w epoce II

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #387

## Kontekst

[[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] przedłużył premie budynków do poziomu 10
(`Ages.bonus_level`), ale zostawił tempo szkolenia bez zmian (pkt 6). Kilka tablic miało nadal
5 wartości i przycinało poziom do 5, więc ulepszenie budynku w epoce II nic nie dawało:

- `RecruitmentConfig.TRAINING_SLOTS = [2, 3, 4, 5, 6]` i `TRAINING_SPEED_PERCENT = [100, 120, 140, 170, 200]`;
  serwer liczył czas szkolenia w `private.train_ms` z `least(..., 5)`;
- `BattleConfig.MOAT_SPIKE_DAMAGE = [2, 3, 4, 5, 6]` (kolce w Fosie suchej z O3)
  i `MOUND_RANGE_BONUS = [1, 1, 2, 2, 2]` (zasięg wieży przy Kopcu);
- `ScoutIntel.from_server` przycinał poziom odsłoniętego budynku do 5, więc na podglądzie planu
  ataku budynek epoki II wyglądał jak budynek epoki I na poziomie 5.

Siła celu PvP (`Strength`, [[ADR/0004-sila-celu-pvp-przedzial-z-serwera|ADR 0004]]) nie korzysta
z kolców ani z Kopca. Ekran Wojsko pokazuje kolejkę szkolenia jako liczbę, a nie jako miejsca.

## Decyzja

Wszystkie liczby są tymczasowe. Zmienia się pkt 6 ADR 0009 w części o tempie szkolenia.

1. Miejsca w kolejce szkolenia na poziomach 6–10: 7, 8, 9, 10, 11.
2. Tempo szkolenia na poziomach 6–10: 230, 260, 300, 340, 400% tempa poziomu 1. Przez epokę II
   tempo rośnie 2×, wolniej niż koszt budowy (około 4×).
3. Kolce w Fosie suchej na poziomach 6–10: 7, 8, 9, 10, 11 HP na sekundę.
4. Zasięg z Kopca na poziomach 6–10: +2, +2, +2, +3, +3 kratki (+3 dopiero od II.4).
5. Żadna z tych premii nie spada na przejściu I.5 → II.1, a poziom ponad 10 liczy się jak 10.
6. Zwiad pokazuje poziom budynku narastająco, przycięty do 10 (`Ages.MAX_TOTAL_LEVEL`), czyli tak
   jak we własnym zamku („poziom 1/5, epoka II”). Osobnego formatu „II.3” nie ma.
7. Serwer liczy czas szkolenia tak samo (`private.train_ms` w migracji `*_training_age_two.sql`,
   poziom do 10). Miejsc w kolejce ani premii bitwy serwer nie liczy.

## Rozważane opcje

- **Premie rosną dalej, wolniej niż koszty** (wybrana): zgodne z zasadą ADR 0009, że nic nie spada
  na przejściu i każda epoka płynnie wynika z poprzedniej.
- **Zostawić poziomy 6–10 jak poziom 5**: odrzucone, bo ulepszenie Koszar, fosy czy Kopca w epoce II
  kosztowałoby, a nic nie dawało.
- **Kopiec +3 od II.1**: odrzucone, bo wieża ma bazowo 6 kratek zasięgu, więc +3 to duży skok.
- **Zwiad z formatem „II.3”**: odrzucone, bo gra już pokazuje poziom epoki II tym samym opisem we
  własnym zamku, a podgląd planu korzysta z tej samej grafiki i karty budynku.

## Konsekwencje

- Budynki rekrutacji epoki II szkolą szybciej i mieszczą dłuższą kolejkę. Fosa i Kopiec w epoce II
  mocniej bronią, więc bitwy na takich zamkach przebiegają inaczej; nowa wersja gry ma nowy
  `sim_version` ([[ADR/0008-wersja-symulacji-ataku-z-klienta|ADR 0008]]). Siła celu PvP się nie zmienia.
- Nowy klient na starym serwerze dostałby `train_too_fast` przy szkoleniu w budynku epoki II, więc
  migrację wgrywa się razem z wydaniem klienta (`docs/PO-WYDANIU.md`). Starszy klient szkoli wolniej,
  więc nowy serwer zawsze go przepuszcza.
- Bez nowych danych o graczu i bez zmian uprawnień: `private.train_ms` woła tylko `service_role`.
- Testy: `tests/test_age_two_bonuses.gd`, `tests/test_army_research_goods_sanity.gd` (zgodność
  z migracją) i pgTAP `supabase/tests/database/training_age_two_test.sql`.

## Dotknięte notatki

- [[Balans]]: premie szkolenia, kolców i Kopca w tabeli § 1.7.
- [[Budynki/Obrona]]: kolce i zasięg Kopca na poziomach epoki II.
- [[Otwarte pytania]]: premie szkolenia, fosy i Kopca w „Ustalone”.
