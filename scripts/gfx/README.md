# scripts/gfx/

Proceduralne rysowanie pixelart (bez zewnętrznych PNG). Kolory **tylko** z `palette.gd`.
Tekstury generuj raz i cache’uj (`ImageTexture`); nie rysuj przez `set_pixel` co klatkę.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `palette.gd` | Palety epok + kolory UI |
| `pixel_canvas.gd` | Prymitywy (`hash2`, dachy, dithering, …) |
| `building_art.gd` | Wygląd budynków (poziomy, zniszczenia, autotiling) |
| `mvp_building_art.gd` / `age_ii_building_art.gd` | Budynki MVP z #35 i budynki epoki II z #102 (Młyn, #388) |
| `building_textures.gd` | Cache tekstur budynków, `warm_up()` |
| `terrain_renderer.gd` | Tekstura terenu z mapy |
| `portrait_art.gd` | Portret władcy w okręgu do HUD-u (#228) |
| `castle_view.gd` | Widok zamku na mapie |
| `ambient_view.gd` | Dym, błyski wody (niska częstotliwość) |
| `pixel_font.gd` / `pixel_icons.gd` | Font 8 px i ikony UI (skróty surowców w tekście rysują się ikonami) |
| `smith_icon.gd` | Animowany kowal przy kowadle 22×16 (3 klatki) na zasłonie ładowania (#316) |

Determinizm faktury: `PixelCanvas.hash2()`, nie `randf()` bez seeda.
