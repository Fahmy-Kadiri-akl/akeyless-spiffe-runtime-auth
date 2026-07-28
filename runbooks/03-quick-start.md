# Quick start

Get a secret end to end on one host. This mirrors the README quick start and
explains what each step does. Every command runs from the repository root.

## 1. Clone and configure

```bash
git clone https://github.com/Fahmy-Kadiri-akl/akeyless-spiffe-runtime-auth.git
cd akeyless-spiffe-runtime-auth
cp spire/spire.env.example .env
```

Edit `.env` and set two values:

```
AKEYLESS_GATEWAY=https://your-account.akeyless.cloud/api/v2
AKEYLESS_TOKEN=<your-temp-token-from-akeyless-auth>
```

You do not set a demo secret value. The bootstrap generates one in Akeyless.
Everything under `# ---- advanced ----` has defaults that work for the demo, so
leave it alone for now. What each value means is in
[Configuration](04-configuration.md).

## 2. Start SPIRE

```bash
./spire/up.sh
```

The script ends with `==> SPIRE is up.` It starts the spire-server, waits for
it to be healthy, mints a one-time join token, starts the host container which
runs the spire-agent, waits for the Workload API socket, registers the
workload, and waits until the agent is issuing SVIDs. The host image is pulled
pre-built from GHCR, so you only build from source if you change the app.

Always start with `./spire/up.sh`, never with plain `docker compose up`. The
compose file leaves `JOIN_TOKEN` empty on purpose, and `up.sh` is what mints
the token and registers the workload. If you start with `docker compose up`,
the host container exits immediately with `JOIN_TOKEN is required`.

## 3. Wire Akeyless

```bash
./bootstrap/setup-akeyless.sh
```

The script ends with `[setup] done.` It dumps the SPIRE trust bundle from the
running server, converts it to a standard JWKS, creates the OAuth2/JWT auth
method with that JWKS, creates a least-privilege role bound to the workload's
SPIFFE ID, creates the demo secret in Akeyless, and writes the auth method's
access id to `spire/.data/akeyless-access-id` for the app to read.

This step is safe to re-run. It recreates the auth method with the current
bundle every time, which matters after any change to the trust root. If you
ever run `spire/down.sh` and bring the stack back up, the server mints a fresh
root, so you must re-run this step or authentication will fail with a stale
JWKS.

The demo secret defaults to a generated value at `/spiffe/demo/db-password`. To
use your own, set `AKEYLESS_SECRET` (the path) and `AKEYLESS_DEMO_SECRET` (the
value) in `.env` before running this step. See
[Configuration](04-configuration.md#the-demo-secret-default-and-override).

## 4. Read the secret

```bash
docker compose --project-directory . -f spire/docker-compose.yml exec host \
  dotnet /app/bin/Release/net8.0/secret-consumer.dll
```

This runs the reference app, which reads the secret from Akeyless. It prints
three steps:

```
[1/3] Fetching JWT-SVID (audience=akeyless) from /tmp/spire-agent/public/api.sock ...
      got SVID (330 bytes), sub=spiffe://example.org/ns/default/sa/secret-consumer, exp=...
[2/3] Authenticating to Akeyless at https://your-account.akeyless.cloud/api/v2/auth ...
      got Akeyless token (35 bytes)
[3/3] Reading secret /spiffe/demo/db-password ...
      secret value: spiffe-demo-<timestamp>
```

Re-run the command any time. Each run fetches a fresh SVID, which lives only
for the call. This output is the proof the demo worked: the workload fetched an
SVID, Akeyless accepted it, and the role granted read access to the secret.

The `exp=...` on the first line is the SVID's expiry time as a Unix timestamp.
It is minutes away, which is the anti-theft window. The `spiffe-demo-<timestamp>`
value is the demo payload the bootstrap wrote into Akeyless; the number is the
time it was created. Both the path and the value are demo defaults; override the
path with `AKEYLESS_SECRET` and the value with `AKEYLESS_DEMO_SECRET` in `.env`
before step 3.

## Tear down

```bash
./spire/down.sh
```

This stops the containers and removes their volumes. The dev CA and keys lived
in those volumes, so the next `up.sh` mints a fresh trust root. After a fresh
root you must re-run `./bootstrap/setup-akeyless.sh`, because the auth method
will hold the old, stale JWKS.

## Where to go next

If you want to understand every value in `.env`, including what each one means
in production, read [Configuration](04-configuration.md). If you want to move
this from a demo toward production, read [Production hardening](05-production.md).
If something failed, find the matching error in [Troubleshooting](07-troubleshooting.md).
