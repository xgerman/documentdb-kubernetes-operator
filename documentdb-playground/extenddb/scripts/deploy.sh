#!/usr/bin/env bash
# Deploy ExtendDB (DynamoDB-compatible API, MongoDB storage backend) wired up
# to an existing DocumentDB instance in the cluster.
#
# Prerequisites: kubectl, envsubst (gettext), a running cluster with the
# DocumentDB operator installed and a DocumentDB resource already deployed
# (see ../documentdb.yaml), and the extenddb-mongo:playground image built
# and loaded/pushed (see build-image.sh).
set -euo pipefail

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
command -v envsubst >/dev/null || { echo "envsubst (gettext) is required" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST_DIR="$SCRIPT_DIR/../manifests"

export EXTENDDB_NAMESPACE="${EXTENDDB_NAMESPACE:-extenddb}"
export EXTENDDB_IMAGE="${EXTENDDB_IMAGE:-extenddb-mongo:playground}"
DOCUMENTDB_NAMESPACE="${DOCUMENTDB_NAMESPACE:-documentdb-test}"
DOCUMENTDB_CLUSTER="${DOCUMENTDB_CLUSTER:-documentdb-cluster}"

echo "=== ExtendDB + DocumentDB Deployment ==="

# 1. Namespace + PVC
echo ""
echo "--- Step 1: Namespace and persistent state volume ---"
envsubst < "$MANIFEST_DIR/namespace.yaml" | kubectl apply -f -

# 2. Resolve the DocumentDB connection string
echo ""
echo "--- Step 2: DocumentDB connection ---"
RAW_CONN=$(kubectl get documentdb "$DOCUMENTDB_CLUSTER" -n "$DOCUMENTDB_NAMESPACE" \
    -o jsonpath='{.status.connectionString}' 2>/dev/null) || true

if [ -z "$RAW_CONN" ]; then
    echo "Could not read status.connectionString from DocumentDB resource" >&2
    echo "'$DOCUMENTDB_CLUSTER' in namespace '$DOCUMENTDB_NAMESPACE'." >&2
    echo "Set MONGO_URI yourself and re-run, or check DOCUMENTDB_NAMESPACE/DOCUMENTDB_CLUSTER." >&2
    exit 1
fi

# The operator embeds $(kubectl get secret ...) substitutions in the printed
# connection string; resolve them. This trusts the operator-supplied field --
# do not point this script at an untrusted DocumentDB resource.
MONGO_URI=$(eval "echo \"$RAW_CONN\"")

# Swap the ClusterIP for the in-cluster DNS name so the URI keeps working
# after the DocumentDB service's IP changes.
SVC_IP=$(kubectl get svc "documentdb-service-${DOCUMENTDB_CLUSTER}" -n "$DOCUMENTDB_NAMESPACE" \
    -o jsonpath='{.spec.clusterIP}' 2>/dev/null) || true
if [ -n "$SVC_IP" ]; then
    SVC_DNS="documentdb-service-${DOCUMENTDB_CLUSTER}.${DOCUMENTDB_NAMESPACE}.svc.cluster.local"
    MONGO_URI=$(echo "$MONGO_URI" | sed "s/$SVC_IP/$SVC_DNS/g")
fi

# ExtendDB's MongoDB backend requires `replicaSet=rs0` in the connection
# string (it uses replica-set-only features: transactions, retryable writes).
# DocumentDB's connection string also sets `directConnection=true`, which
# conflicts with `replicaSet=rs0` for drivers that perform full replica-set
# discovery (see ../README.md's Troubleshooting section) -- strip
# directConnection so the driver negotiates topology against the
# gateway-advertised replica set named rs0 instead of skipping discovery.
MONGO_URI=$(echo "$MONGO_URI" | sed -E 's/[?&]directConnection=[^&]*//g')
# Normalize a stray leading '&' left behind if directConnection was first in
# the query string.
MONGO_URI=$(echo "$MONGO_URI" | sed -E 's/\?&/?/')

echo "Connection string resolved (directConnection stripped, replicaSet=rs0 kept)."

kubectl create secret generic extenddb-mongo-uri \
    -n "$EXTENDDB_NAMESPACE" \
    --from-literal=connection_string="$MONGO_URI" \
    --dry-run=client -o yaml | kubectl apply -f -

# 3. Run the init Job and wait for it to complete before starting the server,
#    since both mount the same ReadWriteOnce PVC.
echo ""
echo "--- Step 3: Initialize ExtendDB (extenddb init --backend mongodb) ---"
kubectl delete job extenddb-init -n "$EXTENDDB_NAMESPACE" --ignore-not-found
envsubst < "$MANIFEST_DIR/init-job.yaml" | kubectl apply -f -
kubectl wait --for=condition=Complete job/extenddb-init -n "$EXTENDDB_NAMESPACE" --timeout=180s

echo ""
echo "Admin credentials (printed once by 'extenddb init' -- save them now):"
echo "----------------------------------------------------------------------"
kubectl logs job/extenddb-init -n "$EXTENDDB_NAMESPACE" | grep -iE "admin|access|secret|account" || true
echo "----------------------------------------------------------------------"

# 4. Deploy the long-running server
echo ""
echo "--- Step 4: Deploy ExtendDB server ---"
envsubst < "$MANIFEST_DIR/serve.yaml" | kubectl apply -f -
echo "Waiting for ExtendDB pod to be ready..."
kubectl wait --for=condition=Ready pod -l app=extenddb -n "$EXTENDDB_NAMESPACE" --timeout=300s

echo ""
echo "✓ ExtendDB deployed in namespace '$EXTENDDB_NAMESPACE', backed by DocumentDB"
echo "  ('$DOCUMENTDB_CLUSTER' in '$DOCUMENTDB_NAMESPACE')."
echo ""
echo "Next: port-forward and test with:"
echo "  kubectl port-forward svc/extenddb 18443:18443 -n $EXTENDDB_NAMESPACE"
echo "  ./scripts/test-connection.sh"
