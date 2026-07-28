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

You need your account's API gateway URL, reachable from the host that runs the
app. It looks like `https://your-account.akeyless.cloud/api/v2`, or an internal
gateway URL if you run one. Note that it must include the `/api/v2` path,
because the auth endpoint is `/api/v2/auth`. A URL without that path lands on
the wrong endpoint and fails with a confusing parameter error.

## A short-lived token for the bootstrap

The bootstrap is the one-time step that wires SPIRE into Akeyless. It runs as
an administrator and authenticates with a short-lived token, never a long-lived
API key. Mint one however you normally authenticate to Akeyless: API key, SAML,
OIDC, or the console. Copy the `t-...` token into `AKEYLESS_TOKEN` in `.env`. It
expires on its own, so no permanent admin credential survives in the repo or CI
history. It needs the capabilities listed under "Required Akeyless permissions"
below.

The bootstrap script calls the Akeyless CLI to create the auth method, role, and
secret, so the CLI must be on PATH wherever you run
`./bootstrap/setup-akeyless.sh`. It is a general tool; install it the way you
normally do for Akeyless. The reference app does not use it: the app calls the
Akeyless REST API directly, so no CLI ships in the container.

### Check that the token works

Before you start, confirm the token is valid and not expired:

```bash
akeyless get-auth-method --name /does-not-matter --token <your-t-token>
```

A valid token prints an error about the method not existing, because
`/does-not-matter` does not exist. That is the expected result. An
authentication error instead means the token itself is invalid or expired, and
you should re-mint it.

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
| Bootstrap | `auth-method-rule` with `create`, `update`, `delete`, `read`; `role-rule` with `create`, `update`; `item-rule` with `create` on the configured paths. A full admin also works. |

Akeyless does not let a role grant a capability its caller lacks. The bootstrap
grants the workload `read` and `list` on the secret folder, so the bootstrap
must itself hold `read` and `list` on that folder.

If you want to avoid full admin, create a role such as `/spiffe/demo/bootstrap-admin`,
associate it with an API-key auth method you control, and grant it:

- `item-rule` on the secret folder: `create`, `read`, `list`
- `auth-method-rule` on the auth method: `create`, `update`, `delete`, `read`
- `role-rule` on the role: `create`, `update`

Then mint your `AKEYLESS_TOKEN` from an identity that holds this role.

## Python, only if you inspect an SVID

You need Python 3 only if you run `bootstrap/verify-svid.sh` to decode and
validate a JWT-SVID by hand. Signature checks also need the cryptography
package:

```bash
pip install cryptography
```

The demo itself does not require Python.

Now read [Quick start](03-quick-start.md).
