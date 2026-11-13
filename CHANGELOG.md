# Changelog

Wszystkie istotne zmiany w grze. Format według [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/),
wersje według [SemVer](https://semver.org/lang/pl/). Przed 1.0.0 wersje mają postać `0.x.y`, a numer
kolejnego wydania wybiera właściciel.

Od wersji 0.0.1 sekcje wydań generują się ze scalonych PR-ów (`tools/changelog.py`): jeden PR to
jeden wpis z tytułu PR, a podsekcję (Dodane, Zmienione, Naprawione, Usunięte) wybiera prefiks gałęzi
albo etykieta. Sekcja „Nieopublikowane” zostaje na ręczne wyjątki. Wydanie przygotowuje workflow
„Przygotuj wydanie” albo `python3 tools/version.py bump ...` (szczegóły w README).

## [Nieopublikowane]

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
