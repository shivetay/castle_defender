# Packi weryfikacji (`verify_<sim_version>.pck`)

Worker woła:

```text
godot --headless --main-pack packs/verify_<sim_version>.pck -- --job in.json --out out.json
```

## Stan (#301)

- [x] Katalog `packs/` w obrazie / montowaniu compose
- [ ] **TODO:** preset eksportu Godota „Verifier” (bez assetów graficznych) w `export_presets.cfg`
- [ ] **TODO:** punkt wejścia `res://server/verify_main.gd` (`VerifyJob.verify`) — §1 #284
- [ ] **TODO:** CI buduje `verify_<wersja>.pck` przy tagu `v*` — §5 #284

Do czasu eksportu: `verify-pack` / pełna pętla `worker` wymagają ręcznego włożenia pliku `.pck` tutaj (lub bind-mount). Nie commituj dużych binarnych packów do gita bez zgody właścicielki.

`sim_version` = kod wersji gry (`tools/version.py` / `config/version`), np. `501` → `verify_501.pck`.
