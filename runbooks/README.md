# Runbooks

Step-by-step guides for authenticating a workload to Akeyless with
SPIFFE/SPIRE, written for a reader who is new to all of it. They build on each
other in order.

## Reading order

The runbooks are numbered and follow a learning path. First-time setup runs
straight through 01 to 04. Guide 08 is an optional demo of X.509-SVID mTLS. If
something breaks, jump to 07.

| # | Guide | When you need it |
|---|---|---|
| 1 | [Concepts you need first](01-concepts.md) | You are new to SPIFFE, SPIRE, SVIDs, trust domains, or audience. Read once before anything else. |
| 2 | [Prerequisites](02-prerequisites.md) | Verify your environment before starting. |
| 3 | [Quick start](03-quick-start.md) | Get a secret end to end on one host. |
| 4 | [Configuration reference](04-configuration.md) | Understand every value in `.env`, including what each means in production. |
| 5 | [Production hardening](05-production.md) | Move from the demo to production: trust root, selectors, environments, bundle distribution, security model. |
| 6 | [Deploying agents](06-deploying-agents.md) | Put an agent on each of your own hosts, for your own app and language. |
| 7 | [Troubleshooting](07-troubleshooting.md) | Categorized failure modes with causes and fixes. |
| 8 | [X.509-SVID mTLS](08-x509-mtls.md) | Optional. See two workloads authenticate each other over mutual TLS with X.509-SVIDs. |

The repository-level [`../README.md`](../README.md) covers what the repo is,
why it exists, and a one-shot quick start. These runbooks go deeper and assume
you have read the concepts in guide 1.
