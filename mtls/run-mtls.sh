#!/usr/bin/env bash
# Demonstrate X.509-SVID mTLS between two workloads with go-spiffe.
#
# This is the other half of SPIFFE identity: where the JWT-SVID path proves a
# workload to Akeyless, this path proves two workloads to EACH OTHER over mutual
# TLS. It needs only SPIRE (./spire/up.sh); it does not touch Akeyless.
#
# This host-side script registers the two workloads, then runs the in-container
# mtls/demo.sh, which starts the server as its own child, runs the client, and
# tears the server down before exiting so nothing lingers. Each workload runs
# under a distinct UID: two root processes both match unix:uid:0 and SPIRE would
# return both identities, so distinct UIDs keep attestation unambiguous.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

set -a; [ -f "$ROOT/.env" ] && . "$ROOT/.env"; set +a

TD="${SPIFFE_TRUST_DOMAIN:-example.org}"
SERVER_ID="${MTLS_SERVER_SPIFFE_ID:-spiffe://${TD}/ns/default/sa/mtls-server}"
CLIENT_ID="${MTLS_CLIENT_SPIFFE_ID:-spiffe://${TD}/ns/default/sa/mtls-client}"
SERVER_UID="${MTLS_SERVER_UID:-10001}"
CLIENT_UID="${MTLS_CLIENT_UID:-10002}"
SERVER_SOCKET_PATH="/tmp/spire-server/private/api.sock"
DC="docker compose --project-directory $ROOT -f spire/docker-compose.yml"
PARENT="spiffe://${TD}/agent/host"

register() {  # <spiffe_id> <uid>
  local id="$1" uid="$2"
  if $DC exec -T spire-server /opt/spire/bin/spire-server entry show \
       -socketPath "$SERVER_SOCKET_PATH" 2>/dev/null | grep -q "$id"; then
    echo "[mtls] $id already registered"
  else
    echo "[mtls] registering $id (selector unix:uid:${uid}) ..."
    $DC exec -T spire-server /opt/spire/bin/spire-server entry create \
       -parentID "$PARENT" -spiffeID "$id" -selector "unix:uid:${uid}" \
       -socketPath "$SERVER_SOCKET_PATH" >/dev/null
    echo "[mtls] registered."
  fi
}

echo "[mtls] registering the two mTLS workloads ..."
register "$SERVER_ID" "$SERVER_UID"
register "$CLIENT_ID" "$CLIENT_UID"

echo "[mtls] running the mTLS demo in the host container ..."
$DC exec -T \
  -e MTLS_SERVER_SPIFFE_ID="$SERVER_ID" \
  -e MTLS_CLIENT_SPIFFE_ID="$CLIENT_ID" \
  -e MTLS_SERVER_UID="$SERVER_UID" \
  -e MTLS_CLIENT_UID="$CLIENT_UID" \
  host /app/mtls/demo.sh

echo "[mtls] done."
