#!/usr/bin/env bash
# Apply the pgcosmos-emulator playground to the current kubectl context.
#
# Prerequisites (one-time):
#   * a kind cluster is running (default name: documentdb-test)
#   * cert-manager + the documentdb-operator helm chart are installed
#   * the documentdb-operator + sidecar-injector images for the version under
#     test have been kind-loaded
#
# This script (re)builds the wrapper image, kind-loads it, then applies the
# CR. It does NOT push any image to a registry.
set -euo pipefail

cd "$(dirname "$0")"

./build.sh

kubectl apply -f documentdb.yaml

echo "==> Waiting for DocumentDB/pgcosmos-emulator to become Ready (up to 10 minutes)..."
if ! kubectl -n pgcosmos-emulator wait --for=condition=Ready documentdb/pgcosmos-emulator --timeout=10m; then
  echo "==> DocumentDB did not reach Ready. Recent diagnostics:"
  kubectl -n pgcosmos-emulator describe documentdb pgcosmos-emulator || true
  kubectl -n pgcosmos-emulator describe cluster.postgresql.cnpg.io pgcosmos-emulator || true
  exit 1
fi

echo
echo "==> DocumentDB ready. Services:"
kubectl -n pgcosmos-emulator get svc

cat <<'EOF'

To reach the gateway from the host, port-forward the gateway service:

  kubectl -n pgcosmos-emulator port-forward svc/pgcosmos-emulator-service-rw 10260:10260

The default credentials live in the `documentdb-credentials` secret (username
`documentdb`, password `Admin100`). Override them by editing documentdb.yaml
before applying.
EOF
