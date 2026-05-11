# pgcosmos-emulator playground (kind-local)

A self-contained playground that wires the public **Azure Cosmos DB
vNext-preview emulator** image into the `documentdb-kubernetes-operator`'s
existing `DocumentDB` CR — no operator source changes required, no proprietary
code copied, no images pushed off the workstation.

When deployed, the operator builds a `Cluster` whose Postgres pod runs the
emulator image (which already ships PostgreSQL 16.12 + Citus + pgcosmos +
helio_gin + rum + postgis + pg_cron) and whose gateway sidecar runs the
emulator's `rust_gateway` against that same Postgres instance over the loopback
interface. The result is a Cosmos DB-compatible HTTP endpoint backed by the
emulator's own Postgres extensions, lifecycle-managed by CloudNative-PG.

> **Distribution:** **kind-local only.** `build.sh` runs `kind load docker-image`
> after `docker build` and **never** pushes. Do not retag and push these images
> to any external registry.

> **Looking for HA / cloud failover?** See
> [`../pgcosmos-emulator-aks-ha/`](../pgcosmos-emulator-aks-ha/) — same image,
> running on AKS with `instancesPerNode: 2`, a private ACR (token-scoped pull
> secret), and a Python `azure-cosmos` client that survives a primary-pod
> deletion.

---

## What this gives you

| Layer | Image | Source |
|-------|-------|--------|
| Postgres | `localhost/pgcosmos-emulator:16.12` | this directory's `Dockerfile` (wrapper) |
| Gateway sidecar | `localhost/pgcosmos-emulator:dev` | same image, different entrypoint |
| Operator | `mcr.microsoft.com/cosmosdb/documentdb-kubernetes-operator:0.1.0` (Helm) | upstream |
| CNPG | bundled by operator Helm chart (`cloudnative-pg-0.27.0`) | upstream |
| cert-manager | `quay.io/jetstack/cert-manager-*:v1.19.2` | upstream |

The same wrapper image is loaded with two tags:

- **`:16.12`** is what the `DocumentDB` CR sets as `postgresImage`. CNPG's
  `vcluster.cnpg.io` validating webhook parses the tag and requires it to look
  like a Postgres version (`X.Y` or `X`); the emulator ships PG 16.12, so this
  tag is honest.
- **`:dev`** is what the CR sets as `gatewayImage`. The gateway sidecar reads no
  PG version from the tag, so this is purely cosmetic.

---

## Why a wrapper image is needed

The base [`azure-cosmos-emulator:vnext-preview`](https://mcr.microsoft.com/en-us/artifact/mar/cosmosdb/linux/azure-cosmos-emulator)
image is built to be invoked directly with `docker run`. Two small alignments
are required to make CNPG and the operator's sidecar-injector drive it without
patching either component:

| Contract | Base image default | Wrapper does |
|----------|---------------------|---------------|
| CNPG runs `/usr/lib/postgresql/<MAJOR>/bin/postgres` | only `/usr/bin/postgres` exists | symlinks `/usr/lib/postgresql/16/bin/*` → `/usr/bin/*` |
| Gateway listens on `$GATEWAY_PORT` (operator default `10260`) | `PORT=8081` | `ENV PORT=10260` |
| Gateway speaks HTTPS so Cosmos SDKs / IDE plugins accept the endpoint | `PROTOCOL=http` | `ENV PROTOCOL=https` (operator's sidecar plugin mounts the cert-manager-issued PEM at `/tls`; adapter wires it into `SetupConfiguration.CertificateOptions`) |
| Gateway sidecar args from `lifecycle.go` (`--start-pg false --pg-port 5432 --create-user T --cert-path ... --key-file ...`) | `rust_gateway` takes a single positional JSON config path | `ENTRYPOINT documentdb-gateway-entry.sh` adapter translates args → SetupConfiguration JSON, exports libpq env, exec's `rust_gateway` |

The Dockerfile is **all `FROM`/`ENV`/symlinks/COPY**. No emulator source is
modified or vendored.

The adapter entrypoint is only invoked by the gateway sidecar — CNPG sets an
explicit `command:` on the Postgres container, which bypasses the image
ENTRYPOINT entirely. So the same image cleanly serves both roles.

---

## Files

- `Dockerfile` — wrapper, ~10 lines of substance.
- `documentdb-gateway-entry.sh` — gateway sidecar adapter (operator args ↔
  `rust_gateway` SetupConfiguration JSON).
- `documentdb.yaml` — Namespace + `documentdb-credentials` Secret + `DocumentDB`
  CR (combined-image mode: `spec.advanced.documentDBImage` is empty,
  `spec.advanced.postgresImage` and `spec.advanced.gatewayImage` point at the
  wrapper image; `tls.gateway.mode: SelfSigned`
  delegates cert issuance to cert-manager).
- `build.sh` — `docker build` + `docker tag :dev :16.12` + `kind load
  docker-image` for both tags. Never pushes.
- `deploy.sh` — runs `build.sh`, applies the manifest, waits for the cluster to
  reach `Ready`, prints the port-forward command.
- `cleanup.sh` — deletes the namespace and CR.

---

## Prerequisites

- A `kind` cluster with K8s **1.35+** (operator hard-fails on older clusters at
  `operator/src/internal/utils/constants.go:25`). For example:

  ```bash
  kind create cluster --name documentdb-test --image kindest/node:v1.35.0
  ```

- The operator Helm chart deployed (which also installs CNPG and cert-manager).
  See the parent [development environment guide](../../docs/developer-guides/development-environment.md).

- Docker (or any Buildx-capable engine) on the workstation.

---

## Build & deploy

```bash
# from this directory
./deploy.sh
```

`deploy.sh` is idempotent and small enough to read in one screen — see the
script for env knobs (`KIND_CLUSTER`, `IMAGE_REPO`, `NAMESPACE`).

When it finishes you'll see something like:

```
NAME                STATUS   AGE
pgcosmos-emulator   Ready    42s

NAME                                   TYPE        CLUSTER-IP      PORT(S)
documentdb-service-pgcosmos-emulator   ClusterIP   10.96.x.y       10260/TCP
pgcosmos-emulator-rw                   ClusterIP   10.96.x.y       5432/TCP
```

To reach the gateway from the host:

```bash
kubectl port-forward -n pgcosmos-emulator \
  svc/documentdb-service-pgcosmos-emulator 10260:10260
```

Smoke-test (`-k` because the cert-manager-issued cert SANs cover the in-cluster
service DNS, not `localhost`):

```bash
curl -sk https://localhost:10260/                # → HTTP 200 plus a hello string
curl -sk -X POST https://localhost:10260/dbs \
  -H 'content-type: application/json' \
  -d '{}'                                        # → 400 "id is required ..."
```

The 400 with that exact body confirms the gateway is reaching pgcosmos and the
Cosmos request pipeline is intact (the emulator is rejecting on validation, not
on transport or auth).

---

## How the manifest works

The CR uses **combined-image mode** — `spec.advanced.documentDBImage` is left blank, which
flips the operator at `operator/src/internal/cnpg/cnpg_cluster.go:26` into a
path that:

1. Skips its built-in `postgresql.extensions` populator.
2. Uses `spec.advanced.postgres.preloadLibraries` and `spec.advanced.postgres.postInitSQL`
   verbatim instead of merging operator defaults.

The manifest's `postInitSQL` therefore has to spell out the full extension
install order itself:

```sql
CREATE EXTENSION IF NOT EXISTS citus;        -- pgcosmos's install path touches pg_dist_shard
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS rum;
CREATE EXTENSION IF NOT EXISTS helio_gin;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcosmos CASCADE;
-- followed by the operator's standard CREATE/ALTER ROLE documentdb block,
-- because postInitSQL replaces the default and the gateway sidecar still
-- expects that role to exist with the password from documentdb-credentials.
```

`pgcosmos.control` only declares
`requires = 'postgis, rum, helio_gin, pg_cron'`, but its installer also writes
into Citus catalog tables, so `citus` **must** be installed first. The
`vector` extension is not in the wrapper image and is intentionally absent
from the SQL.

The `documentdb-credentials` Secret is created by this manifest because the
operator does not auto-create it. The sidecar-injector reads
`username`/`password` from it (defaults at
`operator/src/internal/utils/constants.go:32`) and injects them as env into the
gateway container; the adapter entrypoint forwards them as `PGUSER`/`PGPASSWORD`
so `rust_gateway`'s `tokio_postgres` client picks them up via libpq env.

---

## Validating against pgcosmos's .NET integration suite

The pgcosmos repo ships an MSTest integration suite that drives the gateway
purely over its public Cosmos HTTP surface. With this playground deployed
(HTTPS via cert-manager-issued self-signed cert) and port-forwarded to
`localhost:10260`, the gap is bounded by what a single-node, single-port
configuration can satisfy:

| Bucket | Expected to fail | Reason |
|--------|------:|--------|
| `ThinClient_*`, `RntbdDirect_*` | 12 | Need the **RNTBD/TCP** thin-client port; this playground only exposes the HTTP gateway port (10260). |
| `DatabaseAccount_*Locations*` (subset) | a few | Assert multi-region locations; this playground is single-node. |

`AddressesEndpoint_Https*` and `ThinClient_AcceptsTlsConnection` were the
HTTP-only blockers in the prior `tlsCertProvider: Disabled` configuration. With
HTTPS now the default, those should pass against this playground (subject to
the test client trusting the self-signed cert — point `SSL_CERT_FILE` at the
secret's `ca.crt`, or set `tlsAllowInvalidCertificates` / equivalent on the
client). A future variant that also exposes the RNTBD/TCP port would close the
remaining gap.

To re-run the suite yourself (assuming you have the suite checked out
elsewhere — pgcosmos source is **not** copied into this repo):

```bash
# 1. Make sure the port-forward is alive on :10260.
# 2. From any directory that does not have a global.json ancestor:
EXTERNAL_GATEWAY=https://localhost:10260/ PROTOCOL=https GATEWAYPORT=10260 \
  dotnet vstest /path/to/Cosmos.Postgres.Tests.Integration.dll \
  --TestCaseFilter:"TestCategory!=NOT_SUPPORTED" \
  --logger:"console;verbosity=normal"
```

The suite hits the gateway hard enough that a stock `kubectl port-forward` may
drop mid-run; wrap it in a `while true; do kubectl port-forward ...; done` loop
or expose the service via a NodePort if you see clusters of `Connection
refused` failures.

---

## Cleanup

```bash
./cleanup.sh                                     # delete CR + namespace
docker rmi localhost/pgcosmos-emulator:16.12 \
           localhost/pgcosmos-emulator:dev      # optional
```

---

## Boundaries

- **No `docker push`.** Anywhere in this directory, ever. The image is
  kind-local.
- **No pgcosmos source** is copied into this repo. The wrapper consumes the
  public `:vnext-preview` image as a sealed binary.
- **No operator source changes** are required. Everything sits on top of the
  CR's existing `combinedImage` path, the sidecar-injector's existing args
  contract, and the Helm chart's existing knobs.
