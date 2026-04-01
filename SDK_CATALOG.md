# SDK Catalog

Full list of all projects in the tryAGI workspace, organized by category.

## 1. Core Infrastructure

| Project | Description |
|---------|-------------|
| `AutoSDK/` | Roslyn incremental source generator framework that auto-generates .NET SDKs from OpenAPI specs. CLI tool + NuGet library. The engine behind most SDKs here. |
| `AutoSDK.Portal/` | Next.js/TypeScript SaaS portal for AutoSDK (authentication, Stripe, dashboard). Not a .NET project. |
| `CSharpToJsonSchema/` | Source generator that converts C# interfaces/methods to JSON Schema for function/tool calling (OpenAI, Anthropic, Ollama, etc.). |
| `DotnetCliWrapper/` | .NET wrapper for running `dotnet` CLI commands from C# and parsing structured results. |
| `SdkTemplate/` | Template/scaffold repository for initializing new AutoSDK-based SDK projects. |
| `Tiktoken/` | High-performance .NET port of OpenAI's Tiktoken tokenizer (o200k_base, cl100k_base, r50k_base, p50k_base). |
| `openai-dotnet/` | Fork/mirror of the official OpenAI .NET library (Microsoft collaboration). |

## 2. LangChain Ecosystem

| Project | Description |
|---------|-------------|
| `LangChain/` | C# implementation of the LangChain framework — chat, embeddings, RAG, vector DBs, multi-provider support. |
| `LangChain.Providers/` | Standalone provider abstractions for AI service integrations (usable without LangChain core). |
| `LangChain.Databases/` | Standalone database/vector storage abstractions (usable without LangChain core). |
| `LangChain.Maui/` | .NET MAUI integration and sample app for LangChain. |
| `LangChainChat/` | Blazor chat demo app using LangChain with local or paid AI models. |

## 3. Auto-Generated AI/ML SDKs (via AutoSDK)

All follow the same architecture pattern (see "Common SDK Structure" in [CLAUDE.md](CLAUDE.md)). Each wraps a provider's OpenAPI spec into a typed C# client.

**LLM / Text Generation:**
`Anthropic/`, `Cohere/`, `DeepInfra/`, `Google.Gemini/`, `Mistral/`, `Ollama/`, `OpenAI/`, `PredictionGuard/`, `Reka/`, `SarvamAI/`, `Together/`, `AI21/`, `Upstage/`, `Writer/`, `Writesonic/`, `Xai/`

**Image / Video / 3D Generation:**
`BlackForestLabs/`, `Creatomate/`, `DId/`, `HeyGen/`, `Hedra/`, `Ideogram/`, `KlingAI/`, `Leonardo/`, `Luma/`, `MagicHour/`, `Meshcapade/`, `Meshy/`, `Picsart/`, `Photoroom/`, `Recraft/`, `Replicate/`, `Runway/`, `Shotstack/`, `StabilityAI/`, `Synthesia/`, `Tavus/`, `Tripo/`, `WaveSpeedAI/`

**Audio / Speech:**
`AssemblyAI/`, `Cartesia/`, `Deepgram/`, `ElevenLabs/`, `FishAudio/`, `Gladia/`, `LalalAI/`, `Murf/`, `RetellAI/`, `RevAI/`, `Speechmatics/`, `Ultravox/`, `Vapi/`

**Search / RAG / Embeddings:**
`Algolia/`, `BraveSearch/`, `Exa/`, `GroundX/`, `Jina/`, `Mixedbread/`, `Nomic/`, `Serper/`, `Tavily/`, `Vectara/`, `VoyageAI/`

**Web Scraping / Data Extraction:**
`Apify/`, `ScrapeGraphAI/`

**Vector Databases:**
`Chroma/`, `Milvus/`, `Pinecone/`, `Qdrant/`, `Turbopuffer/`, `Weaviate/`

**Generative Media Inference:**
`Fal/`

**Unified AI Inference:**
`SiliconFlow/`

**AI Gateway / Routing:**
`EdenAI/`, `Martian/`, `OpenRouter/`, `Portkey/`

**Observability / Evaluation:**
`Helicone/`, `Langfuse/`, `Opik/`, `Phoenix/`, `Weave/`

**AI Memory / Agent Infrastructure:**
`Botpress/`, `CursorAgents/`, `Dust/`, `E2B/`, `Julep/`, `Letta/`, `Mem0/`, `Zep/`

**Browser Automation:**
`Browserbase/`

**AI Security / Guardrails:**
`Guardrails/`, `Lakera/`

**Content Moderation:**
`ModerationAPI/`, `Sightengine/`

**Computer Vision:**
`CVAT/`, `Roboflow/`

**Video Understanding:**
`TwelveLabs/`

**Translation / NLP:**
`DeepL/`, `ModernMT/`, `SarvamAI/`

**Voice AI / Phone / Testing:**
`BlandAI/`, `HammingAI/`

**AI Agents / Coding:**
`CursorAgents/`

**Code Intelligence:**
`Greptile/`

**Document Processing:**
`DoclingServe/`, `LlamaParse/`, `Nanonets/`, `Reducto/`

**Emotion AI:**
`HumeAI/`

**Time Series AI:**
`Nixtla/`

**AI Video/Audio Editing:**
`Descript/`

**Prompt Management / Evaluation:**
`Humanloop/`, `PromptLayer/`, `Vellum/`

**Data Labeling / Annotation / RLHF:**
`Dataloop/`, `LabelStudio/`, `ScaleAI/`

**Fine-Tuning / Model Serving:**
`Baseten/`, `Predibase/`

**AI Music Generation:**
`Loudly/`

**Synthetic Data / Privacy:**
`Gretel/`

**Data Security / DLP:**
`NightfallAI/`

**Developer Email:**
`Resend/`

**Recommendation Engine:**
`Recombee/`

**Notification Infrastructure:**
`Novu/`

**Platforms / Orchestration:**
`Composio/`, `Coze/`, `Firecrawl/`, `Flowise/`, `Forem/`, `HuggingFace/`, `Instill/`, `LangSmith/`

**Marketing Content Generation:**
`JasperAI/`, `Writesonic/`

**Placeholder / Incomplete:**
`Groq/`

## 4. Applications & Utilities

| Project | Description |
|---------|-------------|
| `AI/` | CLI tool for AI-powered tasks: summarization, release notes, changelogs, code docs, MCP server. |
| `docs/` | Centralized documentation hub (MkDocs Material). Live at [tryagi.github.io/docs](https://tryagi.github.io/docs/). |
| `askmycv/` | Full-stack job board app (Angular 18 + .NET 7 + PostgreSQL) with AI-powered chat. |
| `PrivateJoi/` | Core Joi logic library using OpenAI API. |
| `Transcendence/` | Placeholder/early-stage project. |
| `Do/` | Empty/placeholder repository. |
