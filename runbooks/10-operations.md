# Operations and observability

How to keep a SPIRE + Akeyless deployment running and catch problems before
they break authentication.

## What to monitor

| Signal | What it tells you | How to check |
|---|---|---|
| SPIRE server health | the server is alive and signing | `spire-server healthcheck` |
| SPIRE agent health | the agent is connected and issuing SVIDs | `spire-agent healthcheck` |
| Workload API socket | the socket exists and responds | `spire-agent api fetch jwt` |
| JWKS freshness | Akeyless has the current signing key | compare bundle timestamps |
| Akeyless auth success rate | SVIDs are being accepted | Akeyless audit log |
| SVID issuance rate | workloads are fetching SVIDs normally | SPIRE server metrics or log volume |

## Health checks

### SPIRE server

```bash
docker compose --project-directory . -f spire/docker-compose.yml \
  exec spire-server /opt/spire/bin/spire-server healthcheck -socketPath /tmp/spire-server/private/api.sock
```

A healthy server prints `Server is healthy.` If it fails, check the server logs
and confirm the data volume is writable.

### SPIRE agent

```bash
docker compose --project-directory . -f spire/docker-compose.yml \
  exec host spire-agent healthcheck -socketPath /tmp/spire-agent/public/api.sock
```

A healthy agent is connected to the server and serving the Workload API. If it
fails, the agent may have lost its registration or the server may be
unreachable.

### End-to-end SVID fetch

```bash
docker compose --project-directory . -f spire/docker-compose.yml \
  exec host spire-agent api fetch jwt -audience akeyless \
  -socketPath /tmp/spire-agent/public/api.sock
```

If this fails, no workload on the host can authenticate. The most common causes
are a stale registration entry, a timing race after registration, or the agent
not seeing the calling process because of selectors or PID namespace
mismatches. See [Troubleshooting](08-troubleshooting.md).

## Detecting broken SVID issuance

SVID issuance can fail silently from the workload's perspective. The app asks
the Workload API, gets nothing, and its Akeyless call fails with an auth error.
Catch it before the app does:

| Symptom | Likely cause | Check |
|---|---|---|
| App reports auth failure | SVID fetch failed or JWKS stale | run the end-to-end fetch above |
| Agent healthcheck fails | agent lost server connection | check agent logs, network |
| No SVIDs issued since restart | registration entry missing or selector mismatch | `spire-server entry show` |
| Auth worked, then stopped after hours | SPIRE rotated JWT key, JWKS stale | re-run `bootstrap/setup-akeyless.sh` or set `SPIRE_BUNDLE_ENDPOINT` |

## JWKS freshness

When SPIRE rotates its JWT signing key, the JWKS on the Akeyless auth method
goes stale and SVIDs are rejected. The fix and the production recommendation
(`SPIRE_BUNDLE_ENDPOINT`) are in
[Configuration: Lifetimes](05-configuration.md#lifetimes) and
[Production: Bundle distribution](06-production.md#bundle-distribution). Alert
when auth failures spike, which is the primary signal.

## Akeyless audit events

Every SVID authentication is recorded in the Akeyless audit log. Key events:

| Event | What it means | Action |
|---|---|---|
| auth success | a workload authenticated with a valid SVID | normal |
| auth failure: invalid signature | JWKS stale or SVID tampered | refresh JWKS |
| auth failure: expired token | SVID used after expiry | normal; investigate if sudden spike |
| auth failure: unknown SPIFFE ID | role binding mismatch | check role association |

Alert on a sudden spike in auth failures, which often signals a stale JWKS or a
misconfigured role binding.

## Alerting recommendations

| Alert | Threshold | Why |
|---|---|---|
| SPIRE server unhealthy | any failure | signing stops; all SVIDs eventually fail |
| SVID issuance drops to zero | no successful fetches in N minutes | workloads cannot authenticate |
| Akeyless auth failure spike | failure rate above baseline for 5 minutes | JWKS stale, role misconfigured, or attack |
| JWKS age approaching CA_TTL | bundle not refreshed within rotation window | SVIDs will be rejected on next rotation |

## A simple health-check script

Run from cron every minute. Alerts if SVID issuance is broken on the host:

```bash
#!/bin/sh
set -e
SOCKET=/tmp/spire-agent/public/api.sock
if ! spire-agent api fetch jwt -audience akeyless -socketPath "$SOCKET" >/dev/null 2>&1; then
  echo "ALERT: SVID fetch failed on $(hostname)" >&2
  exit 1
fi
```

Pair this with an Akeyless-side alert on auth failure spikes for full coverage.

Next: [Migrating from on-disk credentials](11-migration.md)
