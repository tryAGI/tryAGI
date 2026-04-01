# Spec Workarounds

SDK spec fix inventory and auth runtime hooks. When regenerating, **always use the existing `generate.sh`** — don't run `autosdk generate` directly.

## Spec-Level Fixes (Pre-Generation)

Most SDKs have clean `generate.sh` scripts. The following require workarounds due to upstream spec issues or AutoSDK limitations.

| SDK | Workaround | Category |
|-----|-----------|----------|
| Anthropic | `yq`/`jq`: inject Ping schema into MessageStreamEvent | Schema injection |
| Google.Gemini | `python3`: Discovery→OpenAPI conversion, enum fix, endpoint/schema pruning | Format conversion |
| HuggingFace | `python3`: emoji/quote enum chars, `_`-prefixed property dedup, OpenAPI 3.1 compat | Enum/property fix |
| RetellAI | `python3`: comparator enum dedup, EquationCondition `\|\|`/`&&` rename | Enum fix |
| Deepgram | `yq`/`jq`: reserved keyword rename, duplicate JwtAuth removal | Property/auth fix |
| DeepL | `yq`: flatten allOf-wrapping-string schemas (reserved keyword) | Property fix |
| LlamaParse | `jq`: servers injection | Servers injection |
| Composio | `jq`: flatten 74-variant anyOf, remove duplicate parameters | Schema simplification |
| Braintrust | `jq`: remove `/v1/proxy/{path+}` (invalid C# identifier) | Endpoint removal |
| Qdrant | `jq`: server URL, schema renames (Disabled, Match, Snowball) | Servers/schema rename |
| Milvus | `jq`: servers + info.title injection | Servers injection |
| Turbopuffer | `yq`: Stainless `?` path rename, `string` reserved keyword rename | Path/property fix |
| Firecrawl | `python3`: metadata field schema fix (string→union) | Schema fix |
| Speechmatics | `python3`: Swagger 2.0→3.0 auth/servers conversion | Auth/format fix |
| Shotstack | `npx`/`python3`: multi-file spec bundle, auth conversion | Spec bundling/auth |
| Portkey | `python3`: CS9035 required member fix (#202) | Required member fix |
| Gladia | `jq`: normalize dynamic timestamp examples | Example normalization |
| Phoenix | `jq`: servers injection | Servers injection |
| OpenRouter | `jq`: auth fix, schema rename (spaces), param removal | Auth/schema fix |
| PredictionGuard | `python3`: auth fix, servers, param removal | Auth/servers fix |
| Guardrails | `python3`: complete spec rewrite (inline external refs) | Spec rewrite |
| PromptLayer | `jq`: servers, param removal | Servers/param fix |
| Coze | `python3`: servers injection (international + China URLs) | Servers injection |
| Letta | `python3`: SSE removal, empty schema fix, required member fix | Schema fix |
| Nixtla | `jq`: top-level security injection | Auth fix |
| Photoroom | `jq`: simplify GET param schema | Schema simplification |
| LabelStudio | `yq`: apiKey→bearer conversion + `PrepareRequest` Token auth hook | Auth fix |
| VoyageAI | `yq`: remove broken `Authorization: Bearer` apiKey scheme | Auth fix |
| Vapi | `jq`: 7 fixes — LMNTVoice oneOf flatten (#206), operator/punctuation enums, discriminator mappings, 11labs rename, enum dedup, duplicate param rename | Enum/schema fix |

## Post-Generation Fixes

None — all post-generation workarounds eliminated in AutoSDK dev.154.

## Resolved AutoSDK Issues (Workarounds Removed)

- [#200](https://github.com/tryAGI/AutoSDK/issues/200) — allOf inheritance → Variant2 pattern (Opik pragma removed)
- [#201](https://github.com/tryAGI/AutoSDK/issues/201) — Symbolic enum naming → `Eq`/`Neq`/`Gt` etc. (Opik sed, LlamaParse enum rename removed; RetellAI Equation fix removed)
- [#205](https://github.com/tryAGI/AutoSDK/issues/205) — Enum values with embedded quotes now properly escaped via `ToCSharpStringLiteral()` (Vapi transcript enum workaround removed)
- [#207](https://github.com/tryAGI/AutoSDK/issues/207) — Tag↔group PascalCase collision → deferred tag collision resolution (Vectara x-fern stripping removed)

## Open AutoSDK Issues

- [#212](https://github.com/tryAGI/AutoSDK/issues/212) — Malformed OneOf JsonConverter for inline enum oneOf — `voiceId` in `specs/vapi.yaml` (Vapi)
- [#213](https://github.com/tryAGI/AutoSDK/issues/213) — CS9035 in convenience overloads for required non-nullable `object` properties — `variables` in `specs/portkey.yaml` (Portkey)

## Auth Runtime Hooks

Some providers use non-standard auth header names. Use `--security-scheme Http:Header:Bearer` for constructor generation, then add a `PrepareRequest` partial hook to rewrite the header at runtime.

| SDK | Bearer → | Notes |
|-----|----------|-------|
| Deepgram | `Token` | |
| DeepL | `DeepL-Auth-Key` | |
| Fal | `Key` | |
| BraveSearch | `X-Subscription-Token` | |
| Serper | `X-API-KEY` | |
| Portkey | `x-portkey-api-key` | |
| ModernMT | `MMT-ApiKey` | |
| LalalAI | `X-License-Key` | |
| Novu | `ApiKey` | |
| Pinecone | `Api-Key` | |
| ScrapeGraphAI | `SGAI-APIKEY` | |
| Recombee | HMAC-SHA1 query params | `hmac_timestamp` + `hmac_sign` |
| Zep | `Api-Key` | |
| Picsart | `X-Picsart-API-Key` | + multi-host routing by path prefix |
| Algolia | `x-algolia-application-id` + `x-algolia-api-key` | Dual header |
| Vellum | `X-API-KEY` | |
| ScaleAI | HTTP Basic Auth | `Basic base64(apiKey:)` |
| JasperAI | `X-API-Key` | |
| Writesonic | `X-API-KEY` | |
| Baseten | `Api-Key` prefix | |
