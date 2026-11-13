# Castle Defender

Mobilna gra 2D pixelart (Android) z asynchronicznym PvP. Gracze rozbudowują zamki od wałów ziemnych do twierdzy z końca wojen napoleońskich i atakują zamki innych graczy. Cała grafika jest rysowana kodem, bez zewnętrznych assetów.

**Stack:** Godot 4.7 (GDScript), renderer GL Compatibility, eksport na Androida. Backend PvP (Supabase) dojdzie w etapie 8.

## Stan: etap 1 z planu MVP

Etap 1 to „projekt w Godot 4, viewport 320×180, testowy APK na telefon”. W repozytorium jest:

- `project.godot`: viewport 320×180, okno 1280×720, skalowanie całkowite (`integer`), filtr `Nearest`, przyciąganie do pikseli, orientacja pozioma, emulacja dotyku myszą.
- `scenes/main.tscn` + `scripts/main.gd`: scena testowa z terenem, palisadą i dwiema chatami wygenerowanymi przy starcie (`Image.set_pixel` → `ImageTexture`). Tapnięcie zostawia czerwony znacznik, a w rogu widać rozdzielczość i FPS, żeby sprawdzić dotyk i wydajność na telefonie.
- `scripts/gfx/palette.gd`: paleta epoki I.
- `scripts/gfx/pixel_canvas.gd`: deterministyczny `hash2(x, y)` i pierwsze funkcje rysujące.
- `export_presets.cfg`: preset „Android (debug APK)” (arm64-v8a, `com.shivetay.castledefender`).

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

Wersja to SemVer `MAJOR.MINOR.PATCH`. Przed 1.0.0 obowiązuje `0.N.x`, gdzie N to ukończony etap MVP,
a `x` to poprawki. Jedno źródło prawdy to `tools/version.py`, który trzyma w zgodzie
`project.godot`, `export_presets.cfg` (`version/name`, `version/code = MAJOR*10000 + MINOR*100 + PATCH`)
i `CHANGELOG.md`.

- Każda zmiana: dopisz punkt w `CHANGELOG.md` w sekcji „Nieopublikowane” (Dodane / Zmienione / Naprawione / Usunięte).
- Wydanie:

  ```bash
  python3 tools/version.py bump minor    # albo patch, major, 0.3.0
  git commit -am "Wydanie 0.2.0"
  git tag v0.2.0
  git push --follow-tags
  ```

- `python3 tools/version.py check` sprawdza zgodność wersji (uruchamia się też w CI).

## CI/CD (GitHub Actions)

| Workflow | Kiedy | Co robi |
|---|---|---|
| `ci.yml` | każdy push i PR | wersja i changelog, import, kompilacja skryptów, test dymny, testy logiki |
| `release.yml` | push na `main` | CI i debug APK jako artefakt (Actions → Wydanie → przebieg → Artifacts) |
| `release.yml` | tag `vX.Y.Z` | CI, debug APK, GitHub Release z opisem z changelogu (APK do pobrania na telefon) |
| `release.yml` (ręcznie) | Actions → Wydanie → Run workflow | samo debug APK jako artefakt, bez Release |
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
tests/           testy headless (run_tests.gd, check_compile.gd, test_*.gd)
tools/           narzędzia (version.py)
.github/         workflowy CI/CD i skrypty instalacji Godota
.claude/skills/  skille dla agenta AI (zob. CLAUDE.md)
build/           eksportowane APK i logi (ignorowane przez git)
```

## Następny etap

Etap 2: generator terenu 64×64 kratki (8×8 px) i siatka budowy z kamerą (przeciąganie, zoom 1×/2×/4×).
