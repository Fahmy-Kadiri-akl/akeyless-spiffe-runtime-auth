# Runbooks

Step-by-step operator guides for authenticating a workload to Akeyless with
SPIFFE/SPIRE. Read these if you have no background in SPIFFE, SPIRE, or
Akeyless machine identity.

## Reading order

The runbooks are numbered and build on each other. First-time setup runs
straight through 01 to 06. If something breaks, jump to 07.

| # | Document | When you need it |
|---|---|---|
| 1 | [Concepts you need first](01-concepts.md) | You have never heard of SPIFFE, SPIRE, SVIDs, or trust domains. Read once before anything else. |
| 2 | [Prerequisites](02-prerequisites.md) | Verify before starting. Most failures later trace back to a missed prereq. |
| 3 | [Quick start](03-quick-start.md) | Get a secret end to end on one host in about ten minutes. |
| 4 | [Deploying an agent for your application](04-deploying-agents.md) | Your app runs on a different host, or in a different language, and needs identity. |
| 5 | [Configuration reference](05-configuration.md) | Change trust domain, TTLs, gateway, paths, or the demo secret. |
| 6 | [Production hardening](06-production.md) | Moving from the dev demo to production: trust root, selectors, bundle distribution, security model. |
| 7 | [Troubleshooting](07-troubleshooting.md) | Categorized failure modes with diagnoses and fixes. |

The repository-level [`../README.md`](../README.md) covers what the repo is,
why it exists, and a one-shot quick start. These runbooks go deeper and are
written for a reader who is new to all of it.
