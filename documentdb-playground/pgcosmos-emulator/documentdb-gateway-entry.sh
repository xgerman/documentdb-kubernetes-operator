#!/bin/bash
# Wrapper entrypoint that adapts the rust_gateway binary in the public Cosmos
# emulator image to the CLI surface that the documentdb-kubernetes-operator's
# sidecar injector emits.
#
# The injector emits args like:
#   --create-user (true|false) --start-pg false --pg-port 5432 \
#   [--cert-path /tls/tls.crt --key-file /tls/tls.key]
#
# The rust_gateway binary in the upstream image takes a single positional arg
# (a SetupConfiguration JSON file) and reads PG credentials/host from there
# plus libpq env vars. This script translates the operator's flags into a
# generated JSON config, then execs rust_gateway.

set -euo pipefail

# Defaults; can be overridden by env or args below.
PG_HOST="${PG_HOST:-127.0.0.1}"
PG_PORT="${PG_PORT:-5432}"
PG_DATABASE="${PG_DATABASE:-postgres}"
GATEWAY_PORT="${PORT:-10260}"
GATEWAY_PROTOCOL="${PROTOCOL:-http}"
CERT_PATH="${CERT_PATH:-}"
KEY_FILE="${KEY_FILE:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --start-pg)        shift; shift ;;       # ignored — CNPG owns PG
    --pg-port)         shift; PG_PORT="$1"; shift ;;
    --pg-host)         shift; PG_HOST="$1"; shift ;;
    --pg-database)     shift; PG_DATABASE="$1"; shift ;;
    --create-user)     shift; shift ;;       # ignored — postInitSQL owns role creation
    --cert-path)       shift; CERT_PATH="$1"; shift ;;
    --key-file)        shift; KEY_FILE="$1"; shift ;;
    --port)            shift; GATEWAY_PORT="$1"; shift ;;
    --protocol)        shift; GATEWAY_PROTOCOL="$1"; shift ;;
    --help|-h)
      echo "documentdb-gateway-entry.sh: rust_gateway adapter for the documentdb operator"
      echo "  Recognised args: --start-pg <bool> --pg-port N --pg-host H --pg-database D"
      echo "                   --create-user <bool> --cert-path P --key-file K --port N --protocol http|https"
      exit 0
      ;;
    *)
      echo "documentdb-gateway-entry.sh: ignoring unknown arg: $1" >&2
      shift
      ;;
  esac
done

# Username/password for the PG role used by the gateway's connection pools.
# The operator's sidecar injects these from the documentdb-credentials secret.
PG_USER="${USERNAME:-${PG_USER:-documentdb}}"
PG_PASS="${PASSWORD:-${PG_PASS:-}}"

if [[ -z "$PG_PASS" ]]; then
  echo "documentdb-gateway-entry.sh: WARNING — PASSWORD env unset; PG connection will likely fail" >&2
fi

# Export libpq-style env so tokio_postgres / deadpool_postgres pick the
# password up automatically (the Setup JSON has no Password field).
export PGPASSWORD="$PG_PASS"
export PGUSER="$PG_USER"
export PGHOST="$PG_HOST"
export PGPORT="$PG_PORT"
export PGDATABASE="$PG_DATABASE"

ENFORCE_SSL_TCP="false"
if [[ -n "$CERT_PATH" && -n "$KEY_FILE" ]]; then
  ENFORCE_SSL_TCP="true"
fi

CONFIG_PATH="${SETUP_CONFIG_PATH:-/tmp/documentdb-gateway-setup.json}"
mkdir -p "$(dirname "$CONFIG_PATH")"
cat > "$CONFIG_PATH" <<EOF
{
  "NodeHostName": "${PG_HOST}",
  "BlockedRolePrefixes": [],
  "PostgresHostName": "${PG_HOST}",
  "PostgresPort": ${PG_PORT},
  "PostgresDatabase": "${PG_DATABASE}",
  "PostgresSystemUser": "${PG_USER}",
  "GatewayProtocol": "${GATEWAY_PROTOCOL}",
  "GatewayListenAddress": "0.0.0.0",
  "GatewayEndpoint": "127.0.0.1",
  "GatewayListenPort": ${GATEWAY_PORT},
  "TransactionTimeoutSecs": 5,
  "CursorTimeoutSecs": 10,
  "PostgresCommandTimeoutSecs": 10,
  "EnforceSslTcp": ${ENFORCE_SSL_TCP},
  "CertificateOptions": {
    "CertType": "pem",
    "FilePath": "${CERT_PATH}",
    "KeyFilePath": "${KEY_FILE}",
    "CertPassword": ""
  },
  "ApplicationName": "documentdb-operator-gateway",
  "EnableExplorer": false,
  "ThinClientEnabled": false,
  "ThinClientProtocol": "${GATEWAY_PROTOCOL}",
  "ThinClientListenPort": 10250
}
EOF

echo "documentdb-gateway-entry.sh: starting rust_gateway"
echo "  PG: ${PG_USER}@${PG_HOST}:${PG_PORT}/${PG_DATABASE}"
echo "  Gateway: ${GATEWAY_PROTOCOL}://0.0.0.0:${GATEWAY_PORT}  (TLS: ${ENFORCE_SSL_TCP})"
echo "  Config: ${CONFIG_PATH}"

exec /usr/local/bin/rust_gateway "$CONFIG_PATH"
