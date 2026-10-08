# syntax=docker/dockerfile:1.7
# Builds storyteller-web (and the diesel migration runner) from the pinned upstream commit.
# Mirrors upstream build/service_cpu.Dockerfile (ubuntu:jammy, rustup toolchain 1.93.0,
# SQLX_OFFLINE=true, /GIT_SHA file, upstream common/production env files placed next to the binary
# inside the image from the source fetched at build time; nothing upstream is stored in this repo),
# but only builds the storyteller-web binary (workers are intentionally excluded).

ARG BASE_IMAGE=ubuntu:jammy-20250819

# ---------- source: clone pinned commit, verify, apply personal-server patches ----------
FROM ${BASE_IMAGE} AS source
ARG UPSTREAM_REPO=https://github.com/storytold/artcraft-services.git
ARG UPSTREAM_SHA=d950e57352a1b28c9296f69f8ae4eff43877de21
# "true" (default): apply patches/backend/*.patch and patches/frontend/*.patch; "false": pristine upstream.
ARG APPLY_PATCHES=true
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY patches/ /patches/
RUN set -eu; \
    git init -q . \
    && git remote add origin "${UPSTREAM_REPO}" \
    && git fetch -q --depth 1 origin "${UPSTREAM_SHA}" \
    && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA}" \
    && echo -n "${UPSTREAM_SHA}" > /GIT_SHA; \
    : > /PATCHES_APPLIED; \
    if [ "${APPLY_PATCHES}" = "true" ]; then \
      for p in /patches/backend/*.patch /patches/frontend/*.patch; do \
        [ -e "$p" ] || continue; \
        echo "checking $p"; \
        git apply --check --verbose "$p" || { echo "PATCH DOES NOT APPLY: $p" >&2; exit 1; }; \
        git apply --verbose "$p"; \
        basename "$p" >> /PATCHES_APPLIED; \
      done; \
    elif [ "${APPLY_PATCHES}" != "false" ]; then \
      echo "APPLY_PATCHES must be true or false" >&2; exit 1; \
    fi; \
    echo "patches applied:"; cat /PATCHES_APPLIED; \
    rm -rf .git

# ---------- rust-base: same packages/toolchain as upstream service_cpu.Dockerfile ----------
FROM ${BASE_IMAGE} AS rust-base
ARG RUST_TOOLCHAIN=1.93.0
RUN apt-get update && DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y \
        build-essential cmake curl ca-certificates ffmpeg fontconfig git libclang-dev \
        libfontconfig1-dev libssl-dev musl-tools perl pkg-config default-libmysqlclient-dev \
    && rm -rf /var/lib/apt/lists/*
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain "${RUST_TOOLCHAIN}" -y --profile minimal
ENV PATH=/root/.cargo/bin:${PATH}

# ---------- builder ----------
FROM rust-base AS builder
WORKDIR /tmp
COPY --from=source /src/Cargo.lock /src/Cargo.toml ./
COPY --from=source /src/.sqlx ./.sqlx
COPY --from=source /src/_database ./_database
COPY --from=source /src/crates ./crates
COPY --from=source /src/includes ./includes
COPY --from=source /src/test_data ./test_data
# Only storyteller-web is built. Upstream background workers are intentionally excluded (not verified).
RUN set -eux; \
    SQLX_OFFLINE=true cargo build --release --locked --bin storyteller-web; \
    mkdir -p /out; cp target/release/storyteller-web /out/

# ---------- diesel: pinned diesel_cli for migrations ----------
FROM rust-base AS diesel
ARG DIESEL_CLI_VERSION=2.3.14
RUN cargo install diesel_cli --version "${DIESEL_CLI_VERSION}" --locked --no-default-features --features mysql

# ---------- migrate target (one-shot: diesel migrations + ES index init) ----------
FROM ${BASE_IMAGE} AS migrate
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libmysqlclient21 ca-certificates curl mysql-client \
    && rm -rf /var/lib/apt/lists/*
COPY --from=diesel /root/.cargo/bin/diesel /usr/local/bin/diesel
COPY --from=source /src/_database /app/_database
COPY --from=source /src/diesel.toml /app/diesel.toml
COPY --from=source /GIT_SHA /GIT_SHA
COPY docker/migrate-entrypoint.sh /usr/local/bin/migrate-entrypoint.sh
COPY docker/es-init.sh /usr/local/bin/es-init.sh
RUN chmod 0755 /usr/local/bin/migrate-entrypoint.sh /usr/local/bin/es-init.sh
WORKDIR /app
ENTRYPOINT ["/usr/local/bin/migrate-entrypoint.sh"]

# ---------- runtime target ----------
FROM ${BASE_IMAGE} AS runtime
RUN apt-get update && DEBIAN_FRONTEND=noninteractive TZ=Etc/UTC apt-get install -y --no-install-recommends \
        ffmpeg ca-certificates curl libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --system --uid 10001 --home-dir / artcraft
WORKDIR /
COPY --from=source /GIT_SHA /GIT_SHA
COPY --from=source /PATCHES_APPLIED /PATCHES_APPLIED
COPY --from=builder /out/ /
COPY --from=source /src/includes /includes
# Upstream copies these next to the binary (empty files at the pinned SHA); bootstrap searches ".", "./config", ...
COPY --from=source /src/crates/service/web/storyteller_web/config/storyteller-web.common.env /storyteller-web.common.env
COPY --from=source /src/crates/service/web/storyteller_web/config/storyteller-web.production.env /storyteller-web.production.env
RUN touch /.env /.env-secrets && mkdir -p /tmp/storyteller && chown artcraft /tmp/storyteller
ENV TEMP_DIR=/tmp/storyteller
USER artcraft
EXPOSE 12345
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=10 CMD curl -fsS http://127.0.0.1:12345/_status || exit 1
CMD ["/storyteller-web"]

# ---------- webapp-build: upstream artcraft-webapp production build ----------
# Upstream pins no Node version (no .nvmrc / engines); Node 22 LTS is a template choice.
FROM node:22.23.3-bookworm-slim AS webapp-build
# Build-time origins baked into the bundle (see patches/frontend/). "same-origin" = API on the page's origin.
ARG VITE_API_ORIGIN=same-origin
ARG VITE_CDN_ORIGIN=http://localhost:4201
ENV VITE_API_ORIGIN=${VITE_API_ORIGIN} VITE_CDN_ORIGIN=${VITE_CDN_ORIGIN} \
    NX_DAEMON=false NX_NO_CLOUD=true CI=true \
    NODE_OPTIONS=--max-old-space-size=8192
# NODE_OPTIONS heap size mirrors upstream frontend/apps/artcraft-webapp/script/netlify_build.sh
WORKDIR /src/frontend
COPY --from=source /src/frontend/ /src/frontend/
RUN npm ci --no-audit --no-fund \
    && npx nx build artcraft-webapp \
    && test -f apps/artcraft-webapp/dist/index.html

# ---------- webapp: static files + single-origin reverse proxy (/v1 -> API, /media -> MinIO) ----------
FROM nginx:1.30.5-alpine AS webapp
COPY --from=webapp-build /src/frontend/apps/artcraft-webapp/dist/ /usr/share/nginx/html/
COPY docker/nginx-webapp.conf /etc/nginx/conf.d/default.conf
COPY --from=source /GIT_SHA /usr/share/nginx/GIT_SHA
COPY --from=source /PATCHES_APPLIED /usr/share/nginx/PATCHES_APPLIED
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 CMD wget -q -O /dev/null http://127.0.0.1/ || exit 1
