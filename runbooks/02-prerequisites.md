# Prerequisites

Complete every item before you start. Most failures later in these guides trace
back to a missed prerequisite here.

## Docker

You need Docker with the Compose v2 plugin. Check it:

```bash
docker compose version
```

This prints a version line like `Docker Compose version v2.x`. If you see
`unknown command: docker compose`, install the Compose plugin.

Docker must also be able to reach the internet to pull images. The demo pulls
the SPIRE server and agent images and the pre-built host image from GHCR.

## Your Akeyless gateway URL

You need your account's API gateway base URL, reachable from the host that runs
the app. It looks like `https://your-account.akeyless.cloud`, or an internal
gateway URL if you run one. Do not include the `/api/v2` path; the code appends
it automatically.

## A short-lived token for the bootstrap

The bootstrap is the one-time step that wires SPIRE into Akeyless. It runs as
an administrator and authenticates with a short-lived token, never a long-lived
API key. Mint one however you normally authenticate to Akeyless: API key, SAML,
OIDC, or the console. Copy the `t-...` token into `AKEYLESS_TOKEN` in `.env`. It
expires on its own, so no permanent admin credential survives in the repo or CI
history. It needs the capabilities listed under "Required Akeyless permissions"
below.

The bootstrap uses curl and jq to call the Akeyless REST API directly. Both are
standard on most Linux systems. No Akeyless CLI is needed for this repo.

### Check that the token works

Before you start, confirm the token is valid and not expired:

```bash
curl -s -X POST "$AKEYLESS_GATEWAY/api/v2/get-auth-method" \
  -H "Content-Type: application/json" \
  -d '{"name":"/does-not-matter","token":"<your-t-token>"}'
```

A valid token prints an error about the method not existing, because
`/does-not-matter` does not exist. That is the expected result. An
authentication error instead means the token itself is invalid or expired, and
you should create a new one.

## Required Akeyless permissions

Two identities touch a secret, with different jobs. The **bootstrap**
provisions: it creates the auth method, the role, and the secret. The
**workload** reads the secret at runtime, through the role bound to its SPIFFE
ID. That SPIFFE ID is the one from your trust domain, so these capabilities map
onto the identities in [Concepts](01-concepts.md) and the
provisioning-versus-reading model in
[Production](06-production.md#who-provisions-and-who-reads).

Capabilities are `read`, `create`, `update`, `delete`, `list`, and `deny`. The
rule types that matter here are `item-rule`, `auth-method-rule`, and
`role-rule`. The [Akeyless RBAC guide](https://docs.akeyless.io/docs/rbac)
covers the full model.

| Identity | What it needs |
|---|---|
| Workload | An `item-rule` granting `read` and `list` on the secret folder, bound to its SPIFFE ID. Nothing else. |
| Bootstrap | `auth-method-rule` with `create`, `update`, `delete`, `read`; `role-rule` with `create`, `update`; `item-rule` with `create` on the configured paths including the PKI issuer. A full admin also works. |
| UpstreamAuthority plugin | `item-rule` with `read` and `update` on the PKI issuer path (`UPSTREAM_CERT_ISSUER`); `item-rule` with `read`, `create`, `update`, and `list` on the JWT keys item (`UPSTREAM_CERT_ISSUER-jwt-keys` by default). |

Akeyless does not let a role grant a capability its caller lacks. The bootstrap
grants the workload `read` and `list` on the secret folder, so the bootstrap
must itself hold `read` and `list` on that folder.

If you want to avoid full admin, create a role such as `/spiffe/demo/bootstrap-admin`,
associate it with an API-key auth method you control, and grant it:

- `item-rule` on the secret folder: `create`, `read`, `list`
- `auth-method-rule` on the auth method: `create`, `update`, `delete`, `read`
- `role-rule` on the role: `create`, `update`

Then create your `AKEYLESS_TOKEN` from an identity that holds this role.

## Creating the UpstreamAuthority credentials

The UpstreamAuthority plugin needs its own persistent auth method to sign the
trust root through Akeyless PKI. This is the one place in the architecture
where a non-SPIFFE credential is required: the plugin bootstraps the trust
root, so it cannot use an SVID.

### Choosing an access type

| `access_type` | Credential on the spire-server | Blast radius |
|---|---|---|
| `api_key` | a static access-key file | scoped to the PKI issuer and JWT keys paths only |
| `aws_iam` | none; uses the VM's IAM role | the IAM role's permissions |
| `gcp` | none; uses the service account | the service account's permissions |
| `azure` | none; uses managed identity | the managed identity's permissions |
| `universal_identity` | a rotating UID token | scoped to the UID role |

`api_key` is the simplest and works on any host. `aws_iam`, `gcp`, and `azure`
are preferred for cloud deployments because they eliminate the static key
entirely. `universal_identity` auto-rotates the credential on any host.

This is separate from cloud-native workload identity (AWS IRSA, GCP Workload
Identity, Azure Managed Identity), which replaces SPIRE entirely for cloud-only
workloads. SPIRE with cloud-identity auth gives you both: no static key on the
server, and SPIFFE's portability across cloud, on-prem, and hybrid.

### Risk management

The plugin credential is not ideal, but the risk is managed three ways:

1. **Scope**: the RBAC covers only the PKI issuer and JWT keys paths, not the
   whole account. A compromised key can sign certs but cannot read arbitrary
   secrets.
2. **Location**: the credential lives only on the spire-server (one tightly
   controlled host), never on workload hosts. Workloads still have zero
   credentials.
3. **Elimination**: on cloud infrastructure, use cloud identity to remove the
   static key entirely.

### Creating the auth method (api_key)

Replace `<admin-token>` with a token that has admin or equivalent permissions.

```bash
GATEWAY=https://your-account.akeyless.cloud

# 1. Create an API-key auth method for the plugin
RESP=$(curl -s -X POST "$GATEWAY/api/v2/create-auth-method-api-key" \
  -H "Content-Type: application/json" \
  -d '{"name":"/spiffe/demo/upstream-auth","token":"<admin-token>"}')
UPSTREAM_ACCESS_ID=$(echo "$RESP" | jq -r .access_id)
UPSTREAM_ACCESS_KEY=$(echo "$RESP" | jq -r .access_key)
echo "access_id=$UPSTREAM_ACCESS_ID"

# 2. Create a role for the plugin
curl -s -X POST "$GATEWAY/api/v2/create-role" \
  -H "Content-Type: application/json" \
  -d '{"name":"/spiffe/demo/upstream-role","token":"<admin-token>"}'

# 3. Grant read + update on the PKI issuer
curl -s -X POST "$GATEWAY/api/v2/set-role-rule" \
  -H "Content-Type: application/json" \
  -d '{"role-name":"/spiffe/demo/upstream-role","path":"/spiffe/demo/pki","capability":["read","update"],"token":"<admin-token>"}'

# 4. Grant read + create + update + list on the JWT keys item
curl -s -X POST "$GATEWAY/api/v2/set-role-rule" \
  -H "Content-Type: application/json" \
  -d '{"role-name":"/spiffe/demo/upstream-role","path":"/spiffe/demo/pki-jwt-keys","capability":["read","create","update","list"],"token":"<admin-token>"}'

# 5. Associate the role with the auth method
curl -s -X POST "$GATEWAY/api/v2/assoc-role-am" \
  -H "Content-Type: application/json" \
  -d '{"role-name":"/spiffe/demo/upstream-role","am-name":"/spiffe/demo/upstream-auth","token":"<admin-token>"}'
```

Put the `access_id` and `access_key` from step 1 into `.env` as
`UPSTREAM_ACCESS_ID` and `UPSTREAM_ACCESS_KEY`. For cloud identity, create the
auth method with the matching `access_type` instead of api-key, and set
`UPSTREAM_ACCESS_KEY` to empty.

## Creating the Secret Manager credentials

The Secret Manager plugin runs on the agent and stores X.509-SVIDs in Akeyless.
It needs its own auth method with `create`, `update`, and `list` on the target
folder.

The access-type choice and risk-management section above apply identically.
Replace `<admin-token>` with a token that has admin or equivalent permissions.

```bash
GATEWAY=https://your-account.akeyless.cloud

# 1. Create an API-key auth method for the plugin
RESP=$(curl -s -X POST "$GATEWAY/api/v2/create-auth-method-api-key" \
  -H "Content-Type: application/json" \
  -d '{"name":"/spiffe/demo/svid-store-auth","token":"<admin-token>"}')
SVID_STORE_ACCESS_ID=$(echo "$RESP" | jq -r .access_id)
SVID_STORE_ACCESS_KEY=$(echo "$RESP" | jq -r .access_key)
echo "access_id=$SVID_STORE_ACCESS_ID"

# 2. Create a role for the plugin
curl -s -X POST "$GATEWAY/api/v2/create-role" \
  -H "Content-Type: application/json" \
  -d '{"name":"/spiffe/demo/svid-store-role","token":"<admin-token>"}'

# 3. Grant create + update + list on the SVID target folder
curl -s -X POST "$GATEWAY/api/v2/set-role-rule" \
  -H "Content-Type: application/json" \
  -d '{"role-name":"/spiffe/demo/svid-store-role","path":"/spiffe/demo/svid","capability":["create","update","list"],"token":"<admin-token>"}'

# 4. Associate the role with the auth method
curl -s -X POST "$GATEWAY/api/v2/assoc-role-am" \
  -H "Content-Type: application/json" \
  -d '{"role-name":"/spiffe/demo/svid-store-role","am-name":"/spiffe/demo/svid-store-auth","token":"<admin-token>"}'
```

Put the `access_id` and `access_key` from step 1 into `.env` as
`SVID_STORE_ACCESS_ID` and `SVID_STORE_ACCESS_KEY`. For cloud identity, create
the auth method with the matching `access_type` instead of api-key, and set
`SVID_STORE_ACCESS_KEY` to empty.

## Python

The bootstrap script uses Python to convert the SPIRE trust bundle into a JWKS,
so Python 3 and the `cryptography` package are required for the demo, not
optional:

```bash
pip install cryptography
```

You also need them to run `bootstrap/verify-svid.sh` if you validate a JWT-SVID
by hand.

Next: [Quick start](03-quick-start.md)
