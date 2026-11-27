# ADR 0010: Budynki epoki II startują od poziomu 6, pierwszy Młyn

- **Status:** przyjęty
- **Data:** 2026-11-27
- **Issue:** #102 (wdrożenie: #388)

## Kontekst

Epoka II ma budynki, których nie było w epoce I: Młyn, Pomost, Częstokół, Kaplica i zasięg Domu
zwiadowców ([[Otwarte pytania]], #102). Model z [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]
liczy koszt i czas jako ciągłą krzywą przez poziomy narastająco, ale nie mówi, na jakim poziomie
startuje budynek, który pojawia się dopiero w epoce II. [[Progresja budowy]] mówi, że każdy budynek
ma poziomy 1–5 w bieżącej epoce, a po przejściu epoki zaczyna od poziomu 1. Dla budynku nowej epoki
to nie pasuje.

Młyn ([[Drzewko technologiczne|G5 Młyn wodny]]) w [[Budynki/Gospodarka|Gospodarce]] ma tylko opis
„+żywność” bez liczb. Serwer (`private.castle_buildings`) odrzuca budynek wyższy niż Dwór, więc
przed przejściem do epoki II nie da się go postawić.

## Decyzja

1. Budynek, który pojawia się dopiero w epoce II, stawia się od razu na **poziomie narastającym 6**
   (na ekranie „1/5, epoka II”, czyli II.1) i ulepsza do poziomu 10 (II.5). Nie ma w nim poziomów
   1–5 z osobną blokadą epoki.
2. Koszt i czas liczy się z ciągłej krzywej [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]
   (`BuildConfig.COST_PERCENT` i `TIME_MULT`) od poziomu 6: koszt 850 / 1150 / 1500 / 1950 / 2500%
   kosztu poziomu 1 budynku, czas ×130 / 180 / 240 / 320 / 420 czasu poziomu 1 budynku. Premie
   budynku biorą się z `Ages.bonus_level`.
3. Budynku epoki II nie da się postawić przed przejściem do epoki II, bo serwer nie pozwala na
   poziom wyższy niż Dwór.
4. Budynki z #102 idą osobnymi PR-ami: #388 Młyn, #389 Pomost, #390 Częstokół, #391 Kaplica,
   #392 zasięg Domu zwiadowców. Każdy dostaje migrację Supabase (zakres `kind`, czas budowy,
   wymagana technologia) i testy pgTAP w `supabase/tests/database`.
5. **Młyn:**
   - technologia G5 Młyn wodny (epoka II, wymaga G2);
   - budynek 2×2 stawiany przy rzece, jak Rybak;
   - premia: +4 / 8 / 12 / 16 / 20% całej produkcji żywności na poziomach II.1–II.5;
   - liczy się jeden Młyn, na najwyższym poziomie (premie z kilku Młynów nie sumują się);
   - koszt poziomu 1 = 120 Dr, 60 Ka, 20 Ży (tymczasowe), a koszt poziomów epoki II z krzywej:

   | Poziom | Ekran | Drewno | Kamień | Żywność | Czas (× czas poziomu 1) | Premia żywności |
   | --- | --- | --- | --- | --- | --- | --- |
   | 6 | 1/5, II.1 | 1020 | 510 | 170 | ×130 | +4% |
   | 7 | 2/5, II.2 | 1380 | 690 | 230 | ×180 | +8% |
   | 8 | 3/5, II.3 | 1800 | 900 | 300 | ×240 | +12% |
   | 9 | 4/5, II.4 | 2340 | 1170 | 390 | ×320 | +16% |
   | 10 | 5/5, II.5 | 3000 | 1500 | 500 | ×420 | +20% |

   Liczby Dr / Ka / Ży w tabeli to kolejno drewno, kamień i żywność.

## Rozważane opcje

- **Start na poziomie 6, ulepszenie do 10** (wybrana): zachowuje zasadę „poziomy narastająco” z
  [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]] i premie z `Ages.bonus_level`, bo poziom
  budynku nowej epoki od razu pasuje do krzywej.
- **Poziomy 1–5 z osobną blokadą epoki**: odrzucona. Łamie zasadę poziomów narastająco, a premie
  z `Ages.bonus_level` musiałyby osobno liczyć poziomy lokalne epoki.
- **Poziom 1 z mnożnikiem epoki**: odrzucona. [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]]
  usunął mnożnik epoki, bo na przejściu wszystko tanieje albo się skraca.

## Konsekwencje

- Budynek epoki II wchodzi do gry od razu na poziomie 6, więc jego pierwszy koszt jest wysoki
  (Młyn: 1020 Dr, 510 Ka, 170 Ży przy czasie ×130). To kontynuacja krzywej z
  [[ADR/0009-model-balansu-epok-ciagla-krzywa|ADR 0009]], nie osobna tabela.
- [[Progresja budowy]] wymaga dopisku: wyjątek dla budynków pojawiających się w epoce II.
- Kod: `BuildConfig.FIRST_AGE` i `BuildConfig.start_level` mówią, od którego poziomu stawia się budynek;
  kolejka budowy zleca od razu ten poziom i bez Dworu w epoce II odpowiada „Najpierw ulepsz Dwór”.
- Serwer liczy koszt i czas budowy takiego budynku też od poziomu 6 (`private.build_paid`,
  `private.build_need_ms`), bo inaczej doliczyłby poziomy 1–5, których w grze nie ma. Reguła
  „budynek nie wyżej niż Dwór” zostaje bez zmian.
- Pierwszy poziom Młyna (1020 Dr) przekracza zapas samego Dworu (1000), więc wymaga Magazynu.
- Każdy budynek z #102 ma własną migrację Supabase i testy pgTAP. Zmiana schematu bez zielonych
  testów RLS nie jest gotowa.
- Bez nowych danych o graczu; zmieniają się tylko tablice budynków i ich zakres `kind`.
- Liczby tymczasowe. Czas poziomu 1 Młyna to 50 s (jak Kamieniołom), więc II.1 trwa 1 h 48 min.

## Dotknięte notatki

- [[Budynki/Gospodarka|Gospodarka]]: wiersz Młyn z liczbami, G5, przy rzece i #388.
- [[Drzewko technologiczne]]: wiersz G5 z linkiem do ADR.
- [[Progresja budowy]]: wyjątek dla budynków epoki II, start od poziomu 6.
- [[Otwarte pytania]]: wpis w „Ustalone” z datą 27.11.2026 i #102.
