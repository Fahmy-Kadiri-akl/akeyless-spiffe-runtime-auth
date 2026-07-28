#!/usr/bin/env bash
# Bring up the self-contained dev SPIRE topology and register the workload.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$ROOT"

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Run:" >&2
  echo "  cp spire/spire.env.example .env" >&2
  echo "  # then set AKEYLESS_GATEWAY to your account gateway URL" >&2
  exit 1
fi
set -a; . ./.env; set +a

: "${SPIFFE_TRUST_DOMAIN:=example.org}"
: "${JWT_AUDIENCE:=akeyless}"
: "${CA_TTL:=24h}"
: "${X509_SVID_TTL:=1h}"
: "${JWT_SVID_TTL:=5m}"

# Render the trust domain into runtime copies of the SPIRE configs. The
# canonical files in spire/ default to example.org; SPIFFE_TRUST_DOMAIN in .env
# overrides it end to end. Lifetimes default to SPIRE values and can be
# overridden in .env (CA_TTL, X509_SVID_TTL, JWT_SVID_TTL).
mkdir -p "$ROOT/spire/.data"
sed -e "s|example.org|$SPIFFE_TRUST_DOMAIN|g" \
    -e "s|@@CA_TTL@@|$CA_TTL|" \
    -e "s|@@X509_SVID_TTL@@|$X509_SVID_TTL|" \
    -e "s|@@JWT_SVID_TTL@@|$JWT_SVID_TTL|" \
    "$ROOT/spire/server.conf" > "$ROOT/spire/.data/server.conf"
sed "s|example.org|$SPIFFE_TRUST_DOMAIN|g" "$ROOT/spire/agent.conf" > "$ROOT/spire/.data/agent.conf"

PARENT="spiffe://${SPIFFE_TRUST_DOMAIN}/agent/host"
DC="docker compose --project-directory $ROOT -f spire/docker-compose.yml"

echo "==> Starting spire-server ..."
$DC up -d --build spire-server

echo "==> Waiting for spire-server healthcheck ..."
for i in $(seq 1 60); do
  if $DC exec -T spire-server /opt/spire/bin/spire-server healthcheck \
        -socketPath /tmp/spire-server/private/api.sock >/dev/null 2>&1; then
    echo ' ok'; break
  fi
  printf '.'; sleep 1
  if [ "$i" -eq 60 ]; then
    echo; echo "ERROR: spire-server did not become healthy in 60s" >&2
    $DC logs --tail=30 spire-server >&2 || true
    exit 1
  fi
done

echo "==> Generating a one-time join token for the agent ..."
JOIN_TOKEN=$($DC exec -T spire-server /opt/spire/bin/spire-server token generate \
  -spiffeID "$PARENT" \
  -socketPath /tmp/spire-server/private/api.sock \
  | awk '/Token:/ {print $2}')
: "${JOIN_TOKEN:?failed to obtain join token}"

echo "==> Starting host (spire-agent + app) ..."
# Stash the one-time token in .env so compose injects it into the host service.
if grep -q '^JOIN_TOKEN=' .env; then
  sed -i.bak "s|^JOIN_TOKEN=.*|JOIN_TOKEN=$JOIN_TOKEN|" .env && rm -f .env.bak
else
  printf 'JOIN_TOKEN=%s\n' "$JOIN_TOKEN" >> .env
fi
# Use the pre-built host image from GHCR when available; build from source only
# as a fallback so first-time users skip the multi-minute local build.
if ! $DC pull host 2>/dev/null; then
  echo "    (pre-built image unavailable; building from source)"
  $DC build host
fi
$DC up -d host

echo "==> Waiting for the Workload API socket ..."
for i in $(seq 1 60); do
  if $DC exec -T host test -S /tmp/spire-agent/public/api.sock >/dev/null 2>&1; then
    echo ' ok'; break
  fi
  printf '.'; sleep 1
  if [ "$i" -eq 60 ]; then
    echo; echo "ERROR: Workload API socket never appeared" >&2
    $DC logs --tail=30 host >&2 || true
    exit 1
  fi
done

echo "==> Registering the workload ..."
"$SCRIPT_DIR/register-workload.sh"

echo "==> Waiting for the Workload API to issue SVIDs ..."
for i in $(seq 1 30); do
  if $DC exec -T host spire-agent api fetch jwt -audience "$JWT_AUDIENCE" \
        -socketPath /tmp/spire-agent/public/api.sock -output json >/dev/null 2>&1; then
    echo ' ok'; break
  fi
  printf '.'; sleep 1
  if [ "$i" -eq 30 ]; then
    echo; echo "    WARN: not issuing SVIDs yet; rerun the app if the first call fails." >&2
  fi
done

cat <<EOF

==> SPIRE is up. Next steps:
  1. Wire Akeyless:   ./bootstrap/setup-akeyless.sh
  2. Read the secret: $DC exec -T host dotnet /app/bin/Release/net8.0/secret-consumer.dll
EOF
