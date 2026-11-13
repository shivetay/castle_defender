# Castle Defender

Mobilna gra 2D pixelart (Android) z asynchronicznym PvP. Gracze rozbudowują zamki od wałów ziemnych do twierdzy z końca wojen napoleońskich i atakują zamki innych graczy. Cała grafika jest rysowana kodem, bez zewnętrznych assetów.

**Stack:** Godot 4.7 (GDScript), renderer GL Compatibility, eksport na Androida. Backend PvP (Supabase) dojdzie w etapie 8.

## Stan: etap 2 z planu MVP

Etap 1 (szkielet projektu, viewport 320×180, testowy APK) jest zamknięty. Etap 2 to teren i siatka budowy
z kamerą (issues #3 i #4):

- `scripts/world/terrain_map.gd` (`TerrainMap`): mapa 64×64 kratki po 8×8 px z seeda. Wzgórze z szumu
  wartości (4 odcienie trawy, najwyżej pośrodku), rzeka szerokości 2 kratek z boku i dwie ścieżki od grodu:
  na południe i przez most do bocznej krawędzi. Logika jest na liczbach całkowitych, więc ten sam seed
  zawsze daje ten sam teren.
- `scripts/world/build_grid.gd` (`BuildGrid`): zajętość kratek, walidacja miejsca (tylko wolna trawa
  w granicach mapy), stawianie i usuwanie budynków.
- `scripts/gfx/terrain_renderer.gd` (`TerrainRenderer`): cała mapa 512×512 px rysowana raz do jednej
  `ImageTexture`. Kafelki bazowe kopiuje `blit_rect`, a `set_pixel` dorysowuje tylko brzegi, skraje ścieżek
  i zbocza. Zamiast `TileMapLayer`, bo mapa jest statyczna, a jedna tekstura jest prostsza i szybsza
  (ok. 30 ms na komputerze).
- `scripts/camera/pan_zoom_camera.gd` (`PanZoomCamera`): przeciąganie jednym palcem, szczypanie
  (i kółko myszy) przełącza zoom 1×/2×/4×, pozycja w całych pikselach, granice na krawędziach mapy.
  Krótkie dotknięcie bez ruchu to „tap”.
- `scripts/main.gd` + `scripts/ui/hud.gd`: tap na wolnej trawie stawia chatę 2×2 kratki, tap na chacie
  ją usuwa. Zielona ramka oznacza akcję udaną, czerwona miejsce niedozwolone. U góry widać seed, zoom i FPS.

Do ręcznego testu na telefonie: płynność przeciągania, szczypanie i to, czy tap nie myli się z przeciąganiem.

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

Etap 3: biblioteka prymitywów i `draw_building(typ, poziom, stan)` (#5), autotiling wałów i palisady (#6)
oraz pierwsze 5 budynków epoki I z poziomami 1–5 (#7).
