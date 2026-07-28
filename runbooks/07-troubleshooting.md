# Troubleshooting

Categorized failure modes for this integration, with diagnoses and fixes. Find
the closest match to your error.

## SPIRE server won't start

### `Bind for 0.0.0.0:8081 failed: port is already allocated`

Diagnosis: another spire-server (from this repo or another project) is already
bound to port 8081.

Fix: stop the other container (`docker ps | grep spire-server`, then
`docker stop <name>`), or change this server's `bind_port` and the agent's
`server_port` to a distinct value.

### Server crashes with `unable to open database file: no such file or directory`

Diagnosis: the official SPIRE server image runs as uid 1000, but named Docker
volumes mount root-owned, so the server cannot write its SQLite store.

Fix: run the dev server as root (`user: "0:0"` in `spire/docker-compose.yml`).
This is a dev-only concession; production should own the volume as uid 1000 and
drop privileges.

### Host image build fails pulling `docker/dockerfile:1`

Diagnosis: the `# syntax=docker/dockerfile:1` line forces buildkit to pull the
frontend image from Docker Hub, which fails when the network cannot reach it.

Fix: remove the directive so the build uses the built-in frontend and works
offline. If you re-add it, you need Docker Hub access.

## Agent cannot issue SVIDs

### `no identity issued` right after registering a workload

Diagnosis: timing race. The agent has not finished processing the new
registration entry when the workload first asks for an SVID.

Fix: retry the fetch after a second or two. `spire/up.sh` waits until the
Workload API is issuing SVIDs before it finishes, so this should not happen on
a fresh `up.sh`.

### Agent logs `nodeattestor(join_token): join token was not provided`

Diagnosis: the official `spire-agent` image's entrypoint already includes the
`run` subcommand, so `docker run ... spire-agent run -config ...` duplicates it
and the `-joinToken` flag is never parsed.

Fix: do not pass `run` yourself. Either run the image with just the flags, or
for subcommands like `api fetch jwt`, override the entrypoint:
`docker run --entrypoint /opt/spire/bin/spire-agent ... api fetch jwt ...`.

### Agent logs `could not resolve caller information` and the fetch fails with a broken pipe

Diagnosis: the unix workload attestor cannot see the calling process across
separate container PID namespaces. The agent cannot tell which workload is
calling.

Fix: run the agent and the workload with the host PID namespace (`--pid host`)
so the attestor can see host-side processes. `agent/deploy-agent.sh` and the
reference setup already do this.

### `invalid agent ID ... path is in the reserved namespace`

Diagnosis: the agent's SPIFFE ID used the reserved `/spire/` path, which SPIRE
reserves for the server.

Fix: use a path outside the reserved namespace, for example
`spiffe://example.org/agent/host`.

### Socket is at `/tmp/spire-agent/api.sock` but clients cannot find it

Diagnosis: the SPIFFE standard Workload API socket is
`/tmp/spire-agent/public/api.sock`, which client libraries and the CLI resolve
by default. A socket at a different path is not found.

Fix: mount the socket directory at `/tmp/spire-agent/public` so the socket
lands at the standard path. `deploy-agent.sh` defaults to this.

## Akeyless auth method, bundle, and JWT problems

### `auth-method create oauth2` fails: `jwks-uri must be set when using gateway-url`

Diagnosis: passing `--gateway-url` together with an inline `--jwks-json-data`
JWKS is rejected. Akeyless wants a `--jwks-uri` to fetch at runtime instead.

Fix: omit `--gateway-url` for the inline-JWKS create. The profile or token
already carries the gateway. `bootstrap/setup-akeyless.sh` does this.

### Signature verification fails on a valid JWT-SVID (`InvalidSignature`)

Diagnosis: JWT ES256 signatures are raw `r||s` form, but many crypto libraries,
including Go's and Python's `cryptography`, expect a DER-encoded signature.

Fix: convert raw to DER before verifying. `bootstrap/verify-svid.sh` wraps the
signature with `encode_dss_signature` before checking it.

### `InvalidArgument desc = invalid format` dumping the bundle as JWKS

Diagnosis: `spire-server bundle show -format jwks` is not a valid format in
current SPIRE. The spiffe bundle lists JWT signing keys as base64
SubjectPublicKeyInfo blobs, not standard JWKs.

Fix: dump with `-format spiffe -output json` and convert with
`bootstrap/spiffe-bundle-to-jwks.py`, which emits a standard `{"keys":[...]}`
JWKS for the Akeyless auth method.

### Auth fails after recreating the SPIRE stack (`401 AuthenticationFailed`)

Diagnosis: a fresh trust root was minted when the server volume was removed, so
the auth method holds a stale JWKS from the old root.

Fix: `bootstrap/setup-akeyless.sh` re-dumps the bundle from the running server
and recreates the auth method with the current JWKS. Re-run it; do not reuse a
cached bundle file.

### `akeyless auth` reports `undefined option --auth-method-name`

Diagnosis: the CLI `auth` command does not accept `--auth-method-name`. It
needs the auth method's access id.

Fix: use `akeyless auth --access-id <p-...> --access-type jwt --jwt <svid>`.
The bootstrap writes the access id to `spire/.data/akeyless-access-id` and the
app reads it from there.

## Token and access-id problems

### App fails with `access id is required`

Diagnosis: the host container was created before the bootstrap wrote the access
id, so the app's `AKEYLESS_ACCESS_ID` was empty. Container env is fixed at
creation time and does not see later `.env` edits.

Fix: the bootstrap writes the access id to `spire/.data/akeyless-access-id`,
mounted into the host at `/run/spire-data`, and the app reads it at runtime.
Re-run `bootstrap/setup-akeyless.sh`, then the app.

### `failed to get credentials ... InvalidCredentials` / `credentials have expired`

Diagnosis: the short-lived token in `AKEYLESS_TOKEN` expired. Tokens are
short-lived by design.

Fix: re-mint a token with `akeyless auth ...` and update `.env`.

### Secret scanner flags a hardcoded value

Diagnosis: a hardcoded secret-shaped literal passed to `create-secret --value`
reads as a hardcoded secret to scanners like GitGuardian.

Fix: the bootstrap generates the demo payload in Akeyless itself. Never
hardcode any secret-shaped literal.

## TLS and certificate errors

### Self-signed or internal gateway: app fails with a TLS or certificate error

Diagnosis: the app calls the Akeyless REST API over HTTPS with strict TLS. A
self-signed or internal gateway CA is not trusted, so the TLS handshake fails.
The akeyless CLI on the admin host tolerates self-signed certs, but the app's
HTTP client does not.

Fix: set `AKEYLESS_CA_CERT` to a PEM CA certificate file so the app's HTTP
client trusts the gateway CA. For strict-TLS clients such as the Upstream
Authority plugin, set its `custom_ca_bundle` field to the same CA cert file. A
publicly trusted gateway needs no CA file.

### Akeyless auth or plugin calls hit the wrong endpoint

Diagnosis: the auth endpoint is `/api/v2/auth`, not `/auth`. A gateway URL
without the `/api/v2` path lands on the wrong endpoint and returns
`Missing required parameter - AccessId`.

Fix: include `/api/v2` in the gateway URL, for example
`https://your-gateway/api/v2`.

### PKI issuer rejects the SPIRE CA: `not part of allowed URI SANs list`

Diagnosis: the SPIRE CA carries the trust-domain root URI SAN, for example
`spiffe://example.org`, and an `allowed-uri-sans` of `spiffe://example.org/*`
does not match the bare root.

Fix: include the root in the issuer's allowed URI SANs, for example
`spiffe://example.org,spiffe://example.org/*`.

## Docker, environment, and publishing problems

### `docker compose up` errors: `required variable JOIN_TOKEN is missing a value`

Diagnosis: `docker compose` interpolates `${VAR:?msg}` for every service at
parse time, even ones you are not starting yet.

Fix: always start with `./spire/up.sh`, which mints the token and writes it to
`.env`. The compose file leaves `JOIN_TOKEN` empty by default and the host
entrypoint enforces its presence at runtime.

### Bind mount source resolves against the project directory, not the compose file

Diagnosis: a relative bind path like `./server.conf` resolves against the
`--project-directory`, so it points at the repo root instead of `spire/`, and
Docker creates a directory at the mount point instead of mounting the file.

Fix: reference paths relative to the project directory, for example
`./spire/server.conf`, and keep `--project-directory` pointed at the repo root.

### Build context `..` fails with `--project-directory`

Diagnosis: with `--project-directory .`, a `build.context: ..` resolves to the
parent of the repo root, so the Dockerfile is not found.

Fix: use `build.context: .` for the repo root.

### Publishing to GHCR returns `403 Forbidden`

Diagnosis: a manually pushed package is unlinked and user-owned, so the
repo-scoped `GITHUB_TOKEN` in CI cannot write to it.

Fix: build and publish through the CI workflow so the package is repo-linked
and public, and name images under the repo namespace, for example
`ghcr.io/<owner>/<repo>/agent`.

## Intermittent infrastructure failures

### `Could not resolve host` or `server misbehaving` for github.com, ghcr.io, or vault-ro.akeyless.io

Diagnosis: transient DNS or network flakiness on the host, not a repo problem.

Fix: retry. These resolve on their own. If a step depends on them, retry it a
few times before assuming the repo is at fault.
