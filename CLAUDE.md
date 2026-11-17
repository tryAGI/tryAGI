# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working across the tryAGI organization workspace.

## Workspace Overview

This is a **mono-workspace** (not a monorepo) containing ~50 independent git repositories under the [tryAGI](https://github.com/tryAGI) GitHub organization. The primary focus is building .NET/C# SDKs for AI/ML service APIs, along with supporting infrastructure and applications.

## Git Workflow

**Commit and push directly to `main`.** These are small, auto-generated SDK projects — PRs and feature branches are unnecessary overhead. Always commit and push from the `main` branch.

## Common SDK Structure

Most auto-generated SDKs follow this layout:

```
<SdkName>/
├── <SdkName>.slnx
├── src/
│   ├── libs/<SdkName>/
│   │   ├── <SdkName>.csproj
│   │   ├── openapi.yaml          # Source OpenAPI spec
│   │   ├── generate.sh           # Regeneration script (runs autosdk.cli)
│   │   ├── Generated/            # ⚠️ AUTO-GENERATED — never edit manually
│   │   │   ├── *Client.g.cs
│   │   │   ├── *.Models.g.cs
│   │   │   └── ...
│   │   └── *.cs                  # Hand-written extensions/helpers
│   └── tests/IntegrationTests/   # MSTest + AwesomeAssertions/AwesomeAssertions
└── .github/workflows/
    └── auto-update.yml           # CI: fetches latest spec every 3 hours, opens PR
```

### Key Rules for Generated SDKs

- **NEVER edit files in `Generated/` directories** — they are overwritten on regeneration
- Hand-written extensions go in partial classes at the library root (outside `Generated/`)
- Regenerate with: `cd src/libs/<SdkName> && ./generate.sh`
- Requires global tool: `dotnet tool install --global autosdk.cli --prerelease`

### Auth Override with `--security-scheme`

Most API specs use non-standard auth (custom `apiKey` headers, per-operation security blocks, missing `securitySchemes`). Instead of patching the spec with jq/yq, use the `--security-scheme` CLI flag to override auth at generation time:

```bash
autosdk generate openapi.yaml \
  --security-scheme Http:Header:Bearer \
  ...
```

**Format:** `Type:Location:Name`

| Type:Location:Name | Use Case | Example Providers |
|-------------------|----------|-------------------|
| `Http:Header:Bearer` | Standard Bearer token auth | Most SDKs (Anthropic, Ollama, Mistral, etc.) |
| `Http:Header:Basic` | HTTP Basic Auth (username:password) | Langfuse |
| `ApiKey:Header:X-API-KEY` | API key in custom header | PromptLayer |
| `ApiKey:Query:api_key` | API key in query parameter | Roboflow |

**What it does:**
- Injects/overrides `securitySchemes` in the spec
- Adds top-level `security` array (replaces per-operation security blocks)
- Generates appropriate constructor overloads (`apiKey` for Bearer/ApiKey, `username`+`password` for Basic)

**When you still need runtime hooks:** Some providers use non-standard auth header names (e.g., `Token` instead of `Bearer`, `DeepL-Auth-Key`, `X-Subscription-Token`). Use `--security-scheme Http:Header:Bearer` for constructor generation, then add a `PrepareRequest` partial hook to rewrite the header at runtime. See [`SPEC_WORKAROUNDS.md`](SPEC_WORKAROUNDS.md) for the full list.

### Opt-in AutoSDK Codegen Flags

AutoSDK ships a growing set of generator features that stay off by default to avoid surprising existing SDKs. Add the matching CLI flag to the SDK's `generate.sh` (or set the `AutoSDK_*` MSBuild property) when the spec shape warrants it.

| Flag | What it emits | Enable on SDKs with… |
|------|---------------|----------------------|
| `--auto-detect-status-polling` | `<Method>WaitAsync` for GET-by-id endpoints whose response has a status enum/const with terminal states; plus `<CreateMethod>WaitAsync` companions when a sibling 2XX response declares `Location` | Long-running create→poll APIs (Runway, Replicate, Apify, Heygen, Synthesia, Vidu, Luma, Hedra, Mubert, Reve, Tripo, KlingAI, Pika, Higgsfield, Recraft tasks) |
| `--generate-pageable-helpers` | `AutoSDKPager` runtime helper plus `<Method>AutoPagingAsync` for offset/cursor-paged GET endpoints; offset detection wires `has_more`/`has_next` predicates when present. Also exposes `AutoSDKPager.NextUrlAsync` for body-embedded absolute-`next`-URL paging (Firecrawl, Slack, Linear, Notion, HubSpot) with mandatory `EnsureSameOrigin` validation so a hostile server can't harvest the auth header via a foreign `next` URL. | List endpoints with paging (HumeAI, OpenAI assistants/files, AssemblyAI transcripts, ElevenLabs voices, Anthropic message-batches, OpenRouter, LangSmith, Langfuse, Braintrust, Helicone, Opik, Phoenix, Firecrawl crawl/batch-scrape) |
| `--generate-prediction-workflow-helpers` | `PredictionWorkflowRunner<TRequest, TEnvelope, TResult>` runtime helper for create-wait-result composition | Replicate (`Prefer: wait`), Apify (`waitForFinish`), other create-then-poll-then-project flows |
| `--generate-prompt-template-helpers` | `AutoSDK<PromptTemplate*>` DTOs + configurable manager class with `RenderStringAsync`/`RenderMessagesAsync` | LangSmith, Langfuse, PromptLayer, Braintrust prompt-version APIs |
| `--generate-observability-lifecycle-helpers` | Batched ingest lifecycle helper with bounded queue/flush/shutdown | LangSmith, Langfuse, Braintrust, Helicone, Opik, Phoenix trace ingestion |
| `--generate-evaluation-workflow-helpers` | `DatasetEvaluationRunner` for experiment loops | LangSmith, Braintrust, Phoenix eval pipelines |
| `--generate-cloud-signing-helpers` | `CloudRequestSigner` (AWS SigV4, Azure key/token, Tencent TC3) | AwsBedrock, MicrosoftFoundry, TencentTokenHub, any AWS EventStream API |
| `--generate-webhook-verifier` | Replicate/Svix-style HMAC SHA-256 webhook verifier | Replicate, Svix-based webhook APIs |
| `--generate-dynamic-multipart-helpers` | Dynamically named multipart part builders | Helicone, ElevenLabs convai-history, any "log this attachment under arbitrary field name" API |
| `--generate-multipart-upload-helpers` (`--multipart-upload-helper-class-name` to rename) | Typed `AutoSDKUploadFile` record (Filename + Content (stream OR bytes) + ContentType) with `FromBytes`/`FromStream`/`FromPath` factories plus an `AutoSDKMimeTypeGuesser` covering pdf/docx/xlsx/html/json/png/jpg/mp3/wav/mp4/webm/etc. Lets consumers replace hand-rolled `MultipartFormDataContent` assembly. | File-upload APIs: AssemblyAI `POST /v2/upload`, ElevenLabs convai dataset upload, Mistral file API, Firecrawl v2 `POST /parse`, OpenAI/Anthropic files |
| `--generate-polymorphic-array-helpers` | Runtime `AutoSDKPolymorphicFormat` base class + `[AutoSDKPolymorphicFormatVariant("name", typeof(...))]` attribute + `AutoSDKPolymorphicFormatJsonConverter<TBase>` that round-trips array items shaped as `oneOf{string-enum, object-with-type-const}` (Firecrawl v2 scrape `formats`, OpenAI Responses `tools`, Anthropic tool-use `content`). The generator now also **auto-detects** the pattern, emits typed `<Parent><Property>Item` base classes plus sealed bare-string variants (`MarkdownFormat`, `HtmlFormat`, ...) and typed object variants (`JsonFormat`, `HighlightsFormat`, ...), rewrites the consuming property type to `IList<<Parent><Property>Item>` instead of leaving the old `OneOf<string, ...>` surface, automatically registers the generated subclasses in the STJ context/AOT type list, emits the generated hierarchy into the same namespace-delimited component namespace as the owning model, scopes colliding variant subclass names off their base type when they would clash with either sibling polymorphic arrays or existing generated classes/enums in that namespace, and suppresses the legacy inline `Variant*`/`FormatEnum*` wrappers those arrays used to emit. Variant property types now reuse the normal model/type pipeline, so `$ref`s, inline enums, nested objects, and arrays flow through with real generated C# types instead of `object?` fallbacks. | Firecrawl v2, OpenAI Responses, Anthropic tool-use, any spec with `oneOf{string, object}` array items |
| `--generate-http-exception-hierarchy` | Typed `AuthenticationException`/`AuthorizationException`/`PaymentRequiredException`/`NotFoundException`/`RequestTimeoutException`/`ConflictException`/`ValidationException`/`RateLimitException` (with parsed `RetryAfter`)/`ServerException` subclasses of `ApiException`, routed by status code so callers can catch by intent | Firecrawl, Deepgram, Inworld, Anthropic, AssemblyAI — any SDK whose users were branching on `ex.StatusCode == HttpStatusCode.Unauthorized` |
| `--generate-idempotency-helpers` (`--idempotency-header-name` to customize) | Adds an opt-in `idempotencyKey` parameter to every POST/PUT/PATCH/DELETE operation even when the spec doesn't declare `x-fern-idempotent` / `x-idempotency`. The runtime auto-generates a key when the caller passes null. Also honors `x-idempotency: true` as a spec-level alias of `x-fern-idempotent`. | Stripe-style billing/job APIs: Firecrawl, Apify, Replicate, Stripe, etc. |
| `--generate-retry-handler` | Defaults the generated `AutoSDKRetryOptions` to vendor-SDK defaults: 3 attempts, 500ms exponential backoff (2× factor, ±20% jitter), retry on 408/409/429/5xx + `HttpRequestException`, honoring `Retry-After`. Without the flag the SDK stays single-attempt (callers opt in per-call via `AutoSDKRequestOptions.Retry`). | Streaming/audio/realtime SDKs prone to transient 5xx (AssemblyAI, ElevenLabs, Cartesia) and high-volume HTTP SDKs (Anthropic, OpenAI, Mistral) |

#### Vendor extensions that affect runtime auth

These aren't CLI flags but spec-level opt-ins. Patch them into upstream specs via `OpenApiOverrides` (see [`SPEC_WORKAROUNDS.md`](SPEC_WORKAROUNDS.md)) when the SDK needs the behavior and the source spec doesn't declare it.

| Extension | What it does | Enable on SDKs with… |
|-----------|--------------|----------------------|
| `x-call-scoped-auth: true` on an operation | Stamps `AutoSDKHttpRequestOptions.AuthorizationOverride` on the outgoing `HttpRequestMessage` so consumer `DelegatingHandler`s (rotation, account-key injection, etc.) can detect the call-scoped credential and skip the overwrite. Auto-detected for operations whose `security` block structurally differs from the document default; use this extension when the OpenAPI security model can't express the distinction — e.g. two endpoints share the same scheme reference but expect different runtime credentials (session-scoped bearer returned by an upstream poll vs. the account default). | Runway `POST /v1/realtime_sessions/{id}/consume` (session bearer from ready-poll), AssemblyAI streaming `Authorization` header endpoints, ElevenLabs Convai signed-URL session endpoints, any endpoint whose token comes from a sibling `Get…Token`/`…StartSession` call. |

### Common Build & Test Commands

```bash
# Build any SDK
dotnet build <SdkName>.slnx

# Run integration tests (most require an API key env var;
# Chroma/Weaviate/Ollama use Testcontainers — Docker required in CI)
dotnet test src/tests/IntegrationTests/

# Run a specific test
dotnet test src/tests/IntegrationTests/ --filter "FullyQualifiedName~TestName"

# Validate trimming/NativeAOT compatibility
autosdk trim src/libs/<SdkName>/<SdkName>.csproj
```

### Common Conventions

- **Target frameworks:** `net10.0` (all new SDKs target net10.0 only; legacy infrastructure like Tiktoken and CSharpToJsonSchema still multi-target)
- **Language:** C# 13 preview, nullable reference types enabled, implicit usings
- **AOT/trimming:** Source-generated JSON serialization (`JsonSerializerContext`), no reflection
- **Strong naming:** All assemblies signed with `src/key.snk`
- **Versioning:** MinVer with `v` tag prefix (e.g., `v7.0.0`)
- **Testing:** MSTest framework, AwesomeAssertions or AwesomeAssertions
- **Test pattern:** Example test files in `Examples/` directory (single source of truth for tests + docs); legacy repos may still use partial `Tests` class split across `Tests.{Feature}.cs` files
- **Auth in tests:** API key from environment variable (e.g., `OPENAI_API_KEY`), tests skip (not fail) if unset. **Always** use `is { Length: > 0 }` pattern (never `??`) to handle empty strings from CI:
  ```csharp
  // Required env var (throws inconclusive if missing/empty):
  var apiKey =
      Environment.GetEnvironmentVariable("API_KEY") is { Length: > 0 } apiKeyValue ? apiKeyValue :
      Environment.GetEnvironmentVariable("SDK_API_KEY") is { Length: > 0 } sdkKeyValue ? sdkKeyValue :
      throw new AssertInconclusiveException("SDK_API_KEY environment variable is not found.");

  // Optional env var with default:
  var modelId =
      Environment.GetEnvironmentVariable("SDK_MODEL_ID") is { Length: > 0 } modelValue ? modelValue : "default-model";
  ```
- **CI/CD:** Shared workflows from `HavenDV/workflows` repo; Dependabot for NuGet updates
- **Docs:** MkDocs Material deployed to GitHub Pages; `autosdk docs` generates docs from integration tests; comments with `////` prefix in tests become documentation prose

### Client Extension Pattern

Generated clients expose partial method hooks for customization:
- `PrepareArguments` — modify parameters before request
- `PrepareRequest` — modify HttpRequestMessage
- `ProcessResponse` — inspect/modify HttpResponseMessage
- `ProcessResponseContent` — inspect/modify response body

## Microsoft.Extensions.AI (MEAI) Integration Tracker

**Full reference:** See [`MEAI.md`](MEAI.md) for comprehensive MEAI details — feature matrices, namespace conflict patterns, CustomProviders table, per-SDK documentation links, already-implemented table, and not-applicable list.

Goal: All applicable SDKs implement MEAI interfaces for unified .NET AI abstractions.

### MEAI Interfaces

| Interface | Purpose | Namespace |
|-----------|---------|-----------|
| `IChatClient` | Chat completions (text, streaming, tool calling) | `Microsoft.Extensions.AI` |
| `IEmbeddingGenerator<string, Embedding<float>>` | Text embeddings | `Microsoft.Extensions.AI` |
| `ISpeechToTextClient` | Speech-to-text transcription | `Microsoft.Extensions.AI` |

### Implementation Pattern

MEAI implementations are hand-written partial classes in the SDK library root (outside `Generated/`):
- File naming: `{ClientName}.ChatClient.cs`, `{ClientName}.EmbeddingGenerator.cs`, etc.
- Location: `src/libs/{SdkName}/Extensions/`
- Package: `Microsoft.Extensions.AI.Abstractions` (for interfaces only) or `Microsoft.Extensions.AI` (for builders/utilities)
- Tests: `Tests.ChatClient.cs` in integration tests project

### Reference Implementation

Use `Anthropic/src/libs/Anthropic/Extensions/AnthropicClient.ChatClient.cs` as the gold-standard reference for implementing `IChatClient`. It demonstrates:
- `GetResponseAsync()` and `GetStreamingResponseAsync()`
- Text, image, and PDF content handling
- Tool/function calling with `FunctionCallContent` / `FunctionResultContent`
- Token usage tracking (including cache tokens)
- `ChatClientMetadata` for provider info
- Proper `AdditionalProperties` mapping

## Working Across Repos

- Each subdirectory is an independent git repo with its own `.git`
- There is no top-level solution file — `cd` into the specific project
- Cross-project dependencies are via NuGet packages, not project references
- AutoSDK is the upstream generator; changes there affect all downstream SDKs
- CSharpToJsonSchema is a shared dependency for tool-calling SDKs

### Never delete a component because an audit called it unreachable

`scripts/audit_unreferenced_components.py` finds components no `$ref` reaches — **2444 across 81
SDKs**, of 34046 declared — and the number invites deletion. Two checks have to run first, and both
have overturned the conclusion already.

Mind which of its two figures you quote. `--cost` reports **2180**, and that is not a stale 2444:
the cost pass skips any SDK whose orphans produce no generated type at all (`if not emitted:
continue`), so its total covers only the **70** SDKs where at least one orphan really is a public
type. Both numbers are right and they answer different questions - this file described 2180 as the
workspace-wide count for a while, which it is not.

```bash
python3 -I scripts/audit_unreferenced_components.py --cost        # renames vs lost shapes
python3 -I scripts/audit_orphan_type_usage.py --sdk <Name>        # what the SDK's own code uses
```

- **`--cost`** (over those 70 SDKs, 2180 orphans): of 1946 emitted as types, only **452 (23%) have an identically-shaped twin**
  under another name, where deleting costs the readable name alone. The other **1494 (77%) are the
  only expression of their shape**. D-ID is the exception that nearly misled me — 163 twins against
  111 unique, the one large SDK where renaming dominates.
- **`audit_orphan_type_usage`**: **21 components in 6 SDKs are used by hand-written code** despite
  nothing in the document referencing them. Cartesia's ten are its WebSocket vocabulary, which
  OpenAPI structurally cannot reference; D-ID's two are used by its own tests. It finds type
  references with `csharp_references`, not a regex — a regex answered 8 for D-ID where the answer is
  2, counting `response.Status` and a `Role =` initializer as type uses.

An unreachable component is often a real vocabulary the document simply cannot connect to an
operation. Treat the audit as a question, not a verdict.

### Auto-update cannot notice a spec that stopped changing

Each SDK's auto-update workflow compares the fetched spec with the committed one. A spec fetched from
a branch that upstream froze never changes, so no PR is opened and the SDK looks current while
falling behind. Runway hit this with `runwayml/openapi`'s `next` branch and ended up "29 models and
a whole endpoint behind"; its fix — `scripts/check-spec-source.sh`, a CI job that fails when the
fetch points anywhere but the upstream default branch — is the generalisable one.

Checked the other 50 SDKs that fetch a spec from GitHub by ref, comparing the fetched branch's last
commit with the default branch's (2026-11-17):

| SDK | fetches | its last commit | default branch |
|---|---|---|---|
| ~~**Weaviate**~~ | ~~`weaviate/weaviate` @ `openapi_docs`~~ | ~~**2025-02-18**~~ | fixed 2026-11-17 |
| ~~**Julep**~~ | ~~`julep-ai/julep` @ `dev`~~ | ~~**2026-03-13**~~ | not a defect; see below |

Weaviate's source had been frozen for 21 months, and the switch cost two spec patches rather than a
URL swap — the new document carries OpenAPI 3.1's `"type": ["string", "null"]` inside a
`swagger: "2.0"` envelope, and a `text/event-stream` response with no schema; both are in
`SPEC_WORKAROUNDS.md`. What the switch bought: **68 operations to 131**, 79 definitions to 140, and
nothing removed. That is the scale of what a frozen source hides — this SDK shipped 1.29.0 while the
server reached 1.41.0-rc.0.

**Julep was the opposite case, and the dates said nothing useful about it.** Its `dev` branch and the
default `main` really are four months apart, but `main` is **Julep 3** - upstream's own README states
it is "a ground-up rewrite; there is no migration path - v1 and v3 are different products" - and it
carries no OpenAPI document anywhere in the repository. Pointing the fetch at the default branch
would not have updated this SDK, it would have replaced it with a different API's. Julep v1 is
preserved on the `v1` branch, which is the same commit as `dev` and serves a byte-identical document,
so the fetch now reads `v1`: the same bytes under a ref whose name states the intent, where `dev`
reads like a branch that fell behind. Worth knowing separately: `api.julep.ai` is retired - every
path, existing or not, answers with an HTML redirect to `memory.store` - so the SDK's remaining use
is against a self-hosted v1.

A ref that is off the default branch on purpose now lives in the audit's own `DELIBERATE` table with
its reason, so the check exits 0 and can be a gate. Without that it would stay red for ever on a ref
that is correct, and a permanently red check is one nobody reads.

Run it from here rather than copying Runway's script into fifty repositories:

```bash
python3 -I scripts/audit_spec_source_branches.py   # exits 1 when a fetch points off the default branch
```

It asks Runway's question for every SDK at once — 48 fetches are on a default branch or a tag, and
separates two cases that look alike:

- **Letta** pins `letta-ai/letta` at `56ba9c25` *because upstream deleted the spec*. The pin is the
  only way to reach a document that no longer exists, so it is correct — and the reason is bigger than
  a moved file: on 2026-08-16 that repository was **archived into a docs-only shell** ("chore: archive
  the legacy server repository"), and its root now holds nothing but Markdown. Nowhere in the
  `letta-ai` org is there a replacement — searched for `openapi.json`, `openapi.yaml`, `fern.config.json`
  and `generators.yml` across all 66 repositories, and `letta-python`'s `.stats.yml` (it is a Stainless
  SDK, not Fern) records only `configured_endpoints: 129`, no source URL.

  `api.letta.com/openapi.json` answers **401**, which looks like an auth-gated route and is not:
  `api.letta.com/definitely-not-a-route-xyz` answers 401 too, so Letta Cloud authenticates **before**
  it routes and the status says nothing about whether the path exists. `docs.letta.com` serves no
  `docs.json`, `mint.json` or spec of its own.

  **The container idea was tested and is dead.** `letta/letta` on Docker Hub is actively published
  (`0.34.63`, 2026-11-15) and its description still reads "Run the Letta service (previously
  MemGPT)", which is what made it look like a tracking source: Letta's server was FastAPI and would
  serve its own `/openapi.json`. Running it answers otherwise - the container prints the **`letta`
  CLI's help text and exits 0**. There is no server in it and nothing listening on 8283. The same
  repository now publishes the agent CLI under the same name; PyPI says so too, where `letta`
  0.34.12 gives its source as `letta-ai/letta-code`.

  The tag timeline confirms it rather than leaving it to one run: server tags end at **0.16.8,
  2026-05-14**, then nothing until a 2026-09 wave of 0.34.x CLI tags. So even the last server image
  predates the pinned spec (2026-08-14) by three months and would be strictly worse than what is
  committed.

  Which settles the question: **the pin is not merely correct, it is the newest source that exists.**
  There is no tracking source to find, and this SDK is frozen until Letta publishes a v1 spec again
  or the SDK is retired. Do not re-derive the container idea from the image description - it
  describes a product that image no longer contains.
- **Mistral** reports its repository as unreachable, which matches the known 404 on
  `mistralai/platform-docs-public`. **Voicebox**'s `${VOICEBOX_REPOSITORY_REF:-main}` defaults to the
  default branch and is fine.

### A truncated listing undercounts, silently and in one direction

The auto-update workflow titled every PR "feat: Updated OpenAPI spec" whether or not the spec moved,
which is fixed in `tryAGI/workflows` as of 2026-11-17: the commit message and title now follow a
`spec_changed` output, and a regeneration from a byte-identical document says
`chore: Regenerated from an unchanged spec`.

Checking that against the 19 open auto-update PRs gave **three different answers** as the data source
improved, and the first two were wrong the same way:

| how the files were listed | feat | chore |
|---|---|---|
| `per_page=300` (the endpoint caps at 100) | 4 | 15 |
| `--paginate` (the endpoint caps at 3000 files per PR) | 9 | 10 |
| local `git diff origin/main FETCH_HEAD` (no cap) | **12** | **7** |

Each cap hid spec files behind generated ones and so reported a spec change as mere drift. Anthropic,
ElevenLabs and OpenAI all changed their spec and all three read as drift-only until the local diff.
The lesson generalises past this audit: when a listing comes back at exactly 100 or exactly 3000
rows, that is the API's limit, not the answer - and where the repositories are checked out, `git
diff` has no limit at all. The workflow's own detection was never affected, since it runs
`git diff --name-only` locally.

The finding that survives: **7 of 19** open auto-update PRs changed no spec at all - D-ID's touches
4560 files and not one spec line - so a third of what looks like upstream movement is the generator
moving instead.

### A `format` only means something in a schema position

Asked how many SDKs declare a typeless schema with a format nothing recognizes - the shape that
aborted generation outright before AutoSDK gained its `(null, _) => "object"` fallback - a walk over
every dict holding a `format` key and no `type` answered **52 schemas in 16 SDKs**, with formats
like `sse`, `mp4`, `wav`, `gguf` and one `'2.7'`.

Not one of them is a schema. Vectara's are the `format: sse` field of an `x-fern-streaming` vendor
extension; OpenRouter's sit under `components/schemas/ChatContentAudio/example/input_audio`;
Ollama's and Shotstack's are inside request and response **example payloads**. The generator never
type-maps any of that. Restricted to schema positions - excluding anything under `example`,
`examples`, `default` or an `x-` extension - the answer is **0 of 223 specs**.

Which also sizes the fallback honestly: it is hardening against a shape no committed spec currently
has, not a rescue of a fleet that was one vendor extension from failing. Those formats being media
types (`mp4`, `wav`, `srt`, `pdf`, `gguf`) is the tell - a media type is what a payload *is*, never
what a JSON value's type is, so finding one next to a `format` key means you are reading data, not a
schema.

`spec_tools.walk_schema_positions` is that filter, shared. Two things it cost to get right:

- **`default` means two different things.** Under a schema it is a property's default *value*;
  under `responses` it is the catch-all **status code**, and everything below it is as much a schema
  as a `200` would be. Excluding it blindly hid **416** genuine schema positions, all of the shape
  `paths/<route>/<method>/responses/default/content/.../schema`. It was caught by pointing the
  filter at a different question - reachability - and seeing it call those non-schemas.
- **Do not apply it to a reachability question.** Asked which schema `$ref`s sit outside a schema
  position, it answers 209 of 96996, and the remainder is almost entirely vendor extensions that
  hold *real* references: `x-fern-streaming` (152), `x-webhooks` (17), `x-apifox-refs`,
  `x-stainless-stream-event-schema`. Filtering those out would mark ~190 live references as absent
  and **invent orphans**, which is the failure the unreferenced-components audit already warns
  about. Only 12 were genuinely data, under `example`/`examples`. The filter belongs to questions
  about what a schema *declares*, not to questions about what points at one.

Checked the other audits for the same exposure rather than refactoring on principle:
`audit_response_required_defaults.py` iterates `components.schemas` by name and never walks blindly,
and the streaming-media-type scan had 0 hits in non-schema positions. So one filter, two call sites,
and a measured reason not to spread it further.

### A regeneration can break a build with no spec change at all

Julep was regenerated on 2026-11-17 for a reason that had nothing to do with its models - the fetch
ref was renamed - and its spec came back **byte-identical**. The library then failed to compile:
three `CS3001`s, because a released `autosdk.cli` had started mapping `format: int8` to `sbyte`,
which is not CLS-compliant, while `src/libs/Directory.Build.props` declares the assembly
`[CLSCompliant(true)]`. The same regeneration also moved 42 files from `int` to `long`.

So an auto-update PR can go red without upstream touching anything: the generator moved, not the
spec. The per-SDK fix is a `generate.sh` step that drops the offending format and leaves
`type: integer`, which keeps the declared `minimum`/`maximum`.

```bash
python3 -I scripts/audit_non_cls_integer_formats.py   # exits 1 while any SDK is exposed
```

**Only `int8` qualifies, and getting that wrong is easy.** The first version of that script also
flagged `uint16` and `uint32` on the reasoning that `ushort` and `uint` are not CLS-compliant
either, and reported **seven** exposed SDKs. Reading `CSharpTypeMapper` instead of reasoning about
it says AutoSDK never emits those: every unsigned format is deliberately widened into a signed type
(`uint8` -> `byte`, `uint16` -> `int`, `uint32` -> `long`, `uint64` -> `long`). That is also visible
in Julep's own output, where a `format: uint16` field generates a plain `int`. Six of the seven were
never exposed; the audit reports **0** now that Julep carries the step.

### A workspace-wide figure is a snapshot of a moving tree

Every SDK's auto-update workflow fetches its spec every few hours and opens a PR, so the sibling
`Generated/` trees change under you — including mid-session, as soon as a repo is fast-forwarded in
order to commit something unrelated.

Measured on 2026-11-17: the numeric-suffix audit went from 8796 collisions to 8010 in the course of
one session, and almost none of it was the work being done. **17 "Updated OpenAPI spec" commits**
landed in that window:

| | collisions |
|---|---|
| Braintrust spec update | −502 |
| Topaz | −170 |
| Botpress | −96 |
| the D-ID duplicate collapse (deliberate) | −6 |

That is −774 of the −786 the total moved, and three of the four are upstream refreshes.

So when quoting a workspace-wide number: name the date, and if it has to be comparable, measure both
sides from pinned revisions rather than from the working trees.
`audit_snapshot_collisions --rev X --after-rev Y` exists for exactly that reason — the dedup figures
came from AutoSDK revisions and are reproducible; the sibling-SDK figures are not.

### The audits need PyYAML built with libyaml

`spec_tools.load_document` parses with `CSafeLoader` when it exists. The pure-Python loader is about
**11x slower** on these documents (8.80s against 0.79s on Anthropic's 7MB spec) and was 76% of one
audit's runtime before the switch. A PyYAML built without libyaml still works and `spec_tools` warns
once on stderr, because otherwise every audit would simply be slow with nothing to say why.

For reference, with libyaml: orphan-usage 18.6s, duplicate-components 12.2s, numeric-suffixes 11.8s,
collision-distinguisher 8.9s, response-required-defaults 8.3s, unreferenced-components 7.2s,
undeclared-streams 6.3s, generation-inputs 3.5s, keyless-tests 1.2s.

### Read the contract, not the artifact

Three wrong entries went into Cartesia's CLAUDE.md in one sitting, each from inspecting one artifact
and generalizing: `ls asyncapi.*` found nothing so "there is no AsyncAPI" (its contracts are named
`stt-asyncapi.json` and fetched at generation time); a grep for `Cartesia-Version` over generated
output found nothing so "the header is lost" (the contract declares `cartesia_version` as a required
*query* parameter). `scripts/audit_generation_inputs.py` answers the first question properly - it
reads the `autosdk generate` invocations and classifies each document by its `asyncapi:`/`openapi:`
key.

Applied across the 13 SDKs that generate from an AsyncAPI, the question "is this hand-written
realtime client superseded?" has three different answers, and **dates alone give the wrong one**:

| | |
|---|---|
| **Cartesia** | Superseded. Both STT channels are generated, the version is a required typed parameter there, and MEAI never opened a WebSocket. Entry points now `[Obsolete]`. |
| **ElevenLabs** | **Not** superseded, though its hand-written session (2026-05-25) long predates the generated clients (2026-10-19). Its contracts declare `realtime`, `dialogue` and `dialogueMulti` - **no STT channel** - so `RealtimeSpeechToTextSession` is the only implementation of it. Going by dates would have deprecated a live client. |
| **OpenAI** | Genuine overlap - contract and hand-written session both cover `realtime` - but the hand-written one adds an `ILogger` and a service wrapper, and arrived two days before the generated client. A judgement call, not neglect. |
| Deepgram, Inworld, Simli, Xai | Not duplicates at all. Their `*.Auth.cs` / `*.Extensions.cs` files extend the generated clients, which is the pattern here; they only look like candidates because they touch `ClientWebSocket` options. |
| AssemblyAI, Mistral, NariLabs, SmallestAI, Soniox, Ultravox | No hand-written WebSocket code. |

So the check is: which channels does the contract declare, and does the hand-written code implement
one of them. Not the file's age, and not whether a grep finds a string in the output.

### Don't let a suite of nothing but skips pass for a green run

Most integration tests fetch an API key and raise `AssertInconclusiveException` without one, which
MSTest reports as *skipped*. A suite where **every** test does that prints `Skipped!` and exits 0, so
a spec fix or a regenerated model there is backed by nothing but a successful build. Measured
2026-11-17: **137 of 235 SDKs have no key-free test at all.**

```bash
python3 -I scripts/audit_keyless_tests.py           # where the gaps are
python3 -I scripts/audit_keyless_tests.py --check   # exit 1 if an SDK LOSES coverage it had
python3 -I scripts/audit_keyless_tests.py --write-baseline   # after adding tests, lock the gain in
```

`--check` is a ratchet against `scripts/keyless-tests-baseline.json`, not a target: it does not
demand the 137 grow tests, it catches coverage disappearing, which nothing else would notice.

**It cannot run in this repository's CI.** The workspace repo tracks no SDK — only docs and scripts
— so a job here has no `*/src/tests` to scan. Run it where the repositories are checked out side by
side. The per-SDK equivalent belongs in the shared workflow (`HavenDV/workflows`): assert the test
step reported `Passed!` rather than `Skipped!`.

## Reference Files

Detailed reference data is split into dedicated files to keep this file concise:

- [`SDK_CATALOG.md`](SDK_CATALOG.md) — Full list of all ~100+ projects by category (Core Infrastructure, LangChain, Auto-Generated SDKs, Applications)
- [`NEW_SDK_GUIDE.md`](NEW_SDK_GUIDE.md) — Creating new SDKs (`autosdk init`), GitHub repo setup (topics, pages), documentation generation, AsyncAPI, CSharpToJsonSchema tools integration
- [`SPEC_WORKAROUNDS.md`](SPEC_WORKAROUNDS.md) — Spec fix inventory table, resolved/open AutoSDK issues, auth runtime hooks list
- [`MEAI.md`](MEAI.md) — MEAI implementation tracker, feature matrices, namespace conflict patterns, CustomProviders table, already-implemented table, not-applicable list, per-SDK documentation links
