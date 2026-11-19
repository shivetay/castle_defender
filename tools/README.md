# tools/

Narzędzia CLI projektu (Python), używane lokalnie i w CI.

## Kluczowe pliki

| Plik | Rola |
|---|---|
| `version.py` | Jedno źródło wersji; `check` / `bump` — trzyma zgodność `project.godot`, presetu, changelogu |
| `changelog.py` | Changelog ze scalonych PR-ów (`preview`, generowanie sekcji wydania) |
| `test_tools.py` | Testy jednostkowe powyższych |

Wersji i tagów `v*` nie podbijaj ręcznie bez prośby właściciela. Szczegóły: `README.md` (sekcja Wersje).
