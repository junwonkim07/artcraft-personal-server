# MinIO Community no longer publishes its old images. Build pinned official sources.
# Upstream MinIO and mc retain their AGPL-3.0 license; see LICENSE-NOTICE.md.
FROM golang:1.24.8-bookworm AS storage-build
ARG COMPONENT=minio
ARG SOURCE_SHA=9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a
WORKDIR /src
RUN git init -q . && git remote add origin "https://github.com/minio/${COMPONENT}.git" \
    && git fetch --depth 1 origin "${SOURCE_SHA}" && git checkout -q FETCH_HEAD \
    && test "$(git rev-parse HEAD)" = "${SOURCE_SHA}"
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -o /out/program .
FROM ubuntu:jammy-20250819 AS storage
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
COPY --from=storage-build /out/program /usr/local/bin/program
ARG COMPONENT=minio
RUN ln -s /usr/local/bin/program "/usr/local/bin/${COMPONENT}"
ENTRYPOINT ["/usr/local/bin/program"]
