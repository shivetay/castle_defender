# Changelog

Wszystkie istotne zmiany w grze. Format według [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/),
wersje według [SemVer](https://semver.org/lang/pl/). Przed 1.0.0 wersje mają postać `0.x.y`, a numer
kolejnego wydania wybiera właściciel.

Od wersji 0.0.1 sekcje wydań generują się ze scalonych PR-ów (`tools/changelog.py`): jeden PR to
jeden wpis z tytułu PR, a podsekcję (Dodane, Zmienione, Naprawione, Usunięte) wybiera prefiks gałęzi
albo etykieta. Sekcja „Nieopublikowane” zostaje na ręczne wyjątki. Wydanie przygotowuje workflow
„Przygotuj wydanie” albo `python3 tools/version.py bump ...` (szczegóły w README).

## [Nieopublikowane]

## [0.4.0] - 2026-11-17

### Dodane

- Etap 2: generator terenu 64×64, siatka budowy i kamera z gestami (#72)
- Budynki epoki I: wał, palisada, brama, wieża i chata drwala z 5 poziomami (#76)
- Budynki pękają, tracą blanki i rozsypują się w gruz (#78)
- Zamek produkuje drewno, kamień i żywność, także gdy gra jest w tle (#79)
- Budowa kosztuje surowce, trwa i czeka w kolejce, a Dwór wyznacza poziom zamku (#80)
- Zamek zapisuje się i wraca po zamknięciu gry z nadrobioną budową (#83)
- Budowanie w osobnym trybie pod przyciskiem Buduj, z epoką i rokiem na pasku (#118)
- Każdy gracz dostaje własną, losową mapę zamku na stałe (#138)
- Badania: drzewko 34 technologii z ekranem Badania i premiami do produkcji (#139)
- Towary i łańcuchy produkcji: wytwórcy zamieniają surowce w wyposażenie (#140)
- Wytwórcy epoki I: dziewięć budynków produkujących wyposażenie dla wojska (#142)
- Pole lnu i Rybak: len dla cięciw i żywność z rzeki (#143)
- Stajnia w epoce I: konie dla konnicy (#144)
- Budynki rekrutacji: Koszary, Dom drużyny i Strzelnica (#145)
- Klasy jednostek: 13 jednostek MVP i przewagi klas (#146)
- Rekrutacja do oddziałów: ekran Wojsko z limitem armii, globalnie i z budynku (#147)
- Drzewko badań: powiązania technologii i wyróżnione zbadane (#157)
- Panel budowy z kategoriami, koszt ulepszenia i mniejsze przyciski w kolumnie (#160)
- Mapa: dodatkowe oddalenie do 0,5× (#159)
- Chłop: jednostka epoki I do szkolenia bez badań i towarów (#158)
- Deterministyczna symulacja bitwy: ten sam seed, ten sam wynik (#148)
- Donżon jako cel ataku: Wieża grodowa obok Dworu (#152)
- Jednostki w bitwie: oddziały, cechy jednostek i ikony oddziałów (#153)
- Morale oddziałów: złamane oddziały same się wycofują (#155)
- Ekran Wojsko: opis jednostki z rolą i przewagami (#167)
- Brama na linii wału albo palisady zastępuje odcinki (#168)
- Brakujące surowce w kosztach są na czerwono (#169)
- Samouczek PvE: 5 fal oblężenia pod przyciskiem Oblężenie (#170)
- Efekty bitwy: strzały, pociski z cieniem, pył, ogień i dym (#171)
- Zwiadowca i Dom zwiadowców w epoce II (#172)
- Polegli w fali oblężenia znikają z armii (#173)
- Manewry ataku: oddziały wykonują rozkazy z planu (#175)
- Ekran planowania ataku na zamek-cel (#176)
- Ustawienia obrony: posterunki załogi wokół donżonu (#179)
- Zadania obrony: Obrona odcinka, Patrol i priorytet celów wież (#181)
- Badania wymagają budynku gałęzi (#182)
- Ekran Kolejka: co się buduje i szkoli, w zakładkach (#183)
- Zadania obrony: strzelcy na murach, Wypad konnicy i zadania domyślne (#184)
- Pułapki: Wilczy dół, Kolczatka, Zrzucane kłody, Płonące strzały i Wrząca smoła (#186)
- Badania działają w bitwie, a manewry wymagają swoich technologii (#187)
- Prowadzenie gracza przez 5 fal samouczka (#189)
- Budynki przyklejają się do murów jako przybudówki (#190)
- Żywszy zamek: zbocza, ozdoby, cienie, dym i wąska kolumna przycisków (#191)
- Strażnica z wyprawami PvE i ustawienia pod zębatką (#192)
- 20 zamków-botów do zdobycia z wyborem celu Wyprawy (#193)
- Wynik ataku z gwiazdkami, procentem zniszczeń i łupem (#194)

### Zmienione

- Organizacja projektu: Godot 4.7, reguły AI, wersjonowanie i CI/CD (#67)
- CI: Bump the actions group with 4 updates (#68)
- Reguły agenta: opisowe nazwy gałęzi, PR-y od agenta, merge tylko przez właściciela (#70)
- Reguły agenta: stałe obserwowanie własnych PR-ów (#73)
- CI: debug APK przy każdym pushu na main (#71)
- Changelog generowany automatycznie ze scalonych PR-ów (#75)

### Naprawione

- Włącz kompresję ETC2/ASTC wymaganą przy eksporcie na Androida (#69)
- Brama zajmuje 3 kratki i staje nad drogą, w poprzek niej (#82)
- Wał łączy się z palisadą, a luka w linii umocnień daje się wypełnić (#85)
- Napisy na paskach nie chowają się w zaokrąglonych narożnikach ekranu (#86)
- Ekran Wojsko: długie teksty zawijają się zamiast wychodzić poza ekran (#156)
- Ekran Wojsko: braki towarów mieszczą się w dwóch liniach (#162)
- Manewry: zejście z drabiny na wolną kratkę i stan rozkazów w sumie kontrolnej (#178)
- Złamany oddział z posterunku wycofuje się pod donżon (#180)

## [0.3.0] - 2026-11-16

### Dodane

- Etap 2: generator terenu 64×64, siatka budowy i kamera z gestami (#72)
- Budynki epoki I: wał, palisada, brama, wieża i chata drwala z 5 poziomami (#76)
- Budynki pękają, tracą blanki i rozsypują się w gruz (#78)
- Zamek produkuje drewno, kamień i żywność, także gdy gra jest w tle (#79)
- Budowa kosztuje surowce, trwa i czeka w kolejce, a Dwór wyznacza poziom zamku (#80)
- Zamek zapisuje się i wraca po zamknięciu gry z nadrobioną budową (#83)
- Budowanie w osobnym trybie pod przyciskiem Buduj, z epoką i rokiem na pasku (#118)
- Każdy gracz dostaje własną, losową mapę zamku na stałe (#138)
- Badania: drzewko 34 technologii z ekranem Badania i premiami do produkcji (#139)
- Towary i łańcuchy produkcji: wytwórcy zamieniają surowce w wyposażenie (#140)
- Wytwórcy epoki I: dziewięć budynków produkujących wyposażenie dla wojska (#142)
- Pole lnu i Rybak: len dla cięciw i żywność z rzeki (#143)
- Stajnia w epoce I: konie dla konnicy (#144)
- Budynki rekrutacji: Koszary, Dom drużyny i Strzelnica (#145)
- Klasy jednostek: 13 jednostek MVP i przewagi klas (#146)
- Rekrutacja do oddziałów: ekran Wojsko z limitem armii, globalnie i z budynku (#147)
- Drzewko badań: powiązania technologii i wyróżnione zbadane (#157)
- Panel budowy z kategoriami, koszt ulepszenia i mniejsze przyciski w kolumnie (#160)
- Mapa: dodatkowe oddalenie do 0,5× (#159)
- Chłop: jednostka epoki I do szkolenia bez badań i towarów (#158)

### Zmienione

- Organizacja projektu: Godot 4.7, reguły AI, wersjonowanie i CI/CD (#67)
- CI: Bump the actions group with 4 updates (#68)
- Reguły agenta: opisowe nazwy gałęzi, PR-y od agenta, merge tylko przez właściciela (#70)
- Reguły agenta: stałe obserwowanie własnych PR-ów (#73)
- CI: debug APK przy każdym pushu na main (#71)
- Changelog generowany automatycznie ze scalonych PR-ów (#75)

### Naprawione

- Włącz kompresję ETC2/ASTC wymaganą przy eksporcie na Androida (#69)
- Brama zajmuje 3 kratki i staje nad drogą, w poprzek niej (#82)
- Wał łączy się z palisadą, a luka w linii umocnień daje się wypełnić (#85)
- Napisy na paskach nie chowają się w zaokrąglonych narożnikach ekranu (#86)
- Ekran Wojsko: długie teksty zawijają się zamiast wychodzić poza ekran (#156)

## [0.2.0] - 2026-11-13

### Dodane

- Etap 2: generator terenu 64×64, siatka budowy i kamera z gestami (#72)
- Budynki epoki I: wał, palisada, brama, wieża i chata drwala z 5 poziomami (#76)
- Budynki pękają, tracą blanki i rozsypują się w gruz (#78)
- Zamek produkuje drewno, kamień i żywność, także gdy gra jest w tle (#79)
- Budowa kosztuje surowce, trwa i czeka w kolejce, a Dwór wyznacza poziom zamku (#80)
- Zamek zapisuje się i wraca po zamknięciu gry z nadrobioną budową (#83)

### Zmienione

- Organizacja projektu: Godot 4.7, reguły AI, wersjonowanie i CI/CD (#67)
- CI: Bump the actions group with 4 updates (#68)
- Reguły agenta: opisowe nazwy gałęzi, PR-y od agenta, merge tylko przez właściciela (#70)
- Reguły agenta: stałe obserwowanie własnych PR-ów (#73)
- CI: debug APK przy każdym pushu na main (#71)
- Changelog generowany automatycznie ze scalonych PR-ów (#75)

### Naprawione

- Włącz kompresję ETC2/ASTC wymaganą przy eksporcie na Androida (#69)
- Brama zajmuje 3 kratki i staje nad drogą, w poprzek niej (#82)

## [0.1.0] - 2026-11-13

### Dodane

- Etap 2: generator terenu 64×64, siatka budowy i kamera z gestami (#72)
- Budynki epoki I: wał, palisada, brama, wieża i chata drwala z 5 poziomami (#76)

### Zmienione

- Organizacja projektu: Godot 4.7, reguły AI, wersjonowanie i CI/CD (#67)
- CI: Bump the actions group with 4 updates (#68)
- Reguły agenta: opisowe nazwy gałęzi, PR-y od agenta, merge tylko przez właściciela (#70)
- Reguły agenta: stałe obserwowanie własnych PR-ów (#73)
- CI: debug APK przy każdym pushu na main (#71)
- Changelog generowany automatycznie ze scalonych PR-ów (#75)

### Naprawione

- Włącz kompresję ETC2/ASTC wymaganą przy eksporcie na Androida (#69)

## [0.0.1] - 2026-11-13

### Dodane

- Etap 1: projekt Godot, viewport 320×180 ze skalowaniem całkowitym, orientacja pozioma, emulacja dotyku myszą.
- Scena testowa z proceduralnym terenem, ścieżką, palisadą i dwiema chatami (grafika rysowana kodem).
- Paleta epoki I (Gród) i deterministyczny `hash2()` do rysowania pikseli.
- Preset eksportu „Android (debug APK)” (arm64-v8a).
- Reguły pracy z AI (`CLAUDE.md`) i 15 skilli Godota w `.claude/skills/`.
- System wersji: `CHANGELOG.md` i `tools/version.py` (zgodność wersji w projekcie, presecie i changelogu).
- Testy headless: `tests/check_compile.gd` i `tests/run_tests.gd` z testami determinizmu grafiki.
- GitHub Actions: CI (testy przy każdym pushu i PR) oraz wydanie (debug APK i GitHub Release po tagu `v*`).
- Etap 2: teren 64×64 kratki generowany z seeda (wzgórze, rzeka, ścieżki z mostem), rysowany raz do jednej tekstury.
- Siatka budowy: tap na wolnej trawie stawia chatę 2×2, tap na chacie ją usuwa; niedozwolone miejsce świeci na czerwono.
- Kamera: przeciąganie, szczypanie i kółko myszy (zoom 1×/2×/4×), granice mapy, pozycja w całych pikselach.
- Testy generatora terenu, siatki budowy i kamery (determinizm seeda, walidacja miejsca, granice widoku).
- Każdy push na `main` buduje testowy debug APK jako artefakt workflow „Wydanie” (bez GitHub Release).
- Reguła w `CLAUDE.md`: gałęzie tylko z opisowymi nazwami (`<typ>/<opis>`), merge do `main` robi właściciel, a PR-y agent otwiera sam.
- Reguła w `CLAUDE.md`: agent obserwuje swoje PR-y i sam poprawia uwagi z review oraz błędy CI.

### Zmienione

- Godot 4.5 → 4.7 (sprawdzone na 4.7.2).
- Scena startowa pokazuje widok zamku z etapu 2 zamiast statycznej sceny testowej z etapu 1.
- `tools/version.py bump` przy pierwszym wydaniu pozwala opublikować bieżącą wersję bez podbijania numeru.

### Naprawione

- Eksport na Androida: włączona kompresja tekstur ETC2/ASTC, której wymaga Godot przy eksporcie APK.
