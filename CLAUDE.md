# Reguły pracy z AI: Castle Defender

Ten plik czyta agent AI (Claude Code i inne) na początku każdej sesji. Opis gry i instrukcja
uruchomienia są w `README.md`. Tu są zasady, których agent ma się trzymać.

## Projekt w skrócie

- Mobilna gra 2D pixelart na Androida z asynchronicznym PvP. Zamki rozwijają się przez epoki,
  od grodu do twierdzy z czasów napoleońskich.
- **Godot 4.7 (testowane na 4.7.2), GDScript, renderer GL Compatibility.** Wersja jest w `config/features`
  w `project.godot`. Nie podnoś jej i nie używaj API z nowszych wersji bez zgody właściciela.
- Logiczna rozdzielczość to 320×180 ze skalowaniem całkowitym i filtrem `Nearest`.
- Backend PvP (Supabase) pojawi się dopiero w etapie 8.

## Zasady nadrzędne

1. **Cała grafika powstaje w kodzie.** Nie dodawaj PNG, spritesheetów, fontów ani assetów
   z generatorów AI. Wyjątek to `icon.svg`.
2. **Kolory biorą się wyłącznie z palet** w `scripts/gfx/palette.gd`. Nowy kolor dodajesz
   do palety epoki, a nie jako `Color(...)` wpisany w kod rysujący. Wyjątek: przezroczystość
   koloru z palety, np. `Color(Palette.SHADOW, 0.8)`.
3. **Grafika i świat są deterministyczne.** Losowość idzie przez `PixelCanvas.hash2()` albo
   `RandomNumberGenerator` z jawnym seedem, nigdy przez `randi()` lub `randf()` bez seeda.
   Asynchroniczne PvP opiera się na tym, że ten sam seed i te same dane dają zawsze ten sam
   zamek i ten sam przebieg bitwy.
4. **Piksele muszą być ostre.** Pozycje, rozmiary i ruch kamery są w całych pikselach logicznych.
   Nie używaj ułamkowego skalowania, rotacji sprite'ów ani filtrowania tekstur. Zoom tylko 1×/2×/4×.
5. **Pracuj etapami.** Jeden etap planu MVP to jedna spójna zmiana. Po etapie zaktualizuj
   sekcje „Stan” i „Następny etap” w `README.md`. Nie zaczynaj kolejnego etapu bez zgody.

## Styl kodu (GDScript)

- Typuj wszystko: pola, parametry i wartości zwracane. `:=` stosuj tylko wtedy, gdy prawa
  strona ma znany typ statyczny. Dla Variantów (`Dictionary.get`, `get_node`) podaj typ jawnie
  albo rzutuj przez `as`.
- W kodzie typowanym używaj `mini/maxi/clampi/absf` itd. zamiast `min/max/clamp/abs`.
- Nazwy klas, funkcji i zmiennych są po angielsku. Komentarze `##` i teksty w UI są po polsku,
  jak w istniejącym kodzie.
- Funkcje rysujące to `static func` w `PixelCanvas` (lub w pokrewnych klasach w `scripts/gfx/`).
  Przyjmują `Image` i punkt zaczepienia, nie trzymają stanu.
- Wcięcia tabulatorami (`.editorconfig`). Pliki `.tscn` i `project.godot` edytuj ręcznie tylko
  minimalnie i zachowuj ich format.

## Wydajność na telefonie

- `Image.set_pixel()` jest wolne. Generuj tekstury raz (przy starcie, przy zmianie budynku)
  i trzymaj je w cache jako `ImageTexture`. Nie generuj ich co klatkę.
- `_process()` służy do wizualiów, `_physics_process()` do symulacji. Docelowo 60 FPS
  ze stałym zapasem na throttling.
- Logika bitwy powinna działać bez renderowania, w stałym kroku czasu. Dzięki temu da się ją
  odtworzyć i zweryfikować przy PvP.

## Dotyk i UI

- Główne wejście to dotyk (`InputEventScreenTouch`/`ScreenDrag`). Mysz działa tylko przez
  emulację.
- Cele dotyku mają co najmniej 12×12 px logicznych. Ważne przyciski nie stoją przy krawędziach,
  bo przeszkadzają wcięcia ekranu i gesty systemowe.
- Tekst używa fontu 8 px. Sprawdzaj, czy mieści się w 320 px szerokości.

## Weryfikacja przed zgłoszeniem „gotowe”

Całość uruchamia `bash .github/scripts/run_checks.sh` (to samo robi CI). Godota w kontenerze
instaluje `bash .github/scripts/install_godot.sh`. Kroki:

1. `python3 tools/version.py check`: wersja zgodna w projekcie, presecie i changelogu.
2. `godot --headless --path . --import` (rejestruje `class_name`).
3. `godot --headless --path . --script res://tests/check_compile.gd`: kompilacja wszystkich skryptów.
4. Test dymny: 300 klatek bez `SCRIPT ERROR` i `ERROR:` w logu. Godot kończy się kodem 0 nawet
   po błędach, więc nie ufaj samemu kodowi wyjścia.
5. `godot --headless --path . --script res://tests/run_tests.gd`: testy logiki. Nowa logika
   (generator, ekonomia, symulacja bitwy) dostaje test w `tests/test_<nazwa>.gd` (`extends TestCase`,
   każda metoda kończy się `return true`). Determinizm testujesz wprost: ten sam seed daje identyczny wynik.

Jeśli Godota nie ma, napisz to wprost w podsumowaniu i nie twierdź, że kod działa.
Czego nie da się sprawdzić bez telefonu (dotyk, FPS, APK), zostaje do ręcznego testu właściciela.

## Git, wersje i współpraca

- Każda zmiana widoczna dla gracza albo dla procesu (CI, narzędzia) dostaje punkt w `CHANGELOG.md`
  w sekcji „Nieopublikowane”, w tym samym commicie co kod.
- Wersji nie zmieniasz ręcznie, tylko przez `python3 tools/version.py bump`. Tagi `v*` i wydania
  tworzysz wyłącznie na prośbę właściciela, bo tag od razu tworzy GitHub Release.
- Commity po polsku, w trybie rozkazującym lub z prefiksem etapu, np. `Etap 2: generator terenu 64×64`.
- Małe, logiczne commity.
- **PR-y agent tworzy sam:** po wypchnięciu skończonej, zweryfikowanej zmiany otwiera PR do `main`
  z opisem (co, dlaczego, jak sprawdzone, czego nie dało się sprawdzić) i linkiem do issue
  (`Closes #N` tylko wtedy, gdy merge faktycznie domyka issue). Gdy gałąź zależy od innej
  niescalonej gałęzi, pisze to w opisie.
- **Gałęzie mają tylko opisowe nazwy** w formacie `<typ>/<krótki-opis>`, małymi literami
  w kebab-case, bez polskich znaków. Typ to `feat`, `fix`, `ci`, `docs`, `chore`, `refactor`
  albo `test`. Przykłady: `feat/etap-3-budynki-epoki-i`, `fix/android-etc2-astc`,
  `ci/apk-przy-pushu-na-main`. Losowe nazwy, takie jak `claude/serene-edison-5gql30`, są zakazane.
  Jeśli sesja dostała taką gałąź, utwórz od aktualnego `main` gałąź opisową, pracuj na niej
  i tam pushuj. Jedna gałąź to jedna spójna zmiana (etap, poprawka, zmiana CI).
- **Merge do `main` robi wyłącznie właściciel.** Agent nie merguje, nie pushuje na `main`
  i nie zamyka issues, których kod nie trafił jeszcze na `main`.
- **Najpierw zapytaj**, gdy chodzi o: decyzje projektowe gry (balans, mechaniki, kolejność etapów),
  zmianę wersji Godota, nowe addony lub zależności, zmiany w `export_presets.cfg` i ustawieniach
  wyświetlania w `project.godot`.
- Przy niejasnej specyfikacji zaproponuj jedną konkretną opcję z uzasadnieniem, zamiast wymieniać
  pięć.

## Bezpieczeństwo

- Nigdy nie commituj keystore'ów, haseł, kluczy Supabase ani `.env` (są w `.gitignore`;
  nie obchodź tego).
- PvP od etapu 8: klient nie jest zaufany. Wynik ataku liczy albo weryfikuje serwer
  (deterministyczna powtórka symulacji). W Supabase wszystkie tabele mają RLS, a w kliencie jest
  tylko klucz `anon`/publishable, nigdy `service_role`.

## Skille AI

W `.claude/skills/` jest 15 skilli skopiowanych z
[gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
(Apache-2.0, commit `c6ca6c4`, licencja i NOTICE obok). Claude Code wczytuje je sam, gdy pasują
do zadania. Są pisane pod Godot 4.7, czyli pod naszą wersję.

| Skill | Do czego tutaj |
|---|---|
| `godot-gdscript` | typowanie, gotchas, skrypt sprawdzający kompilację |
| `godot-gdscript-headless-testing` | runner testów z poprawnym kodem wyjścia, CI |
| `godot-nodes-scenes`, `godot-signals-groups`, `godot-resources` | sceny, sygnały, dane jako `Resource` |
| `godot-tilemap` | siatka budowy (etap 2), jeśli przejdziemy na `TileMapLayer` |
| `godot-ui-control` | HUD i menu |
| `godot-export` | eksport APK z linii poleceń / CI |
| `procedural-gen` | seedowany generator terenu |
| `camera-systems`, `input-systems` | kamera z przeciąganiem i zoomem, gesty dotykowe |
| `tower-defense` | fale, wieże, krzywe HP i ekonomii (obrona zamku) |
| `save-systems`, `performance-optimization`, `game-ui-ux` | zapis stanu, FPS na telefonie, UX mobilny |

Zasady:

- Gdy skill jest sprzeczny z tym plikiem, wygrywa `CLAUDE.md` (np. grafika tylko w kodzie).
- Nie dodajemy `create-game-assets`, bo grafika powstaje w kodzie (zasada 1).
- Skrypty pomocnicze skilli (`*.py`, `*.gd`) to kod z zewnątrz. Uruchamiaj je dopiero, gdy
  właściciel na to pozwoli. Do tego czasu sprawdzaj kompilację własnym, krótkim runnerem.
- Aktualizacja skilli: skopiuj nowe wersje z upstreamu, w commicie podaj nowy hash i przejrzyj diff.
