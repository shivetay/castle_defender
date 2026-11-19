# AGENTS.md — mapa repozytorium dla agentów

Krótki przewodnik po kodzie Castle Defender. Zasady pracy (grafika w kodzie, determinizm,
bezpieczeństwo, PR-y) są w `CLAUDE.md`. Opis gry i stan etapów: `README.md`.

## Stack

- Godot **4.7** (GDScript), viewport 320×180, renderer GL Compatibility
- Backend PvP: **Supabase** (`supabase/`, klient w `scripts/net/`)
- Cała grafika z kodu (`scripts/gfx/`), kolory tylko z `scripts/gfx/palette.gd`

## Mapa katalogów

| Ścieżka | Co tu jest |
|---|---|
| `scenes/` | Sceny Godota (`main.tscn`) |
| `scripts/` | Logika gry (patrz podfoldery niżej) |
| `scripts/world/` | **Ekonomia**, budowa, teren, badania, rekrutacja, zapis |
| `scripts/battle/` | **Bitwa**: deterministyczna symulacja, plan ataku/obrony, boty |
| `scripts/ui/` | **UI/HUD**: panele budowy, ataku, obrony, badań, wojska |
| `scripts/gfx/` | Rysowanie proceduralne, paleta, widok zamku |
| `scripts/camera/` | Kamera z gestami (pan/zoom) |
| `scripts/net/` | Klient Supabase, sesja, sync zamku, start ataku |
| `tests/` | Testy headless (`TestCase`, `run_tests.gd`) |
| `docs/castle-defender-vault/` | Notatki projektowe (Obsidian; Godot je pomija) |
| `config/` | Wzór `supabase.example.json` (prawdziwy plik poza gitem) |
| `supabase/` | Migracje, Edge Functions, testy RLS (pgTAP) |
| `tools/` | `version.py`, `changelog.py` |
| `.github/` | CI i skrypty (`run_checks.sh`, `install_godot.sh`) |
| `.claude/skills/` | Skille AI (w tym bezpieczeństwa) |
| `.cursor/` | Reguły Cursora / Bugbota → odsyłają do `CLAUDE.md` |

Każdy z tych katalogów ma własny `README.md` z kluczowymi plikami.

## Gdzie szukać mechanik

- **Bitwa / PvE / manewry / pułapki:** `scripts/battle/` (+ UI w `scripts/ui/attack_*.gd`, `defense_panel.gd`)
- **Ekonomia / towary / kolejka budowy:** `scripts/world/economy*.gd`, `goods*.gd`, `build_queue.gd`
- **Budynki / siatka / teren:** `scripts/world/building_types.gd`, `build_grid.gd`, `terrain_map.gd`
- **Badania / epoki:** `scripts/world/research*.gd`, `tech_*.gd`, `ages.gd`
- **Armia / rekrutacja:** `scripts/world/recruitment*.gd`, `unit_types.gd` + `scripts/ui/recruit_panel.gd`
- **HUD i tryby:** `scripts/ui/hud.gd`, `scripts/main.gd`
- **PvP / sieć:** `scripts/net/` + `supabase/`

## Testy i weryfikacja

Wymaga Godota 4.7.2 w PATH jako `godot` (Windows: konsolowy exe + Git Bash).

```bash
bash .github/scripts/run_checks.sh
# albo tylko logika:
godot --headless --path . --script res://tests/run_tests.gd
```

Nowe testy: `tests/test_<nazwa>.gd` → `extends TestCase`, metody `test_*` kończą się `return true`.

RLS (lokalnie, Docker + Supabase CLI):

```bash
supabase start
supabase test db
```

## Twarde reguły (skrót)

1. Bez PNG/fontów/assetów z generatorów — grafika w kodzie.
2. Kolory wyłącznie z palet; determinizm przez seed / `PixelCanvas.hash2()`.
3. Piksele całkowite; zoom tylko 0,5×/1×/2×/4×.
4. Klient niezaufany: wynik/łup/ranking z serwera; w kliencie tylko klucz publishable.
5. Jedna spójna zmiana na gałąź; PR po polsku; merge do `main` robi właściciel.
6. Przed „gotowe”: `run_checks.sh` (nie ufaj samemu exit code Godota przy błędach w logu).
