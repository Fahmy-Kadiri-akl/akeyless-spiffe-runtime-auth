# Runbooks

## Reading order

The runbooks are numbered and follow a learning path. First-time setup runs
straight through 01 to 05. Guide 09 is an optional demo of X.509-SVID mTLS. If
something breaks, jump to 08.

| # | Guide | When you need it |
|---|---|---|
| 1 | [Concepts you need first](01-concepts.md) | You are new to SPIFFE, SPIRE, SVIDs, trust domains, or audience. Read once before anything else. |
| 2 | [Prerequisites](02-prerequisites.md) | Verify your environment before starting. |
| 3 | [Quick start](03-quick-start.md) | Get a secret end to end on one host. |
| 4 | [Wiring Akeyless](04-wiring-akeyless.md) | The one-time bootstrap that connects SPIRE to Akeyless: what it creates and why. |
| 5 | [Configuration reference](05-configuration.md) | Understand every value in `.env`, including what each means in production. |
| 6 | [Production hardening](06-production.md) | Move from the demo to production: trust root, selectors, environments, bundle distribution, security model. |
| 7 | [Deploying agents](07-deploying-agents.md) | Put an agent on each of your own hosts, for your own app and language. |
| 8 | [Troubleshooting](08-troubleshooting.md) | Categorized failure modes with causes and fixes. |
| 9 | [X.509-SVID via Secret Manager](09-x509-svid-store.md) | How X.509-SVIDs are stored in Akeyless automatically by the Secret Manager plugin. |
| 10 | [Operations and observability](10-operations.md) | Monitor a production deployment: health checks, alerting, broken SVID detection. |
| 11 | [Migrating from on-disk credentials](11-migration.md) | Move an existing app from a static API key to SPIFFE identity. |

The repository-level [`../README.md`](../README.md) covers what the repo is,
why it exists, and a one-shot quick start. These runbooks go deeper and assume
you have read the concepts in guide 1.
