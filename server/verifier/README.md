# Verifier Docker (#284 / #301)

Godot **4.7.2** headless + Python **claim/submit** wrapper (`psycopg`) for the PvP
verification worker.

- Same editor binary / SHA-512 as `.github/scripts/install_godot.sh`
- Non-root user `verifier` (uid 10001)
- Packs under `/app/packs` (bake or bind-mount)
- Writable only `/tmp/verifier` (compose uses `read_only` + tmpfs)
- Wrapper: `worker.py` → `private.claim_verification` / `private.submit_verification`

SQL functions and `verify_*.pck` / `verify_main.gd` are **later #284 steps**. Until they
exist on the project, `worker` cannot claim real jobs — use `smoke` on the VPS.

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
