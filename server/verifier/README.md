# Verifier Docker (#284 / #301)

Godot **4.7.2** headless + Python **claim/submit** wrapper (`psycopg`) for the PvP
verification worker.

- Same editor binary / SHA-512 as `.github/scripts/install_godot.sh`
- Non-root user `verifier` (uid 10001)
- Packs under `/app/packs` (bake or bind-mount)
- Writable only `/tmp/verifier` (compose uses `read_only` + tmpfs)
- Wrapper: `worker.py` → `private.claim_verification` / `private.submit_verification`

SQL queue and functions: migration `supabase/migrations/*_attack_verification.sql` (#304).
`verify_main.gd` is in the repo (#303); the `verify_*.pck` export is #305. Until the migration is
applied to the project (owner's approval) and a pack is on the host, use `smoke` on the VPS.

## SQL contract (#304)

| Call | Returns |
| --- | --- |
| `select private.claim_verification(:worker_id)` | one job (`jsonb`, shape of `attack_replay` + `attack_id`, `sim_version`) or `null` when the queue is empty |
| `select private.submit_verification(:attack_id::uuid, :result::jsonb)` | `verified`, `mismatch` or `rejected` (bad shape: job stays queued with `last_error = 'bad_result'`) |

- `worker_id`: `[A-Za-z0-9_.-]{1,64}` (`WORKER_ID`), otherwise `bad_worker`.
- Lease 5 min, max 3 attempts; after that the attack is `failed` (no loot, target unlocked).
- `submit_verification` raises `lease_expired` (no valid lease) or `not_pending` (attack already has a
  result); the wrapper rolls back and the lease runs out.
- A job is claimable once the phone's ruins arrive (`record_destroyed`) or 15 s after `finish_attack`.
- Mode `private.settings.verification_mode`: `shadow` (default; worker only compares) or `enforce`
  (loot, rating, shield and ruins only from the worker result; needs Edge/client §6 first).

## Role `verifier` (owner, on the Supabase project — never in git/PR/logs)

The migration creates `verifier` as `NOLOGIN` with only `USAGE` on `private` and `EXECUTE` on the two
functions above. To let the worker log in (SQL editor, as `postgres`):

```sql
alter role verifier login password '<generated, stored only in server/verifier/.env on the VPS>';
```

Connection string: Supabase pooler with user `verifier.<project-ref>` → `VERIFIER_DATABASE_URL`.
Rotate: run the same `alter role` with a new password and update `.env`.

## Image tag

`castle-defender-verifier:4.7.2`

## Build (on VPS / Linux with Docker)

```bash
docker build -t castle-defender-verifier:4.7.2 -f server/verifier/Dockerfile server/verifier
# or: cd server/verifier && docker compose build
```

## Run smoke (no secrets)

```bash
docker run --rm castle-defender-verifier:4.7.2 smoke
# → Godot 4.7.2.*, psycopg version, listing /app/packs
```

## Worker loop (needs host `.env`)

```bash
cd server/verifier
cp env.example .env
chmod 600 .env
# set VERIFIER_DATABASE_URL = Supabase pooler, role verifier (not service_role)
# command: ["worker"] in docker-compose.yml, then:
docker compose --env-file .env up --build -d
```

One-shot (exit 1 if queue empty):

```bash
docker compose --env-file .env run --rm verifier worker --once
```

Idle poll: 2 s. Godot timeout: 120 s. Logs: `attack_id`, elapsed ms, status / error
**class name** only — no job JSON, no player data, no connection string.

## Packs

See `packs/README.md`. Place `verify_<sim_version>.pck` here (or mount).

```bash
docker run --rm \
  -e SIM_VERSION=501 \
  -v "$PWD/server/verifier/packs:/app/packs:ro" \
  castle-defender-verifier:4.7.2 verify-pack
```

**TODO (#301 checklist):** export preset „Verifier” + CI pack at `v*` — not in this PR.

## Security

- Do **not** put `VERIFIER_DATABASE_URL`, service_role keys, or player data in the image or git.
- Use host `.env` (from `env.example`) only on the VPS.
- Wrapper executes only the two `private.*` RPCs; no table grants expected for role `verifier`.
- No inbound ports; egress to Supabase pooler only.

Owner runbook: Project store `docs/vps-verifier-docker.md` / `docs/verifier-claim-wrapper.md`.
