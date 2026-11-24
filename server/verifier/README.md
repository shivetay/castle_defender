# Verifier Docker (#284)

Minimal **Godot 4.7.2 headless** image for the PvP attack verification worker.

- Same editor binary / SHA-512 as `.github/scripts/install_godot.sh`
- Non-root user `verifier` (uid 10001)
- Packs under `/app/packs` (bake or bind-mount)
- Writable only `/tmp/verifier` (compose uses `read_only` + tmpfs)

Full Python claim/submit wrapper (`psycopg`) lands in a later PR after owner approval of that dependency. This PR is the image + smoke entrypoint.

## Image tag

`castle-defender-verifier:4.7.2`

## Build (on VPS / Linux with Docker)

From repo root after clone:

```bash
docker build -t castle-defender-verifier:4.7.2 -f server/verifier/Dockerfile server/verifier
```

Or from this directory:

```bash
cd server/verifier
docker compose build
```

## Run smoke (no secrets)

```bash
docker run --rm castle-defender-verifier:4.7.2 smoke
# → prints Godot 4.7.2.* and lists /app/packs
```

Compose:

```bash
cd server/verifier
docker compose up --build
```

## Packs

Place `verify_<sim_version>.pck` in `server/verifier/packs/` (or mount that path). Export preset „Verifier” and CI pack build are later #284 steps.

```bash
docker run --rm \
  -e SIM_VERSION=501 \
  -v "$PWD/server/verifier/packs:/app/packs:ro" \
  castle-defender-verifier:4.7.2 verify-pack
```

## Security

- Do **not** put `VERIFIER_DATABASE_URL`, service_role keys, or player data in the image or git.
- Use host `.env` (from `env.example`) only on the VPS.
- No inbound ports; when the wrapper exists, only egress to Supabase pooler.

Owner runbook (Hostinger / scp): Project store `docs/vps-verifier-docker.md`.
