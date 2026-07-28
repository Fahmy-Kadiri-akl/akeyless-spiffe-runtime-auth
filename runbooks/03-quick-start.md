# Quick start

Get a secret end to end on one host. This mirrors the README quick start and
explains what each step does. Every command runs from the repository root.

## 1. Clone and configure

```bash
git clone https://github.com/Fahmy-Kadiri-akl/akeyless-spiffe-runtime-auth.git
cd akeyless-spiffe-runtime-auth
cp spire/spire.env.example .env
```

Edit `.env` and set four values:

```
AKEYLESS_GATEWAY=https://your-account.akeyless.cloud
AKEYLESS_TOKEN=<your-temp-token-from-akeyless-auth>
UPSTREAM_ACCESS_ID=<p-...>
UPSTREAM_ACCESS_KEY=<key>
```

`UPSTREAM_ACCESS_ID` and `UPSTREAM_ACCESS_KEY` authenticate the UpstreamAuthority
plugin to Akeyless PKI. [Create them
first](02-prerequisites.md#creating-the-upstreamauthority-credentials) if you
have not already.

The demo secret is generated in Akeyless by the bootstrap. Everything else
under `# ---- advanced ----` has defaults. See
[Configuration](05-configuration.md) for what each value means.

## 2. Start SPIRE

```bash
./spire/up.sh
```

The script ends with `==> SPIRE is up.` It starts the spire-server, waits for
it to be healthy, creates a one-time join token, starts the host container which
runs the spire-agent, waits for the Workload API socket, registers the
workload, and waits until the agent is issuing SVIDs. The host image is pulled
pre-built from GHCR, so you only build from source if you change the app.

Always start with `./spire/up.sh`, never with plain `docker compose up`. The
compose file leaves `JOIN_TOKEN` empty on purpose, and `up.sh` is what creates
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
ever run `spire/down.sh` and bring the stack back up, the server creates a fresh
root, so you must re-run this step or authentication will fail with a stale
JWKS.

The demo secret defaults to a generated value at `/spiffe/demo/db-password`.
Change the path with `AKEYLESS_SECRET` in `.env`. The value is a secret, so it
is never set in `.env`: to use your own, create it in Akeyless directly and the
bootstrap leaves it alone. See
[Configuration](05-configuration.md#the-demo-secret).

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
time it was created. The path is the demo default, overridable with
`AKEYLESS_SECRET`; the value is generated, so to use your own secret, provision
it in Akeyless directly.

## Tear down

```bash
./spire/down.sh
```

This stops the containers and removes their volumes. The dev CA and keys lived
in those volumes, so the next `up.sh` creates a fresh trust root. After a fresh
root you must re-run `./bootstrap/setup-akeyless.sh`, because the auth method
will hold the old, stale JWKS.

Next: [Wiring Akeyless](04-wiring-akeyless.md)
