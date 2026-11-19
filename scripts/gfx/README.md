# scripts/gfx/

Proceduralne rysowanie pixelart (bez zewnętrznych PNG). Kolory **tylko** z `palette.gd`.
Tekstury generuj raz i cache’uj (`ImageTexture`); nie rysuj przez `set_pixel` co klatkę.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `palette.gd` | Palety epok + kolory UI |
| `pixel_canvas.gd` | Prymitywy (`hash2`, dachy, dithering, …) |
| `building_art.gd` | Wygląd budynków (poziomy, zniszczenia, autotiling) |
| `building_textures.gd` | Cache tekstur budynków, `warm_up()` |
| `terrain_renderer.gd` | Tekstura terenu z mapy |
| `portrait_art.gd` | Portret władcy w okręgu do HUD-u (#228) |
| `castle_view.gd` | Widok zamku na mapie |
| `ambient_view.gd` | Dym, błyski wody (niska częstotliwość) |
| `pixel_font.gd` / `pixel_icons.gd` | Font 8 px i ikony UI |

Determinizm faktury: `PixelCanvas.hash2()`, nie `randf()` bez seeda.
