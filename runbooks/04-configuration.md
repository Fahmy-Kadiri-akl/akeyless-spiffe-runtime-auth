# Configuration reference

Every value you can set lives in `.env`, copied from `spire/spire.env.example`.
This guide explains each one: what it is, what the demo default is, and what it
would mean in production. For the demo you only set `AKEYLESS_GATEWAY` and
`AKEYLESS_TOKEN`. The rest already has working defaults.

## Required

| Variable | What it is |
|---|---|
| `AKEYLESS_GATEWAY` | The Akeyless API gateway the app calls to trade the SVID for a token and read secrets. Must include the `/api/v2` path, for example `https://your-account.akeyless.cloud/api/v2`. |
| `AKEYLESS_TOKEN` | A short-lived token, starting with `t-`, that authenticates the bootstrap. This is the only way the bootstrap authenticates, and a missing token is a hard failure. Mint one with `akeyless auth` and let it expire. |

`AKEYLESS_ACCESS_ID` is the access id of the auth method the bootstrap creates.
You do not set it. The bootstrap writes it into `.env` and into
`spire/.data/akeyless-access-id`, and the app reads it from there at runtime.

## Trust domain and identity

| Variable | Default | What it is |
|---|---|---|
| `SPIFFE_TRUST_DOMAIN` | `example.org` | The trust domain. The boundary of trust. `spire/up.sh` renders it into the server and agent configs, and the agent and workload SPIFFE IDs are built from it. |
| `WORKLOAD_SPIFFE_ID` | `spiffe://example.org/ns/default/sa/secret-consumer` | The identity the workload is registered under and bound to in the Akeyless role. |
| `JWT_AUDIENCE` | `akeyless` | The audience claim the SVID must carry, and that Akeyless requires. |

These three are the heart of the identity model. The detail is in
[Concepts](01-concepts.md). The production implications, in short:

- `SPIFFE_TRUST_DOMAIN` is a label you choose, not a real domain. In production
  pick a unique name per environment and keep production and development in
  separate trust domains, so an identity from one is never trusted in the other.
  Do not reuse `example.org` outside the demo. Changing it on a running
  deployment rewrites every SPIFFE ID and breaks every registration and role
  binding, so set it once when you stand the environment up.
- `WORKLOAD_SPIFFE_ID` names the workload. In production give each workload a
  distinct, readable path so roles and audit logs are unambiguous.
- `JWT_AUDIENCE` scopes a token to a consumer. Keep it specific per downstream
  rather than sharing one broad audience, so a token stolen from one path
  cannot be replayed against another.

## Lifetimes

SPIRE issues identities and keys on fixed cadences. These are the defaults and
what renews each one:

| Lifecycle | Default | Renewal |
|---|---|---|
| JWT-SVID | 5 minutes | Fetched fresh on every run. The app requests a new one each call, so it is never stored or rotated. |
| X.509-SVID | 1 hour | Auto-renewed by spire-agent before expiry. Used by the mTLS demo. |
| Agent SVID | 1 hour | Auto-renewed by spire-agent before expiry. |
| Trust-root CA and JWT signing key | 24 hours | Rotated by spire-server on this cadence. |

You can override the JWT-SVID, X.509-SVID, and CA lifetimes in `.env`. Values
are Go duration strings like `5m`, `1h`, `24h`, and `spire/up.sh` renders them
into the SPIRE configs so a change propagates end to end.

| Variable | Default | What it controls |
|---|---|---|
| `JWT_SVID_TTL` | `5m` | Lifetime of each JWT-SVID. Shorter tightens the anti-theft window, because a stolen SVID stops working sooner. |
| `X509_SVID_TTL` | `1h` | Lifetime of each X.509-SVID, used by the mTLS demo. The go-spiffe library refreshes each one before expiry. |
| `CA_TTL` | `24h` | Lifetime of the trust-root CA and JWT signing key before SPIRE rotates them. |

The agent SVID lifetime is not exposed as a variable. It stays at SPIRE's one
hour and is renewed by the agent. See [X.509-SVID mTLS](08-x509-mtls.md) to run
the X.509 path, and [SVIDs](01-concepts.md#svids-the-identity-document) for why
the Akeyless path itself is JWT-only.

When SPIRE rotates its JWT signing key on the CA cadence, the inline JWKS stored
on the Akeyless auth method goes stale, and SVIDs are rejected until you re-run
`bootstrap/setup-akeyless.sh`. Setting `SPIRE_BUNDLE_ENDPOINT` to a public
bundle endpoint makes Akeyless track that rotation automatically, so you do not
need to re-run the bootstrap after each rotation.

## Akeyless object paths

These are the paths in your Akeyless account that the bootstrap creates.

| Variable | Default | What it is |
|---|---|---|
| `AKEYLESS_AUTH_METHOD` | `/spiffe/demo/auth` | The OAuth2/JWT auth method that validates the SVID. |
| `AKEYLESS_ROLE` | `/spiffe/demo/reader` | The role bound to the workload's SPIFFE ID, granting read on the secret folder. |
| `AKEYLESS_SECRET` | `/spiffe/demo/db-password` | The demo secret path. The role rule is derived from this path's folder. |
| `SPIRE_BUNDLE_ENDPOINT` | empty | Optional public JWKS URL. When set, Akeyless fetches the bundle at runtime instead of using the inline JWKS, and tracks rotation automatically. |

In production, scope these paths to your own folder structure. Every path
follows the variables, so a non-default folder only needs the rules scoped to
that folder. See [Required Akeyless permissions](02-prerequisites.md#required-akeyless-permissions).

## The demo secret lives in Akeyless, not in `.env`

The demo secret is the payload the app reads back to prove the flow worked. The
bootstrap generates an ephemeral value, `spiffe-demo-` plus a timestamp, and
writes it into Akeyless directly. There is no secret-shaped value in `.env` or
in the repo. You do not set it.

In production you provision your own secret in Akeyless through the console or
the admin CLI, and point `AKEYLESS_SECRET` at that path. The app reads it at
runtime from Akeyless. The bootstrap leaves an existing secret alone, because
`create-secret` no-ops when the path already exists.

## TLS and self-signed gateways

The app calls the Akeyless REST API over HTTPS with strict TLS. If your gateway
uses a self-signed or internal certificate, the app's HTTP client will not trust
it and the call fails. Set `AKEYLESS_CA_CERT` to a PEM CA certificate file so
the client trusts the gateway:

```
AKEYLESS_CA_CERT=/path/to/ca.pem
```

The app reads `AKEYLESS_CA_CERT` from its environment. The docker-compose host
service does not inject it automatically, so pass it when you run the app:

```bash
docker compose --project-directory . -f spire/docker-compose.yml exec \
  -e AKEYLESS_CA_CERT=/path/to/ca.pem host \
  dotnet /app/bin/Release/net8.0/secret-consumer.dll
```

Mount the CA file into the container first if it is not already reachable
inside it. A publicly trusted gateway needs no CA file. The same CA is needed
by any strict-TLS client, including the SPIRE Upstream Authority plugin, which
takes it through its `custom_ca_bundle` field.

## How the app calls Akeyless

The .NET app fetches the SVID from the Workload API through the `spire-agent`
CLI, because there is no mature .NET SPIFFE Workload API client. It then calls
the Akeyless REST API directly with `HttpClient`:

1. `POST {gateway}/api/v2/auth` with
   `{"access-type":"jwt","access-id":<auth-method-access-id>,"jwt":<svid>}` to
   get an Akeyless token.
2. `POST {gateway}/api/v2/get-secret-value` with
   `{"names":[<secret-path>],"token":<token>}` to read the secret.

The full endpoint reference is in the
[Akeyless Postman collection](https://github.com/Fahmy-Kadiri-akl/akeyless-postman-collection).

## Notes

- The host container's environment is fixed at creation time. If you change
  `.env` after starting the stack, restart the host container, or re-run
  `up.sh`, so the new values are picked up. The auth-method access id is the
  exception: the app reads it from a mounted file at runtime, so it works even
  if the container started before the bootstrap ran.
- `SPIFFE_WORKLOAD_SOCKET` defaults to `/tmp/spire-agent/public/api.sock`. You
  do not normally change it.
