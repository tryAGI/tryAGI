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

## Reference Files

Detailed reference data is split into dedicated files to keep this file concise:

- [`SDK_CATALOG.md`](SDK_CATALOG.md) — Full list of all ~100+ projects by category (Core Infrastructure, LangChain, Auto-Generated SDKs, Applications)
- [`NEW_SDK_GUIDE.md`](NEW_SDK_GUIDE.md) — Creating new SDKs (`autosdk init`), GitHub repo setup (topics, pages), documentation generation, AsyncAPI, CSharpToJsonSchema tools integration
- [`SPEC_WORKAROUNDS.md`](SPEC_WORKAROUNDS.md) — Spec fix inventory table, resolved/open AutoSDK issues, auth runtime hooks list
- [`MEAI.md`](MEAI.md) — MEAI implementation tracker, feature matrices, namespace conflict patterns, CustomProviders table, already-implemented table, not-applicable list, per-SDK documentation links
