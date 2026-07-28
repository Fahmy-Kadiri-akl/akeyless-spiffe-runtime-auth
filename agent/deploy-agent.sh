#!/usr/bin/env bash
# Deploy a standalone SPIRE agent on this host using the pre-built, portable
# spiffe-agent image from GHCR. The image is app-agnostic: it runs only the
# agent and serves the SPIFFE Workload API, so any application in any language
# can consume it for identity. It is fully decoupled from your application.
#
# Required env:
#   SPIRE_SERVER_ADDRESS  host or IP of the spire-server. To reach a server whose
#                         port is published on THIS docker host, use
#                         host.docker.internal.
#   JOIN_TOKEN            one-time join token from the server. Generate it on the
#                         server with:
#                           spire-server token generate \
#                             -spiffeID spiffe://<trust-domain>/agent/<name>
# Optional env:
#   SPIFFE_TRUST_DOMAIN   default example.org, must match the server
#   SPIRE_SERVER_PORT     default 8081
#   WORKLOAD_SOCKET_DIR   default /tmp/spire-agent/public, the standard SPIFFE
#                         Workload API socket directory
#
# After this runs, register the workload ON THE SERVER (not here), then point
# your application at $WORKLOAD_SOCKET_DIR/api.sock.
set -euo pipefail

: "${SPIRE_SERVER_ADDRESS:?SPIRE_SERVER_ADDRESS is required}"
: "${JOIN_TOKEN:?JOIN_TOKEN is required}"
SPIFFE_TRUST_DOMAIN="${SPIFFE_TRUST_DOMAIN:-example.org}"
SERVER_PORT="${SPIRE_SERVER_PORT:-8081}"
WORKLOAD_SOCKET_DIR="${WORKLOAD_SOCKET_DIR:-/tmp/spire-agent/public}"
IMAGE="${SPIRE_AGENT_IMAGE:-ghcr.io/fahmy-kadiri-akl/akeyless-spiffe-runtime-auth/agent:latest}"
AGENT_NAME="${AGENT_CONTAINER_NAME:-spire-agent}"

mkdir -p "$WORKLOAD_SOCKET_DIR"
docker rm -f "$AGENT_NAME" >/dev/null 2>&1 || true
echo "[agent] starting $AGENT_NAME from $IMAGE -> $SPIRE_SERVER_ADDRESS:$SERVER_PORT ($SPIFFE_TRUST_DOMAIN)"

# --pid host lets the unix WorkloadAttestor see host-side workload processes.
docker run -d --name "$AGENT_NAME" --pid host \
  -e SPIRE_SERVER_ADDRESS="$SPIRE_SERVER_ADDRESS" \
  -e SPIFFE_TRUST_DOMAIN="$SPIFFE_TRUST_DOMAIN" \
  -e SPIRE_SERVER_PORT="$SERVER_PORT" \
  -e JOIN_TOKEN="$JOIN_TOKEN" \
  -v "$WORKLOAD_SOCKET_DIR:/tmp/spire-agent/public" \
  --add-host host.docker.internal:host-gateway \
  "$IMAGE" >/dev/null

echo "[agent] waiting for Workload API at $WORKLOAD_SOCKET_DIR/api.sock ..."
for _ in $(seq 1 60); do
  if [ -S "$WORKLOAD_SOCKET_DIR/api.sock" ]; then
    echo "[agent] ready. Any application can fetch SVIDs from $WORKLOAD_SOCKET_DIR/api.sock"
    exit 0
  fi
  sleep 0.5
done
echo "[agent] FATAL: Workload API socket never appeared" >&2
docker logs "$AGENT_NAME" >&2 || true
exit 1
