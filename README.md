# Castle Defender

Mobilna gra 2D pixelart (Android) z asynchronicznym PvP. Gracze rozbudowują zamki od wałów ziemnych do twierdzy z końca wojen napoleońskich i atakują zamki innych graczy. Cała grafika jest rysowana kodem, bez zewnętrznych assetów.

**Stack:** Godot 4.7 (GDScript), renderer GL Compatibility, eksport na Androida. Backend PvP (Supabase) dojdzie w etapie 8.

## Stan: etap 4 z planu MVP

Etapy 1 (szkielet, viewport 320×180, testowy APK), 2 (teren 64×64 z seeda, siatka budowy, kamera
z gestami) i 3 (budynki epoki I: autotiling umocnień #6, pięć budynków z poziomami 1–5 #7) są zamknięte.
Etap 4 (krok 4 planu MVP) to 4 stany zniszczeń budynków (#8), paleta epoki I zamknięta w 16 kolorach (#5),
ekonomia (#10), progresja: koszty, czasy, kolejka budowy i Dwór jako poziom zamku (#11), oraz zapis
lokalny (#13). Z #5 zostaje pomiar startu na telefonie.

- `scripts/gfx/palette.gd` (`Palette`): 16 kolorów epoki I w `AGE_I`. Rampy `GRASS`, `WOOD`, `EARTH`,
  `THATCH`, `WATER` to widoki na nią (ziemia i drewno dzielą ciemne brązy). Kolory UI są osobno w `UI`.

- `scripts/gfx/pixel_canvas.gd` (`PixelCanvas`): prymitywy rysowania: ściana z bali, ściana z desek,
  belki szkieletu, dach strzechowy, okno, drzwi, flaga i dithering 2×2. Faktura idzie przez `hash2`.
- `scripts/gfx/building_art.gd` (`BuildingArt`): budynki w rzucie 3/4, każdy z 5 poziomami o różnym
  wyglądzie, i 4 stany zniszczeń: cały, pęknięcia, wyrwa w blankach, gruz. W wale i palisadzie
  wyrwa obniża ścianę w blokach 2×2, a gruz leży na kształcie odcinka, więc autotiling dalej się łączy.
  Budynki wielokratkowe dostają wyłomy w górnej krawędzi i kopiec rumowiska na swoich kratkach.
  Wał i palisada mają autotiling: odcinek 1×1 to środek plus ramię do każdego sąsiada z maski N/E/S/W
  (16 wariantów). Ramiona dochodzą do krawędzi kratki, więc dowolny kształt łączy się bez dziur.
  Ściana i blanki rysują się osobno, a palisada ma ścianę wysoką na 4 px.
- `scripts/gfx/building_textures.gd` (`BuildingTextures`): `draw_building(rodzaj, poziom, stan, maska,
  pionowo)` zwraca `ImageTexture` z cache. `warm_up()` rysuje przy starcie 222 całe warianty i place budowy
  (ok. 19 ms na komputerze, headless).
- `scripts/world/building_types.gd` (`BuildingTypes`): Wał ziemny i Palisada (1×1), Brama drewniana (3×1),
  Wieża drewniana, Chata drwala i Dwór (2×2). Wał łączy się z wałem, palisada z palisadą, bramą i wieżą.
  Dwór stoi od startu na środku mapy, jest jeden, nie ma go na pasku budowy i nie da się go rozebrać.
  `state_for_hp(hp, max_hp)` wybiera stan z procentu wytrzymałości: od 76% cały, od 41% pęknięcia,
  od 1% wyrwa, 0 to gruz.
- `scripts/world/build_grid.gd` (`BuildGrid`): rodzaj i poziom budynku (0 = plac budowy), poziom Dworu,
  maski sąsiadów i stała kolejność rysowania (od tyłu do przodu).
  Budynki stoją na trawie. Wyjątkiem jest brama (3 kratki): może stać nad drogą, ale tylko w poprzek niej
  i z drogą pośrodku (pozioma na drodze północ–południe, pionowa na drodze wschód–zachód).
- `scripts/world/build_config.gd` (`BuildConfig`): koszty i czasy budowy w jednym pliku. Poziom 1:
  Wał 10 Dr 10 Ży 5 s, Palisada 20 Dr 5 Ży 10 s, Brama 60 Dr 20 Ka 20 Ży 30 s, Wieża 120 Dr 40 Ka 40 Ży 60 s,
  Chata 80 Dr 30 Ży 45 s. Poziomy 1–5 mnożą koszt ×1/×1,5/×2,5/×4/×6, a czas ×1/×3/×10/×30/×90.
  Dwór 2–5: 300/200/200 10 min, 500/350/350 1 h, 750/550/550 4 h, 1000/800/800 12 h. Budynek nie może
  mieć wyższego poziomu niż Dwór.
- `scripts/world/build_queue.gd` (`BuildQueue`): jeden budowniczy i do 3 czekających zleceń. Koszt schodzi
  przy zleceniu, nowy budynek od razu zajmuje kratki jako plac budowy, anulowanie oddaje cały koszt
  (do pojemności magazynu), a rozbiórka gotowego budynku nic nie zwraca. Zlecenia kończą się po kolei
  według zegara, także w tle, a ekonomia liczy się odcinkami między ukończeniami.
- `scripts/world/save_game.gd` (`SaveGame`): zapis lokalny w `user://castle.json` (JSON z wersją formatu
  i miejscem na migracje). Zapisuje seed terenu, budynki, surowce i kolejkę budowy. Pisze pełny plik
  tymczasowy, a potem tylko zmienia nazwy: poprzedni zapis staje się kopią (`.bak`), a nowy plikiem
  głównym, więc na dysku zawsze leży co najmniej jeden pełny zapis. Nieczytelny plik główny jest
  odkładany obok (`.broken`) i nie trafia do kopii; zapis z nowszej wersji gry też nie jest nadpisywany.
- `scripts/world/economy_config.gd` (`EconomyConfig`): wszystkie liczby ekonomii w jednym pliku.
  Drewno, kamień, żywność i złoto. Start 500/300/300/50, magazyn 1000 każdego surowca, złoto bez
  limitu (docelowo waluta premium, przybywa tylko z łupu i PvE). Gród daje 20/h drewna, kamienia
  i żywności, a Chata drwala +60/90/120/160/200 drewna/h na poziomach 1–5.
- `scripts/world/economy.gd` (`Economy`): naliczanie produkcji w liczbach całkowitych (ten sam wynik
  co klatkę i jednym skokiem), limity magazynów, łup (`add`) i wydawanie (`spend`). Produkcja liczy
  się z zegara systemowego, więc rośnie też, gdy gra jest w tle. Po powrocie komunikat podaje przyrost.
- `scripts/gfx/pixel_icons.gd` (`PixelIcons`): ikony surowców 5×5 zapisane w kodzie jako wzory znaków
  (dwa bale, kamień, jabłko, moneta), kolory z palety, atlas w cache.
- `scripts/ui/hud.gd`: treść pasków trzyma się 12 px od bocznych krawędzi (zaokrąglone narożniki telefonów),
  a wycięcia ekranu zgłoszone przez system odsuwają ją dalej. U góry pasek surowców z ikonami (pełny magazyn ma dopisek „max” i kolor strzechy),
  a z prawej czas budowy i liczba czekających zleceń. Nad budowanym budynkiem pasek postępu.
  Pasek wyboru budynku nad dolną krawędzią pokazuje po wyborze koszt i czas. Po dotknięciu budynku
  karta z poziomem albo czasem budowy i przyciskami Ulepsz, Rozbierz (Anuluj dla zlecenia), Zamknij
  (cele 56×14 px).

Wymagania technologii dojdą z badaniami (#12).
Gra zapisuje się po każdej akcji, po ukończeniu budowy i przy zejściu do tła, a po ponownym uruchomieniu
nadrabia czas nieobecności (budowa i produkcja liczą się tak, jakby gra działała cały czas).

Do ręcznego testu na telefonie: czy przyciski paska i karty łatwo trafić, czy budowa długiego wału
kratka po kratce nie jest zbyt męcząca, czy po zejściu do tła na kilka minut surowce przybywają
i czy po zamknięciu aplikacji (także „ubiciu” z listy ostatnich) zamek wraca z nadrobioną budową.

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

Po scaleniu #13 etap 4 jest zamknięty w kodzie. Przed etapem 5 właściciel testuje go na telefonie
(lista w „Do ręcznego testu na telefonie” wyżej, plus pomiar startu z #5). Etap 5 wybiera właściciel;
najbliżej obecnego stanu są reszta HUD-u, czyli przyciski Buduj i Oblężenie (#9), i badania (#12).
