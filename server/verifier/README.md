# Verifier Docker (#284 / #301)

Godot **4.7.2** headless + Python **claim/submit** wrapper (`psycopg`) for the PvP
verification worker.

- Same editor binary / SHA-512 as `.github/scripts/install_godot.sh`
- Non-root user `verifier` (uid 10001)
- Packs under `/app/packs` (bake or bind-mount)
- Writable only `/tmp/verifier` (compose uses `read_only` + tmpfs)
- Wrapper: `worker.py` → `private.claim_verification` / `private.submit_verification`

SQL queue and functions: migration `supabase/migrations/*_attack_verification.sql` (#304).
`verify_main.gd` is in the repo (#303); the `verify_*.pck` pack comes from the export preset
„Verifier” (#305, `packs/README.md`). Until the migration is applied to the project (owner's
approval) and a pack is on the host, use `smoke` on the VPS.

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

The container mode comes from `VERIFIER_COMMAND` in the host `.env` (`smoke` by default,
`worker`, `verify-pack`), so `docker-compose.yml` stays as in git and `git pull` never conflicts.

```bash
cd server/verifier
cp env.example .env
chmod 600 .env
# set VERIFIER_DATABASE_URL = Supabase session pooler, role verifier (not service_role)
# set VERIFIER_COMMAND=worker, then:
docker compose up --build -d
```

One-shot (exit 1 if queue empty):

```bash
docker compose run --rm verifier worker --once
```

Idle poll: 2 s. Godot timeout: 120 s. Logs: `attack_id`, elapsed ms, status / error
**class name** only — no job JSON, no player data, no connection string.

## Cutover on the VPS (#306)

Order of the owner's steps. Each step is reversible; none opens an inbound port.

1. **Role** (Supabase SQL editor, project `castle_defender`, as `postgres`): `alter role verifier
   login password '…'` (section above). Generate the password on the VPS, e.g.
   `openssl rand -base64 32`, and paste it only into the SQL editor and `.env`.
2. **`.env`** in `server/verifier/` on the VPS from `env.example`, `chmod 600 .env`:
   - `VERIFIER_DATABASE_URL`: Dashboard → Connect → *Session pooler* (IPv4, port 5432), user
     `verifier.<project-ref>`, password from step 1. Not the direct `db.<ref>.supabase.co` host
     (IPv6 only) and never a `service_role` key.
   - `SIM_VERSION`: code of the deployed client version (`python3 tools/version.py current` → `0.5.1` = `501`; the pack file name shows it too).
   - `VERIFIER_COMMAND=smoke` for now.
3. **Code**: `git pull` on `main`.
4. **Pack**: GitHub → Actions → „Wydanie” → *Run workflow* on `main` (no tag needed). From the run,
   download artifact `verify_<n>.pck` (pack + `.sha256`), copy both to `server/verifier/packs/`, then
   `cd packs && sha256sum -c verify_<n>.pck.sha256`.
5. **Image and smoke**:
   ```bash
   docker compose build                                  # castle-defender-verifier:4.7.2
   docker compose run --rm verifier smoke                # Godot 4.7.2, psycopg, pack listed
   docker compose run --rm verifier verify-pack          # exit 0, prints sim_version=<n>
   ```
6. **Database login once**: `docker compose run --rm verifier worker --once` → exit 1 and an
   idle log on an empty queue is correct; `db connect failed` means URL or password (the log shows
   the host only).
7. **Switch**: `VERIFIER_COMMAND=worker` in `.env`, `docker compose up -d`, then
   `docker compose logs -f verifier`: `worker start id=vps-1 …`, no URL, no job JSON.
8. **Check**: `docker compose ps` shows no published ports.

Rollback: `docker compose stop verifier` (the queue keeps its jobs; a lease runs out after 5 min
and the job is claimable again), then set `VERIFIER_COMMAND=smoke` in `.env` so a later `up -d`
does not start the worker again. Check the image with `docker compose run --rm verifier smoke`.
To cut database access entirely: `alter role verifier nologin`.

Restart policy is `on-failure`: a worker that crashes (exit ≠ 0) comes back, `smoke` exits 0 and
stays down. Docker does not start such a container after a VPS reboot, so `docker compose up -d`
on boot comes from systemd (`castle-defender-verifier.service`, once, as root):

```bash
cp castle-defender-verifier.service /etc/systemd/system/
# set WorkingDirectory in the unit to this directory on the VPS
systemctl daemon-reload
systemctl enable --now castle-defender-verifier
```

Rollback with the unit installed: `systemctl stop castle-defender-verifier` (runs
`docker compose stop verifier`), then `VERIFIER_COMMAND=smoke` in `.env`.

With `verification_mode = shadow` (default) the worker only compares results; loot, rating and
shields still come from `finish_attack`. Moving to `enforce` is a separate step (§7 #284).

## Packs

See `packs/README.md`. Place `verify_<sim_version>.pck` here (or mount).

```bash
docker run --rm \
  -e SIM_VERSION=501 \
  -v "$PWD/server/verifier/packs:/app/packs:ro" \
  castle-defender-verifier:4.7.2 verify-pack
```

`verify-pack` runs the pack on its own (`-- --check`) and exits 0 only when the pack reports
`sim_version=$SIM_VERSION`. Build the pack locally or take it from the release (`packs/README.md`).

## Security

- Do **not** put `VERIFIER_DATABASE_URL`, service_role keys, or player data in the image or git.
- Use host `.env` (from `env.example`) only on the VPS.
- Wrapper executes only the two `private.*` RPCs; no table grants expected for role `verifier`.
- No inbound ports; egress to Supabase pooler only.

Owner runbook: section „Cutover on the VPS (#306)” above.
