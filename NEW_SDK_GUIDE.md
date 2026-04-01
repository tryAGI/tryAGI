# New SDK Guide

How to create, configure, and document new AutoSDK-based SDK projects.

## Creating a New SDK

Use `autosdk init` to scaffold a new SDK project (solution, csproj, generate.sh, CI workflows, tests, docs):

```bash
cd /Users/havendv/GitHub/tryAGI
autosdk init <SdkName> <ClientClassName> "<openapi-spec-url>" tryAGI --add-mkdocs --add-tests
```

Then fix the auth scheme in `generate.sh` if needed (many specs use non-standard `apiKey` auth) and run `./generate.sh` to produce the `Generated/` code.

## GitHub Repo Setup

After creating a new SDK repo, configure its GitHub metadata using `gh repo edit`:

**Description format:**
```
C# SDK for the <Provider> API -- <brief capabilities summary>
```

**Homepage:** `https://tryagi.github.io/<SdkName>/`

**Topics** — always apply the core set + category-specific tags + provider name:

| Tag Group | Tags | When to Apply |
|-----------|------|---------------|
| **Core** (always) | `csharp`, `dotnet`, `sdk`, `ai`, `autosdk`, `openapi` | Every SDK |
| **LLM/Chat** | `llm`, `chat-completion` | Chat completion providers |
| **Image generation** | `image-generation` | Image generation providers |
| **Video generation** | `video-generation` | Video generation providers |
| **3D generation** | `3d-generation` | 3D model generation providers |
| **Speech-to-text** | `speech-to-text`, `transcription` | STT providers |
| **Text-to-speech** | `text-to-speech` | TTS providers |
| **Embeddings** | `embeddings` | Embedding providers |
| **Search/RAG** | `search`, `rag` | Search/RAG providers |
| **Vector DB** | `vector-database` | Vector database providers |
| **Observability** | `observability`, `tracing` | Observability/eval platforms |
| **Agent infra** | `ai-agents` | Agent infrastructure providers |
| **Provider name** | e.g., `openai`, `anthropic` | Always — the provider's brand name |

**Example for a new LLM SDK:**
```bash
gh repo edit tryAGI/MyProvider \
  --description "C# SDK for the MyProvider API -- chat completions, embeddings, and tool calling" \
  --homepage "https://tryagi.github.io/MyProvider/" \
  --allow-update-branch \
  --enable-auto-merge \
  --delete-branch-on-merge \
  --topic "csharp,dotnet,sdk,ai,autosdk,openapi,myprovider,llm,chat-completion,embeddings"
```

**Repository settings** — always enable these so bot PRs can auto-merge and stale branches are cleaned up:
- `Always suggest updating pull request branches`
- `Allow auto-merge`
- `Automatically delete head branches`

**Tags to NEVER use** (outdated/misleading):
`net6`, `net7`, `net8`, `net9`, `netstandard`, `netframework`, `nswag`, `swagger`, `specification`, `generated`, `generator`, `langchain`, `langchain-dotnet`

**GitHub Pages** — configure the build source to **GitHub Actions** (not "Deploy from a branch"):

```bash
gh api repos/tryAGI/MyProvider/pages -X POST -f build_type=workflow -f source.branch=main 2>/dev/null || \
gh api repos/tryAGI/MyProvider/pages -X PUT -f build_type=workflow -f source.branch=main
```

This is required for the MkDocs Material CI workflow (`.github/workflows/mkdocs.yml`) to deploy docs to `https://tryagi.github.io/<SdkName>/`.

## Documentation Generation

Integration tests in `Examples/` directories serve as the **single source of truth** for both test coverage and documentation:

```
src/tests/<TestProject>/Examples/
├── ChatCompletion.cs       # /* order: 10, title: Chat Completion, slug: chat-completion */
├── Streaming.cs            # /* order: 20, title: Streaming, slug: streaming */
└── ToolCalling.cs          # /* order: 30, title: Tool Calling, slug: tool-calling */
```

**How it works:**
1. Each Example file has a **JSDoc header** (`order`, `title`, `slug`) consumed by `autosdk docs sync .`
2. Comments prefixed with **`////`** become prose paragraphs in generated docs
3. CI workflow (`.github/workflows/mkdocs.yml`) runs `autosdk docs sync .` to:
   - Auto-generate `docs/examples/` markdown files from Example test files
   - Populate `EXAMPLES:START/END` markers in README.md, docs/index.md, and mkdocs.yml
4. Config file **`autosdk.docs.json`** at repo root points to the examples directory:
   ```json
   { "exampleSourceDirectory": "src/tests/IntegrationTests/Examples" }
   ```

**Conventions:**
- `docs/index.md` must be **identical** to `README.md` (autosdk updates both via markers)
- Hand-written guide pages go in `docs/guides/` (not touched by autosdk)
- Guide pages are listed in `mkdocs.yml` nav **above** the `# EXAMPLES:START/END` markers
- Most SDKs use `src/tests/IntegrationTests/Examples`; some use `src/tests/<SdkName>.IntegrationTests/Examples`

## AsyncAPI & Cross-Namespace Schema Referencing

Some SDKs have both REST (OpenAPI) and WebSocket/realtime (AsyncAPI) APIs. When they share model types, use **cross-namespace schema referencing** to avoid duplicating models:

```bash
# Step 1: Generate REST API (models + HTTP client) in main namespace
autosdk generate openapi.yaml \
  --namespace tryAGI.MyApi \
  --output Generated

# Step 2: Generate WebSocket client referencing existing types (no model duplication)
autosdk generate asyncapi.json \
  --namespace tryAGI.MyApi.Realtime \
  --types-namespace tryAGI.MyApi \
  --generate-models false \
  --json-serializer-context tryAGI.MyApi.SourceGenerationContext \
  --output Generated
```

**Key options:**
- `--types-namespace <ns>` — Type references in generated WebSocket client use `global::<ns>.{TypeName}` instead of the client's own namespace
- `--generate-models false` — Skip model/enum/converter generation (they live in the types namespace)
- `--json-serializer-context <ctx>` — Reference an existing `JsonSerializerContext` from the types namespace

**Constraint:** AsyncAPI schema names must match the target namespace's type names. If they don't match (e.g., OpenAI where AsyncAPI uses different names), use separate namespaces with full model generation.

**SDKs with dual OpenAPI + AsyncAPI:**
- `OpenAI/` — REST API + Realtime WebSocket API
- `ElevenLabs/` — REST API + Realtime Speech-to-Text WebSocket API

## Tools Integration (CSharpToJsonSchema)

SDKs that support function/tool calling (Anthropic, OpenAI, Ollama) use CSharpToJsonSchema:
1. Define C# interface with `[GenerateJsonSchema]` attribute
2. Add `[Description]` attributes for function/parameter docs
3. Convert via `service.AsTools()` / `service.AsCalls()`
