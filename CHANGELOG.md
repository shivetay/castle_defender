# Changelog

Wszystkie istotne zmiany w grze. Format według [Keep a Changelog](https://keepachangelog.com/pl/1.1.0/),
wersje według [SemVer](https://semver.org/lang/pl/): przed 1.0.0 numer `0.N.x` oznacza etap N planu MVP.

Każda zmiana trafia najpierw do sekcji „Nieopublikowane”, w podsekcji: Dodane, Zmienione,
Naprawione, Usunięte. Wydanie tworzy `python3 tools/version.py bump ...` (szczegóły w README).
Pierwsze wydanie (0.2.0) pojawi się razem z pierwszą funkcjonalnością gry, czyli w etapie 2.

## [Nieopublikowane]

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

### Zmienione

- Godot 4.5 → 4.7 (sprawdzone na 4.7.2).
- Scena startowa pokazuje widok zamku z etapu 2 zamiast statycznej sceny testowej z etapu 1.

### Naprawione

- Eksport na Androida: włączona kompresja tekstur ETC2/ASTC, której wymaga Godot przy eksporcie APK.
