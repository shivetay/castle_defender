# Packi weryfikacji (`verify_<sim_version>.pck`)

Worker woła:

```text
godot --headless --main-pack packs/verify_<sim_version>.pck -- --job in.json --out out.json
```

Pack startuje sam, bez `--script`: w presecie „Verifier” działa cecha `verifier`, która w
`project.godot` podmienia główną pętlę na `VerifyMain` (`res://server/verify_main.gd`) i scenę
główną na pustą `res://server/verify_main.tscn`. W grze i w testach te ustawienia nie działają.

`sim_version` = kod wersji gry (`tools/version.py`, `version/code` w `export_presets.cfg`):
`MAJOR*10000 + MINOR*100 + PATCH`, np. `0.5.1` → `501` → `verify_501.pck`. Tę samą nazwę liczą
`worker.py` (`pack_path_for`) i `entrypoint.sh verify-pack` (`PACKS_DIR/verify_${SIM_VERSION}.pck`).

## Co jest w packu

Preset „Verifier” (Linux, `export_filter="resources"`):

- `server/verify_main.gd` i `server/verify_main.tscn` (punkt wejścia);
- całe `scripts/` (bez `*.md`): `VerifyJob` → `BattleReplay` → `Battle`/`PlayerCastle` przez
  `class_name` sięga do `scripts/battle`, `world`, `net`, `gfx`, `ui` i `server`, więc wąska lista
  plików rozjeżdżałaby się z kodem;
- `project.binary`, cache klas i `icon.svg` (dodaje je sam Godot).

Bez `config/` (adres i klucz Supabase klienta), `scenes/`, `tests/`, `supabase/` i dokumentacji.
`build_verify_pack.sh` przerywa, jeśli w packu znajdzie się coś z `config/`.

## Eksport lokalny

Eksport packa **nie potrzebuje szablonów eksportu**, wystarczy Godot 4.7.2 z
`bash .github/scripts/install_godot.sh` (sprawdzony sumą jak w CI).

```bash
godot --headless --path . --import
bash .github/scripts/build_verify_pack.sh                # → server/verifier/packs/verify_<n>.pck
bash .github/scripts/build_verify_pack.sh --check        # + pack liczy fiksturę jak źródło
```

Ręcznie, bez skryptu (to samo co w skrypcie):

```bash
godot --headless --path . --export-pack "Verifier" server/verifier/packs/verify_501.pck
godot --headless --main-pack server/verifier/packs/verify_501.pck -- --check   # sim_version=501
```

`--check` w skrypcie: pack zgłasza swoją `sim_version`, a job z fikstury
`tests/verify_pack_fixture.gd` (te same dane co `tests/test_verify_job.gd`) daje w packu dokładnie
ten sam wynik i checksum co `VerifyJob` ze źródeł. Ten krok jest też w `run_checks.sh`.

Smoke w obrazie workera (pack zamontowany tylko do odczytu, kod wyjścia 0 przy zgodnej wersji):

```bash
docker run --rm -e SIM_VERSION=501 \
  -v "$PWD/server/verifier/packs:/app/packs:ro" \
  castle-defender-verifier:4.7.2 verify-pack
```

## CI

Workflow „Wydanie” (`release.yml`, job `verify-pack`) buduje i sprawdza pack przy tagu `v*`
i przy uruchomieniu ręcznym. Wynik to artefakt `verify_<n>.pck` z plikiem `.sha256`, a przy tagu
także asset GitHub Release. Na VPS pobierz oba pliki, sprawdź `sha256sum -c verify_<n>.pck.sha256`
i włóż pack tutaj (albo zamontuj katalog).

## Zasady

- Nie commituj `.pck` (są w `.gitignore`). Każdy pack buduje się z kodu w repo.
- Zmiana symulacji, która zmienia wynik fikstury, wymaga nowej wersji gry (nowy `sim_version`),
  bo stare packi muszą dalej liczyć bitwy starych klientów.
