# scripts/ui/

**UI / HUD** — panele i nakładki w rozdzielczości logicznej 320×180, font 8 px.
Wejście: dotyk (`InputEventScreenTouch` / `ScreenDrag`); mysz tylko przez emulację.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `hud.gd` | Główny HUD, tryby (oglądanie / budowa / …), skróty do paneli |
| `build_panel.gd` | Pasek wyboru budynków |
| `queue_panel.gd` | Kolejka budowy |
| `research_panel.gd` | Drzewko badań |
| `recruit_panel.gd` | Ekran Wojsko / rekrutacja |
| `attack_panel.gd` / `attack_planner.gd` | Atak i plan manewrów |
| `defense_panel.gd` | Ustawienia obrony |
| `target_picker.gd` | Wyprawa: 3 karty celów, gracze z serwera i boty (#24) |
| `bot_picker.gd` | Pełna lista 20 zamków-botów (#26); Planuj od razu otwiera plan (#312) |
| `result_panel.gd` | Podsumowanie bitwy; po powtórce raport obrony (#29) |
| `replay_panel.gd` | Powtórki: 5 ostatnich obron z serwera (#29) |
| `info_popup.gd` / `info_text.gd` | Karty info i teksty |
| `settings_panel.gd` | Ustawienia (m.in. tryb offline) |
| `onboarding_panel.gd` | Pierwsze uruchomienie: imię gracza, nazwa zamku, domyślny władca (#228) |
| `tutorial_hints.gd` / `tutorial_prompt.gd` | Mini-samouczek: podświetlenie kolejnego dotknięcia i pytanie o wyłączenie (#251) |
| `sync_curtain.gd` / `sync_loader_panel.gd` | Zasłona ładowania przy synchronizacji z serwerem: start po reinstalacji i przywracanie zamku, bez migania (#316) |
| `ruler_panel.gd` | Panel władcy z portretu: perk władcy, koszt zmiany (#32) |

Orkiestracja trybów: `scripts/main.gd`. Ikony/rysunki UI: `scripts/gfx/pixel_icons.gd`, `pixel_font.gd`.
