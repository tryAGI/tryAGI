# Video API Coverage Audit

Audit date: 2026-05-04

This file tracks the video-generation benchmark rows against tryAGI SDK coverage. It prioritizes direct provider APIs, then official aggregator APIs where the provider does not expose a public direct API, then hosted/open-weight model-platform coverage, and finally blocked/private APIs.

## SDKs Added / Updated

| Provider | SDK | Models covered from list | Source / change |
| --- | --- | --- | --- |
| PixVerse | `PixVerse` | PixVerse V4.5, V5, V5.5, V5.6, V6 | Added from official PixVerse Platform API docs: `https://app-api.pixverse.ai/openapi/v2/`, `API-KEY`, `Ai-trace-id`, text/image video generation, status polling, uploads, lip-sync, restyle, fusion, swap, extend, mimic, and modify endpoints. |
| Pruna AI | `Pruna` | P-Video | Added from official Pruna API docs: `/v1/predictions`, `/v1/predictions/status/{id}`, `/v1/predictions/delivery/{path}`, `/v1/files`, `apikey` auth, and the `p-video` model. |
| Lightricks | `LTX` | LTX-2 Fast, LTX-2 Pro, LTX-2.3 Fast, LTX-2.3 Pro | Added from official LTX docs: `https://api.ltx.video/v1`, bearer auth, text-to-video, image-to-video, audio-to-video, retake, extend, upload, and LTX-2/LTX-2.3 model variants. |
| Haiper | `Haiper` | Haiper 2.0 | Added from Haiper docs and official OpenAPI source. The checked-in spec keeps the real Gen2 text-to-video, image-to-video, text-to-image, keyframe conditioning, status/detail, watermark-free URL, and cancel endpoints, while excluding unrelated sample `plants` paths from the published OpenAPI file. |
| Alibaba Cloud Model Studio | `DashScope` | Wan 2.1, Wan 2.2, Wan 2.5 Preview, Wan 2.6 | Updated existing SDK with the official DashScope async Wan endpoint `POST /services/aigc/video-generation/video-synthesis`, plus generated `Videos` client and a paid-test opt-in example. |

## Existing Direct SDK Coverage

| Provider | Existing SDK | Models / rows covered | Notes |
| --- | --- | --- | --- |
| xAI | `Xai` | `grok-imagine-video` | Existing spec includes `/videos/generations`, `/videos/{requestId}`, `/videos/edits`, and model listing endpoints. |
| Vidu | `Vidu` | Vidu Q1, Q2, Q2 Pro/Turbo, Q3 Pro | Existing manual spec covers text-to-video, image-to-video, reference/start-end/template video, lip-sync, upscale, task status, and cancel endpoints. |
| KlingAI | `KlingAI` | Kling 1.0, 1.5, 1.6, 2.0, 2.1 | Existing direct SDK covers older official model enums. Current-list rows for Kling 2.5, 2.6, O1, and 3.0 are covered through `Krea`; direct `KlingAI` should be refreshed only from official provider docs/spec. |
| Google | `Google.Gemini` | Veo 2, Veo 3, Veo 3.1, Veo 3.1 Fast/Lite, Veo 3 Fast Preview | Google documents Veo video generation in the Gemini API. |
| Runway | `Runway` | Gen 3 Alpha Turbo (`gen3a_turbo`), Gen-4, Gen-4.5/current Runway API video models | Existing SDK is generated from Runway's official OpenAPI and includes current video models such as `gen4_turbo`, `gen4_aleph`, `gen4.5`, `gen3a_turbo`, and hosted Veo models. |
| MiniMax | `MiniMax` | Hailuo 02 Fast/Standard/Pro, Hailuo 2.3, Hailuo 2.3 Fast, T2V-01, T2V-01-Director | Existing SDK covers `/v1/video_generation` and task query endpoints. |
| Luma Labs | `Luma` | Ray family | Existing SDK covers Dream Machine video generation/editing/upscale endpoints. Verify exact Ray 1/2/3 model names against current docs before marking all benchmark aliases exact. |
| Leonardo.Ai | `Leonardo` | Motion 2.0 | Existing SDK includes Leonardo API coverage; verify current Motion model naming before marking as exact. |
| OpenAI | `OpenAI` | Sora 2, Sora 2 Pro | Existing local OpenAI spec includes `/videos`, `/videos/{video_id}`, `/videos/{video_id}/content`, `/videos/{video_id}/remix`, `/videos/edits`, `/videos/extensions`, and `VideoModel` values for `sora-2`, `sora-2-pro`, and dated Sora 2 snapshots. |
| Krea | `Krea` | Aggregated rows: Seedance 2 / 1.x, Sora 2, Veo 2/3/3.1, Kling 2.5/2.6/O1, Hailuo 2.3, Runway Gen-4.5, Wan 2.1/2.2/2.5, Ray 2 | Existing Krea SDK exposes official Krea REST endpoints for many video models that have limited or unavailable direct APIs. It is aggregator coverage, not a direct provider SDK. |
| Z AI | `ZAI` | CogVideoX direct API family | Existing ZAI SDK includes `/paas/v4/videos/generations` for CogVideoX/Vidu-style video generation. The benchmark's CogVideoX-5B row remains open-weight/hosted coverage rather than an exact ZAI hosted API row. |

## Hosted / Open-Weight Coverage

| Provider / model family | Existing SDK path | Notes |
| --- | --- | --- |
| Tencent HunyuanVideo / HunyuanVideo-1.5 | `Fal`, `HuggingFace`, `Replicate` | Benchmark rows are tagged open weights or hosted on Fal. Direct Tencent public API was not added. |
| Alibaba Wan open-weight rows | `Fal`, `HuggingFace`, `Replicate`, `WaveSpeedAI`; direct commercial via `DashScope`; aggregator via `Krea` | Wan 2.1/2.2 open-weight and hosted variants are covered through model-platform SDKs; commercial DashScope text-to-video is now direct SDK coverage. |
| ByteDance Seedance 1.x / 2.0 | `Krea`, `Fal`, `Replicate`, `WaveSpeedAI` candidate coverage | Direct ByteDance/Dreamina SDK was not added. Krea provides official aggregator endpoints for Seedance 1.x/2.0 rows. |
| Genmo Mochi 1 | `Fal`, `HuggingFace`, `Replicate` | Open-weight/hosted model row; no direct Genmo API SDK was added. |
| Krea Realtime | `HuggingFace` / open-weight model-platform SDKs | The row is marked open weights. Existing `Krea` SDK covers Krea's public REST API, but this benchmark row should be treated as open-weight/hosted unless Krea exposes a named realtime endpoint in its API spec. |
| StepFun Step-Video-T2V | `HuggingFace`, `GitHub` / model-platform SDKs | Step-Video-T2V is published as open-source/open-weight research; the existing `StepFun` SDK covers Step audio/text APIs and does not expose a hosted Step video endpoint. |
| Z AI CogVideoX-5B | `HuggingFace`, `Replicate`; direct adjacent coverage via `ZAI` | The benchmark row is open-weight. Existing `ZAI` direct video API covers CogVideoX-3 rather than the exact CogVideoX-5B open-weight row. |
| Pyramid Flow | `HuggingFace`, `Replicate`, `Fal` candidate coverage | Open-weight/hosted row; no direct provider API SDK was added. |

## Blocked SDKs

| Provider / model | Status | Reason |
| --- | --- | --- |
| Alibaba-ATH HappyHorse-1.0 | Blocked | Listed as "Coming soon"; no public API contract found. |
| ByteDance Dreamina Seedance 2.0 direct API | Blocked direct / covered via `Krea` | Listed as "No API available" for direct Dreamina access. Krea provides official aggregator coverage, but no direct ByteDance/Dreamina spec was found. |
| TeleAI TeleVideo 2.0 | Blocked | Listed as "No API available"; no public API docs found. |
| Pika Art Pika 1.5 / 2.0 / 2.2 / 2.5 | Blocked | Listed as "No API available"; existing local `Pika` SDK targets PikaStream/avatar workflows, not an official Pika video-generation API. |
| Midjourney V1 | Blocked | Listed as "No API available"; no official public API/SDK for programmatic generation. |
| HiDream Vivago 2.0 | Blocked | Listed as "No API available"; no public API docs found. |
| Moonvalley Marey | Blocked | No public API docs found. |
| OpenAI legacy Sora row | Blocked as legacy label / superseded | Current OpenAI API coverage is Sora 2 and Sora 2 Pro. The benchmark row named only `Sora` and marked "No API available" should not be treated as an exact current API model. |
| Luma Ray 1 | Blocked as legacy / coming soon row | Existing `Luma` SDK covers Dream Machine/Ray-family API surfaces, but this exact legacy benchmark label is listed as "Coming soon" and should be verified before exact mapping. |

## Source Links

- PixVerse Platform API: https://docs.platform.pixverse.ai/pixverse-api-llm-txt-2109771m0
- Pruna APIs: https://docs.api.pruna.ai/apis
- Pruna P-Video: https://docs.api.pruna.ai/guides/models/p-video
- LTX API docs: https://docs.ltx.video/
- LTX API reference: https://docs.ltx.video/api-reference
- LTX supported models: https://docs.ltx.video/models
- Haiper API overview: https://docs.haiper.ai/api-reference/overview
- Haiper Text to Video: https://docs.haiper.ai/api-reference/endpoint/2-0-text-to-video
- Haiper OpenAPI: https://docs.haiper.ai/api-reference/openapi.json
- Alibaba Cloud Wan video API: https://www.alibabacloud.com/help/en/model-studio/text-to-video-api-reference
- Krea API: https://www.krea.ai/features/api
- Krea image-to-video example: https://docs.krea.ai/developers/examples/image-to-video
- Step-Video-T2V technical report: https://arxiv.org/abs/2502.10248
- xAI video generation: https://docs.x.ai/developers/model-capabilities/video/generation
- Google Veo in Gemini API: https://ai.google.dev/gemini-api/docs/video
- OpenAI Sora video generation: https://platform.openai.com/docs/guides/video-generation
- OpenAI Sora 2 model: https://platform.openai.com/docs/models/sora-2/
- Runway model list: https://docs.dev.runwayml.com/guides/models/
- Vidu API image-to-video reference: https://platform.vidu.com/docs/image-to-video/
- MiniMax video generation docs: https://platform.minimax.io/docs/api-reference/video-generation-intro
