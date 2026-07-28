# Runtime Authentication to Akeyless with SPIFFE / SPIRE

A runnable reference for authenticating an on-premises workload to Akeyless with a SPIRE-issued JWT-SVID and reading a secret. The workload holds no credential of any kind. On each run it fetches a fresh identity document from the SPIRE Workload API, trades it for a short-lived Akeyless token, and reads the secret. Nothing secret is stored on disk.

This README is the landing page. It tells you what the repo is, gets you through a working demo, and points you at the [runbooks](runbooks/) for the full explanation. If any term below is new to you, read [Concepts you need first](runbooks/01-concepts.md) before the quick start. It defines every piece in plain language.

## Why use this

- Zero secret material on the host. There is no token file and no API key at rest.
- Workloads prove who they are instead of carrying a credential.
- Identities are short-lived and audience-bound, so they expire on their own and cannot be replayed elsewhere.
- A workload's authority is scoped to a single secret path by a role bound to its identity.

## How it works

```mermaid
sequenceDiagram
    participant App as Workload (.NET)
    participant Agent as spire-agent
    participant Server as spire-server
    participant AKL as Akeyless Gateway
    Agent->>Server: attest (join token)
    Server-->>Agent: agent SVID + bundle
    App->>Agent: fetch JWT-SVID (audience=akeyless)
    Agent-->>App: JWT-SVID (sub=spiffe://..., ttl minutes)
    App->>AKL: auth (access-id, jwt=SVID)
    AKL-->>App: Akeyless token
    App->>AKL: get-secret-value (token)
    AKL-->>App: secret value
```

SPIRE vouches for the workload and hands it a short-lived JWT-SVID. The workload trades that SVID for an Akeyless token and reads the secret. The SVID lives only in memory for the call. Each piece is defined in [Concepts](runbooks/01-concepts.md).

## Alternatives

This repo is the SPIFFE/SPIRE counterpart to [akeyless-uid-runtime-auth](https://github.com/Fahmy-Kadiri-akl/akeyless-uid-runtime-auth), which solves the same problem with Akeyless Universal Identity.

| Concern | Universal Identity | SPIFFE / SPIRE |
|---|---|---|
| Credential on the host | A token file, rotated every few minutes | None. The SVID lives only in memory for the call. |
| Rotation mechanism | A systemd timer you install and operate | The SPIRE Workload API, at fetch time |
| Bootstrap material | One admin-generated token planted on the host | None. The workload is attested by SPIRE selectors. |
| Operational dependencies | Akeyless only | SPIRE server and agent, plus Akeyless |
| Best when | You want rotation without deploying SPIRE | You can run SPIRE and want zero on-disk credentials |

## Prerequisites

- Docker with the Compose v2 plugin. Verify with `docker compose version`.
- The Akeyless CLI on the admin host, used to mint a token and run the bootstrap.
- A short-lived Akeyless token starting with `t-`, with permission to create auth methods, roles, and secrets.
- Your Akeyless API gateway URL, reachable from the host running the app.

For install commands, token minting, and the exact capabilities the token needs, see [Prerequisites](runbooks/02-prerequisites.md).

## Quick start

Run every command from the repository root. [Runbook 03](runbooks/03-quick-start.md) walks through the same steps with full explanations.

### 1. Clone

```bash
git clone https://github.com/Fahmy-Kadiri-akl/akeyless-spiffe-runtime-auth.git
cd akeyless-spiffe-runtime-auth
```

### 2. Configure

```bash
cp spire/spire.env.example .env
```

Edit `.env` and set two values:

```
AKEYLESS_GATEWAY=https://your-account.akeyless.cloud/api/v2
AKEYLESS_TOKEN=<your-temp-token-from-akeyless-auth>
```

Everything else in `.env` sits under `# ---- advanced ----` and already has defaults that work for the demo. Leave it as-is. What each value means, including what it would mean in production, is in the [Configuration reference](runbooks/04-configuration.md).

### 3. Start SPIRE

```bash
./spire/up.sh
```

The script ends with `==> SPIRE is up.`

### 4. Wire Akeyless

```bash
./bootstrap/setup-akeyless.sh
```

The script ends with `[setup] done.`

### 5. Read the secret

```bash
docker compose --project-directory . -f spire/docker-compose.yml exec host \
  dotnet /app/bin/Release/net8.0/secret-consumer.dll
```

The app prints:

```
[1/3] Fetching JWT-SVID (audience=akeyless) from /tmp/spire-agent/public/api.sock ...
      got SVID (330 bytes), sub=spiffe://example.org/ns/default/sa/secret-consumer, exp=...
[2/3] Authenticating to Akeyless at https://your-account.akeyless.cloud/api/v2/auth ...
      got Akeyless token (35 bytes)
[3/3] Reading secret /spiffe/demo/db-password ...
      secret value: spiffe-demo-<timestamp>
```

Re-run the command any time. Each run fetches a fresh SVID.

### Tear down

```bash
./spire/down.sh
```

If a step fails, find the matching error in [Troubleshooting](runbooks/07-troubleshooting.md).

## Where to go next

| Goal | Guide |
|---|---|
| Understand SPIFFE, SPIRE, SVIDs, trust domains, and audience | [Concepts](runbooks/01-concepts.md) |
| Verify your environment and permissions | [Prerequisites](runbooks/02-prerequisites.md) |
| The quick start with full explanations | [Quick start runbook](runbooks/03-quick-start.md) |
| Understand every value in `.env`, including TTLs and production implications | [Configuration reference](runbooks/04-configuration.md) |
| Move from the demo to production, including per-environment trust domains | [Production hardening](runbooks/05-production.md) |
| Run an agent for your own app, host, or language | [Deploying agents](runbooks/06-deploying-agents.md) |
| Diagnose a failure | [Troubleshooting](runbooks/07-troubleshooting.md) |
| See X.509-SVID mTLS between two workloads (optional) | [X.509 mTLS demo](runbooks/08-x509-mtls.md) |

## Security model

No credential is written to disk. The SVID lives only in memory for the call, is short-lived and audience-bound, and replaying it after expiry fails and is recorded in the Akeyless audit log. The workload's authority comes from the Akeyless role bound to its SPIFFE ID, not from the SVID itself.

A compromised host is not stopped in real time: an attacker running code as the workload's UID can fetch valid SVIDs for as long as they hold that position. The defense is detection and revocation, which the short SVID lifetime and audit log make possible. For the full model and its limits, see [Production hardening](runbooks/05-production.md).

## Repository layout

```
spire/                         dev SPIRE topology and orchestration
  docker-compose.yml           spire-server and host services
  server.conf                  dev trust domain, self-signed CA, lifetimes
  agent.conf                   Workload API socket, bootstrap
  Dockerfile.host              .NET 8 app + spire-agent + the Go X.509 mTLS demo pair
  up.sh / down.sh              start and tear down the stack
  register-workload.sh         register the workload by Unix UID
  spire.env.example            template for .env
bootstrap/                     one-time Akeyless wiring
  setup-akeyless.sh            create auth method, role, demo secret
  spiffe-bundle-to-jwks.py     convert the SPIRE bundle into a JWKS
  verify-svid.sh               decode and validate a JWT-SVID
agent/                         portable, app-agnostic SPIRE agent
  Dockerfile.agent             slim agent image, no application
  agent-entrypoint.sh          renders agent config from env, runs the agent
  deploy-agent.sh              deploy the agent on a workload host
app/                           .NET 8 reference workload
  Program.cs                   fetch SVID, authenticate, read secret
  SecretConsumer.csproj
mtls/                          X.509-SVID mTLS demo (Go + go-spiffe)
  server/ client/              mTLS pair that proves two workloads to each other
  demo.sh                      in-container demo runner
  run-mtls.sh                  host-side entry point: register workloads and run
runbooks/                      beginner guides: concepts, setup, production, troubleshooting
```

## License

MIT.
