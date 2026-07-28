# Troubleshooting

Categorized failure modes for this integration, each with a cause and a fix.
Find the entry whose symptom matches your error.

## The SPIRE server will not start

### `Bind for 0.0.0.0:8081 failed: port is already allocated`

**Cause.** Another spire-server, from this repo or another project, is already
bound to port 8081.

**Fix.** Stop the other container with `docker ps | grep spire-server` and then
`docker stop <name>`. Alternatively, change this server's `bind_port` and the
agent's `server_port` to a distinct value.

### The server crashes with `unable to open database file: no such file or directory`

**Cause.** The official SPIRE server image runs as uid 1000, but named Docker
volumes are owned by root, so the server cannot write its SQLite store.

**Fix.** Run the dev server as root. The compose file sets `user: "0:0"` on the
spire-server service for exactly this reason, so if you removed it, restore it.
This is a dev-only concession. In production, own the volume as uid 1000 and
drop privileges instead.

### The host image build fails pulling `docker/dockerfile:1`

**Cause.** A `# syntax=docker/dockerfile:1` directive in a Dockerfile forces
BuildKit to pull that frontend image from Docker Hub. The build fails when the
network cannot reach Docker Hub.

**Fix.** Remove the directive so the build uses the built-in frontend and works
offline. The Dockerfiles in this repo do not use the directive, so this only
applies if you added one.

## The agent cannot issue SVIDs

### `no identity issued` right after registering the workload

**Cause.** A timing race. The agent has not finished processing the new
registration entry when the workload first asks for an SVID.

**Fix.** Retry the fetch after a second or two. `spire/up.sh` waits until the
Workload API is issuing SVIDs before it finishes, so this should not happen on
a fresh `up.sh` run.

### The agent logs `nodeattestor(join_token): join token was not provided`

**Cause.** The official `spire-agent` image's entrypoint already includes the
`run` subcommand. Passing `docker run ... spire-agent run -config ...` duplicates
it, and the `-joinToken` flag is never parsed.

**Fix.** Do not pass `run` yourself. Run the image with just the flags, or, for
subcommands such as `api fetch jwt`, override the entrypoint:
`docker run --entrypoint /opt/spire/bin/spire-agent ... api fetch jwt ...`.

### The agent logs `could not resolve caller information` and the fetch fails with a broken pipe

**Cause.** The Unix workload attestor cannot see the calling process across
separate container PID namespaces, so the agent cannot tell which workload is
calling.

**Fix.** Run the agent and the workload with the host PID namespace, using
`--pid host`, so the attestor can see host-side processes. `agent/deploy-agent.sh`
and the reference setup already do this.

### `invalid agent ID ... path is in the reserved namespace`

**Cause.** The agent's SPIFFE ID used the reserved `/spire/` path, which SPIRE
reserves for the server.

**Fix.** Use a path outside the reserved namespace, for example
`spiffe://example.org/agent/host`.

### Clients cannot find the socket, which is at `/tmp/spire-agent/api.sock`

**Cause.** The SPIFFE standard Workload API socket is
`/tmp/spire-agent/public/api.sock`, which client libraries and the CLI resolve
by default. A socket at a different path is not found.

**Fix.** Mount the socket directory at `/tmp/spire-agent/public` so the socket
lands at the standard path. `deploy-agent.sh` defaults to this.

## Akeyless auth method, bundle, and JWT problems

### `auth-method create oauth2` fails: `jwks-uri must be set when using gateway-url`

**Cause.** Passing `--gateway-url` together with an inline `--jwks-json-data`
JWKS is rejected. Akeyless wants either an inline JWKS or a `--jwks-uri` it can
fetch at runtime, not both with a gateway URL.

**Fix.** Omit `--gateway-url` for the inline-JWKS create. The token carries its
own gateway. `bootstrap/setup-akeyless.sh` does this. If you want runtime
fetch instead, set `SPIRE_BUNDLE_ENDPOINT` and the bootstrap uses `--jwks-uri`.

### Signature verification fails on a valid JWT-SVID with `InvalidSignature`

**Cause.** JWT ES256 signatures are raw `r||s` form, but many crypto libraries,
including Go's and Python's `cryptography`, expect a DER-encoded signature.

**Fix.** Convert the raw signature to DER before verifying.
`bootstrap/verify-svid.sh` wraps the signature with `encode_dss_signature`
before checking it.

### Dumping the bundle as JWKS fails with `InvalidArgument desc = invalid format`

**Cause.** `spire-server bundle show -format jwks` is not a valid format in
current SPIRE. The SPIFFE bundle lists JWT signing keys as base64
SubjectPublicKeyInfo blobs, not standard JWKs.

**Fix.** Dump with `-format spiffe -output json` and convert with
`bootstrap/spiffe-bundle-to-jwks.py`, which emits a standard `{"keys":[...]}`
JWKS for the auth method. `setup-akeyless.sh` does this for you.

### `auth` fails after recreating the SPIRE stack with `401 AuthenticationFailed`

**Cause.** Removing the server volume minted a fresh trust root, so the auth
method holds a stale JWKS from the old root.

**Fix.** Re-run `./bootstrap/setup-akeyless.sh`. It re-dumps the bundle from
the running server and recreates the auth method with the current JWKS. Do not
reuse a cached bundle file.

### `akeyless auth` reports `undefined option --auth-method-name`

**Cause.** The CLI `auth` command does not accept `--auth-method-name`. It needs
the auth method's access id.

**Fix.** Use `akeyless auth --access-id <p-...> --access-type jwt --jwt <svid>`.
The bootstrap writes the access id to `spire/.data/akeyless-access-id`, and the
app reads it from there.

## Token and access-id problems

### The app fails with `access id is required`

**Cause.** The host container was created before the bootstrap wrote the access
id, and container environment is fixed at creation time, so the app's
`AKEYLESS_ACCESS_ID` was empty.

**Fix.** The app reads the access id from a mounted file at
`/run/spire-data/akeyless-access-id` at runtime, which works regardless of
container start order. Re-run `./bootstrap/setup-akeyless.sh`, then run the app
again.

### `failed to get credentials ... InvalidCredentials` or `credentials have expired`

**Cause.** The short-lived token in `AKEYLESS_TOKEN` expired. Tokens are
short-lived by design.

**Fix.** Re-mint a token with `akeyless auth ...` and update `AKEYLESS_TOKEN`
in `.env`.

### A secret scanner flags a hardcoded value

**Cause.** A hardcoded, secret-shaped literal passed to `create-secret --value`
reads as a hardcoded secret to scanners such as GitGuardian.

**Fix.** The bootstrap generates the demo payload in Akeyless itself, as
`spiffe-demo-` plus a timestamp, so nothing secret-shaped is committed. Never
hardcode a secret-shaped literal.

## TLS and certificate errors

### A self-signed or internal gateway fails with a TLS or certificate error

**Cause.** The app calls the Akeyless REST API over HTTPS with strict TLS. A
self-signed or internal gateway CA is not trusted, so the handshake fails. The
`akeyless` CLI on the admin host tolerates self-signed certificates, but the
app's HTTP client does not.

**Fix.** Set `AKEYLESS_CA_CERT` to a PEM CA certificate file so the app's HTTP
client trusts the gateway CA. Pass it to the app at exec time, because the host
service does not inject it automatically. For strict-TLS clients such as the
Upstream Authority plugin, set its `custom_ca_bundle` field to the same CA
file. A publicly trusted gateway needs no CA file.

### Akeyless calls hit the wrong endpoint, or fail with `Missing required parameter - AccessId`

**Cause.** The auth endpoint is `/api/v2/auth`, not `/auth`. A gateway URL
without the `/api/v2` path lands on the wrong endpoint.

**Fix.** Include `/api/v2` in the gateway URL, for example
`https://your-gateway/api/v2`.

### The PKI issuer rejects the SPIRE CA with `not part of allowed URI SANs list`

**Cause.** The SPIRE CA carries the trust-domain root URI SAN, for example
`spiffe://example.org`, and an `allowed-uri-sans` of `spiffe://example.org/*`
does not match the bare root.

**Fix.** Include the root in the issuer's allowed URI SANs, for example
`spiffe://example.org,spiffe://example.org/*`.

## Docker, environment, and publishing problems

### `docker compose up` errors: `required variable JOIN_TOKEN is missing a value`

**Cause.** `docker compose` interpolates `${VAR:?msg}` for every service at
parse time, even services you have not started yet. The compose file leaves
`JOIN_TOKEN` empty on purpose, and enforces its presence at runtime.

**Fix.** Always start with `./spire/up.sh`, which mints the token and writes it
to `.env`.

### A bind mount resolves against the project directory instead of the compose file

**Cause.** A relative bind path such as `./server.conf` resolves against the
`--project-directory`, so it points at the repo root instead of `spire/`, and
Docker creates a directory at the mount point instead of mounting the file.

**Fix.** Reference paths relative to the project directory, for example
`./spire/server.conf`, and keep `--project-directory` pointed at the repo root.

### A build context of `..` fails with `--project-directory`

**Cause.** With `--project-directory .`, a `build.context` of `..` resolves to
the parent of the repo root, so the Dockerfile is not found.

**Fix.** Use `build.context: .` for the repo root.

### Publishing to GHCR returns `403 Forbidden`

**Cause.** A manually pushed package is unlinked and user-owned, so the
repo-scoped `GITHUB_TOKEN` in CI cannot write to it.

**Fix.** Build and publish through the CI workflow so the package is
repo-linked and public, and name images under the repo namespace, for example
`ghcr.io/<owner>/<repo>/agent`.

## Intermittent infrastructure failures

### `Could not resolve host` or `server misbehaving` for github.com, ghcr.io, or vault-ro.akeyless.io

**Cause.** Transient DNS or network flakiness on the host, not a repo problem.

**Fix.** Retry. These resolve on their own. If a step depends on them, retry it
a few times before assuming the repo is at fault.
