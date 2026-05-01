#!/usr/bin/env bash
# Build the kind-local wrapper image for the Cosmos emulator.
#
# This image is NOT pushed to any registry. It is loaded directly into a
# local kind cluster via `kind load docker-image`.
set -euo pipefail

IMAGE_REPO="${IMAGE_REPO:-localhost/pgcosmos-emulator}"
IMAGE_TAG="${IMAGE_TAG:-dev}"
# CNPG's admission webhook validates that spec.imageName carries a
# Postgres-version-looking tag. The wrapper bundles PostgreSQL 16.12, so we
# also publish that tag locally for use as spec.postgresImage.
PG_VERSION_TAG="${PG_VERSION_TAG:-16.12}"
KIND_CLUSTER="${KIND_CLUSTER:-documentdb-test}"

cd "$(dirname "$0")"

PRIMARY="${IMAGE_REPO}:${IMAGE_TAG}"
PG_TAGGED="${IMAGE_REPO}:${PG_VERSION_TAG}"

echo "==> Building $PRIMARY"
docker build -t "$PRIMARY" .
echo "==> Tagging $PRIMARY as $PG_TAGGED (CNPG-compatible tag)"
docker tag "$PRIMARY" "$PG_TAGGED"

if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
    echo "==> Loading $PRIMARY into kind cluster $KIND_CLUSTER"
    kind load docker-image "$PRIMARY" --name "$KIND_CLUSTER"
    echo "==> Loading $PG_TAGGED into kind cluster $KIND_CLUSTER"
    kind load docker-image "$PG_TAGGED" --name "$KIND_CLUSTER"
else
    echo "==> Kind cluster '$KIND_CLUSTER' not found (or kind not installed); skipping kind load."
    echo "    Run 'kind create cluster --name $KIND_CLUSTER' first, then re-run this script."
fi

echo "==> Done. Images $PRIMARY and $PG_TAGGED are local-only — DO NOT 'docker push' them."
