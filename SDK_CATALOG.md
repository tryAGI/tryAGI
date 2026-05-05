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
`Anthropic/`, `Arcee/`, `AwsBedrock/`, `Cohere/`, `DashScope/`, `DeepInfra/`, `Gonka/`, `Google.Gemini/`, `Mistral/`, `Moonshot/`, `Ollama/`, `OpenAI/`, `PredictionGuard/`, `Reka/`, `SarvamAI/`, `StepFun/`, `TencentTokenHub/`, `Together/`, `AI21/`, `Upstage/`, `Writer/`, `Writesonic/`, `Xai/`, `ZAI/`

**Image / Video / 3D Generation:**
`BlackForestLabs/`, `BlockadeLabs/`, `BytePlusModelArk/`, `Creatomate/`, `CsmAi/`, `DashScope/`, `DId/`, `DoubaoSeed3D/`, `EigenAI/`, `HeyGen/`, `Hedra/`, `Hitem3D/`, `Hyper3D/`, `Ideogram/`, `ImagineArt/`, `KlingAI/`, `Krea/`, `Leonardo/`, `Luma/`, `MagicHour/`, `Meshcapade/`, `Meshy/`, `MicrosoftFoundry/`, `Neural4D/`, `Picsart/`, `Photoroom/`, `Pruna/`, `Recraft/`, `Replicate/`, `Reve/`, `Runware/`, `Runway/`, `Shotstack/`, `Sloyd/`, `StabilityAI/`, `Synthesia/`, `Tavus/`, `ThreeDAIStudio/`, `Tripo/`, `Triverse/`, `WaveSpeedAI/`, `WorldLabs/`, `ZAI/`

**Document / Presentation / PDF Generation:**
`APITemplate/`, `Gamma/`, `PDF4Dev/`, `Presenton/`

**Audio / Speech:**
`AssemblyAI/`, `AsyncAI/`, `Cartesia/`, `Deepgram/`, `ElevenLabs/`, `FishAudio/`, `Gladia/`, `Gradium/`, `Inworld/`, `LalalAI/`, `LMNT/`, `MiniMax/`, `Murf/`, `PlayHT/`, `ResembleAI/`, `RetellAI/`, `RevAI/`, `Revocalize/`, `Reverie/`, `Rime/`, `SmallestAI/`, `Speechify/`, `Speechmatics/`, `StepFun/`, `Ultravox/`, `Vapi/`, `VoiceAI/`, `ZAI/`

**Search / RAG / Embeddings:**
`Algolia/`, `BraveSearch/`, `DashScope/`, `Exa/`, `GroundX/`, `Jina/`, `Mixedbread/`, `Nomic/`, `Serper/`, `Tavily/`, `Vectara/`, `VoyageAI/`

**Web Scraping / Data Extraction:**
`Apify/`, `ScrapeGraphAI/`

**Vector Databases:**
`Chroma/`, `Milvus/`, `Pinecone/`, `Qdrant/`, `Turbopuffer/`, `Weaviate/`

**Generative Media Inference:**
`EachLabs/`, `Fal/`

**Unified AI Inference:**
`SiliconFlow/`

**AI Gateway / Routing:**
`AwsBedrock/`, `EdenAI/`, `Martian/`, `OpenRouter/`, `Portkey/`, `TencentTokenHub/`

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
`CursorAgents/`, `V0/`

**Code Intelligence:**
`Greptile/`

**Document Processing:**
`DoclingServe/`, `LlamaParse/`, `Nanonets/`, `Reducto/`

**Emotion AI:**
`HumeAI/`

**Time Series AI:**
`Nixtla/`

**CAD Generation:**
`Zoo/`

**AI Video/Audio Editing:**
`Descript/`, `Revocalize/`

**Prompt Management / Evaluation:**
`Humanloop/`, `PromptLayer/`, `Vellum/`

**Data Labeling / Annotation / RLHF:**
`Dataloop/`, `LabelStudio/`, `ScaleAI/`

**Fine-Tuning / Model Serving:**
`Baseten/`, `Predibase/`

**AI Music Generation:**
`Beatoven/`, `ElevenLabs/`, `Google.Gemini/`, `Loudly/`, `MiniMax/`, `Mubert/`, `Mureka/`, `Sonauto/`

`Google.Gemini/` covers Google Lyria music generation, including the Producer.ai / Google Flow Music-style path, through [Gemini API Lyria helpers](https://ai.google.dev/gemini-api/docs/music-generation). Do not create a separate `Producer.ai/` SDK unless Google publishes a first-party Producer.ai or Flow Music API that is distinct from Gemini/Lyria.

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

## 3.1 SDK Candidate Notes

See [`TTS_API_COVERAGE.md`](TTS_API_COVERAGE.md) for the 2026-05-04 text-to-speech provider coverage pass, including new SDKs, existing coverage, hosted/open-weight paths, external official SDKs, and blocked direct SDKs.

**Blocked first-party SDKs:**

| Candidate | Status | Reason / Existing Path |
|-----------|--------|------------------------|
| `Producer.ai/` | Blocked | Producer.ai is now a [Google Labs](https://blog.google/innovation-and-ai/models-and-research/google-labs/producerai/) / Google Flow Music product. Use `Google.Gemini/` Lyria helpers for the documented API path unless Google publishes a separate first-party Producer.ai or Flow Music API. |
| `Udio/` | Blocked | [Udio does not currently offer a public API](https://help.udio.com/en/articles/10756277-udio-public-api). Avoid a first-party `Udio/` SDK until Udio publishes official API documentation. |

**Third-party music gateway candidates:**

| Candidate | Status | Recommendation |
|-----------|--------|----------------|
| `AIMusicAPI/` | Viable | Best fit if a third-party music-generation gateway is acceptable. It documents [Producer endpoints](https://docs.aimusicapi.ai/producer-api-overview) plus Sonic/Nuro music workflows; expect a hand-maintained OpenAPI spec unless an official spec becomes available. |
| `TTAPI/` | Viable but broad | Covers [Producer/Lyria](https://docs.ttapi.io/api/en/producer) and many non-music models. Consider only if a broad unified AI gateway SDK is desired, or scope the generated spec to the Producer endpoints first. |
| `UdioApiPro/` / `Apiframe/` | Use caution | These expose [Udio-style third-party](https://altrix.udioapi.pro/docs) APIs, but should be named after the gateway provider, not `Udio/`, because Udio itself has no public API. |

## 4. Applications & Utilities

| Project | Description |
|---------|-------------|
| `AI/` | CLI tool for AI-powered tasks: summarization, release notes, changelogs, code docs, MCP server. |
| `docs/` | Centralized documentation hub (MkDocs Material). Live at [tryagi.github.io/docs](https://tryagi.github.io/docs/). |
| `askmycv/` | Full-stack job board app (Angular 18 + .NET 7 + PostgreSQL) with AI-powered chat. |
| `PrivateJoi/` | Core Joi logic library using OpenAI API. |
| `Transcendence/` | Placeholder/early-stage project. |
| `Do/` | Empty/placeholder repository. |
