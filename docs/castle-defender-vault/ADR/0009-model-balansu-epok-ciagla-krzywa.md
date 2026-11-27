# ADR 0009: Model balansu epok: ciągła krzywa kosztu i czasu, premie do poziomu 10

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #262

## Kontekst

Przejście I → II (#34, PR #261) weszło na liczbach tymczasowych. Budynki w epoce II liczyły koszt
i czas jako poziom w epoce razy mnożnik epoki (`AGE_COST_PERCENT = [100, 200]`,
`AGE_TIME_MULT = [1, 2]`). Na przejściu I.5 → II.1 koszt spadał z 600% do 200% kosztu poziomu 1,
a czas z ×90 do ×2. Wieża 5 kosztowała 720 Dr i trwała 90 min, a Wieża II.1 240 Dr i 2 min. Dwór
II.2 (600/400/400, 20 min) był tańszy i krótszy niż Dwór 5 (1000/800/800, 12 h).

Premie budynków na poziomach 6–10 zostawały jak na poziomie 5: `Ages.bonus_level` obcinał poziom
do 5, a serwer (`private.castle_buildings`) tak samo. Epoka II kosztowała, ale nic nie dawała.
Notatka [[Progresja budowy]] miała „typowe czasy” (epoka II: 2 min na poziomie 1, 30 min na
poziomie 5), które nie zgadzały się z kodem. Propozycje balansu: [[Balans]].

## Decyzja

Każda kolejna epoka płynnie wynika z poprzedniej, jest droższa i dłuższa. Na przejściu nic nie
tanieje ani nie skraca się. Czasy mają lekki przechył na dłużej (miejsce na reklamy
przyspieszenia, #33). Wszystkie nowe liczby są tymczasowe.

1. Epoka I zostaje bez zmian (z Chłopem). Skala czasów zostaje z kodu, a notatka
   [[Progresja budowy]] idzie za kodem.
2. Koszt i czas budowy to **jedna ciągła krzywa przez 10 poziomów** narastająco, bez mnożnika
   epoki: koszt w % kosztu poziomu 1 `[100, 150, 250, 400, 600, 850, 1150, 1500, 1950, 2500]`,
   czas razy czas poziomu 1 `[1, 3, 10, 30, 90, 130, 180, 240, 320, 420]` (`BuildConfig`).
   Kolejne epoki przedłużają tę krzywą.
3. Umocnienia (wał, palisada, fosa sucha, brama) biorą koszt z krzywej, a czas na poziomach
   epoki II to połowa krzywej. W epoce I bez zmian.
4. Dwór na poziomach 6–10: 1000/1000/1000 Dr/Ka/Ży i 14 h, 1300/1100/1100 i 18 h,
   1700/1400/1400 i 24 h, 2200/1800/1800 i 30 h, 2800/2300/2300 i 40 h. Poziomy 1–5 bez zmian.
5. Premie poziomów 6–10 rosną dalej. `Ages.bonus_level` obcina do 10, a tablice per poziom mają
   10 wartości:
   - Chata drwala oraz Pole i spichlerz: 240, 280, 330, 380, 440 na godzinę; Rybak i Kamieniołom
     170, 200, 230, 270, 310;
   - wytwórcy (także żywność Chaty myśliwego): 425, 500, 575, 650, 750% tempa poziomu 1;
   - wytrzymałość w bitwie: 560, 680, 810, 950, 1100%;
   - Magazyn: 2500, 3000, 3500, 4500, 6000;
   - limit armii: Dwór 10 za poziom w epoce I i 8 za poziom w epoce II (do 90), Koszary 2 za
     każdy poziom; garnizon 4 za poziom (do 40); pułapki 2 za poziom (do 20).
6. Bez zmian: strefa obrony ([[ADR/0007-strefa-obrony-z-dworu-i-technologii|ADR 0007]], nadal
   jak przy Dworze 5), badania epoki II, rok na pasku, tempo szkolenia.
7. Serwer powtarza te same tablice (migracja `*_age_two_balance.sql`): koszt i czas budowy,
   produkcję, pojemność, zużycie wytwórców, limit armii i siłę umocnień do poziomu 10. Testy gry
   i pgTAP pilnują, że klient i serwer liczą tak samo.

## Rozważane opcje

- **Ciągła krzywa przez 10 poziomów** (wybrana): nic nie spada na przejściu, a kolejna epoka to
  tylko kolejne wpisy w tablicy.
- **Mnożnik epoki ×2 względem tego samego poziomu epoki I** (dotychczasowe liczby): odrzucony,
  bo II.1 był tańszy i krótszy niż I.5.
- **Opcja C z [[Balans]] („Spokojny rytm”)**: przyjęto z niej tylko zasadę, że reklamy i sklep
  przyspieszają, a nie odblokowują. Odrzucono mnożnik `AGE_COST_PERCENT = 175`, krótsze
  `TIME_MULT = [1, 2, 6, 20, 55]`, przebudowę Dworu za 800/800/800 i 8 h oraz premie
  „L6→1 … L10→5” (poziom lokalny epoki), bo premie spadałyby na przejściu.
- **Opcje A i B z [[Balans]]**: odrzucone jako skrajne odniesienia. Z B zostaje kierunek „tablice
  `per_level` do 10”.
- **Skrócenie skali czasów do „typowych czasów” z notatki**: odrzucone, notatka idzie za kodem.

## Konsekwencje

- Epoka II jest wyraźnie droższa i dłuższa niż dotąd (Wieża II.1: 1020 Dr i 2 h 10 min zamiast
  240 Dr i 2 min), ale też daje więcej (produkcja, Magazyn, limit armii, wytrzymałość). Koszt
  każdego poziomu mieści się w magazynie osiągalnym przy Dworze tego poziomu.
- Wyjątek od zasady „nic się nie skraca”: czas umocnień na II.1 to połowa krzywej (65 zamiast 90
  razy czas poziomu 1), więc odcinek wału II.1 buduje się krócej niż wał 5. Zostaje jak w
  ustaleniach #262, do ewentualnej korekty właścicielki.
- Zamki z budynkami epoki II mają mocniejsze mury i wieże, więc bitwy na takich zamkach przebiegają
  inaczej; nowa wersja gry ma nowy `sim_version` ([[ADR/0008-wersja-symulacji-ataku-z-klienta|ADR 0008]]).
  Siła celu PvP liczy umocnienia do poziomu 10 ([[ADR/0004-sila-celu-pvp-przedzial-z-serwera|ADR 0004]]).
- Starszy klient płaci za budowę epoki II mniej i buduje krócej, niż wymaga nowy serwer, więc jego
  zapis z nowym poziomem epoki II serwer odrzuci (`economy_too_fast`, `build_too_fast`). Migrację
  wgrywa się razem z wydaniem klienta i podniesieniem `min_code`
  ([[ADR/0006-wymuszenie-aktualizacji-wersji-klienta|ADR 0006]], `docs/PO-WYDANIU.md`).
- Bez nowych danych o graczu i bez zmian uprawnień: funkcje serwera zostają w schemacie `private`,
  woła je tylko `service_role`.
- Testy: `tests/test_age_balance.gd` (pojedynki epok, ciągłość, magazyn) i pgTAP
  `supabase/tests/database/age_two_balance_test.sql`.

## Dotknięte notatki

- [[Balans]]: przyjęty model, co z Opcji C przyjęto, a co odrzucono, nowe liczby epoki II.
- [[Progresja budowy]]: krzywa kosztu i czasu z kodu, przykład palisady i typowe czasy z kodu.
- [[Otwarte pytania]]: premie poziomów 6–10 i pierwsza passa balansu w „Ustalone”.
- [[Stan prac]]: wpis o #262.
