# tests/

Testy headless Godota (logika, determinizm). CI uruchamia je przez `.github/scripts/run_checks.sh`.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `run_tests.gd` | Runner: zbiera `test_*.gd`, raportuje wynik, exit code |
| `check_compile.gd` | Kompilacja wszystkich skryptów projektu |
| `test_case.gd` | Baza `TestCase` — metody `test_*` → `return true` |
| `test_*.gd` | Przypadki (bitwa, ekonomia, UI, sieć, …) |

## Uruchomienie

```bash
godot --headless --path . --script res://tests/run_tests.gd
# albo pełne CI lokalnie:
bash .github/scripts/run_checks.sh
```

Wzór nowego testu: skopiuj `test_pixel_canvas.gd`. Godot kończy się kodem 0 nawet po `SCRIPT ERROR` —
sprawdzaj log (robi to `run_checks.sh`).
