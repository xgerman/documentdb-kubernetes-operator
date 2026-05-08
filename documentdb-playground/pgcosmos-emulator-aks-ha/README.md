# pgcosmos-emulator AKS HA failover demo

A 5-minute live demo that runs the [pgcosmos-emulator](../pgcosmos-emulator/)
on AKS with the DocumentDB Kubernetes operator in a true HA topology, kills
the primary pod mid-traffic, and shows a Python (`azure-cosmos` SDK) client
recover automatically without any DNS or connection-string change.

## Why this exists

The sibling [`pgcosmos-emulator/`](../pgcosmos-emulator/) playground is a
single-replica kind-local sandbox — fine for kicking the tyres, but no
failover story. This walkthrough adds:

* a private ACR holding the wrapper image (anonymous pull stays disabled),
* an AKS cluster pulling the image via a token-scoped pull secret wired
  through the new `spec.imagePullSecrets` field on the DocumentDB CR,
* `instancesPerNode: 2` so CNPG runs primary + sync standby,
* a `LoadBalancer` Service whose endpoint follows the primary
  (`cnpg.io/instanceRole: primary`) automatically — clients see a single
  IP/host and never re-resolve,
* a `failover_demo.py` client that loops upserts + reads and reports the
  longest visible downtime.

## Prerequisites

* Logged-in `az` CLI with permission to create resource groups, ACR, AKS
* `kubectl`, `docker buildx`, `python3`, `envsubst` (from `gettext`)
* DocumentDB operator + CNPG + cert-manager already installed in the AKS
  cluster (the `aks-setup/scripts/create-cluster.sh` helper can do this in
  one shot — pass `INSTALL_OPERATOR=true`).

## One-time setup

```bash
# 1. AKS cluster (skip if you already have one)
cd ../aks-setup/scripts
INSTALL_OPERATOR=true ./create-cluster.sh
cd -

# 2. Private ACR with two scope-map tokens (push for laptop, pull for AKS).
#    Prints the laptop docker-login command on stdout — copy/run it once.
ACR_NAME=mypgcosmosacr ./acr-setup.sh

# 3. Build the wrapper image and push it to the ACR.
#    ACR_LOGIN_SERVER comes from the comment line printed by acr-setup.sh.
ACR_LOGIN_SERVER=mypgcosmosacr.azurecr.io REPO=pgcosmos-emulator \
    ./build-and-push.sh
```

> **Image tags.** CNPG's admission webhook validates that `postgresImage`
> carries a Postgres-version-shaped tag, so the script publishes the same
> image content under `:16.12` (used as `postgresImage`) and `:dev` (used
> as `gatewayImage`).

## Run the demo

```bash
ACR_LOGIN_SERVER=mypgcosmosacr.azurecr.io ./run_demo.sh
```

Watch the terminal:

1. The DocumentDB CR is applied with the ACR login server substituted in.
2. CNPG bootstraps a 2-instance cluster (~3-5 min on a fresh ACR + AKS).
3. The Azure LoadBalancer surfaces a public IP.
4. `failover_demo.py` starts inserting heartbeats every 0.5 s.
5. Around `t+15s`, `run_demo.sh` deletes the pod with `cnpg.io/instanceRole: primary`.
6. CNPG promotes the standby; the operator-managed Service automatically
   retargets to the new primary's `cnpg.io/instanceRole=primary` label, so
   the LoadBalancer external IP keeps working.
7. The Python client logs a few `503` / connection errors, reconnects, and
   resumes inserting. Final summary line shows the visible downtime
   (typically 5-15 s end-to-end).

## How it ties to the operator changes

* `spec.imagePullSecrets` on the DocumentDB CR is forwarded verbatim to
  `cnpgv1.ClusterSpec.ImagePullSecrets`. CNPG schedules the gateway sidecar
  into the same pod as the postgres container, so a single secret reference
  covers every container — no separate plumbing for sidecars.
* `spec.exposeViaService.serviceType: LoadBalancer` makes the operator
  create a Service whose selector is `cnpg.io/instanceRole: primary`.
  When CNPG promotes the standby, the same Service immediately picks up
  the new primary's pod IP. No DNS update, no client reconfig.
* `spec.tls.gateway.mode: SelfSigned` makes the operator request a
  cert-manager-issued cert. The Python client passes
  `connection_verify=False` because we trust the LB IP we own.

## Cleanup

```bash
kubectl delete -f documentdb-aks.yaml --ignore-not-found
# Tear down ACR (costs pennies but worth it)
az acr delete -n "$ACR_NAME" -g pgcosmos-demo-rg --yes
# Optional: tear down the AKS cluster
cd ../aks-setup/scripts && ./delete-cluster.sh
```

## Files

| File | Purpose |
|---|---|
| `acr-setup.sh` | Creates ACR, scope maps, push/pull tokens, namespaced pull secret |
| `build-and-push.sh` | Builds the pgcosmos-emulator wrapper and pushes both tags |
| `documentdb-aks.yaml` | The HA-shaped DocumentDB CR (`instancesPerNode: 2`, `LoadBalancer`, `imagePullSecrets`) |
| `failover_demo.py` | `azure-cosmos` client loop with reconnect + downtime tracking |
| `requirements.txt` | Pinned demo dependencies |
| `run_demo.sh` | Orchestrator — apply, wait, kill primary, run client |
