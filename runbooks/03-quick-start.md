# Quick start

Get a secret end to end on one host. Every command runs from the repository
root. This mirrors the README quick start and explains each step.

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

You do not set a demo value. The bootstrap generates one in Akeyless.

## 2. Start SPIRE

```bash
./spire/up.sh
```

The script ends with `==> SPIRE is up.` It starts the spire-server,
starts the spire-agent with a one-time join token, waits until the Workload API
is issuing SVIDs, and registers the workload. The `host` image is pulled
pre-built from GHCR; you only build from source if you change the app.

Always start with `./spire/up.sh`, never plain `docker compose up`, because
`up.sh` also generates the join token and registers the workload.

## 3. Wire Akeyless

```bash
./bootstrap/setup-akeyless.sh
```

The script ends with `[setup] done.` It dumps the SPIRE trust bundle,
converts it to a standard JWKS, creates the OAuth2/JWT auth method, creates a
least-privilege role bound to the workload's SPIFFE ID, creates the demo
secret, and publishes the auth-method access id to
`spire/.data/akeyless-access-id`. It is safe to re-run; it recreates the auth
method with the current bundle each time.

## 4. Read the secret

```bash
docker compose --project-directory . -f spire/docker-compose.yml exec host \
  dotnet /app/bin/Release/net8.0/secret-consumer.dll
```

The app prints three steps:

```
[1/3] Fetching JWT-SVID (audience=akeyless) from /tmp/spire-agent/public/api.sock ...
      got SVID (330 bytes), sub=spiffe://example.org/ns/default/sa/secret-consumer, exp=...
[2/3] Authenticating to Akeyless at https://your-account.akeyless.cloud/api/v2/auth ...
      got Akeyless token (35 bytes)
[3/3] Reading secret /spiffe/demo/db-password ...
      secret value: spiffe-demo-<timestamp>
```

Re-run the command any time; each run fetches a fresh SVID. This proves the
workload authenticated with a SPIRE-issued SVID and read the secret. The app
fetches the SVID from the Workload API, then calls the Akeyless REST API
directly with `HttpClient` to authenticate and read the secret. The demo
payload lives in Akeyless. For the full endpoint reference, see the
[Akeyless Postman collection](https://github.com/Fahmy-Kadiri-akl/akeyless-postman-collection).

## Tear down

```bash
./spire/down.sh
```

If anything in these steps fails, go to
[07-troubleshooting.md](07-troubleshooting.md) and find the matching error.
