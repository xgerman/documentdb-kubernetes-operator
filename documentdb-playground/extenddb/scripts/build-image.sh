#!/usr/bin/env bash
# Build the ExtendDB (MongoDB backend) container image and, if a local kind
# cluster is active, load it directly so no registry push is required.
set -euo pipefail

command -v docker >/dev/null || { echo "docker is required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLAYGROUND_DIR="$(dirname "$SCRIPT_DIR")"
IMAGE="${EXTENDDB_IMAGE:-extenddb-mongo:playground}"
KIND_CLUSTER="${KIND_CLUSTER:-}"

echo "=== Building ${IMAGE} ==="
docker build -t "${IMAGE}" "${PLAYGROUND_DIR}"

if command -v kind >/dev/null 2>&1; then
    # Auto-detect the current kind cluster from the active kube context unless
    # KIND_CLUSTER was set explicitly.
    if [ -z "${KIND_CLUSTER}" ]; then
        CTX="$(kubectl config current-context 2>/dev/null || true)"
        case "${CTX}" in
            kind-*) KIND_CLUSTER="${CTX#kind-}" ;;
        esac
    fi
    if [ -n "${KIND_CLUSTER}" ] && kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER}$"; then
        echo "Loading ${IMAGE} into kind cluster '${KIND_CLUSTER}'..."
        kind load docker-image "${IMAGE}" --name "${KIND_CLUSTER}"
    else
        echo "No active kind cluster detected; skipping 'kind load'."
        echo "If your cluster is not kind, push ${IMAGE} to a registry it can pull from"
        echo "and set EXTENDDB_IMAGE to that reference before running deploy.sh."
    fi
else
    echo "kind not found; skipping image load. Push ${IMAGE} to a reachable registry"
    echo "and set EXTENDDB_IMAGE accordingly before running deploy.sh."
fi

echo ""
echo "✓ Image ${IMAGE} ready"
