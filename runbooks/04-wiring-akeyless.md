# Wiring Akeyless

The one-time admin step that connects SPIRE to Akeyless. It gives Akeyless the
public key to verify your workloads' SVIDs and creates the role that decides
what each workload may read.

## What the bootstrap does

Run it after SPIRE is up:

```bash
./bootstrap/setup-akeyless.sh
```

Six steps, in order:

1. Dump the SPIRE trust bundle from the running server.
2. Convert it to a standard JWKS with `bootstrap/spiffe-bundle-to-jwks.py`.
3. Create the OAuth2/JWT auth method with that JWKS, so Akeyless can verify SVID
   signatures.
4. Create a least-privilege role bound to the workload's SPIFFE ID, granting
   read on the secret folder.
5. Create the demo secret with a generated value, if it does not already exist.
6. Publish the auth method's access id to `spire/.data/akeyless-access-id` so
   the app can find the auth method at runtime.

It authenticates with a short-lived token (`AKEYLESS_TOKEN`), never a long-lived
key. See [Prerequisites](02-prerequisites.md).

## The objects it creates

| Object | Default path | Purpose |
|---|---|---|
| auth method | `/spiffe/demo/auth` | validates the JWT-SVID against the JWKS |
| role | `/spiffe/demo/reader` | binds the workload's SPIFFE ID; grants read on the secret folder |
| secret | `/spiffe/demo/db-password` | the value the app reads back |

Override the paths with `AKEYLESS_AUTH_METHOD`, `AKEYLESS_ROLE`, and
`AKEYLESS_SECRET` in `.env`. Full detail in
[Configuration](05-configuration.md#akeyless-object-paths).

## How Akeyless verifies the SVID

SPIRE signs JWT-SVIDs with a key whose public half is in the trust bundle. The
bootstrap puts that public key, as a JWKS, onto the auth method. When the
workload presents an SVID, Akeyless checks the signature against that JWKS and
matches the `sub` claim to the role. The conversion step is necessary because
SPIRE's bundle format is not a standard JWKS on its own. See
[Concepts](01-concepts.md#trust-bundle-and-jwks).

## The access id

The Akeyless `/api/v2/auth` endpoint takes the auth method's access id, not its
name. The bootstrap writes that id to `spire/.data/akeyless-access-id`, which the host container
mounts at `/run/spire-data/akeyless-access-id`. The app reads it at runtime, so
the bootstrap can run after the container starts. If the app cannot find it, see
[Troubleshooting](08-troubleshooting.md).

## The demo secret

The bootstrap creates the demo secret with a generated, throwaway value, so no
secret value sits in `.env` or the repo. To use your own secret, create it in
Akeyless directly at the path `AKEYLESS_SECRET` points to; the bootstrap leaves
an existing secret alone. See
[Configuration](05-configuration.md#the-demo-secret).

## Re-running

The bootstrap is idempotent and safe to re-run. It recreates the auth method
with the current bundle every time, which is what you want after the trust root
changes: removing the server volume creates a fresh root, the old JWKS goes stale,
and re-running refreshes it. For production, prefer a public bundle endpoint so
Akeyless tracks rotation without a re-bootstrap. See
[Production](06-production.md#bundle-distribution).

## Who can do what

The bootstrap is the provisioning identity: it creates the auth method, the
role, and the secret. The workload only reads. That split, and the capability
set for each, is covered in
[Production](06-production.md#who-provisions-and-who-reads) and
[Prerequisites](02-prerequisites.md#required-akeyless-permissions).

## Cleanup

`spire/down.sh` removes the SPIRE containers and volumes but leaves the Akeyless
auth method, role, and secret in your account. To remove them:

```bash
GATEWAY="${AKEYLESS_GATEWAY%/}"
T="$AKEYLESS_TOKEN"
curl -s -X POST "$GATEWAY/api/v2/delete-item" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AKEYLESS_SECRET\",\"token\":\"$T\"}"
curl -s -X POST "$GATEWAY/api/v2/delete-role" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AKEYLESS_ROLE\",\"token\":\"$T\"}"
curl -s -X POST "$GATEWAY/api/v2/delete-auth-method" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$AKEYLESS_AUTH_METHOD\",\"token\":\"$T\"}"
curl -s -X POST "$GATEWAY/api/v2/delete-item" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$SVID_STORE_TARGET_FOLDER\",\"token\":\"$T\"}"
```

You can also remove them through the Akeyless console.

Next: [Configuration](05-configuration.md)
