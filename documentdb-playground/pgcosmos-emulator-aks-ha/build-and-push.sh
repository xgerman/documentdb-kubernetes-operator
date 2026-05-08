#!/usr/bin/env bash
# build-and-push.sh — build the wrapper image locally and push to the private
# ACR provisioned by acr-setup.sh. Re-uses the existing pgcosmos-emulator
# Dockerfile (no source changes — only the registry destination differs).
#
# Required env (no defaults):
#   ACR_LOGIN_SERVER   e.g. mypgcosmosacr.azurecr.io   (printed by acr-setup.sh)
#   REPO               pgcosmos-emulator
#
# Optional env:
#   POSTGRES_TAG    16.12   (must match what CNPG's webhook accepts as a Postgres version)
#   GATEWAY_TAG     dev
#   PLATFORM        linux/amd64   (AKS nodepools default to amd64; override for arm64 nodes)

set -euo pipefail

ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER is required (printed by acr-setup.sh)}"
REPO="${REPO:?REPO is required (matches acr-setup.sh REPO)}"
POSTGRES_TAG="${POSTGRES_TAG:-16.12}"
GATEWAY_TAG="${GATEWAY_TAG:-dev}"
PLATFORM="${PLATFORM:-linux/amd64}"

# Build context is the sibling pgcosmos-emulator/ directory — single source
# of truth for the Dockerfile.
HERE="$(cd "$(dirname "$0")" && pwd)"
CONTEXT="$(cd "$HERE/../pgcosmos-emulator" && pwd)"

REMOTE_PG="$ACR_LOGIN_SERVER/$REPO:$POSTGRES_TAG"
REMOTE_GW="$ACR_LOGIN_SERVER/$REPO:$GATEWAY_TAG"

echo "[build-and-push] context: $CONTEXT"
echo "[build-and-push] platform: $PLATFORM"
echo "[build-and-push] tags: $REMOTE_PG  $REMOTE_GW"

# --- Single buildx build, two tags (avoids double-pull overhead). ---
# CNPG's admission webhook validates that postgresImage tag parses as a
# Postgres version, so :16.12 must exist. Same image content under :dev
# satisfies the gateway image reference.
docker buildx build \
    --platform "$PLATFORM" \
    --tag "$REMOTE_PG" \
    --tag "$REMOTE_GW" \
    --push \
    "$CONTEXT"

echo "[build-and-push] pushed $REMOTE_PG and $REMOTE_GW"
