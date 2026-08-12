#!/usr/bin/env bash
# Smoke test: port-forward to the ExtendDB service and run
# CreateTable/PutItem/GetItem/DeleteTable through the AWS CLI to confirm the
# DynamoDB API round-trips through ExtendDB into DocumentDB.
#
# Requires the admin access key/secret printed by scripts/deploy.sh (from the
# extenddb-init Job logs). Pass them via EXTENDDB_ACCESS_KEY_ID /
# EXTENDDB_SECRET_ACCESS_KEY, or export them as AWS_ACCESS_KEY_ID /
# AWS_SECRET_ACCESS_KEY yourself before running this script.
set -euo pipefail

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }
command -v aws >/dev/null || { echo "aws CLI is required" >&2; exit 1; }

EXTENDDB_NAMESPACE="${EXTENDDB_NAMESPACE:-extenddb}"
LOCAL_PORT="${LOCAL_PORT:-18443}"
ENDPOINT="https://127.0.0.1:${LOCAL_PORT}"
TABLE_NAME="${TABLE_NAME:-extenddb-playground-smoke-test}"

export AWS_ACCESS_KEY_ID="${EXTENDDB_ACCESS_KEY_ID:-${AWS_ACCESS_KEY_ID:-}}"
export AWS_SECRET_ACCESS_KEY="${EXTENDDB_SECRET_ACCESS_KEY:-${AWS_SECRET_ACCESS_KEY:-}}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Set EXTENDDB_ACCESS_KEY_ID / EXTENDDB_SECRET_ACCESS_KEY (from the" >&2
    echo "extenddb-init Job logs printed by deploy.sh), or AWS_ACCESS_KEY_ID /" >&2
    echo "AWS_SECRET_ACCESS_KEY directly." >&2
    exit 1
fi

echo "=== ExtendDB Connection Smoke Test ==="

# ExtendDB uses a self-signed TLS certificate by default; skip verification
# for this local playground test rather than extracting the generated cert.
AWS_CLI_OPTS=(--endpoint-url "$ENDPOINT" --no-verify-ssl)

echo ""
echo "--- Port-forwarding svc/extenddb (namespace: $EXTENDDB_NAMESPACE) ---"
kubectl port-forward svc/extenddb "${LOCAL_PORT}:18443" -n "$EXTENDDB_NAMESPACE" >/tmp/extenddb-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill "$PF_PID" 2>/dev/null || true' EXIT
sleep 3

echo ""
echo "--- CreateTable ---"
aws dynamodb create-table "${AWS_CLI_OPTS[@]}" \
    --table-name "$TABLE_NAME" \
    --attribute-definitions AttributeName=id,AttributeType=S \
    --key-schema AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST >/dev/null
aws dynamodb wait table-exists "${AWS_CLI_OPTS[@]}" --table-name "$TABLE_NAME"
echo "Table '$TABLE_NAME' created."

echo ""
echo "--- PutItem ---"
aws dynamodb put-item "${AWS_CLI_OPTS[@]}" \
    --table-name "$TABLE_NAME" \
    --item '{"id": {"S": "smoke-test-1"}, "message": {"S": "hello from ExtendDB via DocumentDB"}}'
echo "Item written."

echo ""
echo "--- GetItem ---"
aws dynamodb get-item "${AWS_CLI_OPTS[@]}" \
    --table-name "$TABLE_NAME" \
    --key '{"id": {"S": "smoke-test-1"}}'

echo ""
echo "--- DeleteTable (cleanup) ---"
aws dynamodb delete-table "${AWS_CLI_OPTS[@]}" --table-name "$TABLE_NAME" >/dev/null
echo "Table '$TABLE_NAME' deleted."

echo ""
echo "✓ ExtendDB is serving the DynamoDB API on top of DocumentDB."
