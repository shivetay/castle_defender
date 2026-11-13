# Castle Defender

Mobilna gra 2D pixelart (Android) z asynchronicznym PvP. Gracze rozbudowują zamki od wałów ziemnych do twierdzy z końca wojen napoleońskich i atakują zamki innych graczy. Cała grafika jest rysowana kodem, bez zewnętrznych assetów.

**Stack:** Godot 4.7 (GDScript), renderer GL Compatibility, eksport na Androida. Backend PvP (Supabase) dojdzie w etapie 8.

## Stan: etap 3 z planu MVP

Etapy 1 (szkielet, viewport 320×180, testowy APK) i 2 (teren 64×64 z seeda, siatka budowy, kamera
z gestami) są zamknięte. Etap 3 to budynki epoki I rysowane kodem (issues #5, #6 i #7):

- `scripts/gfx/pixel_canvas.gd` (`PixelCanvas`): prymitywy rysowania: ściana z bali, ściana z desek,
  belki szkieletu, dach strzechowy, okno, drzwi, flaga i dithering 2×2. Faktura idzie przez `hash2`.
- `scripts/gfx/building_art.gd` (`BuildingArt`): budynki w rzucie 3/4, każdy z 5 poziomami o różnym
  wyglądzie, i stany: cały, uszkodzony, zniszczony (pełne 4 stany zniszczeń to #8).
  Wał i palisada mają autotiling: odcinek 1×1 to środek plus ramię do każdego sąsiada z maski N/E/S/W
  (16 wariantów). Ramiona dochodzą do krawędzi kratki, więc dowolny kształt łączy się bez dziur.
  Ściana i blanki rysują się osobno, a palisada ma ścianę wysoką na 4 px.
- `scripts/gfx/building_textures.gd` (`BuildingTextures`): `draw_building(rodzaj, poziom, stan, maska)`
  zwraca `ImageTexture` z cache. `warm_up()` rysuje przy starcie 175 całych wariantów
  (ok. 18 ms na komputerze).
- `scripts/world/building_types.gd` (`BuildingTypes`): Wał ziemny i Palisada (1×1), Brama drewniana (2×1),
  Wieża drewniana i Chata drwala (2×2). Wał łączy się z wałem, palisada z palisadą, bramą i wieżą.
- `scripts/world/build_grid.gd` (`BuildGrid`): rodzaj i poziom budynku, ulepszanie do poziomu 5,
  maski sąsiadów i stała kolejność rysowania (od tyłu do przodu).
- `scripts/ui/hud.gd`: pasek wyboru budynku nad dolną krawędzią, a po dotknięciu budynku karta
  z poziomem i przyciskami Ulepsz, Rozbierz, Zamknij (cele 56×14 px).

Ulepszanie jest na razie darmowe i natychmiastowe. Koszty, czasy i kolejka budowy to #11.

Do ręcznego testu na telefonie: czy przyciski paska i karty łatwo trafić i czy budowa długiego wału
kratka po kratce nie jest zbyt męcząca.

## Uruchomienie

1. Zainstaluj [Godot 4.7.2](https://godotengine.org/download) (wersja standardowa, nie .NET).
2. W Godocie: **Import** → wskaż `project.godot`.
3. **F5** uruchamia scenę testową na komputerze.

## Testowy APK na telefon

Jednorazowa konfiguracja:

1. Zainstaluj JDK 17 (np. `brew install --cask zulu@17`) i Android SDK (najprościej przez Android Studio: SDK Platform-Tools, Build-Tools, SDK Platform 34+).
2. W Godocie: **Editor → Manage Export Templates → Download and Install**.
3. **Editor Settings → Export → Android**: ustaw ścieżkę do JDK i Android SDK. Debug keystore Godot tworzy sam przy pierwszym eksporcie.
4. Na telefonie włącz opcje programisty i debugowanie USB.

Potem:

- **Project → Export → Android (debug APK) → Export Project** zapisuje `build/castle_defender.apk`, albo
- ikona Androida w prawym górnym rogu edytora (**Remote Deploy**) instaluje i uruchamia grę na podłączonym telefonie jednym kliknięciem.

## Testy

Wymagają Godota 4.7.2 w PATH jako `godot`. Na Windows użyj `Godot_v4.7.2-stable_win64_console.exe` i Git Bash.

```bash
bash .github/scripts/run_checks.sh          # wszystko naraz, to samo co CI
godot --headless --path . --script res://tests/run_tests.gd   # same testy logiki
```

Nowe testy dodajesz jako `tests/test_<nazwa>.gd` z `extends TestCase`. Każda metoda `test_*`
kończy się `return true` (wzór: `tests/test_pixel_canvas.gd`).

## Wersje i changelog

Wersja to SemVer `MAJOR.MINOR.PATCH`. Pierwsze wydanie, 0.0.1, obejmuje etapy 1 i 2 (szkielet projektu,
teren, siatka budowy i kamera). Przed 1.0.0 wersje mają postać `0.x.y`, a numer kolejnego wydania wybiera właściciel. Jedno źródło prawdy to `tools/version.py`, który trzyma w zgodzie
`project.godot`, `export_presets.cfg` (`version/name`, `version/code = MAJOR*10000 + MINOR*100 + PATCH`)
i `CHANGELOG.md`.

- **Changelog generuje się ze scalonych PR-ów.** Tytuł PR to wpis w changelogu. Podsekcję wybiera
  prefiks gałęzi (`feat/` → Dodane, `fix/` → Naprawione, reszta → Zmienione) albo etykieta PR
  (`dodane`, `zmienione`, `naprawione`, `usuniete`). Etykieta `bez-changelogu` pomija PR.
  Podgląd następnego wydania (wymaga `gh` albo `GITHUB_TOKEN`): `python3 tools/changelog.py preview`.
- Wydanie:
  1. **Actions → Przygotuj wydanie → Run workflow** (`patch`, `minor`, `major` albo `X.Y.Z`). Workflow
     generuje sekcję changelogu z PR-ów od ostatniego tagu, podbija wersję i otwiera PR „Wydanie X.Y.Z”.
     Wymaga włączonego *Settings → Actions → General → Allow GitHub Actions to create pull requests*.
     Bez tego wypchnie tylko gałąź, a PR otwierasz ręcznie.
  2. Po merge'u PR-a z wydaniem:

     ```bash
     git tag vX.Y.Z origin/main
     git push origin vX.Y.Z
     ```

  To samo lokalnie: `python3 tools/version.py bump minor`, potem commit, PR i tag.

- `python3 tools/version.py check` sprawdza zgodność wersji (uruchamia się też w CI).

## CI/CD (GitHub Actions)

| Workflow | Kiedy | Co robi |
|---|---|---|
| `ci.yml` | każdy push i PR | wersja i changelog, import, kompilacja skryptów, test dymny, testy logiki |
| `release.yml` | push na `main` | CI i debug APK jako artefakt (Actions → Wydanie → przebieg → Artifacts) |
| `release.yml` | tag `vX.Y.Z` | CI, debug APK, GitHub Release z opisem z changelogu (APK do pobrania na telefon) |
| `release.yml` (ręcznie) | Actions → Wydanie → Run workflow | samo debug APK jako artefakt, bez Release |
| `prepare-release.yml` | Actions → Przygotuj wydanie → Run workflow | changelog z PR-ów, nowa wersja, PR „Wydanie X.Y.Z” |
| `dependabot.yml` | co miesiąc | PR z aktualizacjami akcji |

Godot jest pobierany z oficjalnych wydań i weryfikowany przypiętą sumą SHA-512
(`.github/scripts/install_godot.sh`). Zmiana wersji Godota oznacza podmianę wersji i sum w tym pliku.
APK jest podpisany jednorazowym kluczem debug, więc przed instalacją nowej wersji odinstaluj
poprzednią. Podpis release (Google Play) dojdzie później, z kluczem w sekretach repozytorium.

## Struktura

```
scenes/          sceny Godota
scripts/         logika gry
scripts/gfx/     rysowanie proceduralne i palety
scripts/world/   dane świata: teren, siatka budowy
scripts/camera/  kamera z gestami
scripts/ui/      HUD
tests/           testy headless (run_tests.gd, check_compile.gd, test_*.gd)
tools/           narzędzia (version.py, changelog.py i ich testy)
.github/         workflowy CI/CD i skrypty instalacji Godota
.claude/skills/  skille dla agenta AI (zob. CLAUDE.md)
build/           eksportowane APK i logi (ignorowane przez git)
```

## Następny etap

Etap 4: kolejny krok planu MVP. Kolejność wybiera właściciel; najbliżej obecnego stanu są stany zniszczeń
(#8), HUD z surowcami (#9) i ekonomia (#10).
