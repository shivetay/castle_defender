# scripts/battle/

**Bitwa** — deterministyczna symulacja w stałym kroku czasu, bez zależności od renderu.
Ten sam seed + dane → ten sam przebieg (ważne dla weryfikacji PvP).

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `battle.gd` | Silnik symulacji |
| `battle_config.gd` | Stałe / balans bitwy |
| `battle_rng.gd` | Seedowany RNG bitwy |
| `battle_effects.gd` | Efekty (m.in. z badań) |
| `battle_result.gd` | Wynik, łup (logika klienta; serwer weryfikuje przy PvP) |
| `battle_view.gd` | Wizualizacja przebiegu (osobno od logiki) |
| `attack_plan.gd` | Plan ataku i manewry |
| `defense_plan.gd` | Posterunki i zadania obrony |
| `trap_config.gd` | Pułapki |
| `battle_replay.gd` | Powtórka obrony (#29): bitwa z danych `attack_replay` tą samą drogą co u atakującego (`PlayerCastle`) |
| `scout_intel.gd` | Mgła wojny w planie ataku (#28): fragment zamku odsłonięty przez zwiad |
| `bot_castle.gd` / `bot_roster.gd` | Generator zamku i składu bota |
| `pve_waves.gd` | Fale PvE |

UI planu/ataku/obrony: `scripts/ui/`. Testy: `tests/test_battle*.gd`, `test_attack_plan.gd`, `test_defense*.gd`, `test_traps.gd`.
