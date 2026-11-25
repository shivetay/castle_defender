# scripts/server/

Logika workera weryfikacji PvP po stronie Godota (#284), bez sieci i bez stanu gry.

| Plik | Rola |
|---|---|
| `verify_job.gd` | `VerifyJob.verify(job)` — bitwa z jobu jak `attack_replay` (#303) |

Punkt wejścia headless: `res://server/verify_main.gd` (katalog `server/` w korzeniu repo). Obraz Dockera i wrapper claim/submit: `server/verifier/`.
