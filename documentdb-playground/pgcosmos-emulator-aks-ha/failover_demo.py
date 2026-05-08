#!/usr/bin/env python3
"""Failover demo client for the pgcosmos-emulator AKS HA playground.

Continuously inserts a heartbeat document and re-reads the latest entry from
the same partition. Every iteration is its own try/except; transient errors
trigger a CosmosClient reconnect with backoff. The point of the demo is that
the operator-managed Service follows the CNPG primary-role label, so when we
``kubectl delete pod`` the current primary, the LB target retargets and the
client recovers without any DNS or IP change.

Run via ``run_demo.sh``, or directly:

    pip install -r requirements.txt
    python failover_demo.py \
        --endpoint https://<aks-lb-ip>:10260 \
        --duration 90

The endpoint should be the LoadBalancer IP printed by ``run_demo.sh``. We
default the gateway port to 10260 (rust_gateway over TLS) and disable cert
validation because the cluster ships a self-signed cert from cert-manager.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
import time
import uuid
from typing import Optional

from azure.cosmos import CosmosClient, PartitionKey, exceptions

DEFAULT_KEY = "Admin100"
DEFAULT_DB = "demo"
DEFAULT_CONTAINER = "heartbeats"
DEFAULT_PARTITION = "global"


def make_client(endpoint: str, key: str) -> CosmosClient:
    """Build a Cosmos client that tolerates the cluster's self-signed cert.

    azure-cosmos honours ``connection_verify=False`` and forwards it to the
    underlying httpx/requests session, which skips CA validation. We trust the
    LB IP because we own the AKS cluster and the gateway pod's serving cert is
    issued by the cluster's own cert-manager Issuer.
    """
    return CosmosClient(url=endpoint, credential=key, connection_verify=False)


def ensure_schema(client: CosmosClient, db_name: str, container_name: str):
    db = client.create_database_if_not_exists(db_name)
    return db.create_container_if_not_exists(
        id=container_name,
        partition_key=PartitionKey(path="/pk"),
    )


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


class FailoverState:
    """Tracks the longest unavailability window during the demo run.

    We measure downtime as wall-clock between consecutive successful
    iterations. A successful iteration is one that completed both an upsert
    and a query without an exception. The metric isn't to-the-millisecond
    precise (the loop sleeps between iterations), but it's the right
    user-visible figure: how long was the client visibly stuck?
    """

    def __init__(self) -> None:
        self.last_ok: Optional[float] = None
        self.max_gap: float = 0.0
        self.errors: int = 0
        self.successes: int = 0
        self.total_iterations: int = 0

    def mark_ok(self) -> None:
        now = time.monotonic()
        if self.last_ok is not None:
            self.max_gap = max(self.max_gap, now - self.last_ok)
        self.last_ok = now
        self.successes += 1

    def mark_error(self) -> None:
        self.errors += 1


def run(args: argparse.Namespace) -> int:
    state = FailoverState()
    deadline = time.monotonic() + args.duration

    print(f"[{now_iso()}] connecting to {args.endpoint}")
    client = make_client(args.endpoint, args.key)
    container = ensure_schema(client, args.database, args.container)
    print(f"[{now_iso()}] schema ready (db={args.database}, container={args.container})")

    while time.monotonic() < deadline:
        state.total_iterations += 1
        doc_id = str(uuid.uuid4())
        try:
            container.upsert_item(
                {
                    "id": doc_id,
                    "pk": args.partition,
                    "ts": now_iso(),
                    "iteration": state.total_iterations,
                }
            )
            # Read-back proves the primary that accepted our write is still
            # serving queries; during failover this is what fails first.
            latest = list(
                container.query_items(
                    query=(
                        "SELECT TOP 1 c.id, c.iteration, c.ts FROM c "
                        "WHERE c.pk = @pk ORDER BY c.iteration DESC"
                    ),
                    parameters=[{"name": "@pk", "value": args.partition}],
                    partition_key=args.partition,
                )
            )
            top = latest[0] if latest else {}
            state.mark_ok()
            print(
                f"[{now_iso()}] OK iter={state.total_iterations} "
                f"id={doc_id[:8]} latest_iter={top.get('iteration')}"
            )
        except (exceptions.CosmosHttpResponseError, exceptions.ServiceRequestError) as exc:
            # 503 / connection refused / timeout — retry on a fresh client.
            state.mark_error()
            print(f"[{now_iso()}] ERR iter={state.total_iterations} {type(exc).__name__}: {exc}", file=sys.stderr)
            try:
                client = make_client(args.endpoint, args.key)
                container = client.get_database_client(args.database).get_container_client(args.container)
            except Exception as reconnect_err:  # pragma: no cover — defensive
                print(f"[{now_iso()}] RECONNECT_ERR {reconnect_err}", file=sys.stderr)
        except Exception as exc:
            # Catch-all for anything the SDK didn't classify. Re-raise after
            # logging — these typically indicate a programming error rather
            # than a transient failure, and we don't want to hide them.
            state.mark_error()
            print(f"[{now_iso()}] FATAL iter={state.total_iterations} {type(exc).__name__}: {exc}", file=sys.stderr)
            raise

        time.sleep(args.interval)

    print()
    print("=== demo summary ===")
    print(f"total iterations:   {state.total_iterations}")
    print(f"successes:          {state.successes}")
    print(f"errors:             {state.errors}")
    print(f"max success-gap:    {state.max_gap:.2f}s   (effective downtime)")
    return 0 if state.successes > 0 else 1


def parse_args(argv: list[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--endpoint", default=os.environ.get("PGCOSMOS_ENDPOINT"),
                   help="https://<lb-ip>:10260 (default: env PGCOSMOS_ENDPOINT)")
    p.add_argument("--key", default=os.environ.get("PGCOSMOS_KEY", DEFAULT_KEY),
                   help="Auth key — defaults to the demo password Admin100 (env PGCOSMOS_KEY)")
    p.add_argument("--database", default=DEFAULT_DB)
    p.add_argument("--container", default=DEFAULT_CONTAINER)
    p.add_argument("--partition", default=DEFAULT_PARTITION)
    p.add_argument("--duration", type=int, default=90, help="Total seconds to run (default 90)")
    p.add_argument("--interval", type=float, default=0.5, help="Seconds between iterations (default 0.5)")
    args = p.parse_args(argv)
    if not args.endpoint:
        p.error("--endpoint is required (or set PGCOSMOS_ENDPOINT)")
    return args


if __name__ == "__main__":
    # Silence the urllib3-via-azure-core "Unverified HTTPS request" spam —
    # the connection_verify=False is intentional for the demo.
    import warnings
    import urllib3

    warnings.simplefilter("ignore", urllib3.exceptions.InsecureRequestWarning)
    sys.exit(run(parse_args(sys.argv[1:])))
