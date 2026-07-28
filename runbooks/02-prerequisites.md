# Prerequisites

Complete every item before starting. Most failures later in these guides trace
back to a missed prerequisite here.

## Docker

- [ ] Docker with the Compose v2 plugin. Verify with:

  ```bash
  docker compose version
  ```

  Expected: a version line like `Docker Compose version v2.x`. If you see
  `unknown command: docker compose`, install the plugin.

- [ ] Docker can reach the internet to pull images (`ghcr.io` for the SPIRE
  images and the pre-built host image).

## Akeyless

- [ ] An Akeyless account and your account's API gateway URL, reachable from
  the host that runs the app. It looks like
  `https://your-account.akeyless.cloud/api/v2` or an internal gateway URL.

- [ ] The Akeyless CLI installed on the admin host, the machine where you will
  run the bootstrap. It is a single static binary:

  ```bash
  curl -fsSL -o akeyless https://akeyless-cli.s3.us-east-2.amazonaws.com/cli/latest/production/cli-linux-amd64
  chmod +x akeyless
  ```

  The CLI self-installs into `~/.akeyless/bin` on first run. This CLI is used
  only to mint a token and run the bootstrap; the CLI bundled in the container
  is for the app at runtime.

- [ ] A short-lived token to run the bootstrap. Mint one with whichever auth
  method you prefer:

  ```bash
  akeyless auth --access-id <p-...> --access-type access_key \
    --access-key <key> --gateway-url <your-gateway>
  ```

  Copy the printed `Token: t-...` value into `AKEYLESS_TOKEN` in `.env`. The
  token expires on its own. It needs the capabilities listed under "Required
  Akeyless permissions" in the repo README.

### Verify the token works

```bash
akeyless get-auth-method --name /does-not-matter --token <your-t-token>
```

Expected: an error about the method not existing, not an auth error. An auth
error means the token is invalid or expired; re-mint it.

## Python (optional)

- [ ] Python 3, only if you run `bootstrap/verify-svid.sh`. Signature checks
  additionally need `pip install cryptography`.

Now read [03-quick-start.md](03-quick-start.md).
