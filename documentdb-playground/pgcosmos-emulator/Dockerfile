# Wrapper image: aligns the public Azure Cosmos emulator image with the
# documentdb-kubernetes-operator's CloudNative-PG cluster expectations.
#
# Build:
#   docker build -t localhost/pgcosmos-emulator:dev .
# Load into kind:
#   kind load docker-image localhost/pgcosmos-emulator:dev --name <cluster>
#
# This image is intentionally kind-local only. DO NOT push it to any registry.

FROM mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview

# 1. Align the gateway with the operator's GATEWAY_PORT default (10260).
# 2. Keep the gateway on plain HTTP for v1; PEM->PFX conversion will be a
#    follow-up once the operator learns to project PEM certificates as PFX.
ENV PORT=10260 \
    PROTOCOL=http

# CNPG's instance-manager invokes /usr/lib/postgresql/<MAJOR>/bin/postgres
# (debian-style versioned layout). The base image installs PostgreSQL with
# bindir=/usr/bin and pkglibdir=/usr/lib/postgresql (unversioned), so the
# versioned bin/ directory does not exist. Create it and populate it with
# symlinks to /usr/bin/<tool> for the binaries CNPG actually invokes.
USER root
RUN set -eux; \
    PG_MAJOR="$(/usr/bin/postgres --version | awk '{print $3}' | cut -d. -f1)"; \
    target="/usr/lib/postgresql/${PG_MAJOR}/bin"; \
    mkdir -p "${target}"; \
    for b in \
        postgres pg_ctl initdb \
        pg_basebackup pg_isready psql \
        pg_dump pg_dumpall pg_restore \
        pg_archivecleanup pg_controldata pg_resetwal pg_rewind pg_waldump \
        pg_config pg_verifybackup pg_checksums pg_receivewal pg_recvlogical; \
    do \
        if [ -e "/usr/bin/${b}" ] && [ ! -e "${target}/${b}" ]; then \
            ln -s "/usr/bin/${b}" "${target}/${b}"; \
        fi; \
    done; \
    "${target}/postgres" --version

# Adapter entrypoint that translates the documentdb-operator sidecar args
# (--start-pg, --pg-port, --create-user, --cert-path, --key-file) into a
# rust_gateway SetupConfiguration JSON and execs the gateway. Only used by
# the gateway sidecar container — the postgres container's command is set
# explicitly by CloudNative-PG and bypasses ENTRYPOINT.
COPY documentdb-gateway-entry.sh /usr/local/bin/documentdb-gateway-entry.sh
RUN chmod 0755 /usr/local/bin/documentdb-gateway-entry.sh

USER cosmosdev
ENTRYPOINT ["/usr/local/bin/documentdb-gateway-entry.sh"]
