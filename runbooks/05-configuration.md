# Configuration reference

All user-facing values live in `.env`, copied from `spire/spire.env.example`.
This is what each variable does.

## Required

| Variable | Purpose |
|---|---|
| `AKEYLESS_GATEWAY` | The Akeyless API gateway the app calls to trade the SVID for a token and read secrets. |
| `AKEYLESS_TOKEN` | A short-lived token (`t-...`) for the bootstrap. The only way the bootstrap authenticates; a missing token is a hard failure. |

`AKEYLESS_CA_CERT` is optional: set it to a PEM CA certificate file so the
app's HTTP client trusts a self-signed or internal gateway. See
[TLS and self-signed gateways](#tls-and-self-signed-gateways) below.

## Trust domain and identity

| Variable | Default | Purpose |
|---|---|---|
| `SPIFFE_TRUST_DOMAIN` | `example.org` | The trust domain. Rendered into the server and agent configs and used for agent and workload SPIFFE IDs. |
| `WORKLOAD_SPIFFE_ID` | `spiffe://example.org/ns/default/sa/secret-consumer` | The SPIFFE ID the workload is registered with and bound to in the Akeyless role. |
| `JWT_AUDIENCE` | `akeyless` | The audience claim required on the JWT-SVID. |

## Lifetimes

SPIRE defaults apply unless you override these. Values are Go duration strings
like `5m`, `1h`, `24h`.

| Variable | Default | Purpose |
|---|---|---|
| `JWT_SVID_TTL` | `5m` | Lifetime of each JWT-SVID. Shorter tightens the anti-theft window. |
| `X509_SVID_TTL` | `1h` | Lifetime of X.509-SVIDs. |
| `CA_TTL` | `24h` | Lifetime of the trust-root CA and JWT signing key before rotation. |

## Akeyless object paths

| Variable | Default | Purpose |
|---|---|---|
| `AKEYLESS_AUTH_METHOD` | `/spiffe/demo/auth` | The OAuth2/JWT auth method path. |
| `AKEYLESS_ROLE` | `/spiffe/demo/reader` | The role bound to the workload's SPIFFE ID. |
| `AKEYLESS_SECRET` | `/spiffe/demo/db-password` | The demo secret path. The role rule is derived from this path's folder. |
| `SPIRE_BUNDLE_ENDPOINT` | empty | Optional public bundle endpoint so Akeyless tracks key rotation instead of using the inline JWKS. |

## The demo secret lives in Akeyless, not in .env

The demo secret is the payload the app reads back to prove the flow worked. The
bootstrap generates an ephemeral value in Akeyless itself, so there is nothing
secret-shaped in `.env` or in the repo. You do not set a value for it. In a real
deployment you provision your own secret in your Akeyless account and point
`AKEYLESS_SECRET` at that path; the app reads it at runtime from Akeyless, and
the bootstrap leaves it alone.

> [!TIP]
> The app reads secrets from Akeyless at runtime. It does not create or modify
> secrets, and it does not read a secret value from `.env`. Provisioning is the
> app owner's job, done once through the Akeyless console or the admin bootstrap.

## How the app calls Akeyless

The .NET reference app fetches the SVID from the Workload API (via the
`spire-agent` CLI, the only mature way to reach the Workload API from .NET),
then calls the Akeyless REST API directly with `HttpClient`:

1. `POST {gateway}/api/v2/auth` with `{"access-type":"jwt","access-id":<auth-method-access-id>,"jwt":<svid>}` for an Akeyless token.
2. `POST {gateway}/api/v2/get-secret-value` with `{"names":[<secret-path>],"token":<token>}` to read the secret.

The full endpoint reference is in the [Akeyless Postman collection](https://github.com/Fahmy-Kadiri-akl/akeyless-postman-collection).

### TLS and self-signed gateways

Set `AKEYLESS_CA_CERT` to a PEM CA certificate file so the app's HTTP client
trusts a self-signed or internal gateway. Leave it unset for a publicly trusted
gateway.

## Notes

- `AKEYLESS_ACCESS_ID` is auto-populated by the bootstrap into `.env` and into
  `spire/.data/akeyless-access-id`. You do not set it by hand.
- Changing `SPIFFE_TRUST_DOMAIN` on a running deployment rewrites every SPIFFE
  ID and invalidates registrations and role bindings. Treat it as fixed per
  environment.
