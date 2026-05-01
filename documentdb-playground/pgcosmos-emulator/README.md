# pgcosmos-emulator wrapper image (kind-local only)

> ⚠️ **Status:** stub — a follow-up agent will fill in the full README.

This directory builds a thin wrapper around the public Azure Cosmos DB emulator
image so it can be driven by the `documentdb-kubernetes-operator`'s existing
`DocumentDB` CR without source changes to the operator.

- **Base image:** [`mcr.microsoft.com/cosmosdb/linux/azure-cosmos-emulator:vnext-preview`](https://mcr.microsoft.com/en-us/artifact/mar/cosmosdb/linux/azure-cosmos-emulator)
- **Output tag:** `localhost/pgcosmos-emulator:dev`
- **Distribution:** **kind-local only.** The build script loads the image into
  a local `kind` cluster via `kind load docker-image`. **Do not** `docker push`
  it to any registry.

## Why a wrapper is needed

Two small alignments with the operator/CNPG contract:

| Operator/CNPG expectation                           | Base default       | Wrapper does                        |
|-----------------------------------------------------|--------------------|-------------------------------------|
| Gateway listens on `10260` (operator's `GATEWAY_PORT`) | `PORT=8081`     | `ENV PORT=10260`                    |
| Plain HTTP for v1 (no PFX projection yet)            | `PROTOCOL=http`    | `ENV PROTOCOL=http` (explicit)      |
| `/usr/lib/postgresql/<MAJOR>/bin/postgres` exists    | only `/usr/bin/postgres` | symlinks `/usr/lib/postgresql/16/bin/*` → `/usr/bin/*` |

No proprietary source is copied into the image — it is `FROM` the public image
plus `ENV` and a symlink farm.

## Build

```bash
./build.sh
# or
IMAGE_TAG=localhost/pgcosmos-emulator:dev KIND_CLUSTER=documentdb-test ./build.sh
```
