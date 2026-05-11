#!/usr/bin/env bash
# acr-setup.sh — provision a private ACR with two scope-map tokens for the
# pgcosmos-emulator demo:
#
#   * laptop-push token  — content/write on the wrapper image repository,
#                          handed back to the operator on stdout
#   * aks-pull token     — content/read on the same repository, materialised
#                          as a docker-registry secret in the demo namespace
#                          so the DocumentDB CR's spec.advanced.imagePullSecrets can
#                          reference it
#
# Anonymous pull stays disabled, so the wrapper image is invisible to the
# public even after we push to it. Tokens are independently rotatable.
#
# Idempotent — re-running rotates the laptop password (Azure scope-map
# tokens cap at two passwords, so we always rotate password1) and refreshes
# the in-cluster pull secret.
#
# Required env / flags (defaults shown):
#   ACR_NAME         (required, no default — must be globally unique 5-50 chars, lowercase alphanumeric)
#   RESOURCE_GROUP   pgcosmos-demo-rg
#   LOCATION         westus2
#   AKS_CLUSTER      pgcosmos-demo-aks
#   NAMESPACE        pgcosmos-emulator
#   PULL_SECRET      pgcosmos-acr-pull
#   REPO             pgcosmos-emulator   (the path inside the registry)

set -euo pipefail

ACR_NAME="${ACR_NAME:?ACR_NAME is required (5-50 chars, lowercase alphanumeric, globally unique)}"
RESOURCE_GROUP="${RESOURCE_GROUP:-pgcosmos-demo-rg}"
LOCATION="${LOCATION:-westus2}"
AKS_CLUSTER="${AKS_CLUSTER:-pgcosmos-demo-aks}"
NAMESPACE="${NAMESPACE:-pgcosmos-emulator}"
PULL_SECRET="${PULL_SECRET:-pgcosmos-acr-pull}"
REPO="${REPO:-pgcosmos-emulator}"

# --- 1. Resource group + ACR (Standard SKU is the cheapest with scope-map support) ---
if ! az group show -n "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "[acr-setup] creating resource group $RESOURCE_GROUP in $LOCATION"
    az group create -n "$RESOURCE_GROUP" -l "$LOCATION" >/dev/null
fi

if ! az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" >/dev/null 2>&1; then
    echo "[acr-setup] creating ACR $ACR_NAME (Standard, admin disabled, anonymous-pull disabled)"
    az acr create \
        -n "$ACR_NAME" \
        -g "$RESOURCE_GROUP" \
        --sku Standard \
        --admin-enabled false \
        --public-network-enabled true \
        --anonymous-pull-enabled false >/dev/null
else
    # Lock down an existing registry that may have been created with admin on.
    az acr update -n "$ACR_NAME" -g "$RESOURCE_GROUP" \
        --admin-enabled false --anonymous-pull-enabled false >/dev/null
fi

ACR_LOGIN_SERVER="$(az acr show -n "$ACR_NAME" -g "$RESOURCE_GROUP" --query loginServer -o tsv)"

# --- 2. Scope maps (one per audience) ---
PUSH_SCOPE_MAP="${REPO}-push"
PULL_SCOPE_MAP="${REPO}-pull"

ensure_scope_map() {
    local name="$1" perms="$2"
    if ! az acr scope-map show -r "$ACR_NAME" -n "$name" >/dev/null 2>&1; then
        echo "[acr-setup] creating scope-map $name ($perms on repositories/$REPO)"
        # shellcheck disable=SC2086
        az acr scope-map create \
            -r "$ACR_NAME" -n "$name" \
            $(for p in $perms; do printf -- "--repository %s %s " "$REPO" "$p"; done) >/dev/null
    fi
}

ensure_scope_map "$PUSH_SCOPE_MAP" "content/read content/write metadata/read"
ensure_scope_map "$PULL_SCOPE_MAP" "content/read metadata/read"

# --- 3. Tokens + passwords ---
PUSH_TOKEN="${REPO}-push-token"
PULL_TOKEN="${REPO}-pull-token"

ensure_token() {
    local name="$1" scope_map="$2"
    if ! az acr token show -r "$ACR_NAME" -n "$name" >/dev/null 2>&1; then
        az acr token create -r "$ACR_NAME" -n "$name" --scope-map "$scope_map" \
            --status enabled --no-passwords >/dev/null
    fi
}

ensure_token "$PUSH_TOKEN" "$PUSH_SCOPE_MAP"
ensure_token "$PULL_TOKEN" "$PULL_SCOPE_MAP"

# Always rotate password1 — keeps re-runs deterministic and respects the
# 2-passwords-per-token Azure cap (password2 stays valid as a backup).
echo "[acr-setup] rotating password1 on $PUSH_TOKEN (laptop push)" >&2
PUSH_PASSWORD="$(az acr token credential generate \
    -r "$ACR_NAME" -n "$PUSH_TOKEN" \
    --password1 --years 1 \
    --query 'passwords[?name==`password1`].value | [0]' -o tsv)"

echo "[acr-setup] rotating password1 on $PULL_TOKEN (AKS pull)" >&2
PULL_PASSWORD="$(az acr token credential generate \
    -r "$ACR_NAME" -n "$PULL_TOKEN" \
    --password1 --years 1 \
    --query 'passwords[?name==`password1`].value | [0]' -o tsv)"

# --- 4. AKS pull secret in the demo namespace ---
if kubectl get ns "$NAMESPACE" >/dev/null 2>&1; then
    echo "[acr-setup] (re)creating docker-registry secret $NAMESPACE/$PULL_SECRET" >&2
    kubectl -n "$NAMESPACE" delete secret "$PULL_SECRET" --ignore-not-found
    kubectl -n "$NAMESPACE" create secret docker-registry "$PULL_SECRET" \
        --docker-server="$ACR_LOGIN_SERVER" \
        --docker-username="$PULL_TOKEN" \
        --docker-password="$PULL_PASSWORD" >/dev/null
else
    echo "[acr-setup] namespace $NAMESPACE missing — skipping pull-secret install (run again after run_demo.sh applies the manifest)" >&2
fi

# --- 5. Hand back the laptop login command on stdout (single source of truth) ---
cat <<EOF
# Loginserver: $ACR_LOGIN_SERVER
# Push from your laptop:
echo '$PUSH_PASSWORD' | docker login $ACR_LOGIN_SERVER -u '$PUSH_TOKEN' --password-stdin

# Tag + push (build-and-push.sh wraps this):
ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER REPO=$REPO ./build-and-push.sh
EOF
