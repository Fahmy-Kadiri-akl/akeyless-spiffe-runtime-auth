#!/usr/bin/env bash
# One-time (and re-runnable) admin setup: wire the SPIRE trust bundle into
# Akeyless as an OAuth2/JWT auth method, create a least-privilege role bound to
# the workload's SPIFFE ID, and drop a demo secret for the app to read.
#
#   ./bootstrap/setup-akeyless.sh
#
# Idempotent and always-fresh: it recreates the auth method with the current
# SPIRE bundle on every run, so it is safe to re-run after a new trust root
# (e.g. after spire/down.sh). Requires the Akeyless CLI and python3+cryptography
# on the PATH, and AKEYLESS_TOKEN (a short-lived temp token) in .env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

# Source .env so this works when run directly (matching the README quickstart).
set -a; [ -f "$ROOT/.env" ] && . "$ROOT/.env"; set +a

DC="docker compose --project-directory $ROOT -f spire/docker-compose.yml"

# --- config (env-overridable; defaults match spire/spire.env.example) ---
WORKLOAD_SPIFFE_ID="${WORKLOAD_SPIFFE_ID:-spiffe://example.org/ns/default/sa/secret-consumer}"
AUDIENCE="${JWT_AUDIENCE:-akeyless}"
AUTH_METHOD="${AKEYLESS_AUTH_METHOD:-/spiffe/demo/auth}"
ROLE="${AKEYLESS_ROLE:-/spiffe/demo/reader}"
SECRET="${AKEYLESS_SECRET:-/spiffe/demo/db-password}"
# The demo secret lives only in Akeyless. The bootstrap generates an ephemeral
# payload and writes it there so a first-time user has something to read back.
# Nothing is stored in .env. In production you provision your own secret at this
# path and the bootstrap leaves it alone.
DEMO_SECRET_VALUE="${AKEYLESS_DEMO_SECRET:-spiffe-demo-$(date +%s)}"
# Rule path covers the secret's folder, so a custom SECRET path still works.
RULE_PATH="$(dirname "$SECRET")"/*

# Files written for the host container (mounted at /run/spire-data).
RAW_BUNDLE="${SPIRE_RAW_BUNDLE:-$ROOT/spire/.data/bundle.spiffe.json}"
JWKS_FILE="${SPIRE_BUNDLE_JWKS:-$ROOT/spire/.data/bundle.jwks}"
ACCESS_ID_FILE="$ROOT/spire/.data/akeyless-access-id"
JWKS_URI="${SPIRE_BUNDLE_ENDPOINT:-}"

# Authenticate with a short-lived temp token (AKEYLESS_TOKEN), not a long-lived
# API key. Mint one out-of-band and let it expire on its own, for example:
#   akeyless auth --access-id <p-...> --access-type access_key \
#     --access-key <key> --gateway-url <gw>
# or via SAML/OIDC, then set AKEYLESS_TOKEN to the printed t-... value. The token
# needs the capabilities in "Required Akeyless permissions" in the README.
# Token is the only supported method. A missing token is a hard failure.
: "${AKEYLESS_TOKEN:?AKEYLESS_TOKEN is required. Mint a temp token with 'akeyless auth' and put it in .env. It expires on its own.}"
AUTH_FLAG=(--token "$AKEYLESS_TOKEN")
# Do not pass --gateway-url: auth-method create oauth2 rejects it together with
# an inline --jwks-json-data JWKS. The token and the profile both carry their own
# gateway, and --token routes itself.
akl() { akeyless "$@" "${AUTH_FLAG[@]}"; }

mkdir -p "$(dirname "$RAW_BUNDLE")"

# --- 1. obtain the SPIRE bundle as a standard JWKS ---
if [ -n "$JWKS_URI" ]; then
  echo "[setup] using public bundle endpoint: $JWKS_URI"
  BUNDLE_ARGS=(--jwks-uri "$JWKS_URI")
else
  # Always re-dump from the running server. The trust root changes whenever the
  # server volume is removed, so a cached bundle would reject new SVIDs.
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
  BUNDLE_ARGS=(--jwks-json-data "$JWKS_B64")
fi

# --- 2. (re)create the OAuth2/JWT auth method with the current bundle ---
# Delete first so a stale bundle from a previous trust root is replaced. The
# access id changes on recreate; we publish it below for the app to read.
if akl get-auth-method --name "$AUTH_METHOD" >/dev/null 2>&1; then
  echo "[setup] refreshing auth method $AUTH_METHOD (stale JWKS would reject new SVIDs) ..."
  akl auth-method delete --name "$AUTH_METHOD" >/dev/null
fi
echo "[setup] creating auth method $AUTH_METHOD ..."
akl auth-method create oauth2 \
  --name "$AUTH_METHOD" \
  --unique-identifier sub \
  --audience "$AUDIENCE" \
  "${BUNDLE_ARGS[@]}"

# --- 3. least-privilege role bound to this workload's SPIFFE ID ---
echo "[setup] creating role $ROLE ..."
akl create-role --name "$ROLE" >/dev/null 2>&1 || echo "[setup] (role already exists; reusing)"

akl assoc-role-am \
  --role-name "$ROLE" \
  --am-name "$AUTH_METHOD" \
  --case-sensitive sub \
  --sub-claims "sub=$WORKLOAD_SPIFFE_ID" \
  || echo "[setup] (association may already exist; continuing)"

akl set-role-rule \
  --role-name "$ROLE" \
  --path "$RULE_PATH" \
  --capability read \
  --capability list

# --- 4. demo secret ---
echo "[setup] creating demo secret $SECRET ..."
akl create-secret --name "$SECRET" --value "$DEMO_SECRET_VALUE" \
  >/dev/null 2>&1 || echo "[setup] (secret already exists; reusing)"

# --- 5. publish the auth method's access id for the app ---
# `akeyless auth` takes the access id, not the method name. Write it to a file
# the host container reads at runtime (mounted at /run/spire-data), so the app
# works regardless of whether the container started before this script ran.
AM_ACCESS_ID="$(akl get-auth-method --name "$AUTH_METHOD" 2>/dev/null \
  | grep -oE '"auth_method_access_id"[^"]*"[^"]+"' | grep -oE 'p-[a-z0-9]+' | head -1)"
if [ -z "$AM_ACCESS_ID" ]; then
  echo "[setup] WARNING: could not read the auth method access id" >&2
  exit 1
fi
printf '%s\n' "$AM_ACCESS_ID" > "$ACCESS_ID_FILE"
chmod 600 "$ACCESS_ID_FILE"
# Also keep .env in sync for humans reading it.
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
