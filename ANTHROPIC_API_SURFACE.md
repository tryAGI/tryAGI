# Anthropic API — what the credits can buy

Read off `Anthropic/src/libs/Anthropic/openapi.yaml` (OpenAPI 3.1, 253 path items, **385 operations**),
not from memory. Every operation listed here is reachable from `tryAGI.Anthropic` today.

**Not in this document: per-token prices.** They change, and quoting them from memory is how a budget
plan goes wrong. Take them from the pricing page, or measure: `POST /v1/messages/count_tokens` prices
a request before you send it, and the Admin API's usage/cost reports (under `organizations`) give what
was actually spent.

## How the spec is keyed, which matters for reading it

A spec cannot declare two operations on one path and method, so the beta variant of an endpoint is
keyed by appending a query string — `/v1/messages?beta=true`. That is **not** a query parameter; it is
a disambiguator. `generate.sh` tags those with `x-autosdk-path` so the real path is what gets sent.
Half of the 385 operations are these beta twins.

| Family | Availability | What it is |
|---|---|---|
| `messages` | GA + beta | Inference, batches, token counting |
| `models` | GA + beta | Model discovery |
| `files` | GA + beta | Upload once, reference by id |
| `skills` | GA + beta | Packaged instructions the model loads |
| `organizations` | GA + beta | Admin: members, workspaces, API keys, **usage and cost reports, spend limits** |
| `user_profiles` | GA + beta | Acting on behalf of an end user; enrollment and action URLs |
| `agents`, `sessions`, `deployments`, `deployment_runs`, `environments`, `memory_stores`, `vaults`, `tunnels`, `dreams` | **beta only** | Managed Agents: Anthropic runs the agent loop and hosts the sandbox |

## 1. Inference — the main cost centre

| Operation | Note |
|---|---|
| `POST /v1/messages` | The one call that does the work. Streams when the response declares `text/event-stream` |
| `POST /v1/messages/count_tokens` | **Free.** Price a request before sending it |
| `POST /v1/messages/batches` | Batch; the standing discount for anything not interactive |
| `GET /v1/messages/batches`, `/{id}`, `/{id}/results`, `POST /{id}/cancel`, `DELETE /{id}` | Batch lifecycle |
| `GET /v1/models`, `GET /v1/models/{id}` | Discover what the account can actually call — cheaper than hardcoding ids |

Levers that change the bill for the same work, all expressed inside `POST /v1/messages`:

- **Prompt caching** (`cache_control`) — a cache write costs more than a plain input token, a cache
  read far less. Worth it whenever a long prefix repeats.
- **Batch** — for anything that can wait.
- **Thinking** (`thinking`) — adaptive on current models; thinking tokens are output tokens.
- **`speed` / `service_tier`** — beta; trades latency against price.
- **`max_tokens`** — caps the only part of the bill the model controls. `max_tokens: 0` is valid and
  is how you pre-warm a cache.
- **`output_config.format`** — structured output, so you stop paying for re-asks and parsing retries.

Server-side tools billed as part of the call: web search, web fetch, code execution, browser and
computer toolsets, text editor, memory, tool search. These are why `caller` mattered — the spec marked
it required on 52 response block schemas and the API never sends it, which broke every server-tool
response until `generate.sh` stripped it.

## 2. Managed Agents (beta) — the part that can spend a budget on its own

This is the surface worth knowing about, because it is the one that runs without you in the loop.

| Group | Operations | What it buys |
|---|---|---|
| `agents` | create, update, get, list, versions, archive | A stored, **versioned** agent config. A session pins a version, so a config change cannot silently alter running work |
| `sessions` | create, update, get, list, archive, delete; events (list, send, **stream**); threads (list, get, events, **stream**, archive); resources (add, get, list, update, delete) | A running agent with its own container. Two SSE streams: whole-session and per-thread |
| `deployments` | create, update, get, list, **run now**, pause, unpause, archive | Scheduled agents. `run` fires one now; pause is the brake if a schedule misbehaves |
| `deployment_runs` | list, get | What the schedule actually did |
| `environments` | create, update, get, list, archive, delete; work (list, **poll**, get, update, ack, heartbeat, stop, stats) | A work queue with poll/ack/heartbeat — your own workers pulling agent work |
| `memory_stores` | stores (CRUD, archive); memories (CRUD); memory_versions (list, get, **redact**) | Memory that outlives a session, versioned, with redaction |
| `vaults` | vaults (create, get, list, delete); credentials (create, get, list, delete) | Credentials Anthropic stores and substitutes at egress — never visible in the sandbox |
| `tunnels` | create, get, list, archive; certificates (create, get, list, archive); **reveal_token**, **rotate_token** | Reaching a private network from the sandbox, with rotatable tokens |
| `dreams` | create, get, list, cancel, archive | Background work, cancellable |
| `skills` | create, versions (create, list, get, **download content**), delete | Instructions packaged once and reused across agents |

**Everything here is beta**, so each call needs the matching `anthropic-beta` flag. The SDK sends
`managed-agents-2026-04-01` by default on the session event streams, because the endpoint rejects the
request without it and the spec does not imply it.

## 3. Admin — how to not overspend

Under `organizations`, 152 operations. The ones that matter for a budget:

- **Usage and cost reports** — what was actually spent, by workspace and key. This is the only
  honest input to a spend plan.
- **Spend limits** — `BetaSetSpendLimitV1OrganizationsSpendLimitsPost`. Set this before pointing a
  scheduled deployment at a budget, not after.
- **Workspaces and API keys** — a key per workload is what makes the cost report readable.
- Members, invites, audit logs.

## 4. Webhooks

Standard Webhooks (`webhook-id`, `webhook-timestamp`, `webhook-signature`, HMAC-SHA256, 5-minute
window). `AnthropicWebhooks.Unwrap` / `CreateVerifier` in the SDK; signing key from
`ANTHROPIC_WEBHOOK_SIGNING_KEY`. This is what makes long-running agent work usable without polling.

## Where the money goes, in order

1. **A scheduled Managed Agents deployment** is the only thing here that spends while you sleep. It
   is also the most interesting thing to spend on. Set a spend limit first.
2. **Inference in a loop** — agent sessions, evals, batch jobs.
3. **Interactive calls** — the smallest line unless something is wrong.
4. **Everything else is effectively free**: token counting, model discovery, file and skill storage,
   admin reads.

The tiered spend proposal built on top of this surface was sent separately as
`anthropic-200-usd-plan.md`.
