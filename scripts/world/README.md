# scripts/world/

Dane i logika świata zamku (poza bitwą i UI). Tu żyje **ekonomia**, budowa i progresja.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `terrain_map.gd` | Mapa 64×64 z seeda (trawa, woda, drogi, wysokości) |
| `world_seed.gd` / `player_profile.gd` | Seed zamku i tożsamość gracza (`user://player.json`) |
| `rulers.gd` | Władcy zamku; na razie domyślny bez premii (#228) |
| `building_types.gd` | Rodzaje budynków, rozmiary, stany HP → zniszczenia |
| `build_grid.gd` | Siatka budowy, sąsiedztwo, kolejność rysowania |
| `build_config.gd` / `build_queue.gd` | Koszty/czasy i kolejka budowy |
| `economy.gd` / `economy_config.gd` | Zasoby, produkcja, magazyn |
| `goods.gd` / `goods_config.gd` | Towary i łańcuchy produkcji |
| `research.gd` / `research_config.gd` | Badania w toku |
| `tech_tree.gd` / `tech_links.gd` | Drzewko i zależności technologii |
| `ages.gd` | Epoki |
| `recruitment.gd` / `recruitment_config.gd` | Kolejki szkolenia, limity armii |
| `unit_types.gd` | Klasy jednostek, statystyki, koszty |
| `save_game.gd` | Zapis/odczyt stanu zamku |
| `tutorial_goals.gd` | Cele samouczka |

Testy: `tests/test_economy.gd`, `test_buildings.gd`, `test_goods.gd`, `test_research.gd`, `test_recruitment.gd`, …
