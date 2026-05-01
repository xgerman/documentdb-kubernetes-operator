#!/usr/bin/env bash
# Remove the pgcosmos-emulator playground from the current kubectl context.
set -euo pipefail

cd "$(dirname "$0")"

kubectl delete -f documentdb.yaml --ignore-not-found
kubectl delete namespace pgcosmos-emulator --ignore-not-found
