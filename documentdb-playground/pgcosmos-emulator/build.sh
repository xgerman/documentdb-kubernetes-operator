#!/usr/bin/env bash
# Build the kind-local wrapper image for the Cosmos emulator.
#
# This image is NOT pushed to any registry. It is loaded directly into a
# local kind cluster via `kind load docker-image`.
set -euo pipefail

IMAGE_TAG="${IMAGE_TAG:-localhost/pgcosmos-emulator:dev}"
KIND_CLUSTER="${KIND_CLUSTER:-documentdb-test}"

cd "$(dirname "$0")"

echo "==> Building $IMAGE_TAG"
docker build -t "$IMAGE_TAG" .

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    echo "==> Loading $IMAGE_TAG into kind cluster $KIND_CLUSTER"
    kind load docker-image "$IMAGE_TAG" --name "$KIND_CLUSTER"
else
    echo "==> Kind cluster '$KIND_CLUSTER' not found (or kind not installed); skipping kind load."
    echo "    Run 'kind create cluster --name $KIND_CLUSTER' first, then re-run this script."
fi

echo "==> Done. Image $IMAGE_TAG is local-only — DO NOT 'docker push' it."
