# Microsoft.Extensions.AI (MEAI) — tryAGI SDK Reference

This document provides a single source of truth for MEAI interface implementations across all tryAGI SDKs.

> **Published version:** [tryagi.github.io/docs/meai/](https://tryagi.github.io/docs/meai/)

## Quick Reference

| SDK | `IChatClient` | `IEmbeddingGenerator` | `ISpeechToTextClient` | `AIFunction` | Namespace Conflict |
|-----|:---:|:---:|:---:|:---:|:---:|
| [Anthropic](https://github.com/tryAGI/Anthropic) | Y | - | - | - | No |
| [Ollama](https://github.com/tryAGI/Ollama) | Y | Y | - | - | No |
| [OpenAI](https://github.com/tryAGI/OpenAI) | Y | Y | - | - | Yes (`Meai`) |
| [Google.Gemini](https://github.com/tryAGI/Google_Generative_AI) | Y | Y | - | - | No |
| [Mistral](https://github.com/tryAGI/Mistral) | Y | - | - | - | Yes (`Meai`) |
| [Cohere](https://github.com/tryAGI/Cohere) | Y | Y | - | - | Yes (`Meai`) |
| [Coze](https://github.com/tryAGI/Coze) | Y | - | - | - | No |
| [Together](https://github.com/tryAGI/Together) | Y | Y | - | - | Yes (`Meai`) |
| [AI21](https://github.com/tryAGI/AI21) | Y | - | - | - | No |
| [Reka](https://github.com/tryAGI/Reka) | Y | - | Y | - | Yes (`Meai`) |
| [HuggingFace](https://github.com/tryAGI/HuggingFace) | Y | Y | - | - | No |
| [Jina](https://github.com/tryAGI/Jina) | - | Y | - | - | No |
| [VoyageAI](https://github.com/tryAGI/VoyageAI) | - | Y | - | - | No |
| [Nomic](https://github.com/tryAGI/Nomic) | - | Y | - | Y | No |
| [ElevenLabs](https://github.com/tryAGI/ElevenLabs) | - | - | Y | - | No |
| [AssemblyAI](https://github.com/tryAGI/AssemblyAI) | - | - | Y | - | No |
| [Gladia](https://github.com/tryAGI/Gladia) | - | - | Y | - | No |
| [Cartesia](https://github.com/tryAGI/Cartesia) | - | - | Y | - | No |
| [Writer](https://github.com/tryAGI/Writer) | Y | - | - | - | Yes (`Meai`) |
| [Mixedbread](https://github.com/tryAGI/Mixedbread) | - | Y | - | - | Yes (`Meai`) |
| [Deepgram](https://github.com/tryAGI/Deepgram) | - | - | Y | - | No |
| [Pinecone](https://github.com/tryAGI/Pinecone) | - | Y | - | Y | Yes (`Meai`) |
| [RevAI](https://github.com/tryAGI/RevAI) | - | - | Y | Y | No |
| [Speechmatics](https://github.com/tryAGI/Speechmatics) | - | - | Y | Y | No |
| [Upstage](https://github.com/tryAGI/Upstage) | Y | Y | - | Y | Yes (`Meai`) |
| [Tavily](https://github.com/tryAGI/Tavily) | - | - | - | Y | No |
| [Exa](https://github.com/tryAGI/Exa) | - | - | - | Y | No |
| [Serper](https://github.com/tryAGI/Serper) | - | - | - | Y | No |
| [TwelveLabs](https://github.com/tryAGI/TwelveLabs) | - | Y | - | - | No |
| [DeepL](https://github.com/tryAGI/DeepL) | - | - | - | Y | No |
| [Braintrust](https://github.com/tryAGI/Braintrust) | - | - | - | Y | No |
| [LlamaParse](https://github.com/tryAGI/LlamaParse) | - | - | - | Y | No |
| [Opik](https://github.com/tryAGI/Opik) | - | - | - | Y | No |
| [Browserbase](https://github.com/tryAGI/Browserbase) | - | - | - | Y | No |
| [Composio](https://github.com/tryAGI/Composio) | - | - | - | Y | No |
| [Helicone](https://github.com/tryAGI/Helicone) | - | - | - | Y | No |
| [BraveSearch](https://github.com/tryAGI/BraveSearch) | - | - | - | Y | No |
| [FishAudio](https://github.com/tryAGI/FishAudio) | - | - | Y | Y | No |
| [SarvamAI](https://github.com/tryAGI/SarvamAI) | Y | - | Y | Y | Yes (`Meai`) |
| [KlingAI](https://github.com/tryAGI/KlingAI) | - | - | - | Y | No |
| [CursorAgents](https://github.com/tryAGI/CursorAgents) | - | - | - | Y | No |
| [Vapi](https://github.com/tryAGI/Vapi) | - | - | - | Y | No |
| [Tavus](https://github.com/tryAGI/Tavus) | - | - | - | Y | No |
| [RetellAI](https://github.com/tryAGI/RetellAI) | - | - | - | Y | No |
| [DId](https://github.com/tryAGI/DId) | - | - | - | Y | No |
| [Synthesia](https://github.com/tryAGI/Synthesia) | - | - | - | Y | No |
| [Milvus](https://github.com/tryAGI/Milvus) | - | - | - | Y | No |

### Via tryAGI.OpenAI CustomProviders

These providers get `IChatClient` + `IEmbeddingGenerator` through `CustomProviders.*()`:

| Provider | Factory Method | Default Chat Model |
|----------|---------------|-------------------|
| Azure | `CustomProviders.Azure(key, endpoint)` | `gpt-4o-mini` |
| DeepInfra | `CustomProviders.DeepInfra(key)` | `Qwen/Qwen2.5-72B-Instruct` |
| DeepSeek | `CustomProviders.DeepSeek(key)` | `deepseek-chat` |
| Groq | `CustomProviders.Groq(key)` | `llama-3.3-70b-versatile` |
| XAi | `CustomProviders.XAi(key)` | `grok-3-mini` |
| Fireworks | `CustomProviders.Fireworks(key)` | `llama-v3p3-70b-instruct` |
| OpenRouter | `CustomProviders.OpenRouter(key)` | `meta-llama/llama-3.2-3b-instruct:free` |
| Together | `CustomProviders.Together(key)` | `Llama-3.3-70B-Instruct-Turbo` |
| Perplexity | `CustomProviders.Perplexity(key)` | `sonar` |
| SambaNova | `CustomProviders.SambaNova(key)` | `Meta-Llama-3.3-70B-Instruct` |
| Mistral | `CustomProviders.Mistral(key)` | `mistral-large-latest` |
| Codestral | `CustomProviders.Codestral(key)` | `codestral-latest` |
| Cerebras | `CustomProviders.Cerebras(key)` | `llama3.1-70b` |
| Cohere | `CustomProviders.Cohere(key)` | `command-r-08-2024` |
| Nebius | `CustomProviders.Nebius(key)` | `Qwen/Qwen2.5-72B-Instruct` |
| Hyperbolic | `CustomProviders.Hyperbolic(key)` | `Llama-3.3-70B-Instruct` |
| Nvidia | `CustomProviders.Nvidia(key)` | `meta/llama-3.3-70b-instruct` |
| GitHub Models | `CustomProviders.GitHubModels(token)` | `gpt-4o` |
| Ollama | `CustomProviders.Ollama()` | `llama3.2` |
| Ollama Cloud | `CustomProviders.OllamaCloud(key)` | `llama3.2` |
| LM Studio | `CustomProviders.LmStudio()` | (user-selected) |
| Minimax | `CustomProviders.Minimax(key)` | `MiniMax-M1` |
| NovitaAI | `CustomProviders.NovitaAI(key)` | (user-selected) |
| Qwen | `CustomProviders.Qwen(key)` | (user-selected) |
| LeptonAI | `CustomProviders.LeptonAI(key)` | (user-selected) |
| Cleanlab | `CustomProviders.Cleanlab(key)` | (user-selected) |
| SiliconFlow | `CustomProviders.SiliconFlow(key)` | (user-selected) |

## MEAI Version

All SDKs use **Microsoft.Extensions.AI.Abstractions 10.4.1**.

## Namespace Conflict Pattern

Some auto-generated SDKs have their own `IChatClient` interface that shadows `Microsoft.Extensions.AI.IChatClient`. Use the `Meai` alias:

```csharp
using Meai = Microsoft.Extensions.AI;

Meai.IChatClient chatClient = client;
var response = await chatClient.GetResponseAsync(
    [new Meai.ChatMessage(Meai.ChatRole.User, "Hello!")],
    new Meai.ChatOptions { ModelId = "model-name" });
```

**SDKs with conflict:** OpenAI, Mistral, Cohere, Together, Reka, Writer, Mixedbread, SarvamAI
**SDKs without conflict:** Anthropic, Ollama, Google.Gemini, AI21, HuggingFace, Jina, VoyageAI, ElevenLabs, AssemblyAI, Gladia, Cartesia, Deepgram, Tavily, Exa, Serper, TwelveLabs, Browserbase, Composio, Helicone, BraveSearch, FishAudio, KlingAI, CursorAgents, Vapi, Tavus, RetellAI

## Feature Comparison

### IChatClient Features

| Feature | Anthropic | Ollama | OpenAI | Gemini | Mistral | Cohere | Together | AI21 | Reka | HuggingFace | Writer | SarvamAI |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Text | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Streaming | Y | Y | Y | Y | Y | ~* | Y | Y | Y | Y | Y | - |
| Tool calling | Y | Y | Y | Y | Y | Y | Y | Y | Y** | Y | Y | Y |
| Streaming tools | Y | Y*** | Y | Y*** | Y | - | Y | Y | Y | Y | Y | - |
| Images | Y | Y | Y | Y | Y | - | - | - | Y | - | - | - |
| PDFs | Y | - | - | - | - | - | - | - | Y | - | - | - |
| Audio/Video | - | - | - | - | - | - | - | - | Y | - | - | - |
| Thinking | Y | Y | - | Y | - | - | - | - | - | - | - | - |
| Structured output | - | - | Y | - | - | - | - | - | Y | - | - | - |
| Reasoning | - | - | - | - | - | - | Y | Y | - | - | - | Y |

*Cohere: simulated streaming (not true SSE)
**Reka: tool results sent as user text (API limitation)
***Ollama/Gemini: API sends complete tool calls per chunk (no fragment accumulation needed); all other SDKs accumulate streamed JSON argument fragments via `Dictionary<int, (string Id, string Name, StringBuilder Args)>` pattern

### IEmbeddingGenerator Features

| Feature | Ollama | OpenAI | Gemini | Cohere | Together | HuggingFace | Jina | VoyageAI | Mixedbread | TwelveLabs |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Single input | Y | Y | Y | Y | Y | Y | Y | Y | Y | Y |
| Batch input | Y | Y | Y | Y | Y | Y | Y | Y | Y | ~* |
| Custom dimensions | Y | Y | - | - | - | Y | Y | Y | Y | - |
| Token usage | Y | Y | - | - | - | Y | Y | Y | Y | - |

*TwelveLabs: batch input processed sequentially (one API call per text, no native batch support)

### ISpeechToTextClient Features

| Feature | Reka | ElevenLabs | AssemblyAI | Gladia | Cartesia | Deepgram | FishAudio | SarvamAI |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| File transcription | Y | Y | Y | Y | Y | -† | Y | Y |
| URL transcription | Y | - | Y | Y* | - | Y | - | - |
| Streaming | -** | Y | - | -** | -** | -** | -** | -** |
| Translation | Y | - | - | Y*** | - | - | - | - |
| Timestamps | Y | Y | Y | Y | Y | Y | Y | - |

*Gladia: audio URL via `RawRepresentationFactory` with `InitTranscriptionRequest`
**Delegates to non-streaming (API limitation)
***Gladia: translation via `RawRepresentationFactory` with `Translation = true`
†Deepgram: URL-based only; audio URL provided via `RawRepresentationFactory` with `ListenV1RequestUrl`

### AIFunction Tools

| Feature | Tavily | Exa | Serper | BraveSearch | Phoenix | DeepL | Braintrust | LlamaParse | Opik | Browserbase | Composio | Helicone | FishAudio | SarvamAI | KlingAI | CursorAgents | Vapi | Tavus | RetellAI |
|---------|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| Web search | Y (`AsSearchTool`) | Y (`AsSearchTool`) | Y (`AsSearchTool`) | Y (`AsSearchTool`) | - | - | - | - | - | Y (`AsSearchWebTool`) | - | - | - | - | - | - | - | - | - |
| Content extraction | Y (`AsExtractTool`) | Y (`AsGetContentsTool`) | - | - | - | - | - | - | - | Y (`AsFetchPageTool`) | - | - | - | - | - | - | - | - | - |
| Answer/RAG | - | Y (`AsAnswerTool`) | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| News search | - | - | Y (`AsNewsTool`) | Y (`AsNewsTool`) | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - |
| Translation | - | - | - | - | - | Y (`AsTranslateTool`) | - | - | - | - | - | - | - | Y (`AsTranslateTool`) | - | - | - | - | - |
| Transliteration | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsTransliterateTool`) | - | - | - | - | - |
| Language detection | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsDetectLanguageTool`) | - | - | - | - | - |
| Text improvement | - | - | - | - | - | Y (`AsRephraseTool`) | - | - | - | - | - | - | - | - | - | - | - | - | - |
| Document translation | - | - | - | - | - | Y (`AsTranslateDocumentTool`) | - | - | - | - | - | - | - | - | - | - | - | - | - |
| Prompt management | - | - | - | - | Y (`AsGetPromptTool`, `AsListPromptsTool`) | - | Y (`AsGetPromptTool`, `AsListPromptsTool`) | - | Y (`AsListPromptsTool`) | - | - | Y (`AsListPromptsTool`) | - | - | - | - | - | - | - |
| Project/experiment mgmt | - | - | - | - | - | - | Y (`AsListProjectsTool`, `AsListExperimentsTool`) | - | Y (`AsListProjectsTool`, `AsCreateProjectTool`) | - | - | - | - | - | - | - | - | - | - |
| Trace/span logging | - | - | - | - | - | - | - | - | Y (`AsCreateTraceTool`, `AsCreateSpanTool`) | - | - | - | - | - | - | - | - | - | - |
| Document parsing | - | - | - | - | - | - | - | Y (`AsParseUrlTool`) | - | - | - | - | - | - | - | - | - | - | - |
| Job status/result | - | - | - | - | - | - | - | Y (`AsGetJobStatusTool`, `AsGetJobResultTool`) | - | - | - | - | - | - | - | - | - | - | - |
| File format info | - | - | - | - | - | - | - | Y (`AsSupportedExtensionsTool`) | - | - | - | - | - | - | - | - | - | - | - |
| Observability | - | - | - | - | Y (`AsAnnotateSpanTool`, `AsListTracesTool`) | - | - | - | Y (`AsGetTraceTool`) | - | - | - | - | - | - | - | - | - | - |
| Browser sessions | - | - | - | - | - | - | - | - | - | Y (`AsCreateSessionTool`, `AsListSessionsTool`) | - | - | - | - | - | - | - | - | - |
| Tool execution | - | - | - | - | - | - | - | - | - | - | Y (`AsExecuteToolTool`) | - | - | - | - | - | - | - | - |
| Tool/integration listing | - | - | - | - | - | - | - | - | - | - | Y (`AsListToolsTool`, `AsListToolkitsTool`) | - | - | - | - | - | - | - | - |
| Connected accounts | - | - | - | - | - | - | - | - | - | - | Y (`AsListConnectedAccountsTool`) | - | - | - | - | - | - | - | - |
| Cost metrics | - | - | - | - | - | - | - | - | - | - | - | Y (`AsGetTotalCostTool`) | - | - | - | - | - | - | - |
| Request metrics | - | - | - | - | - | - | - | - | - | - | - | Y (`AsGetTotalRequestsTool`) | - | - | - | - | - | - | - |
| Latency metrics | - | - | - | - | - | - | - | - | - | - | - | Y (`AsGetAverageLatencyTool`) | - | - | - | - | - | - | - |
| Text-to-speech | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsTextToSpeechTool`) | - | - | - | - | - | - |
| Voice model listing | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListModelsTool`) | - | - | - | - | - | - |
| Voice model details | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsGetModelTool`) | - | - | - | - | - | - |
| Text-to-video | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsTextToVideoTool`) | - | - | - | - |
| Image-to-video | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsImageToVideoTool`) | - | - | - | - |
| Image generation | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsImageGenerationTool`) | - | - | - | - |
| Task status | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsGet*TaskTool`) | - | - | - | - |
| Agent creation | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsCreateAgentTool`) | - | - | - |
| Agent listing | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListAgentsTool`) | - | - | Y (`AsListAgentsTool`) |
| Agent status | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsGetAgentTool`) | - | - | Y (`AsGetAgentTool`) |
| Assistant mgmt | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListAssistantsTool`, `AsGetAssistantTool`, `AsCreateAssistantTool`) | - | - |
| Call mgmt | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListCallsTool`, `AsGetCallTool`) | - | Y (`AsListCallsTool`, `AsGetCallTool`, `AsCreatePhoneCallTool`) |
| Phone numbers | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListPhoneNumbersTool`) | - | Y (`AsListPhoneNumbersTool`) |
| Conversation mgmt | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsCreateConversationTool`, `AsListConversationsTool`, `AsGetConversationTool`, `AsEndConversationTool`) | - |
| Persona listing | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListPersonasTool`) | - |
| Replica listing | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | - | Y (`AsListReplicasTool`) | - |

## Documentation Links

Each SDK has a dedicated MEAI guide page in its mkdocs documentation:

| SDK | Guide |
|-----|-------|
| OpenAI | `docs/guides/meai.md` |
| Ollama | `docs/guides/meai.md` |
| Anthropic | `docs/guides/meai.md` |
| Google.Gemini | `docs/guides/meai.md` |
| Mistral | `docs/guides/meai.md` |
| Cohere | `docs/guides/meai.md` |
| Together | `docs/guides/meai.md` |
| AI21 | `docs/guides/meai.md` |
| Reka | `docs/guides/meai.md` |
| HuggingFace | `docs/guides/meai.md` |
| Jina | `docs/guides/meai.md` |
| VoyageAI | `docs/guides/meai.md` |
| ElevenLabs | `docs/guides/meai.md` |
| AssemblyAI | `docs/guides/meai.md` |
| Gladia | `docs/guides/meai.md` |
| Cartesia | `docs/guides/meai.md` |
| Writer | `docs/guides/meai.md` |
| Mixedbread | `docs/guides/meai.md` |
| Deepgram | `docs/guides/meai.md` |
| Tavily | `docs/guides/meai.md` |
| Exa | `docs/guides/meai.md` |
| Serper | `docs/guides/meai.md` |
| TwelveLabs | `docs/guides/meai.md` |
| DeepL | `docs/guides/meai.md` |
| Braintrust | `docs/guides/meai.md` |
| LlamaParse | `docs/guides/meai.md` |
| Opik | `docs/guides/meai.md` |
| Browserbase | `docs/guides/meai.md` |
| Composio | `docs/guides/meai.md` |
| Helicone | `docs/guides/meai.md` |
| BraveSearch | `docs/guides/meai.md` |
| FishAudio | `docs/guides/meai.md` |
| SarvamAI | `docs/guides/meai.md` |
| KlingAI | `docs/guides/meai.md` |
| CursorAgents | `docs/guides/meai.md` |
| Vapi | `docs/guides/meai.md` |
| Tavus | `docs/guides/meai.md` |
| RetellAI | `docs/guides/meai.md` |
| DId | `docs/guides/meai.md` |
| Synthesia | `docs/guides/meai.md` |
| Milvus | `docs/guides/meai.md` |

## Implementation Pattern

MEAI implementations are hand-written partial classes outside `Generated/`:

```
src/libs/{SdkName}/Extensions/
  {ClientName}.ChatClient.cs          # IChatClient
  {ClientName}.EmbeddingGenerator.cs  # IEmbeddingGenerator
  {ClientName}.SpeechToTextClient.cs  # ISpeechToTextClient
  {ClientName}.AsTool.cs              # AIFunction tools (static extension methods)
  {ClientName}.Auth.cs                # Auth hook (e.g., PrepareRequest for custom headers)
```

Reference implementations:
- `IChatClient`: `Anthropic/src/libs/Anthropic/Extensions/AnthropicClient.ChatClient.cs`
- `AIFunction` tools: `Tavily/src/libs/Tavily/Extensions/TavilyClient.AsTool.cs`

## Already Implemented

| Repository | Interface(s) | Version | Maturity |
|------------|-------------|---------|----------|
| `Anthropic/` | `IChatClient` | 10.4.1 | Full (text, streaming, tools, images, PDFs, thinking) |
| `Ollama/` | `IChatClient` + `IEmbeddingGenerator` | 10.4.1 | Full (text, streaming, tools, images, thinking) / Full (embeddings) |
| `HuggingFace/` | `IChatClient` + `IEmbeddingGenerator` | 10.4.1 | Partial (chat) / Full (embeddings) |
| `Google.Gemini/` | `IChatClient` + `IEmbeddingGenerator` | 10.4.1 | Full (text, streaming, tools, images, thinking, thought signatures) / Full (embeddings) |
| `Mistral/` | `IChatClient` | 10.4.1 | Full (text, streaming, tools, images) |
| `Cohere/` | `IChatClient` + `IEmbeddingGenerator` | 10.4.1 | Partial (text, tools; no true streaming) / Full (embeddings) |
| `Reka/` | `IChatClient` + `ISpeechToTextClient` | 10.4.1 | Full (text, streaming, tools, images/audio/video/PDF URLs, speech-to-text) |
| `ElevenLabs/` | `ISpeechToTextClient` | 10.4.1 | Full |
| `AssemblyAI/` | `ISpeechToTextClient` | 10.4.1 | Full |
| `Gladia/` | `ISpeechToTextClient` | 10.4.1 | Full (upload + poll, 100+ languages, RawRepresentationFactory) |
| `Cartesia/` | `ISpeechToTextClient` | 10.4.1 | Full (synchronous STT, 115+ languages, word timestamps) |
| `CSharpToJsonSchema/` | Tooling (`MeaiFunction`, `AsMeaiTools()`) | 10.4.1 | Framework/tooling support |
| `LangChain.Providers/` | Bridge (`ChatClientModel` adapter) | 9.6.0 | Full bridge between MEAI <> LangChain |
| `LangChain/` | Consumer | 10.4.1 | Uses MEAI in CLI |
| `Together/` | `IChatClient` + `IEmbeddingGenerator` | 10.4.1 | Full (text, streaming, tools, reasoning) / Full (embeddings) |
| `AI21/` | `IChatClient` | 10.4.1 | Full (text, streaming, tools, reasoning) |
| `Jina/` | `IEmbeddingGenerator` | 10.4.1 | Full (text embeddings, custom dimensions, multimodal extensions for images/PDFs) |
| `VoyageAI/` | `IEmbeddingGenerator` | 10.4.1 | Full (text embeddings, custom dimensions, token usage) |
| `OpenAI/` | `IChatClient` + `IEmbeddingGenerator` | 10.4.1 | Full (text, streaming, tools, images, JSON/structured output, temp/topP/seed, AdditionalProperties pass-through) / Full (embeddings with dimensions) |
| `Coze/` | `IChatClient` | 10.4.1 | Partial (text, streaming, reasoning text; bot-centric chat requiring `bot_id` and `user_id`; provider-issued tool calls are not yet emitted as `FunctionCallContent`) |
| `Tavily/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsExtractTool()` wrappers for use with any `IChatClient`) |
| `DeepInfra/` | `IChatClient` + `IEmbeddingGenerator` (via `tryAGI.OpenAI`) | 10.4.1 | Full — uses `CustomProviders.DeepInfra()` from `tryAGI.OpenAI` (OpenAI-compatible API) |
| `Groq/` | `IChatClient` + `IEmbeddingGenerator` (via `tryAGI.OpenAI`) | 10.4.1 | Full — uses `CustomProviders.Groq()` from `tryAGI.OpenAI` (OpenAI-compatible API) |
| `Writer/` | `IChatClient` | 10.4.1 | Full (text, streaming, tools) |
| `Mixedbread/` | `IEmbeddingGenerator` | 10.4.1 | Full (embeddings, custom dimensions, token usage) |
| `Deepgram/` | `ISpeechToTextClient` | 10.4.1 | Full (URL-based pre-recorded transcription, timestamps) |
| `Phoenix/` | `AIFunction` tools | 10.4.1 | Full (`AsGetPromptTool()`, `AsListPromptsTool()`, `AsAnnotateSpanTool()`, `AsListTracesTool()` for use with any `IChatClient`) |
| `Exa/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsGetContentsTool()` + `AsAnswerTool()` wrappers for use with any `IChatClient`) |
| `Serper/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsNewsTool()` wrappers for use with any `IChatClient`; `PrepareRequest` auth hook converts Bearer to X-API-KEY) |
| `TwelveLabs/` | `IEmbeddingGenerator` | 10.4.1 | Partial (text embeddings only via embed v2 sync API, marengo3.0 model, one text per request; requires `WithApiKey()`) |
| `DeepL/` | `AIFunction` tools | 10.4.1 | Full (`AsTranslateTool()` + `AsRephraseTool()` + `AsTranslateDocumentTool()` wrappers for use with any `IChatClient`) |
| `Braintrust/` | `AIFunction` tools | 10.4.1 | Full (`AsListPromptsTool()` + `AsGetPromptTool()` + `AsListProjectsTool()` + `AsListExperimentsTool()` wrappers for use with any `IChatClient`) |
| `LlamaParse/` | `AIFunction` tools | 10.4.1 | Full (`AsParseUrlTool()` + `AsGetJobStatusTool()` + `AsGetJobResultTool()` + `AsSupportedExtensionsTool()` wrappers for use with any `IChatClient`) |
| `Opik/` | `AIFunction` tools | 10.4.1 | Full (`AsListProjectsTool()` + `AsGetTraceTool()` + `AsListPromptsTool()` + `AsCreateProjectTool()` + `AsCreateTraceTool()` + `AsCreateSpanTool()` wrappers for use with any `IChatClient`) |
| `Browserbase/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchWebTool()` + `AsFetchPageTool()` + `AsCreateSessionTool()` + `AsListSessionsTool()` wrappers for use with any `IChatClient`) |
| `Composio/` | `AIFunction` tools | 10.4.1 | Full (`AsExecuteToolTool()` + `AsListToolsTool()` + `AsListToolkitsTool()` + `AsListConnectedAccountsTool()` wrappers for use with any `IChatClient`) |
| `Helicone/` | `AIFunction` tools | 10.4.1 | Full (`AsGetTotalCostTool()` + `AsGetTotalRequestsTool()` + `AsGetAverageLatencyTool()` + `AsListPromptsTool()` wrappers for use with any `IChatClient`) |
| `BraveSearch/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsNewsTool()` wrappers for use with any `IChatClient`; `PrepareRequest` auth hook converts Bearer to X-Subscription-Token) |
| `FishAudio/` | `ISpeechToTextClient` + `AIFunction` tools | 10.4.1 | Full (STT via `/v1/asr` with timestamps) / Full (`AsTextToSpeechTool()` + `AsListModelsTool()` + `AsGetModelTool()` wrappers for use with any `IChatClient`) |
| `SarvamAI/` | `IChatClient` + `ISpeechToTextClient` + `AIFunction` tools | 10.4.1 | Full (chat, STT for 22+ Indian languages, `AsTranslateTool()` + `AsTransliterateTool()` wrappers) |
| `KlingAI/` | `AIFunction` tools | 10.4.1 | Full (`AsTextToVideoTool()` + `AsImageToVideoTool()` + `AsImageGenerationTool()` + `AsGetTextToVideoTaskTool()` + `AsGetImageToVideoTaskTool()` + `AsGetImageGenerationTaskTool()` wrappers for use with any `IChatClient`) |
| `CursorAgents/` | `AIFunction` tools | 10.4.1 | Full (`AsCreateAgentTool()` + `AsListAgentsTool()` + `AsGetAgentTool()` wrappers for use with any `IChatClient`) |
| `Vapi/` | `AIFunction` tools | 10.4.1 | Full (`AsListAssistantsTool()` + `AsGetAssistantTool()` + `AsCreateAssistantTool()` + `AsListCallsTool()` + `AsGetCallTool()` + `AsListPhoneNumbersTool()` wrappers for use with any `IChatClient`) |
| `Tavus/` | `AIFunction` tools | 10.4.1 | Full (`AsCreateConversationTool()` + `AsListConversationsTool()` + `AsGetConversationTool()` + `AsEndConversationTool()` + `AsListPersonasTool()` + `AsListReplicasTool()` wrappers for use with any `IChatClient`) |
| `RetellAI/` | `AIFunction` tools | 10.4.1 | Full (`AsListAgentsTool()` + `AsGetAgentTool()` + `AsCreatePhoneCallTool()` + `AsListCallsTool()` + `AsGetCallTool()` + `AsListPhoneNumbersTool()` wrappers for use with any `IChatClient`) |
| `DId/` | `AIFunction` tools | 10.4.1 | Full (`AsCreateTalkTool()` + `AsGetTalkTool()` + `AsListTalksTool()` + `AsListAgentsTool()` + `AsGetCreditsTool()` + `AsListVoicesTool()` wrappers for use with any `IChatClient`) |
| `Synthesia/` | `AIFunction` tools | 10.4.1 | Full (`AsCreateVideoTool()` + `AsCreateVideoFromTemplateTool()` + `AsListTemplatesTool()` + `AsGetVideoTool()` + `AsListVideosTool()` + `AsDeleteVideoTool()` wrappers for use with any `IChatClient`) |
| `Milvus/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchVectorsTool()` + `AsInsertVectorsTool()` + `AsCreateCollectionTool()` + `AsListCollectionsTool()` + `AsDescribeCollectionTool()` + `AsQueryVectorsTool()` + `AsDeleteVectorsTool()` wrappers for use with any `IChatClient`) |
| `Upstage/` | `IChatClient` + `IEmbeddingGenerator` + `AIFunction` tools | 10.4.1 | Full (text, streaming, tools, images) / Full (embeddings) / Full (`AsGroundednessCheckTool()` + `AsTranslateTool()` + `AsDocumentParseTool()` wrappers for use with any `IChatClient`) |
| `PromptLayer/` | `AIFunction` tools | 10.4.1 | Full (`AsListPromptsTool()` + `AsGetPromptTool()` + `AsSearchRequestsTool()` + `AsListWorkflowsTool()` wrappers for use with any `IChatClient`) |
| `Lakera/` | `AIFunction` tools | 10.4.1 | Full (`AsGuardTool()` + `AsGuardResultsTool()` wrappers for screening content for prompt injection, PII, jailbreaks) |
| `Guardrails/` | `AIFunction` tools | 10.4.1 | Full (`AsValidateTool()` + `AsListGuardsTool()` + `AsGetGuardTool()` wrappers for LLM validation, hallucination detection, PII protection) |
| `Murf/` | `AIFunction` tools | 10.4.1 | Full (`AsTextToSpeechTool()` + `AsListVoicesTool()` + `AsTranslateTool()` wrappers for use with any `IChatClient`) |
| `RevAI/` | `ISpeechToTextClient` + `AIFunction` tools | 10.4.1 | Full (URL + file upload transcription, poll for completion) / Full (`AsTranscribeUrlTool()` + `AsGetJobStatusTool()` + `AsListJobsTool()` wrappers for use with any `IChatClient`) |
| `Photoroom/` | `AIFunction` tools | 10.4.1 | Full (`AsRemoveBackgroundTool()` + `AsGenerateBackgroundTool()` + `AsRelightTool()` wrappers for use with any `IChatClient`) |
| `Nanonets/` | `AIFunction` tools | 10.4.1 | Full (`AsOcrTool()` + `AsClassifyTool()` + `AsExtractTool()` wrappers for use with any `IChatClient`) |
| `Speechmatics/` | `ISpeechToTextClient` + `AIFunction` tools | 10.4.1 | Full (batch STT, 55+ languages, poll for completion) / Full (`AsTranscribeUrlTool()` + `AsGetJobStatusTool()` + `AsListJobsTool()` wrappers for use with any `IChatClient`) |
| `Shotstack/` | `AIFunction` tools | 10.4.1 | Full (`AsGetRenderStatusTool()` + `AsListTemplatesTool()` + `AsProbeTool()` + `AsListAssetsTool()` wrappers for use with any `IChatClient`) |
| `OpenRouter/` | `AIFunction` tools | 10.4.1 | Full (`AsListModelsTool()` + `AsGetModelTool()` + `AsGetGenerationTool()` + `AsGetCreditsTool()` wrappers for use with any `IChatClient`) |
| `HumeAI/` | `AIFunction` tools | 10.4.1 | Full (`AsStartBatchJobTool()` + `AsGetJobStatusTool()` + `AsListJobsTool()` + `AsSynthesizeSpeechTool()` + `AsListVoicesTool()` + `AsListChatsTool()` wrappers for use with any `IChatClient`) |
| `Nixtla/` | `AIFunction` tools | 10.4.1 | Full (`AsForecastTool()` + `AsAnomalyDetectionTool()` + `AsListModelsTool()` wrappers for use with any `IChatClient`) |
| `GroundX/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsIngestUrlTool()` + `AsGetIngestStatusTool()` + `AsListBucketsTool()` wrappers for use with any `IChatClient`) |
| `PredictionGuard/` | `AIFunction` tools | 10.4.1 | Full (`AsFactualityCheckTool()` + `AsToxicityCheckTool()` + `AsPiiDetectionTool()` + `AsInjectionDetectionTool()` wrappers for use with any `IChatClient`) |
| `LabelStudio/` | `AIFunction` tools | 10.4.1 | Full (`AsListProjectsTool()` + `AsGetProjectTool()` + `AsListTasksTool()` + `AsCreateAnnotationTool()` wrappers for use with any `IChatClient`) |
| `NightfallAI/` | `AIFunction` tools | 10.4.1 | Full (`AsScanTextTool()` + `AsInitFileUploadTool()` + `AsScanUploadedFileTool()` wrappers for use with any `IChatClient`) |
| `Humanloop/` | `AIFunction` tools | 10.4.1 | Full (`AsListPromptsTool()` + `AsGetPromptTool()` + `AsListEvaluationsTool()` + `AsListDatasetsTool()` wrappers for use with any `IChatClient`) |
| `Vectara/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsListCorporaTool()` + `AsListLLMsTool()` wrappers for use with any `IChatClient`) |
| `Weave/` | `AIFunction` tools | 10.4.1 | Full (`AsListCallsTool()` + `AsGetCallTool()` + `AsListObjectsTool()` + `AsQueryTableTool()` + `AsAddFeedbackTool()` + `AsGetCallStatsTool()` wrappers for use with any `IChatClient`) |
| `ModernMT/` | `AIFunction` tools | 10.4.1 | Full (`AsTranslateTool()` + `AsListLanguagesTool()` + `AsListMemoriesTool()` + `AsDetectLanguageTool()` wrappers for use with any `IChatClient`) |
| `LalalAI/` | `AIFunction` tools | 10.4.1 | Full (`AsCheckTaskStatusTool()` + `AsGetMinutesLeftTool()` + `AsListVoicePacksTool()` + `AsCancelTasksTool()` wrappers for use with any `IChatClient`) |
| `Reducto/` | `AIFunction` tools | 10.4.1 | Full (`AsParseDocumentTool()` + `AsExtractDataTool()` + `AsClassifyDocumentTool()` + `AsGetJobStatusTool()` + `AsListJobsTool()` + `AsCancelJobTool()` wrappers for use with any `IChatClient`) |
| `Gretel/` | `AIFunction` tools | 10.4.1 | Full (`AsListProjectsTool()` + `AsGetProjectTool()` + `AsListModelsTool()` + `AsGetModelTool()` + `AsGetWorkflowRunTool()` + `AsListWorkflowsTool()` wrappers for use with any `IChatClient`) |
| `MagicHour/` | `AIFunction` tools | 10.4.1 | Full (`AsTextToVideoTool()` + `AsImageToVideoTool()` + `AsGetVideoStatusTool()` + `AsGetImageStatusTool()` + `AsGenerateImageTool()` + `AsFaceSwapVideoTool()` + `AsLipSyncTool()` wrappers for use with any `IChatClient`) |
| `Dust/` | `AIFunction` tools | 10.4.1 | Full (`AsListAgentsTool()` + `AsGetAgentTool()` + `AsSearchAgentsTool()` + `AsCreateConversationTool()` + `AsGetConversationTool()` + `AsSendMessageTool()` + `AsListSpacesTool()` + `AsListDataSourcesTool()` wrappers for use with any `IChatClient`) |
| `Loudly/` | `AIFunction` tools | 10.4.1 | Full (`AsTextToMusicTool()` + `AsGenerateMusicTool()` + `AsListGenresTool()` + `AsListStructuresTool()` + `AsSearchCatalogTool()` + `AsGetAccountLimitsTool()` wrappers for use with any `IChatClient`) |
| `Creatomate/` | `AIFunction` tools | 10.4.1 | Full (`AsCreateRenderTool()` + `AsGetRenderStatusTool()` + `AsListTemplatesTool()` + `AsGetTemplateTool()` wrappers for use with any `IChatClient`) |
| `Greptile/` | `AIFunction` tools | 10.4.1 | Full (`AsQueryCodebaseTool()` + `AsSearchCodebaseTool()` + `AsIndexRepositoryTool()` + `AsGetRepositoryStatusTool()` wrappers for use with any `IChatClient`) |
| `Novu/` | `AIFunction` tools | 10.4.1 | Full (`AsTriggerEventTool()` + `AsSearchSubscribersTool()` + `AsListWorkflowsTool()` + `AsListNotificationsTool()` + `AsGetNotificationTool()` + `AsListTopicsTool()` wrappers for use with any `IChatClient`) |
| `Resend/` | `AIFunction` tools | 10.4.1 | Full (`AsSendEmailTool()` + `AsGetEmailTool()` + `AsListEmailsTool()` + `AsListDomainsTool()` + `AsListContactsTool()` + `AsListTemplatesTool()` wrappers for use with any `IChatClient`) |
| `Apify/` | `AIFunction` tools | 10.4.1 | Full (`AsRunActorTool()` + `AsGetRunStatusTool()` + `AsListActorsTool()` + `AsGetDatasetItemsTool()` + `AsListRunsTool()` wrappers for use with any `IChatClient`) |
| `Pinecone/` | `IEmbeddingGenerator` + `AIFunction` tools | 10.4.1 | Full (embeddings via inference API) / Full (`AsListIndexesTool()` + `AsDescribeIndexTool()` + `AsEmbedTool()` + `AsRerankTool()` + `AsListModelsTool()` + `AsListCollectionsTool()` wrappers for use with any `IChatClient`) |
| `Julep/` | `AIFunction` tools | 10.4.1 | Full (`AsListAgentsTool()` + `AsGetAgentTool()` + `AsCreateAgentTool()` + `AsListSessionsTool()` + `AsCreateSessionTool()` + `AsListTasksTool()` + `AsGetExecutionTool()` + `AsListAgentToolsTool()` wrappers for use with any `IChatClient`) |
| `ScrapeGraphAI/` | `AIFunction` tools | 10.4.1 | Full (`AsSmartScraperTool()` + `AsSearchScraperTool()` + `AsMarkdownifyTool()` + `AsGetCreditsTool()` + `AsGetSitemapTool()` wrappers for use with any `IChatClient`) |
| `Sightengine/` | `AIFunction` tools | 10.4.1 | Full (`AsModerateImageTool()` + `AsDetectAiGeneratedTool()` + `AsModerateTextTool()` + `AsValidateUsernameTool()` wrappers for use with any `IChatClient`) |
| `ModerationAPI/` | `AIFunction` tools | 10.4.1 | Full (`AsModerateTextTool()` + `AsModerateImageTool()` + `AsGetQueueStatsTool()` + `AsListActionsTool()` wrappers for use with any `IChatClient`) |
| `Recombee/` | `AIFunction` tools | 10.4.1 | Full (`AsRecommendItemsTool()` + `AsSearchItemsTool()` + `AsAddInteractionTool()` + `AsListItemsTool()` wrappers for use with any `IChatClient`) |
| `Zep/` | `AIFunction` tools | 10.4.1 | Full (`AsAddMemoryTool()` + `AsSearchMemoryTool()` + `AsGetContextTool()` + `AsListThreadsTool()` + `AsGetUserNodeTool()` + `AsAddMessagesTool()` wrappers for use with any `IChatClient`) |
| `CVAT/` | `AIFunction` tools | 10.4.1 | Full (`AsListProjectsTool()` + `AsGetTaskTool()` + `AsListLabelsTool()` + `AsGetJobStatusTool()` wrappers for use with any `IChatClient`) |
| `Nomic/` | `IEmbeddingGenerator` + `AIFunction` tools | 10.4.1 | Full (text embeddings with task types, dimensions) / Full (`AsEmbedTextTool()` + `AsEmbedImageTool()` wrappers for use with any `IChatClient`) |
| `Picsart/` | `AIFunction` tools | 10.4.1 | Full (`AsRemoveBackgroundTool()` + `AsUpscaleTool()` + `AsTextToImageTool()` + `AsListEffectsTool()` + `AsGetBalanceTool()` wrappers for use with any `IChatClient`) |
| `Algolia/` | `AIFunction` tools | 10.4.1 | Full (`AsSearchTool()` + `AsGetObjectTool()` + `AsListIndicesTool()` + `AsBrowseTool()` + Recommend: `AsFrequentlyBoughtTogetherTool()` + `AsRelatedProductsTool()` + `AsTrendingItemsTool()` + `AsLookingSimilarTool()` wrappers for use with any `IChatClient`) |
| `SiliconFlow/` | `AIFunction` tools | 10.4.1 | Full (`AsRerankTool()` + `AsTextToImageTool()` + `AsListModelsTool()` + `AsGetUserInfoTool()` wrappers for use with any `IChatClient`) |
| `Vellum/` | `AIFunction` tools | 10.4.1 | Full (`AsExecutePromptTool()` + `AsSearchDocumentsTool()` + `AsListDeploymentsTool()` + `AsListDocumentIndexesTool()` wrappers for use with any `IChatClient`) |
| `Dataloop/` | `AIFunction` tools | 10.4.1 | Full (`AsListProjectsTool()` + `AsListDatasetsTool()` + `AsListTasksTool()` + `AsGetItemTool()` wrappers for use with any `IChatClient`) |
| `ScaleAI/` | `AIFunction` tools | 10.4.1 | Full (`AsListProjectsTool()` + `AsGetProjectTool()` + `AsListTasksTool()` + `AsGetTaskTool()` + `AsGetBatchStatusTool()` wrappers for use with any `IChatClient`) |
| `EdenAI/` | `AIFunction` tools | 10.4.1 | Full (`AsChatTool()` + `AsTranslateTool()` + `AsGenerateImageTool()` + `AsSummarizeTool()` + `AsSentimentAnalysisTool()` + `AsDetectLanguageTool()` wrappers for use with any `IChatClient`) |
| `JasperAI/` | `AIFunction` tools | 10.4.1 | Full (`AsGenerateContentTool()` + `AsSearchKnowledgeTool()` + `AsListTasksTool()` + `AsListVoicesTool()` wrappers for use with any `IChatClient`) |
| `HammingAI/` | `AIFunction` tools | 10.4.1 | Full (`AsRunVoiceAgentTestTool()` + `AsGetVoiceExperimentStatusTool()` + `AsGetVoiceExperimentCallsTool()` + `AsListDatasetsTool()` wrappers for use with any `IChatClient`) |
| `Writesonic/` | `AIFunction` tools | 10.4.1 | Full (`AsChatSonicTool()` + `AsGenerateArticleTool()` + `AsRephraseTool()` + `AsGenerateImageTool()` + `AsSeoMetaTagsTool()` wrappers for use with any `IChatClient`) |
| `Predibase/` | `AIFunction` tools | 10.4.1 | Full (`AsListDeploymentsTool()` + `AsGetDeploymentTool()` + `AsCreateFinetuningJobTool()` + `AsGetFinetuningJobTool()` + `AsListFinetuningJobsTool()` + `AsListDatasetsTool()` wrappers for use with any `IChatClient`) |
| `Baseten/` | `AIFunction` tools | 10.4.1 | Full (`AsListModelsTool()` + `AsGetModelTool()` + `AsGetDeploymentStatusTool()` + `AsListSecretsTool()` wrappers for use with any `IChatClient`) |
| `WaveSpeedAI/` | `AIFunction` tools | 10.4.1 | Full (`AsGenerateImageTool()` + `AsGenerateVideoTool()` + `AsGetTaskResultTool()` + `AsListPredictionsTool()` wrappers for use with any `IChatClient`) |
| `Martian/` | `AIFunction` tools | 10.4.1 | Full (`AsListModelsTool()` + `AsChatCompletionTool()` + `AsRoutedChatTool()` + `AsAnthropicMessageTool()` wrappers for use with any `IChatClient`) |
| `Botpress/` | `AIFunction` tools | 10.4.1 | Full (`AsListBotsTool()` + `AsGetBotTool()` + `AsListConversationsTool()` + `AsListMessagesTool()` + `AsGetBotAnalyticsTool()` wrappers for use with any `IChatClient`) |
| `AI/` | Consumer | 10.4.1 | Uses MEAI + `Microsoft.Extensions.AI.OpenAI` |

## Not Applicable — No Matching MEAI Interface

These SDKs have no applicable MEAI interface and are not expected to implement one:

- `Ultravox/` — Voice conversation platform (bi-directional voice calls, not speech-to-text transcription)
- `RetellAI/` — Voice AI phone agents platform (`AIFunction` tools for agent/call/phone management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Vapi/` — Voice AI agent platform (call orchestration, assistants, phone numbers; no direct STT/TTS transcription interface)
- `Tavus/` — Conversational video AI platform (`AIFunction` tools for conversation/persona/replica management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Vectara/` — RAG platform (`AIFunction` tools for search/corpora/LLM discovery; no standard MEAI interface like IChatClient/IEmbeddingGenerator)
- `Milvus/` — Vector database (`AIFunction` tools for search/insert/query/delete vectors, collection management; no standard MEAI interface like IChatClient/IEmbeddingGenerator)
- `Chroma/`, `Qdrant/`, `Turbopuffer/`, `Weaviate/` — Vector DBs (no standard MEAI interface)
- `BlackForestLabs/` — FLUX image generation models (no standard MEAI interface)
- `DId/` — Talking avatar video generation platform (`AIFunction` tools for talk/agent/credits/voice management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Synthesia/` — Enterprise AI video generation platform (`AIFunction` tools for video/template management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `HeyGen/`, `Hedra/`, `Ideogram/`, `Leonardo/`, `Luma/`, `Meshy/`, `Recraft/`, `Replicate/`, `Runway/`, `StabilityAI/`, `Tripo/`, `Fal/` — Image/video/3D generation (no standard MEAI interface)
- `Meshcapade/` — 3D avatar/motion platform (no matching MEAI interface)
- `E2B/` — AI agent cloud sandboxes (no matching MEAI interface)
- `Mem0/` — AI memory layer for agents (no matching MEAI interface)
- `Xai/` — Standalone SDK for unique xAI endpoints (images, video, realtime voice); MEAI chat/embeddings via `CustomProviders.XAi()` in `tryAGI.OpenAI`
- `Langfuse/` — LLM observability/evaluation platform (tracing, scoring, prompt management; no LLM provider interface)
- `Roboflow/` — Computer vision inference platform (object detection, segmentation, OCR; no matching MEAI interface)
- `Letta/` — Stateful AI agents with persistent memory (agent/memory/tool/conversation management; no standard MEAI interface; `AIFunction` tools candidate)
- `Portkey/` — AI gateway platform (LLM routing, guardrails, prompt management, observability; no standard MEAI interface)
- `BlandAI/` — AI phone call platform (calls, batches, pathways, voices; no standard MEAI interface)
- `DoclingServe/` — IBM document processing (self-hosted FastAPI; conversion, chunking; no matching MEAI interface)
- `Descript/` — AI video/audio editing platform (beta API; import, agent editing, job management; no matching MEAI interface)
- `PromptLayer/` — Prompt management/versioning/tracking platform (`AIFunction` tools for prompt/workflow/request management; no LLM provider interface)
- `Lakera/` — AI security platform (`AIFunction` tools for content screening; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Guardrails/` — LLM validation platform (self-hosted; `AIFunction` tools for guard validation, hallucination detection, PII; no standard MEAI interface)
- `Murf/` — TTS platform with 150+ voices (`AIFunction` tools for speech generation; no ISpeechToTextClient — TTS only, no STT)
- `Photoroom/` — AI image editing platform (`AIFunction` tools for background removal, AI backgrounds, relighting; no standard MEAI interface)
- `Nanonets/` — Document AI/OCR platform (`AIFunction` tools for OCR, classification, extraction; no standard MEAI interface)
- `Shotstack/` — Programmatic video editing platform (`AIFunction` tools for render status, templates, probing, assets; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `OpenRouter/` — LLM gateway/routing platform (`AIFunction` tools for model discovery, generation stats, credits; chat completions via `CustomProviders.OpenRouter()` in `tryAGI.OpenAI`)
- `HumeAI/` — Emotion AI platform (`AIFunction` tools for batch emotion analysis, TTS, voice/chat management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Nixtla/` — Time series AI platform (`AIFunction` tools for forecasting, anomaly detection, model listing; no standard MEAI interface)
- `GroundX/` — RAG infrastructure platform (`AIFunction` tools for document ingestion, search, bucket management; no standard MEAI interface)
- `PredictionGuard/` — LLM + guardrails platform (`AIFunction` tools for factuality, toxicity, PII, injection detection; potential `IChatClient` for chat completions)
- `LabelStudio/` — Data labeling platform (`AIFunction` tools for project/task/annotation management; no standard MEAI interface)
- `NightfallAI/` — Data security/DLP platform (`AIFunction` tools for PII/PHI/PCI scanning; no standard MEAI interface)
- `Humanloop/` — Prompt management platform (`AIFunction` tools for prompt/evaluation/dataset management; no standard MEAI interface)
- `Weave/` — W&B Weave LLM observability platform (`AIFunction` tools for call/object/table querying and feedback; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `ModernMT/` — Adaptive machine translation platform (`AIFunction` tools for translation, language detection, memory management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `LalalAI/` — Audio stem separation platform (`AIFunction` tools for task status, minutes, voice packs, cancellation; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Reducto/` — Document processing platform (`AIFunction` tools for parsing, extraction, classification, job management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Gretel/` — Synthetic data generation platform (`AIFunction` tools for project/model/workflow management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `MagicHour/` — AI video generation platform (`AIFunction` tools for text-to-video, image-to-video, face swap, lip sync, image gen; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Dust/` — AI agent platform (`AIFunction` tools for agent/conversation/space/data source management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Loudly/` — AI music generation platform (`AIFunction` tools for text-to-music, genre/structure listing, catalog search; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Creatomate/` — Programmatic video/image rendering platform (`AIFunction` tools for render creation, status, templates; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Greptile/` — Code intelligence platform (`AIFunction` tools for codebase Q&A, code search, repo indexing; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Novu/` — Notification infrastructure platform (`AIFunction` tools for triggering events, subscribers, workflows, topics; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Resend/` — Developer email platform (`AIFunction` tools for sending emails, domains, contacts, templates; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Apify/` — Web scraping platform (`AIFunction` tools for running actors, datasets, run management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Pinecone/` — Vector database + inference platform (`IEmbeddingGenerator` for embeddings; `AIFunction` tools for index management, reranking, collections)
- `Julep/` — Stateful AI agent workflow platform (`AIFunction` tools for agent/session/task/execution management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `ScrapeGraphAI/` — AI-powered web scraping platform (`AIFunction` tools for smart scraping, search, markdownify; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Sightengine/` — Visual content moderation platform (`AIFunction` tools for image/text moderation, AI-generated image detection; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `ModerationAPI/` — Multi-modal content moderation platform (`AIFunction` tools for text/image moderation, queue stats, actions; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Recombee/` — AI recommendation engine (`AIFunction` tools for personalized recommendations, search, interactions; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Zep/` — AI agent memory/context platform (`AIFunction` tools for knowledge graph memory, search, threads, context; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `CVAT/` — Computer vision annotation platform (`AIFunction` tools for projects, tasks, labels, job status; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Nomic/` — Embeddings + Atlas visualization platform (`IEmbeddingGenerator` for text embeddings; `AIFunction` tools for text/image embeddings)
- `Picsart/` — AI image/video editing platform (`AIFunction` tools for background removal, upscale, text-to-image, effects; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Algolia/` — AI search/recommendations platform (`AIFunction` tools for search, browse, index management + recommend; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Vellum/` — Prompt management/evaluation platform (`AIFunction` tools for prompt execution, document search, deployments; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Dataloop/` — Data management/annotation platform (`AIFunction` tools for projects, datasets, tasks, items; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `SiliconFlow/` — Unified AI inference platform (`AIFunction` tools for reranking, image gen, models; chat/embeddings via `CustomProviders.SiliconFlow()` in `tryAGI.OpenAI`)
- `ScaleAI/` — Data labeling/RLHF platform (`AIFunction` tools for projects, tasks, batches; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `EdenAI/` — Unified AI gateway platform (`AIFunction` tools for chat, translation, image gen, summarization, sentiment, language detection; no standard MEAI interface — meta-API routing)
- `JasperAI/` — AI marketing content generation platform (`AIFunction` tools for content generation, knowledge search, tasks, brand voices; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `HammingAI/` — Voice agent testing platform (`AIFunction` tools for running tests, experiment status, call results, datasets; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Writesonic/` — AI content generation platform (`AIFunction` tools for ChatSonic, articles, image gen, SEO; no standard MEAI interface — content templates, not direct LLM)
- `Predibase/` — LoRA fine-tuning/inference platform (`AIFunction` tools for deployments, fine-tuning jobs, datasets; inference is OpenAI-compatible via CustomProviders pattern)
- `Baseten/` — Model serving platform (`AIFunction` tools for models, deployments, secrets; no standard MEAI interface — deployment management, not direct inference)
- `WaveSpeedAI/` — Multi-model generation platform (`AIFunction` tools for image/video gen, task results, predictions; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Martian/` — LLM router/gateway (`AIFunction` tools for model listing, chat completions, routed chat; OpenAI-compatible endpoint also usable via CustomProviders)
- `Botpress/` — AI chatbot/agent platform (`AIFunction` tools for bot/conversation/message management; no standard MEAI interface like IChatClient/ISpeechToTextClient)
- `Firecrawl/`, `Flowise/`, `Forem/`, `Instill/`, `LangSmith/` — Platform/orchestration (no matching interface)

**Note:** OpenAI-compatible providers (Groq, DeepInfra, Fireworks, Together, SambaNova, Cerebras, Hyperbolic, Perplexity, Codestral, XAi, Nvidia, Ollama Cloud, SiliconFlow, etc.) get MEAI support via `CustomProviders.*()` factory methods in `tryAGI.OpenAI` — no standalone MEAI implementation needed in their individual SDKs.
