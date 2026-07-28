#!/usr/bin/env bash
# Register the reference workload so spire-agent will issue it a JWT-SVID.
# Idempotent: skips creation when an entry for this SPIFFE ID already exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
set -a; . "$ROOT/.env"; set +a

TRUST_DOMAIN="${SPIFFE_TRUST_DOMAIN:-example.org}"
WORKLOAD_SPIFFE_ID="${WORKLOAD_SPIFFE_ID:-spiffe://example.org/ns/default/sa/secret-consumer}"
PARENT="spiffe://${TRUST_DOMAIN}/agent/host"
SERVER_SOCKET="/tmp/spire-server/private/api.sock"
DC="docker compose --project-directory $ROOT -f spire/docker-compose.yml"

echo "[register] looking for an existing entry for $WORKLOAD_SPIFFE_ID ..."
if $DC exec -T spire-server /opt/spire/bin/spire-server entry show \
     -socketPath "$SERVER_SOCKET" 2>/dev/null | grep -q "$WORKLOAD_SPIFFE_ID"; then
  echo "[register] entry already exists; nothing to do."
  exit 0
fi

echo "[register] creating entry: parent=$PARENT spiffeID=$WORKLOAD_SPIFFE_ID selector=unix:uid:0"
$DC exec -T spire-server /opt/spire/bin/spire-server entry create \
  -parentID "$PARENT" \
  -spiffeID "$WORKLOAD_SPIFFE_ID" \
  -selector "unix:uid:0" \
  -socketPath "$SERVER_SOCKET"
