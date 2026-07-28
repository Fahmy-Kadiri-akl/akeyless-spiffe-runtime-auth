#!/bin/sh
# Run the X.509-SVID mTLS demo INSIDE the host container.
#
# The server is started as a child of this shell and is killed before the shell
# exits, so it never outlives the demo and never leaks its listen socket across
# runs. Both workloads run under distinct UIDs so SPIRE attests them separately.
#
# Env (passed by run-mtls.sh):
#   MTLS_SERVER_SPIFFE_ID, MTLS_CLIENT_SPIFFE_ID, MTLS_SERVER_UID, MTLS_CLIENT_UID
set -eu

ADDR=127.0.0.1:8443
SOCK=unix:///tmp/spire-agent/public/api.sock
SERVER_ID="${MTLS_SERVER_SPIFFE_ID:?MTLS_SERVER_SPIFFE_ID is required}"
CLIENT_ID="${MTLS_CLIENT_SPIFFE_ID:?MTLS_CLIENT_SPIFFE_ID is required}"
SERVER_UID="${MTLS_SERVER_UID:-10001}"
CLIENT_UID="${MTLS_CLIENT_UID:-10002}"
LOG=/tmp/mtls-server.log

echo "[mtls] starting mTLS server as uid $SERVER_UID ..."
SPIFFE_ENDPOINT_SOCKET=$SOCK MTLS_CLIENT_SPIFFE_ID=$CLIENT_ID MTLS_LISTEN_ADDR=$ADDR \
  setpriv --reuid=$SERVER_UID --regid=$SERVER_UID --clear-groups \
  /app/mtls/server > "$LOG" 2>&1 &
SRV=$!
trap 'kill "$SRV" 2>/dev/null || true; wait "$SRV" 2>/dev/null || true' EXIT INT TERM

echo "[mtls] waiting for the server to come up ..."
i=0
while [ "$i" -lt 40 ]; do
  if grep -q "listening on" "$LOG" 2>/dev/null; then break; fi
  sleep 0.5; i=$((i + 1))
done
if ! grep -q "listening on" "$LOG" 2>/dev/null; then
  echo "[mtls] ERROR: server did not start. Log:" >&2
  cat "$LOG" >&2 || true
  exit 1
fi

echo "[mtls] running mTLS client as uid $CLIENT_UID ..."
SPIFFE_ENDPOINT_SOCKET=$SOCK MTLS_SERVER_SPIFFE_ID=$SERVER_ID MTLS_SERVER_ADDR=$ADDR \
  setpriv --reuid=$CLIENT_UID --regid=$CLIENT_UID --clear-groups \
  /app/mtls/client
RC=$?

echo
echo "[mtls] server log:"
cat "$LOG" 2>/dev/null || true
exit "$RC"
