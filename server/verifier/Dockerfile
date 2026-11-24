# Godot 4.7.2 headless verifier image for castle_defender (#284).
# Build (repo root or this directory context — see README):
#   docker build -t castle-defender-verifier:4.7.2 -f server/verifier/Dockerfile server/verifier
#
# Sumy SHA-512 jak w .github/scripts/install_godot.sh (nie commituj sekretów).
FROM debian:bookworm-slim

ARG GODOT_VERSION=4.7.2
ARG GODOT_SHA512=9aa00f7a605200940bce3027a567b782f49bd8e940dd06ae9e987bd65aee1b1467edd56ed84fcdcbdd44354bf613bdbb4e5d2913e925850368e150c59ed54c65

ENV DEBIAN_FRONTEND=noninteractive \
	GODOT_VERSION=${GODOT_VERSION} \
	LANG=C.UTF-8

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		ca-certificates \
		curl \
		unzip \
		libfontconfig1 \
		libglu1-mesa \
	&& rm -rf /var/lib/apt/lists/*

WORKDIR /opt/godot

RUN set -eu; \
	BASE="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"; \
	ZIP="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"; \
	curl -fsSL --retry 3 -o "${ZIP}" "${BASE}/${ZIP}"; \
	echo "${GODOT_SHA512}  ${ZIP}" | sha512sum --check; \
	unzip -oq "${ZIP}"; \
	install -m 0755 "Godot_v${GODOT_VERSION}-stable_linux.x86_64" /usr/local/bin/godot; \
	rm -f "${ZIP}" "Godot_v${GODOT_VERSION}-stable_linux.x86_64"; \
	godot --headless --version

# Non-root; packs can be baked in or bind-mounted at /app/packs.
RUN groupadd --system --gid 10001 verifier \
	&& useradd --system --uid 10001 --gid verifier --home-dir /app --shell /usr/sbin/nologin verifier \
	&& mkdir -p /app/packs /tmp/verifier \
	&& chown -R verifier:verifier /app /tmp/verifier

COPY --chown=verifier:verifier entrypoint.sh /app/entrypoint.sh
COPY --chown=verifier:verifier packs/ /app/packs/

RUN chmod 0755 /app/entrypoint.sh

USER verifier
WORKDIR /app

# Runtime: mount packs and/or set VERIFIER_DATABASE_URL on the host — never bake secrets.
ENV PACKS_DIR=/app/packs \
	TMPDIR=/tmp/verifier \
	WORKER_ID=

VOLUME ["/tmp/verifier"]

ENTRYPOINT ["/app/entrypoint.sh"]
CMD ["smoke"]
