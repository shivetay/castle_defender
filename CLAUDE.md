# Reguły pracy z AI: Castle Defender

Ten plik czyta agent AI (Claude Code i inne) na początku każdej sesji. Opis gry i instrukcja
uruchomienia są w `README.md`. Tu są zasady, których agent ma się trzymać.

## Projekt w skrócie

- Mobilna gra 2D pixelart na Androida z asynchronicznym PvP. Zamki rozwijają się przez epoki,
  od grodu do twierdzy z czasów napoleońskich.
- **Godot 4.5, GDScript, renderer GL Compatibility.** Wersja jest w `config/features`
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

Gdy Godot jest dostępny w środowisku (`godot --headless --version`):

1. `godot --headless --path . --import` przy świeżym checkoucie (rejestruje `class_name`).
2. Sprawdź kompilację wszystkich skryptów, np. skryptem `check_scripts_compile.gd`
   ze skilla `godot-gdscript` (patrz niżej).
3. Krótki test dymny: `godot --headless --path . --quit-after 300 > run.log 2>&1`, potem
   `grep -nE "SCRIPT ERROR|^ERROR:" run.log`. Wynik musi być pusty. Godot kończy się kodem 0
   nawet po błędach, więc nie ufaj samemu kodowi wyjścia.
4. Testy logiki (generator terenu, ekonomia, symulacja bitwy) piszesz w `tests/` jako runner
   `SceneTree` z `quit(1 if failed > 0 else 0)`. Determinizm testujesz wprost: ten sam seed
   musi dać identyczny wynik.

Jeśli Godota nie ma, napisz to wprost w podsumowaniu i nie twierdź, że kod działa.
Czego nie da się sprawdzić bez telefonu (dotyk, FPS, APK), zostaje do ręcznego testu właściciela.

## Git i współpraca

- Commity po polsku, w trybie rozkazującym lub z prefiksem etapu, np. `Etap 2: generator terenu 64×64`.
- Małe, logiczne commity. Push tylko na gałąź przydzieloną sesji. Bez PR-ów, dopóki
  właściciel o nie nie poprosi.
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

## Skille AI (opcjonalne)

Repo [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills)
(Apache-2.0) ma skille, które pasują do tego projektu:

| Skill | Do czego tutaj |
|---|---|
| `godot-gdscript` | typowanie, gotchas, skrypt sprawdzający kompilację |
| `godot-gdscript-headless-testing` | runner testów z poprawnym kodem wyjścia, CI |
| `godot-tilemap` | siatka budowy (etap 2), jeśli przejdziemy na `TileMapLayer` |
| `godot-ui-control` | HUD i menu |
| `godot-export` | eksport APK z linii poleceń / CI |
| `procedural-gen` | seedowany generator terenu |
| `camera-systems`, `input-systems` | kamera z przeciąganiem i zoomem, gesty dotykowe |
| `tower-defense` | fale, wieże, krzywe HP i ekonomii (obrona zamku) |
| `save-systems`, `performance-optimization`, `game-ui-ux` | zapis stanu, FPS na telefonie, UX mobilny |

Te skille są pisane pod **Godot 4.7**, a projekt używa **4.5**. Uwagi o zmianach w 4.6 i 4.7
nas nie dotyczą, a `Dictionary[K, V]` (od 4.4) i `@abstract` (od 4.5) są dozwolone.
Skilla `create-game-assets` nie używamy, bo grafika powstaje w kodzie (zasada 1).
