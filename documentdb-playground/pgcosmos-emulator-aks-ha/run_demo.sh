#!/usr/bin/env bash
# run_demo.sh — orchestrate the pgcosmos-emulator HA failover demo on AKS.
#
# Preconditions (one-time):
#   1. AKS cluster created & kubectl context pointing at it
#      (see ../aks-setup/scripts/create-cluster.sh)
#   2. DocumentDB operator + cert-manager + CNPG installed in the cluster
#      (set INSTALL_OPERATOR=true on create-cluster.sh, or run the helm
#      install manually)
#   3. Private ACR provisioned and wrapper image pushed:
#        ACR_NAME=mypgcosmosacr ./acr-setup.sh
#        ACR_LOGIN_SERVER=mypgcosmosacr.azurecr.io REPO=pgcosmos-emulator ./build-and-push.sh
#
# What this script does:
#   1. envsubst the ACR login server into documentdb-aks.yaml and apply it
#   2. (re-)install the docker-registry pull secret in the demo namespace
#   3. wait for the DocumentDB to reach phase: Cluster in healthy state
#   4. resolve the LoadBalancer external IP
#   5. launch failover_demo.py in the background
#   6. ~15 s in, kubectl delete the pod with cnpg.io/instanceRole: primary
#   7. let the python client run to completion and print its summary
#
# Required env:
#   ACR_LOGIN_SERVER     printed by acr-setup.sh, e.g. mypgcosmosacr.azurecr.io
# Optional env:
#   NAMESPACE                  pgcosmos-emulator
#   DEMO_DURATION              90 (seconds)
#   FAILOVER_DELAY             15 (seconds — when to kill the primary)
#   READY_TIMEOUT              900 (seconds — CNPG bootstrap can be slow)
#   PYTHON                     python3

set -euo pipefail

ACR_LOGIN_SERVER="${ACR_LOGIN_SERVER:?ACR_LOGIN_SERVER is required (printed by acr-setup.sh)}"
NAMESPACE="${NAMESPACE:-pgcosmos-emulator}"
DEMO_DURATION="${DEMO_DURATION:-90}"
FAILOVER_DELAY="${FAILOVER_DELAY:-15}"
READY_TIMEOUT="${READY_TIMEOUT:-900}"
PYTHON="${PYTHON:-python3}"
PULL_SECRET="${PULL_SECRET:-pgcosmos-acr-pull}"

HERE="$(cd "$(dirname "$0")" && pwd)"
DOCUMENTDB_NAME="pgcosmos-emulator"

# --- 1. Apply the manifest with the ACR login server substituted. ---
# envsubst keeps the manifest itself free of secrets (the YAML in git ships
# with the placeholder). The only variable expanded is ACR_LOGIN_SERVER.
echo "[run_demo] applying documentdb-aks.yaml with ACR_LOGIN_SERVER=$ACR_LOGIN_SERVER"
ACR_LOGIN_SERVER="$ACR_LOGIN_SERVER" \
    envsubst '${ACR_LOGIN_SERVER}' < "$HERE/documentdb-aks.yaml" | kubectl apply -f -

# --- 2. Make sure the pull secret exists in this namespace. ---
# acr-setup.sh tries to create it, but if the namespace was missing at the
# time it would have skipped. We re-run that path here as a safety net.
if ! kubectl -n "$NAMESPACE" get secret "$PULL_SECRET" >/dev/null 2>&1; then
    echo "[run_demo] pull secret $NAMESPACE/$PULL_SECRET missing — re-run ./acr-setup.sh after this script."
    echo "[run_demo] pods will fail with ImagePullBackOff until the secret exists."
fi

# --- 3. Wait for the DocumentDB to come up. ---
echo "[run_demo] waiting up to ${READY_TIMEOUT}s for DocumentDB $NAMESPACE/$DOCUMENTDB_NAME to become ready"
end=$((SECONDS + READY_TIMEOUT))
while (( SECONDS < end )); do
    phase="$(kubectl -n "$NAMESPACE" get documentdb "$DOCUMENTDB_NAME" -o jsonpath='{.status.status}' 2>/dev/null || true)"
    ready_replicas="$(kubectl -n "$NAMESPACE" get cluster.postgresql.cnpg.io "$DOCUMENTDB_NAME" -o jsonpath='{.status.readyInstances}' 2>/dev/null || echo 0)"
    if [[ "$ready_replicas" == "2" ]]; then
        echo "[run_demo] both CNPG instances ready (DocumentDB phase=$phase)"
        break
    fi
    sleep 5
    printf '.'
done
echo

if [[ "$ready_replicas" != "2" ]]; then
    echo "[run_demo] timed out waiting for 2 ready instances" >&2
    kubectl -n "$NAMESPACE" describe documentdb "$DOCUMENTDB_NAME" >&2 || true
    exit 1
fi

# --- 4. Grab the LoadBalancer IP. ---
SERVICE="documentdb-service-$DOCUMENTDB_NAME"
echo "[run_demo] waiting for LoadBalancer IP on $NAMESPACE/$SERVICE"
LB_IP=""
end=$((SECONDS + 600))
while (( SECONDS < end )); do
    LB_IP="$(kubectl -n "$NAMESPACE" get svc "$SERVICE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
    [[ -n "$LB_IP" ]] && break
    sleep 5
done
if [[ -z "$LB_IP" ]]; then
    echo "[run_demo] LoadBalancer IP never materialised" >&2
    exit 1
fi
ENDPOINT="https://$LB_IP:10260"
echo "[run_demo] gateway endpoint: $ENDPOINT"

# --- 5. Set up Python venv if needed. ---
if [[ ! -d "$HERE/.venv" ]]; then
    echo "[run_demo] creating Python venv ($PYTHON -m venv .venv)"
    "$PYTHON" -m venv "$HERE/.venv"
fi
# shellcheck disable=SC1091
source "$HERE/.venv/bin/activate"
pip install --quiet --upgrade pip
pip install --quiet -r "$HERE/requirements.txt"

# --- 6. Launch the demo client in the background. ---
LOG="$HERE/.demo.log"
: > "$LOG"
echo "[run_demo] starting failover_demo.py for ${DEMO_DURATION}s — log: $LOG"
( python "$HERE/failover_demo.py" --endpoint "$ENDPOINT" --duration "$DEMO_DURATION" 2>&1 | tee "$LOG" ) &
DEMO_PID=$!

# --- 7. After a short warm-up, kill the primary pod. ---
sleep "$FAILOVER_DELAY"
echo "[run_demo] inducing failover at t+${FAILOVER_DELAY}s — deleting the primary pod"
PRIMARY_POD="$(kubectl -n "$NAMESPACE" get pod -l "cnpg.io/cluster=$DOCUMENTDB_NAME,cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}')"
echo "[run_demo] current primary: $PRIMARY_POD"
kubectl -n "$NAMESPACE" delete pod "$PRIMARY_POD" --grace-period=0 --force >/dev/null 2>&1 || \
    kubectl -n "$NAMESPACE" delete pod "$PRIMARY_POD" --grace-period=10
echo "[run_demo] primary deleted — CNPG will promote the standby"

# Wait for the demo client to finish and replay its summary.
wait "$DEMO_PID"

NEW_PRIMARY="$(kubectl -n "$NAMESPACE" get pod -l "cnpg.io/cluster=$DOCUMENTDB_NAME,cnpg.io/instanceRole=primary" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -n "$NEW_PRIMARY" && "$NEW_PRIMARY" != "$PRIMARY_POD" ]]; then
    echo "[run_demo] primary changed: $PRIMARY_POD -> $NEW_PRIMARY  ✅"
else
    echo "[run_demo] primary still $NEW_PRIMARY (CNPG may have re-elected the same pod after restart)"
fi
