# Migrating from on-disk credentials

How to move an existing application from a static API key on disk to SPIFFE
identity with Akeyless. This is the playbook for the most common real-world
scenario: you have a service reading a secret today using a key file, and you
want to eliminate that key.

## The before state

Your application has a credential on disk:

```
/etc/akeyless/key    # an API key, or a long-lived token file
```

It uses that key to call Akeyless `auth` and get a token, then reads the
secret. The key is permanent. Anyone who reads the file becomes the workload.
Rotation is a manual process or a separate timer job.

## Prerequisites

Complete the quick start and wiring first:

1. SPIRE is deployed: server running, agent on the workload host.
2. Akeyless is wired: auth method, role, and secret exist.
3. The workload is registered with selectors.

See [Wiring Akeyless](04-wiring-akeyless.md) and
[Deploying agents](07-deploying-agents.md).

## Step 1: Deploy the SPIRE agent

If the agent is not already on the workload host, install it:

```bash
SPIRE_SERVER_ADDRESS=<server> JOIN_TOKEN=<token> \
  SPIFFE_TRUST_DOMAIN=<trust-domain> ./agent/deploy-agent.sh
```

Confirm the Workload API socket is up:

```bash
test -S /tmp/spire-agent/public/api.sock && echo "socket ready"
```

## Step 2: Register the workload

Register the workload with selectors that match your application's process:

```bash
spire-server entry create \
  -parentID spiffe://<trust-domain>/agent/<host-name> \
  -spiffeID spiffe://<trust-domain>/sa/<workload-name> \
  -selector unix:uid:<dedicated-uid> \
  -socketPath /tmp/spire-server/private/api.sock
```

Verify the workload can fetch an SVID:

```bash
spire-agent api fetch jwt -audience akeyless \
  -socketPath /tmp/spire-agent/public/api.sock
```

## Step 3: Update the application

Replace the key-file logic with the SVID flow. The change is small:

| Before | After |
|---|---|
| read API key from `/etc/akeyless/key` | fetch JWT-SVID from the Workload API |
| call `auth` with the API key | call `auth` with the SVID, access-type `jwt` |
| read the secret with the resulting token | unchanged |

The Akeyless token step and the secret-read step stay the same. Only the
authentication source changes: the API key is replaced by the SVID. See
[How the app calls Akeyless](05-configuration.md#how-the-app-calls-akeyless)
for the curl equivalent, which you can port to any language.

## Step 4: Dual-run (recommended)

Run both paths in parallel during the transition. The app tries the SVID path
first and falls back to the key file if the SVID fetch fails. This gives you a
safety net while you validate the new path in production:

```python
# Pseudocode for dual-run
try:
    svid = fetch_svid_from_workload_api()
    token = authenticate_with_svid(svid)
except SvidFetchFailed:
    key = read_key_file("/etc/akeyless/key")
    token = authenticate_with_key(key)
secret = read_secret(token)
```

Keep the dual-run for at least one full `CA_TTL` rotation cycle to confirm the
JWKS refreshes correctly.

## Step 5: Verify

Confirm the new path works end to end:

1. The app fetches an SVID. Check the app logs or the SPIRE agent logs.
2. Akeyless accepts the SVID. Check the Akeyless audit log for auth success.
3. The secret is read correctly. Compare the value with the old path's output.

## Step 6: Remove the old credential

Once the SVID path is verified and stable:

1. Delete the key file: `rm /etc/akeyless/key`.
2. Revoke or disable the API key in Akeyless so it cannot be reused.
3. Remove the dual-run fallback from the application code.
4. Confirm no process on the host still reads the old key path.

The host now holds no credential. The workload authenticates solely through its
SPIFFE identity. See [Operations and observability](10-operations.md) for how to
monitor the new path in production.

## Rollback

If the SVID path fails and you need to fall back quickly:

1. Restore the API key file to `/etc/akeyless/key`.
2. Re-enable the API key in Akeyless if it was revoked.
3. Switch the app back to the key-file path, or re-enable the dual-run
   fallback.

Rollback is fast because the old path is independent of SPIRE. The key file and
the SVID path do not interfere with each other.
