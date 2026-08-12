# ExtendDB (DynamoDB API) on DocumentDB

This playground runs [ExtendDB](https://extenddb.org) — an open-source,
DynamoDB-wire-protocol-compatible server — configured with its MongoDB
storage backend pointed at a DocumentDB instance in Kubernetes. Any AWS SDK,
CLI, or tool that speaks the DynamoDB API works against ExtendDB unchanged,
while the data actually lives in DocumentDB.

> **Disclaimer:** ExtendDB is an independent open source project; it is not
> Amazon DynamoDB and contains no DynamoDB source code. "DynamoDB" is a
> trademark of Amazon.com, Inc. This playground is not affiliated with or
> endorsed by AWS.

## Architecture

```
┌───────────────────────────────────────────────────────────┐
│                     Kubernetes Cluster                    │
│                                                            │
│   AWS SDK / CLI                                           │
│        │  DynamoDB wire protocol (HTTPS)                  │
│        ▼                                                  │
│  ┌──────────────┐   MongoDB wire protocol   ┌────────────┐│
│  │   ExtendDB   │──────────────────────────▶│ DocumentDB ││
│  │ (DynamoDB    │  connection_string with    │  (Gateway) ││
│  │  API server) │  replicaSet=rs0            └─────┬──────┘│
│  └──────────────┘                                  │       │
│                                                     ▼       │
│                                              ┌────────────┐│
│                                              │ PostgreSQL ││
│                                              │   (CNPG)   ││
│                                              └────────────┘│
└───────────────────────────────────────────────────────────┘
```

ExtendDB's storage layer is trait-based and backend-agnostic; the MongoDB
backend implementation issues standard MongoDB CRUD/transaction operations,
which DocumentDB's gateway serves against its Postgres-backed engine.

## Prerequisites

- A Kubernetes cluster (kind, AKS, EKS, etc.) with the
  [DocumentDB operator](../../README.md) installed
- `kubectl`, `docker`, and `envsubst` (part of `gettext`) installed locally
- AWS CLI v2, for the connectivity smoke test
- No official ExtendDB container image ships with the MongoDB backend
  enabled (only a PostgreSQL-backend image is published upstream), so this
  playground builds one from source — a Rust toolchain is **not** required
  locally; the build happens inside Docker (see [`Dockerfile`](Dockerfile))

## Quick Start

```bash
# 1. Deploy a DocumentDB instance (skip if you already have one)
#    Edit documentdb.yaml first and replace the placeholder password.
kubectl create namespace documentdb-test
kubectl apply -f documentdb.yaml
kubectl wait --for=jsonpath='{.status.status}'="Cluster in healthy state" \
    documentdb/documentdb-cluster -n documentdb-test --timeout=300s

# 2. Build the ExtendDB (MongoDB backend) image and load it into your cluster
./scripts/build-image.sh

# 3. Deploy ExtendDB, wired up to the DocumentDB instance
./scripts/deploy.sh
# Save the admin access key ID/secret printed at the end of this step --
# they are shown once and cannot be retrieved later.

# 4. Test the DynamoDB API end to end
EXTENDDB_ACCESS_KEY_ID=<from step 3> \
EXTENDDB_SECRET_ACCESS_KEY=<from step 3> \
    ./scripts/test-connection.sh

# 5. (Optional) Run the small Python demo, or explore interactively with ddbsh
kubectl port-forward svc/extenddb 18443:18443 -n extenddb &
pip install -r demo/requirements.txt
EXTENDDB_ACCESS_KEY_ID=<from step 3> \
EXTENDDB_SECRET_ACCESS_KEY=<from step 3> \
    ./demo/demo.py

# Cleanup when done
./scripts/cleanup.sh
```

`scripts/deploy.sh` defaults to `DOCUMENTDB_NAMESPACE=documentdb-test`,
`DOCUMENTDB_CLUSTER=documentdb-cluster`, and `EXTENDDB_NAMESPACE=extenddb`.
Override via env vars if your cluster uses different names:

```bash
DOCUMENTDB_NAMESPACE=my-ns DOCUMENTDB_CLUSTER=my-cluster EXTENDDB_NAMESPACE=dynamo \
    ./scripts/deploy.sh
```

## What the Scripts Do

`scripts/build-image.sh`:

1. Builds [`Dockerfile`](Dockerfile), which clones ExtendDB and compiles it
   with `cargo build --release --no-default-features --features mongodb`
   (ExtendDB's `postgres`/`mongodb`/`sqlite` backends are mutually exclusive
   at compile time — a build enabling more than one is rejected).
2. If a kind cluster is active in your current `kubectl` context, loads the
   image directly with `kind load docker-image` so no registry push is
   needed. For non-kind clusters, push the image yourself and set
   `EXTENDDB_IMAGE` before running `deploy.sh`.

`scripts/deploy.sh`:

1. Creates the `extenddb` namespace and a 1Gi PVC for ExtendDB's generated
   config (`extenddb.toml`) and self-signed TLS certificate.
2. Reads the connection string from the `DocumentDB` resource's
   `status.connectionString`, resolves the embedded `kubectl get secret`
   commands, and swaps the ClusterIP for the in-cluster DNS name.
3. **Strips `directConnection=true`** from the connection string (see
   [Troubleshooting](#troubleshooting-replicaset-vs-directconnection) below)
   while keeping `replicaSet=rs0`, which ExtendDB's MongoDB backend requires.
4. Stores the resolved URI in an `extenddb-mongo-uri` Secret.
5. Runs a one-shot `extenddb init --backend mongodb` Job against that URI,
   waits for it to complete, and prints the generated admin credentials from
   the Job logs (shown once by ExtendDB — save them).
6. Deploys the long-running `extenddb serve --foreground` Deployment and a
   ClusterIP Service on port `18443`.

`scripts/test-connection.sh`:

Port-forwards to the ExtendDB Service and runs
CreateTable → PutItem → GetItem → DeleteTable through the AWS CLI to confirm
the round trip through DocumentDB.

`scripts/cleanup.sh`:

Deletes the `extenddb` namespace. Leaves the DocumentDB instance untouched.

## Demo Program

[`demo/demo.py`](demo/demo.py) is a small, self-contained `boto3` script that
walks through the classic DynamoDB "Movies" tutorial table end to end:
`CreateTable`, `BatchWriteItem`, `GetItem`, `Query`, `UpdateItem`, `Scan`,
`DeleteItem`, and `DeleteTable` — all served by ExtendDB and persisted in
DocumentDB.

```bash
kubectl port-forward svc/extenddb 18443:18443 -n extenddb &
pip install -r demo/requirements.txt
EXTENDDB_ACCESS_KEY_ID=<from deploy.sh output> \
EXTENDDB_SECRET_ACCESS_KEY=<from deploy.sh output> \
    ./demo/demo.py
```

## Interactive Shell: ddbsh

There's no official "DynamoDB shell" from AWS, but
[`ddbsh`](https://github.com/awslabs/dynamodb-shell) (AWS Labs' open-source
DynamoDB Shell) is the closest equivalent to `mongosh`/`psql` — a readline
REPL that accepts SQL-like DDL/DML (`SELECT`, `INSERT`, `CREATE TABLE`,
`DESCRIBE`, etc.) and talks the same DynamoDB wire protocol ExtendDB serves.

Install (macOS):

```bash
brew tap aws/tap
brew install aws-ddbsh
```

For Linux, grab a prebuilt binary from the latest "Build DynamoDB Shell"
GitHub Actions run, or build from source (see the
[project README](https://github.com/awslabs/dynamodb-shell) for
prerequisites — cmake, a C++ compiler, and the AWS C++ SDK).

Point it at ExtendDB with the same credentials `scripts/deploy.sh` printed,
and override the endpoint via `DDBSH_ENDPOINT_OVERRIDE`:

```bash
kubectl port-forward svc/extenddb 18443:18443 -n extenddb &

export AWS_ACCESS_KEY_ID=<from deploy.sh output>
export AWS_SECRET_ACCESS_KEY=<from deploy.sh output>
export AWS_DEFAULT_REGION=us-east-1
export DDBSH_ENDPOINT_OVERRIDE="https://127.0.0.1:18443"

ddbsh
# ddbsh - version 0.5.1
# us-east-1 (*)> select * from "Movies";
```

You can also switch endpoints from inside a running shell session with
`CONNECT region WITH ENDPOINT endpoint;`. The `(*)` in the prompt confirms
you're pointed at a non-standard endpoint rather than real AWS DynamoDB.

> **TLS note:** ddbsh uses the AWS C++ SDK's standard TLS verification and
> has no `--no-verify-ssl` equivalent. Against ExtendDB's self-signed
> certificate you'll need to trust it system-wide (e.g. add
> `~/.extenddb/tls/cert.pem`, or the cert extracted from the `extenddb-state`
> PVC, to your OS/OpenSSL trust store) rather than disabling verification
> as the Python demo and `test-connection.sh` do.

## Configuration

### Using a different ExtendDB version

`Dockerfile` accepts build args to pin a specific source ref:

```bash
docker build --build-arg EXTENDDB_REF=v0.1.3 -t extenddb-mongo:playground .
```

### Connecting from outside the cluster

By default the `extenddb` Service is `ClusterIP`. For external access, either
`kubectl port-forward` (as `test-connection.sh` does) or edit
[`manifests/serve.yaml`](manifests/serve.yaml) to set `type: LoadBalancer`.

### TLS

ExtendDB requires TLS and refuses to start without it; `extenddb init`
auto-generates a self-signed certificate. `test-connection.sh` uses
`aws ... --no-verify-ssl` for simplicity. For a more realistic setup, extract
the generated certificate from the PVC (or the init Job's logs directory
`/var/lib/extenddb`) and pass it via `AWS_CA_BUNDLE` instead.

## Troubleshooting

### `replicaSet` vs. `directConnection`

DocumentDB's printed connection string sets both `directConnection=true` and
`replicaSet=rs0`. Several MongoDB drivers (e.g. the Go driver used by KEDA,
`pymongo` as used by the [LightRAG playground](../lightrag/)) fail when both
are combined, because `directConnection` skips replica-set discovery, but the
gateway doesn't advertise its replica-set name to a driver in direct mode —
producing errors like *"client is configured to connect to a replica set
named 'rs0' but this node belongs to a set named 'None'"*.

ExtendDB's MongoDB backend, however, **requires** `replicaSet=rs0` in its
connection string (its transactional and retryable-write code paths depend on
replica-set semantics) — it cannot be dropped the way other playgrounds drop
it. `scripts/deploy.sh` instead strips `directConnection=true` and keeps
`replicaSet=rs0`, so the Rust `mongodb` driver performs full topology
discovery against the gateway-advertised replica set. If you see connection
or topology errors from the `extenddb-init` Job or the `extenddb` Deployment,
check the resolved connection string in the `extenddb-mongo-uri` Secret first:

```bash
kubectl get secret extenddb-mongo-uri -n extenddb \
    -o jsonpath='{.data.connection_string}' | base64 -d
```

### Init Job fails or admin credentials were lost

`extenddb init` refuses to run twice against the same catalog/data
databases. To start over:

```bash
kubectl delete job extenddb-init -n extenddb --ignore-not-found
kubectl exec -n extenddb deploy/extenddb -- extenddb destroy --config /var/lib/extenddb/extenddb.toml --yes
kubectl delete deployment extenddb -n extenddb
./scripts/deploy.sh
```

### Table/Item operations return errors referencing transactions

ExtendDB's MongoDB backend uses multi-document transactions for some
operations (e.g. `TransactWriteItems`). Confirm your DocumentDB extension
version supports the MongoDB transaction commands ExtendDB issues; check
`kubectl logs deploy/extenddb -n extenddb` for the underlying MongoDB error.

## Cleanup

```bash
./scripts/cleanup.sh                          # removes the extenddb namespace
kubectl delete namespace documentdb-test      # removes DocumentDB (optional)
```
