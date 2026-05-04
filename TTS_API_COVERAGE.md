# TTS API Coverage

Coverage audit for the TTS ranking list requested on 2026-05-04.

The goal is to have a typed SDK wherever a stable public API contract can be
identified. Direct provider SDKs are preferred. Open-weight models are tracked
through hosted inference SDKs unless the model publisher exposes a first-party
HTTP API contract.

## New SDKs Added

| Provider | SDK | Source contract |
|----------|-----|-----------------|
| LMNT | `LMNT/` | Official OpenAPI document at `https://api.lmnt.com/spec`; generation strips the non-OpenAPI preface and bundled AsyncAPI section before generating the REST client. |
| Smallest.ai | `SmallestAI/` | Official OpenAPI document at `https://docs.smallest.ai/openapi.yaml?api=148120e3-2d93-487e-9a21-5704cd2be0c4`. |
| Gradium | `Gradium/` | Official OpenAPI document at `https://docs.gradium.ai/api-reference/openapi.json`. |
| Async Voice API | `AsyncAI/` | Manual OpenAPI assembled from the provider's public endpoint-level OpenAPI snippets in `https://docs.async.com/llms.txt`. |
| Neuphonic | `Neuphonic/` | Manual OpenAPI assembled from the provider's public docs, official Python/JavaScript SDKs, and the live FastAPI OpenAPI surface at `https://api.neuphonic.com/openapi.json`. |

## Provider Coverage

| Listed provider / model family | Coverage | Notes |
|--------------------------------|----------|-------|
| Inworld TTS / Realtime TTS | `Inworld/` | Existing direct SDK. |
| Google Gemini TTS | `Google.Gemini/` | Existing direct SDK for Gemini API models. |
| Google Studio, Journey, Chirp, WaveNet, Neural2, Standard | External official SDK / candidate | Google Cloud Text-to-Speech is public, but the contract is Google Discovery/gRPC rather than an OpenAPI document in this workspace. Use Google's client libraries unless a hand-maintained OpenAPI SDK is explicitly desired. |
| ElevenLabs models | `ElevenLabs/` | Existing direct SDK. |
| MiniMax Speech/T2A models | `MiniMax/` | Existing direct SDK. |
| StepFun Step TTS / Audio EditX | `StepFun/` / hosted open-weight SDKs | Existing direct SDK for StepFun APIs; open-weight models can also be reached through hosted inference providers when available. |
| Fish Audio / OpenAudio / Fish Speech | `FishAudio/` / `HuggingFace/` | Existing direct SDK plus hosted/open-weight coverage. |
| Microsoft Azure Neural / Azure HD | External official SDK / candidate | Azure Speech REST is public but uses Azure token exchange and regional endpoints. Use Azure Speech SDK unless a hand-maintained OpenAPI SDK is requested. |
| Microsoft MAI-Voice-1 | Blocked | No standalone public endpoint-level API contract found for the listed model. |
| Microsoft VibeVoice | Hosted/open-weight coverage | Open-weight model family; no first-party hosted API SDK target identified. |
| OpenAI TTS | `OpenAI/` | Existing direct SDK. |
| Gradium TTS | `Gradium/` | New direct SDK. |
| Cartesia Sonic | `Cartesia/` | Existing direct SDK. |
| NVIDIA Magpie | Hosted/open-weight coverage | Open-weight model family; use `HuggingFace/`, `Replicate/`, `Fal/`, or other hosting SDKs when deployed. |
| Speechify SIMBA | `Speechify/` | Existing direct SDK. |
| Kokoro | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |
| Amazon Polly | External official SDK / candidate | Public AWS API, but the native contract uses AWS service models and SigV4 rather than simple OpenAPI. Prefer `AWSSDK.Polly` unless a dedicated manual SDK is needed. |
| Mistral Voxtral TTS | `Mistral/` / hosted open-weight SDKs | Existing Mistral SDK; open-weight variants can be reached through hosted inference providers when available. |
| AsyncFlow / Async Voice API | `AsyncAI/` | New direct SDK from manual OpenAPI based on official docs. |
| Maya Research Maya1 | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |
| Hume AI Octave | `HumeAI/` | Existing direct SDK. |
| Smallest.ai Lightning | `SmallestAI/` | New direct SDK. |
| Resemble AI Chatterbox | `ResembleAI/` / hosted open-weight SDKs | Existing direct SDK plus hosted/open-weight coverage. |
| Xiaomi MiMo-V2-TTS | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |
| Rime Arcana / Mist | `Rime/` | Existing direct SDK. |
| Zyphra Zonos | Blocked for direct SDK | Public package/model references exist, but no public OpenAPI or endpoint-level API reference was found. Use hosted/open-weight paths until Zyphra publishes a stable public contract. |
| LMNT | `LMNT/` | New direct SDK. |
| Neuphonic TTS | `Neuphonic/` | New direct SDK from a focused manual OpenAPI spec covering SSE TTS, voices, and agent management. The live FastAPI OpenAPI exists but lacks useful response schemas/security, so the checked-in spec is typed from official docs and SDKs. |
| Alibaba Qwen TTS | `DashScope/` / hosted open-weight SDKs | Existing Alibaba DashScope SDK is the first path to check for hosted Qwen APIs; open-weight variants are hosted-model coverage. |
| Murf Speech / Falcon | `Murf/` | Existing direct SDK. |
| OpenVoice | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |
| Coqui XTTS | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |
| StyleTTS | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |
| MetaVoice | Hosted/open-weight coverage | Open-weight model; no first-party hosted API contract. |

## Blocked Provider Backlog

| Provider | Current blocker | What would unblock it | Next check |
|----------|-----------------|-----------------------|------------|
| Microsoft MAI-Voice-1 | No public endpoint-level API contract found for the listed model. | Official API docs, OpenAPI, Postman collection, or Azure Foundry endpoint documentation with auth and request/response schemas. | Recheck Microsoft Learn, Azure AI Foundry model catalog, and any MAI product announcement docs. |
| Zyphra Zonos direct API | Public model/package references exist, but no public OpenAPI or endpoint-level API reference was available during the audit. | Public API reference or OpenAPI documenting auth, base URL, model ids, request/response bodies, and audio output formats. | Recheck Zyphra docs, PyPI package docs, and playground/account docs if made public. |
| First-party open-weight-only models | Model cards or repositories exist, but no hosted API contract is published by the model owner. | A first-party hosted REST API or documented supported deployment endpoint. | Prefer hosted inference SDKs (`HuggingFace/`, `Replicate/`, `Fal/`, `DeepInfra/`, `SiliconFlow/`) until first-party APIs appear. |

For any blocked entry, the minimum SDK intake criteria are:

- Base URL and supported environments.
- Authentication scheme and token/header/query details.
- Endpoint list with HTTP methods and paths.
- Request and response schemas, including audio formats and streaming/task behavior.
- Error schema and rate-limit behavior if available.
- Terms that allow using the API from a generated public SDK.

## Source References

- LMNT OpenAPI: <https://api.lmnt.com/spec>
- LMNT API reference: <https://docs.lmnt.com/api-reference>
- Smallest.ai API reference/OpenAPI: <https://docs.smallest.ai/waves/api-reference>
- Gradium API reference: <https://docs.gradium.ai/api-reference/introduction>
- Async Voice API docs: <https://docs.async.com/llms.txt>
- Google Cloud Text-to-Speech REST reference: <https://docs.cloud.google.com/text-to-speech/docs/reference/rest>
- Azure Speech text-to-speech REST reference: <https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech>
- Amazon Polly API reference: <https://docs.aws.amazon.com/polly/latest/dg/API_Reference.html>
- Neuphonic docs: <https://docs.neuphonic.com/>
- Neuphonic text-to-speech docs: <https://docs.neuphonic.com/build-group/text-to-speech>
- Neuphonic voice cloning docs: <https://docs.neuphonic.com/build-group/voice-cloning>
- Neuphonic live FastAPI OpenAPI: <https://api.neuphonic.com/openapi.json>
- Neuphonic Python SDK: <https://github.com/neuphonic/pyneuphonic>
- Neuphonic JavaScript SDK: <https://github.com/neuphonic/neuphonic-js>
- Zyphra package reference: <https://pypi.org/project/zyphra/>
