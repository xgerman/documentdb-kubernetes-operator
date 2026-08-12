# Builds the ExtendDB server binary with the MongoDB storage backend
# compiled in. ExtendDB does not (as of this writing) publish an official
# container image with the MongoDB backend enabled -- only a PostgreSQL
# backend image is documented in the upstream repo's docker/README.md.
# Backends are mutually exclusive at compile time (see
# docs/local-mongodb-setup.md upstream), so we build our own single-backend
# image here with `--no-default-features --features mongodb`.
#
# Build (from this directory):
#   docker build -t extenddb-mongo:playground .
#
# Override the source ref/repo if you want a different version:
#   docker build --build-arg EXTENDDB_REF=v0.1.3 -t extenddb-mongo:playground .

ARG EXTENDDB_REPO=https://github.com/ExtendDB/extenddb.git
ARG EXTENDDB_REF=main

FROM rust:1.88-slim-bookworm AS build
ARG EXTENDDB_REPO
ARG EXTENDDB_REF

RUN apt-get update && apt-get install -y --no-install-recommends \
        git ca-certificates pkg-config libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone --depth 1 --branch "${EXTENDDB_REF}" "${EXTENDDB_REPO}" . \
    || (git clone "${EXTENDDB_REPO}" . && git checkout "${EXTENDDB_REF}")

# MongoDB backend build: the postgres/mongodb/sqlite features are mutually
# exclusive, so the default postgres feature must be disabled explicitly.
RUN cargo build --release --no-default-features --features mongodb

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates libssl3 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 10001 extenddb \
    && useradd -u 10001 -g extenddb -m -d /home/extenddb -s /usr/sbin/nologin extenddb

COPY --from=build /src/target/release/extenddb /usr/local/bin/extenddb

# Config, TLS state, and (for the mongodb backend) no local data files are
# written here -- state lives in MongoDB/DocumentDB -- but extenddb still
# needs a writable directory for extenddb.toml and the generated TLS cert.
RUN mkdir -p /var/lib/extenddb && chown extenddb:extenddb /var/lib/extenddb

USER extenddb:extenddb
WORKDIR /var/lib/extenddb
EXPOSE 18443

ENTRYPOINT ["extenddb"]
CMD ["serve", "--config", "/var/lib/extenddb/extenddb.toml", "--foreground"]
