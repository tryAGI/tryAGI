# STT API Coverage

Coverage audit for the speech-to-text / transcription ranking list requested on
2026-05-04.

The goal is to have a typed SDK wherever a stable public API contract can be
identified. Direct provider SDKs are preferred. Hosted open-weight models are
tracked through their hosting-provider SDKs unless the model publisher exposes a
first-party HTTP API contract.

## New SDKs Added

| Provider | SDK | Source contract |
|----------|-----|-----------------|
| Fireworks AI | `Fireworks/` | Manual OpenAPI assembled from the official Fireworks audio transcription and translation API references. Fireworks does not publish a downloadable OpenAPI document for these audio endpoints. |

## Provider Coverage

| Listed provider / model family | Coverage | Notes |
|--------------------------------|----------|-------|
| OpenAI Whisper Large v2, GPT-4o Transcribe, GPT-4o Mini Transcribe | `OpenAI/` | Existing direct SDK for OpenAI audio transcription endpoints. |
| fal.ai Wizper / Whisper | `Fal/` | Existing hosted inference SDK. |
| Replicate Incredibly Fast Whisper, Whisper Large v3, Parakeet RNNT, Canary Qwen | `Replicate/` | Existing hosted inference SDK for Replicate model deployments. |
| Groq Whisper Large v3 Turbo | `Groq/` | Existing direct SDK includes OpenAI-compatible `/openai/v1/audio/transcriptions` and `/openai/v1/audio/translations`. |
| Fireworks Whisper Large v3 / Whisper Large v3 Turbo | `Fireworks/` | New direct SDK for Fireworks pre-recorded transcription and translation. The generated client defaults to `whisper-v3`; pass `baseUri: FireworksClient.WhisperV3TurboBaseUri` for `whisper-v3-turbo`. |
| Together.ai Whisper Large v3 | `Together/` | Existing direct SDK includes `/audio/transcriptions` and `/audio/translations`. |
| Speechmatics Standard / Enhanced | `Speechmatics/` | Existing direct SDK for Speechmatics batch ASR jobs. |
| Deepgram Nova, Base, Nova-2, Nova-3 | `Deepgram/` | Existing direct SDK includes `/v1/listen`. |
| AssemblyAI Universal / Universal-3 Pro | `AssemblyAI/` | Existing direct SDK for upload/transcript workflows. |
| Amazon Transcribe | External official SDK / candidate | Public AWS service, but the canonical contract uses AWS service models and SigV4 rather than a simple OpenAPI document. Prefer `AWSSDK.TranscribeService` unless a dedicated hand-maintained SDK is explicitly desired. |
| Amazon Bedrock Nova 2 Omni / Nova 2 Pro | `AwsBedrock/` | Existing Bedrock SDK path for Amazon Nova multimodal model invocation. |
| Rev AI | `RevAI/` | Existing direct SDK for async speech-to-text jobs. |
| Google Chirp / Chirp 2 / Chirp 3 | External official SDK / candidate | Public Google Cloud Speech-to-Text API, but this workspace does not currently have a direct Google Cloud Speech SDK. Prefer Google Cloud client libraries unless a hand-maintained OpenAPI SDK is requested. |
| Google Gemini audio transcription models | `Google.Gemini/` | Existing direct SDK for Gemini audio-capable models. |
| ElevenLabs Scribe v1 / v2 | `ElevenLabs/` | Existing direct SDK includes speech-to-text endpoints. |
| Mistral Voxtral Mini Transcribe / Voxtral Small | `Mistral/` | Existing Mistral SDK covers audio transcription APIs and audio-capable chat models. |
| DeepInfra Voxtral Mini | `DeepInfra/` | Existing hosted inference SDK. |
| Gladia Solaria-1 | `Gladia/` | Existing direct SDK. |
| Soniox V4 | `Soniox/` | Existing direct SDK. |
| Smallest.ai Pulse STT | `SmallestAI/` | Existing direct SDK includes Pulse speech-to-text. |
| Alibaba Cloud Qwen3.5 Omni Flash / Plus | `DashScope/` | Existing hand-maintained DashScope SDK is the workspace path for Alibaba Cloud Qwen multimodal APIs. Realtime-only WebSocket flows may need follow-up outside OpenAPI. |
| NVIDIA Parakeet TDT 0.6B V2 | Hosted/open-weight coverage | Open-weight model family; no stable first-party REST/OpenAPI SDK target was identified. Use hosted inference SDKs such as `Replicate/`, `Fal/`, `DeepInfra/`, or `HuggingFace/` when deployed through those providers. |

## Blocked Provider Backlog

| Provider / model family | Current blocker | What would unblock it | Next check |
|-------------------------|-----------------|-----------------------|------------|
| NVIDIA Parakeet direct SDK | Public model references exist, but no stable first-party endpoint-level REST/OpenAPI contract was identified for this benchmark row. | NVIDIA-hosted REST API docs, OpenAPI, Postman collection, or NIM endpoint documentation with auth, request, and response schemas for the specific model. | Recheck NVIDIA API Catalog / NIM docs and model cards. |
| Google Cloud Speech direct SDK | Public API exists, but no direct workspace SDK is present and the primary contract is Google Cloud REST/gRPC/Discovery rather than a local OpenAPI spec. | Decision to add a hand-maintained Google Cloud Speech OpenAPI SDK or consume Google Discovery/gRPC tooling directly. | Recheck Google Cloud Speech-to-Text v2 REST docs and existing Google SDK coverage. |
| Amazon Transcribe direct SDK | Public API exists, but the primary contract is AWS service models plus SigV4, not a simple public OpenAPI spec. | Decision to wrap AWS service models or hand-maintain OpenAPI plus SigV4 signing support. | Recheck AWS SDK/service model support and whether a dedicated `AwsTranscribe/` SDK is worth the maintenance cost. |
| Realtime WebSocket-only STT APIs | OpenAPI generation does not model bidirectional WebSocket sessions cleanly. | AsyncAPI or hand-written streaming client support for each provider with stable event schemas. | Prioritize Fireworks streaming ASR, Alibaba Qwen-Omni realtime, and AssemblyAI/Deepgram realtime only if streaming STT is requested. |

For any blocked entry, the minimum SDK intake criteria are:

- Base URL and supported environments.
- Authentication scheme and token/header/query details.
- Endpoint list with HTTP methods and paths.
- Request and response schemas, including audio formats and streaming/task behavior.
- Error schema and rate-limit behavior if available.
- Terms that allow using the API from a generated public SDK.

## Source References

- Fireworks speech-to-text guide: <https://docs.fireworks.ai/guides/querying-asr-models>
- Fireworks transcribe audio API reference: <https://docs.fireworks.ai/api-reference/audio-transcriptions>
- Fireworks translate audio API reference: <https://docs.fireworks.ai/api-reference/audio-translations>
- Fireworks streaming ASR API reference: <https://docs.fireworks.ai/api-reference/audio-streaming-transcriptions>
- Fireworks batch audio API reference: <https://docs.fireworks.ai/api-reference/create-batch-request>
- Mistral audio transcription API reference: <https://docs.mistral.ai/api/endpoint/audio/transcriptions>
- Mistral audio capabilities docs: <https://docs.mistral.ai/capabilities/audio/>
- Alibaba Cloud Qwen-Omni realtime docs: <https://www.alibabacloud.com/help/en/model-studio/realtime>
- Alibaba Cloud Qwen-Omni docs: <https://www.alibabacloud.com/help/doc-detail/2867839.html>
- Replicate Canary Qwen API reference: <https://replicate.com/nvidia/canary-qwen-2.5b/api/api-reference>
- Google Cloud Speech-to-Text REST reference: <https://cloud.google.com/speech-to-text/docs/reference/rest>
- Amazon Transcribe API reference: <https://docs.aws.amazon.com/transcribe/latest/APIReference/>
- OpenAI audio transcription API reference: <https://platform.openai.com/docs/api-reference/audio/createTranscription>
