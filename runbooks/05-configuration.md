# Configuration reference

Every value lives in `.env`, copied from `spire/spire.env.example`. For the demo
you set only `AKEYLESS_GATEWAY` and `AKEYLESS_TOKEN`; the rest has working
defaults. Each table below says what a value is and what it means in production.

## Required

| Variable | What it is |
|---|---|
| `AKEYLESS_GATEWAY` | Gateway the app calls to trade the SVID for a token and read secrets. Must include `/api/v2`, for example `https://your-account.akeyless.cloud/api/v2`. |
| `AKEYLESS_TOKEN` | Short-lived token, starting with `t-`, that authenticates the bootstrap. The only bootstrap credential; a missing token is a hard failure. Mint one with `akeyless auth` and let it expire. |

`AKEYLESS_ACCESS_ID` is the auth method's access id. You do not set it. The
bootstrap writes it into `.env` and `spire/.data/akeyless-access-id`, and the
app reads it from there at runtime.

## Trust domain and identity

| Variable | Default | What it is |
|---|---|---|
| `SPIFFE_TRUST_DOMAIN` | `example.org` | The trust domain. `spire/up.sh` renders it into the server and agent configs; agent and workload SPIFFE IDs are built from it. |
| `WORKLOAD_SPIFFE_ID` | `spiffe://example.org/ns/default/sa/secret-consumer` | The identity the workload is registered under and bound to in the Akeyless role. |
| `JWT_AUDIENCE` | `akeyless` | The audience claim the SVID must carry and Akeyless requires. |

> [!WARNING]
> `example.org` is the public SPIFFE sample name. Use it only for the demo. In
> production choose a name you control, such as `spiffe.acme.internal`, and use
> a distinct one per environment.

For the model behind these values, see [Concepts](01-concepts.md). For the
production patterns, one trust domain per environment and per business unit, see
[Environments and trust domains](06-production.md#environments-and-trust-domains).
Two rules that catch people:

- Changing `SPIFFE_TRUST_DOMAIN` on a running deployment rewrites every SPIFFE
  ID and breaks every registration and role binding. Set it once per
  environment.
- Give each workload a distinct, readable path so roles and audit logs stay
  unambiguous, and keep audiences specific per downstream so a stolen token
  cannot be replayed against another.

## Lifetimes

SPIRE issues identities and keys on fixed cadences. Defaults and what renews
each one:

| Lifecycle | Default | Renewal |
|---|---|---|
| JWT-SVID | 5 minutes | Fetched fresh on every run; never stored or rotated. |
| X.509-SVID | 1 hour | Auto-renewed by spire-agent before expiry. Used by the mTLS demo. |
| Agent SVID | 1 hour | Auto-renewed by spire-agent before expiry. |
| Trust-root CA and JWT signing key | 24 hours | Rotated by spire-server on this cadence. |

Override the JWT-SVID, X.509-SVID, and CA lifetimes in `.env`. Values are Go
duration strings like `5m`, `1h`, `24h`; `spire/up.sh` renders them into the
SPIRE configs so a change propagates end to end.

| Variable | Default | What it controls |
|---|---|---|
| `JWT_SVID_TTL` | `5m` | Lifetime of each JWT-SVID. Shorter tightens the anti-theft window, because a stolen SVID stops working sooner. |
| `X509_SVID_TTL` | `1h` | Lifetime of each X.509-SVID, used by the mTLS demo. go-spiffe refreshes each one before expiry. |
| `CA_TTL` | `24h` | Lifetime of the trust-root CA and JWT signing key before SPIRE rotates them. |

The agent SVID lifetime is not exposed as a variable; it stays at SPIRE's one
hour and is renewed by the agent.

A tuning example. A captured JWT-SVID works until it expires, so the JWT TTL is
the replay window. The default five minutes is a starting point. A service under
stricter policy might set `JWT_SVID_TTL=2m` to halve that window, at the cost of
more fetches. Shorten the JWT-SVID to tighten the theft window; keep `CA_TTL`
long enough that key rotation is routine rather than frequent.

When SPIRE rotates its JWT signing key on the CA cadence, the inline JWKS on the
Akeyless auth method goes stale, and SVIDs are rejected until you re-run
`bootstrap/setup-akeyless.sh`. Set `SPIRE_BUNDLE_ENDPOINT` to a public bundle
endpoint so Akeyless tracks that rotation automatically.

## Akeyless object paths

Paths in your Akeyless account that the bootstrap creates:

| Variable | Default | What it is |
|---|---|---|
| `AKEYLESS_AUTH_METHOD` | `/spiffe/demo/auth` | The OAuth2/JWT auth method that validates the SVID. |
| `AKEYLESS_ROLE` | `/spiffe/demo/reader` | The role bound to the workload's SPIFFE ID, granting read on the secret folder. |
| `AKEYLESS_SECRET` | `/spiffe/demo/db-password` | The demo secret path. The role rule is derived from this path's folder. |

`SPIRE_BUNDLE_ENDPOINT` is not an Akeyless object; it is the public JWKS URL
SPIRE exposes so Akeyless can track key rotation. See
[Lifetimes](#lifetimes) and [Bundle distribution](06-production.md#bundle-distribution).

Namespace these per environment so each bootstrap touches only its own objects:

| Environment | Auth method | Role | Secret |
|---|---|---|---|
| prod | `/spiffe/prod/auth` | `/spiffe/prod/reader` | `/spiffe/prod/db-password` |
| staging | `/spiffe/staging/auth` | `/spiffe/staging/reader` | `/spiffe/staging/db-password` |
| qa | `/spiffe/qa/auth` | `/spiffe/qa/reader` | `/spiffe/qa/db-password` |
| dev | `/spiffe/dev/auth` | `/spiffe/dev/reader` | `/spiffe/dev/db-password` |

See [Required Akeyless permissions](02-prerequisites.md#required-akeyless-permissions).

## The demo secret

The demo secret proves the flow worked. The bootstrap writes it into Akeyless
directly with a generated, throwaway value, so no secret value sits in `.env` or
the repo.

| What | Default | How to use your own |
|---|---|---|
| secret path | `/spiffe/demo/db-password` | set `AKEYLESS_SECRET` in `.env` |
| secret value | a generated throwaway, `spiffe-demo-<timestamp>` | provision the secret in Akeyless directly |

The path is configuration, so it is overridable in `.env`. The value is a
secret, so it is never set in `.env` or the repo: create it in Akeyless through
the console or the admin CLI at the path `AKEYLESS_SECRET` points to, and the
bootstrap leaves it alone, because `create-secret` only runs when the path does
not already exist.

## TLS and self-signed gateways

The app calls the Akeyless REST API over HTTPS with strict TLS. A self-signed or
internal gateway certificate will not be trusted, and the call fails. Set
`AKEYLESS_CA_CERT` to a PEM CA certificate file so the client trusts the gateway:

```
AKEYLESS_CA_CERT=/path/to/ca.pem
```

The docker-compose host service does not inject this automatically, so pass it
when you run the app:

```bash
docker compose --project-directory . -f spire/docker-compose.yml exec \
  -e AKEYLESS_CA_CERT=/path/to/ca.pem host \
  dotnet /app/bin/Release/net8.0/secret-consumer.dll
```

Mount the CA file into the container first if it is not already reachable inside
it. A publicly trusted gateway needs no CA file. Any strict-TLS client needs the
same CA, including the SPIRE Upstream Authority plugin, which takes it through
its `custom_ca_bundle` field.

## How the app calls Akeyless

The app fetches the SVID from the Workload API through the `spire-agent` CLI,
because there is no mature .NET SPIFFE Workload API client. It then calls the
Akeyless REST API directly with `HttpClient`:

1. `POST {gateway}/api/v2/auth` with
   `{"access-type":"jwt","access-id":<auth-method-access-id>,"jwt":<svid>}` to
   get an Akeyless token.
2. `POST {gateway}/api/v2/get-secret-value` with
   `{"names":[<secret-path>],"token":<token>}` to read the secret.

The full endpoint reference is in the
[Akeyless Postman collection](https://github.com/Fahmy-Kadiri-akl/akeyless-postman-collection).

## Notes

- The host container's environment is fixed at creation time. If you change
  `.env` after starting the stack, restart the host container or re-run `up.sh`.
  The auth-method access id is the exception: the app reads it from a mounted
  file at runtime, so it works even if the container started before the
  bootstrap ran.
- `SPIFFE_WORKLOAD_SOCKET` defaults to `/tmp/spire-agent/public/api.sock` and
  rarely changes.
