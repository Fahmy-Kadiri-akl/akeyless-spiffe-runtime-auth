#!/usr/bin/env bash
# One-time (and re-runnable) admin setup: wire the SPIRE trust bundle into
# Akeyless as an OAuth2/JWT auth method, create a least-privilege role bound to
# the workload's SPIFFE ID, and drop a demo secret for the app to read.
#
#   ./bootstrap/setup-akeyless.sh
#
# Idempotent and always-fresh: it recreates the auth method with the current
# SPIRE bundle on every run, so it is safe to re-run after a new trust root
# (e.g. after spire/down.sh). Requires curl, jq, and python3+cryptography on
# the PATH, and AKEYLESS_TOKEN (a short-lived token) in .env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# Source .env so this works when run directly (matching the README quickstart).
set -a; [ -f "$ROOT/.env" ] && . "$ROOT/.env"; set +a

DC="docker compose --project-directory $ROOT -f spire/docker-compose.yml"

# --- required ---
: "${AKEYLESS_GATEWAY:?AKEYLESS_GATEWAY is required. Set it in .env.}"
: "${AKEYLESS_TOKEN:?AKEYLESS_TOKEN is required. Mint a short-lived token and set it in .env. It expires on its own.}"
GATEWAY="${AKEYLESS_GATEWAY%/}"

# --- config (env-overridable; defaults match spire/spire.env.example) ---
WORKLOAD_SPIFFE_ID="${WORKLOAD_SPIFFE_ID:-spiffe://example.org/ns/default/sa/secret-consumer}"
AUDIENCE="${JWT_AUDIENCE:-akeyless}"
AUTH_METHOD="${AKEYLESS_AUTH_METHOD:-/spiffe/demo/auth}"
ROLE="${AKEYLESS_ROLE:-/spiffe/demo/reader}"
SECRET="${AKEYLESS_SECRET:-/spiffe/demo/db-password}"
DEMO_SECRET_VALUE="spiffe-demo-$(date +%s)"
RULE_PATH="$(dirname "$SECRET")"/*

# Files written for the host container (mounted at /run/spire-data).
RAW_BUNDLE="${SPIRE_RAW_BUNDLE:-$ROOT/spire/.data/bundle.spiffe.json}"
JWKS_FILE="${SPIRE_BUNDLE_JWKS:-$ROOT/spire/.data/bundle.jwks}"
ACCESS_ID_FILE="$ROOT/spire/.data/akeyless-access-id"
JWKS_URI="${SPIRE_BUNDLE_ENDPOINT:-}"

# Helper: call an Akeyless REST endpoint. Args: endpoint, json-body.
api() {
  curl -fsS -X POST "$GATEWAY/api/v2/$1" \
    -H "Content-Type: application/json" \
    -d "$2" 2>/dev/null
}
# Same but suppress errors (for idempotent create-if-absent calls).
api_quiet() {
  curl -sS -X POST "$GATEWAY/api/v2/$1" \
    -H "Content-Type: application/json" \
    -d "$2" >/dev/null 2>&1 || true
}

mkdir -p "$(dirname "$RAW_BUNDLE")"

# --- 1. obtain the SPIRE bundle as a standard JWKS ---
if [ -n "$JWKS_URI" ]; then
  echo "[setup] using public bundle endpoint: $JWKS_URI"
  USE_URI=true
else
  echo "[setup] dumping SPIRE trust bundle from the running server ..."
  if ! $DC exec -T spire-server /opt/spire/bin/spire-server bundle show \
        -format spiffe -output json \
        -socketPath /tmp/spire-server/private/api.sock > "$RAW_BUNDLE" 2>/dev/null; then
    echo "[setup] Could not dump the bundle. Ensure SPIRE is up (./spire/up.sh)" >&2
    echo "[setup] first, or set SPIRE_BUNDLE_ENDPOINT to a public bundle URL." >&2
    exit 1
  fi
  echo "[setup] converting trust bundle to a standard JWKS ..."
  if ! python3 "$SCRIPT_DIR/spiffe-bundle-to-jwks.py" "$RAW_BUNDLE" > "$JWKS_FILE"; then
    echo "[setup] JWKS conversion failed. Is 'cryptography' installed? (pip install cryptography)" >&2
    exit 1
  fi
  JWKS_B64="$(base64 -w0 "$JWKS_FILE" 2>/dev/null || base64 < "$JWKS_FILE" | tr -d '\n')"
  USE_URI=false
fi

# --- 2. (re)create the OAuth2/JWT auth method with the current bundle ---
# Delete first so a stale bundle from a previous trust root is replaced.
if api get-auth-method "$(jq -cn --arg n "$AUTH_METHOD" --arg t "$AKEYLESS_TOKEN" \
  '{name:$n, token:$t}')" >/dev/null 2>&1; then
  echo "[setup] refreshing auth method $AUTH_METHOD (stale JWKS would reject new SVIDs) ..."
  api delete-auth-method "$(jq -cn --arg n "$AUTH_METHOD" --arg t "$AKEYLESS_TOKEN" \
    '{name:$n, token:$t}')" >/dev/null
fi

echo "[setup] creating auth method $AUTH_METHOD ..."
if [ "$USE_URI" = true ]; then
  BODY=$(jq -cn \
    --arg name "$AUTH_METHOD" \
    --arg uid  "sub" \
    --arg aud  "$AUDIENCE" \
    --arg uri  "$JWKS_URI" \
    --arg t    "$AKEYLESS_TOKEN" \
    '{name:$name, "unique-identifier":$uid, audience:$aud, "jwks-uri":$uri, token:$t}')
else
  BODY=$(jq -cn \
    --arg name "$AUTH_METHOD" \
    --arg uid  "sub" \
    --arg aud  "$AUDIENCE" \
    --arg jwks "$JWKS_B64" \
    --arg t    "$AKEYLESS_TOKEN" \
    '{name:$name, "unique-identifier":$uid, audience:$aud, "jwks-json-data":$jwks, token:$t}')
fi
api create-auth-method-oauth2 "$BODY" >/dev/null

# --- 3. least-privilege role bound to this workload's SPIFFE ID ---
echo "[setup] creating role $ROLE ..."
api_quiet create-role "$(jq -cn --arg n "$ROLE" --arg t "$AKEYLESS_TOKEN" \
  '{name:$n, token:$t}')"

echo "[setup] associating role with auth method ..."
api_quiet assoc-role-am "$(jq -cn \
  --arg rn "$ROLE" \
  --arg am "$AUTH_METHOD" \
  --arg sid "$WORKLOAD_SPIFFE_ID" \
  --arg t  "$AKEYLESS_TOKEN" \
  '{"role-name":$rn, "am-name":$am, "case-sensitive":"sub", "sub-claims":{"sub":$sid}, token:$t}')"

echo "[setup] granting read + list on $RULE_PATH ..."
api set-role-rule "$(jq -cn \
  --arg rn "$ROLE" \
  --arg p  "$RULE_PATH" \
  --arg t  "$AKEYLESS_TOKEN" \
  '{"role-name":$rn, path:$p, capability:["read","list"], token:$t}')" >/dev/null

# --- 4. demo secret ---
echo "[setup] creating demo secret $SECRET ..."
api_quiet create-secret "$(jq -cn \
  --arg n "$SECRET" \
  --arg v  "$DEMO_SECRET_VALUE" \
  --arg t  "$AKEYLESS_TOKEN" \
  '{name:$n, value:$v, token:$t}')"

# --- 5. publish the auth method's access id for the app ---
RESP="$(api get-auth-method "$(jq -cn --arg n "$AUTH_METHOD" --arg t "$AKEYLESS_TOKEN" \
  '{name:$n, token:$t}')")"
AM_ACCESS_ID="$(echo "$RESP" | jq -r '."auth_method_access_id" // .auth_method_access_id // empty' 2>/dev/null)"
if [ -z "$AM_ACCESS_ID" ]; then
  echo "[setup] WARNING: could not read the auth method access id" >&2
  exit 1
fi
printf '%s\n' "$AM_ACCESS_ID" > "$ACCESS_ID_FILE"
chmod 600 "$ACCESS_ID_FILE"
if grep -q '^AKEYLESS_ACCESS_ID=' "$ROOT/.env" 2>/dev/null; then
  sed -i.bak "s|^AKEYLESS_ACCESS_ID=.*|AKEYLESS_ACCESS_ID=$AM_ACCESS_ID|" "$ROOT/.env" && rm -f "$ROOT/.env.bak"
else
  printf 'AKEYLESS_ACCESS_ID=%s\n' "$AM_ACCESS_ID" >> "$ROOT/.env"
fi
echo "[setup] published auth-method access id to spire/.data/akeyless-access-id"

cat <<EOF

[setup] done. Workload $WORKLOAD_SPIFFE_ID can authenticate to Akeyless via
        $AUTH_METHOD and read secrets under $RULE_PATH.

Next: read the secret from the host container:
  $DC exec -T host dotnet /app/bin/Release/net8.0/secret-consumer.dll
EOF
