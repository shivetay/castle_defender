# scripts/

Logika gry w GDScript. Wejście aplikacji: `main.gd` (scena `scenes/main.tscn`).

## Podfoldery

| Folder | Rola |
|---|---|
| `world/` | Świat gracza: teren, budowa, ekonomia, badania, rekrutacja, zapis |
| `battle/` | Deterministyczna bitwa (bez renderu) + boty, plany, pułapki |
| `ui/` | HUD i panele (budowa, atak, obrona, badania, wojsko) |
| `gfx/` | Proceduralne rysowanie i cache tekstur |
| `camera/` | Pan/zoom kamery (gesty) |
| `net/` | Klient Supabase i synchronizacja PvP |

Szczegóły w `README.md` każdego podfolderu. Zasady kodu: `CLAUDE.md` (typowanie, determinizm, grafika).
