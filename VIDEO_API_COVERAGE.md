# Video API Coverage Audit

Audit date: 2026-05-04

This file tracks the video-generation benchmark list against tryAGI SDK coverage. It focuses on direct provider APIs first, then hosted/open-weight coverage through aggregator SDKs, and finally blocked/private APIs.

## SDKs Added

| Provider | SDK | Models covered from list | Source |
| --- | --- | --- | --- |
| PixVerse | `PixVerse` | PixVerse V4.5, V5, V5.5, V5.6, V6 | Official PixVerse Platform API docs describe `https://app-api.pixverse.ai/openapi/v2/`, `API-KEY`, `Ai-trace-id`, text/image video generation, status polling, uploads, lip-sync, restyle, fusion, swap, extend, mimic, and modify endpoints. |
| Pruna AI | `Pruna` | P-Video | Official Pruna API docs expose `/v1/predictions`, `/v1/predictions/status/{id}`, `/v1/predictions/delivery/{path}`, `/v1/files`, `apikey` auth, and the `p-video` model. |
| Lightricks | `LTX` | LTX-2 Fast, LTX-2 Pro, LTX-2.3 Fast, LTX-2.3 Pro | Official LTX docs expose `https://api.ltx.video/v1`, bearer auth, text-to-video, image-to-video, audio-to-video, retake, extend, upload, and LTX-2/LTX-2.3 model variants. |

## Existing Direct SDK Coverage

| Provider | Existing SDK | Models / rows covered | Notes |
| --- | --- | --- | --- |
| xAI | `Xai` | `grok-imagine-video` | Existing spec includes `/videos/generations`, `/videos/{requestId}`, `/videos/edits`, and model listing endpoints. |
| Vidu | `Vidu` | Vidu Q1, Q2 Pro/Turbo, Q3 Pro | Existing manual spec covers text-to-video, image-to-video, reference/start-end/template video, lip-sync, upscale, task status, and cancel endpoints. |
| KlingAI | `KlingAI` | Kling 1.6, 2.0, 2.1 | Existing SDK covers Kling video endpoints. The benchmark's 2.5/2.6/3.0 model names need a spec/model enum refresh before they can be marked fully covered. |
| Google | `Google.Gemini` | Veo 2, Veo 3, Veo 3.1, Veo 3.1 Fast/Lite | Google documents Veo video generation in the Gemini API. |
| Runway | `Runway` | Gen-4/Gen-4.5 and current Runway API video models | Runway now documents `gen4.5`, `gen4_turbo`, `gen4_aleph`, `act_two`, and hosted Veo models. Local SDK should be checked against the latest official spec for `gen4.5`. |
| MiniMax | `MiniMax` | Hailuo 02, Hailuo 2.3, Hailuo 2.3 Fast | Existing SDK covers `/v1/video_generation` and task query endpoints. |
| Luma Labs | `Luma` | Ray family | Existing SDK covers Dream Machine video generation/editing/upscale endpoints. Verify Ray 3 model enums against current docs. |
| Leonardo.Ai | `Leonardo` | Motion 2.0 | Existing SDK includes Leonardo API coverage; verify current Motion model naming before marking as exact. |
| OpenAI | `OpenAI` | Sora | OpenAI now documents the Videos API in preview for Sora. The local OpenAI spec should be refreshed or manually extended if it does not yet include `/videos`. |

## Hosted / Open-Weight Coverage

| Provider / model family | Existing SDK path | Notes |
| --- | --- | --- |
| Tencent HunyuanVideo / HunyuanVideo-1.5 | `Fal`, `HuggingFace`, `Replicate` | Benchmark rows are tagged open weights or hosted on Fal. Direct Tencent public API was not added. |
| Alibaba Wan open-weight rows | `Fal`, `HuggingFace`, `Replicate`, `WaveSpeedAI` | Wan 2.1/2.2 open-weight and hosted variants are covered through hosted/model-platform SDKs. |
| Alibaba Wan commercial API | `DashScope` candidate | Alibaba Cloud documents Wan video-generation APIs under DashScope. The existing `DashScope` SDK does not yet include these video endpoints and should be extended separately. |
| ByteDance Seedance 1.x | `Fal`, `Replicate`, `WaveSpeedAI` candidate coverage | Direct ByteDance/Dreamina SDK was not added. Hosted endpoints exist in aggregator SDKs; official direct API coverage needs a provider spec. |

## Blocked SDKs

| Provider / model | Status | Reason |
| --- | --- | --- |
| Alibaba-ATH HappyHorse-1.0 | Blocked | Listed as "Coming soon"; no public API contract found. |
| ByteDance Dreamina Seedance 2.0 | Blocked | Listed as "No API available"; public sources indicate official API access is not generally available and many integrations are reverse-engineered wrappers. |
| TeleAI TeleVideo 2.0 | Blocked | Listed as "No API available"; no public API docs found. |
| Pika Art Pika 2.2 / 2.5 | Blocked | Listed as "No API available"; existing local `Pika` SDK targets PikaStream/avatar workflows, not official Pika generation API. |
| Midjourney V1 | Blocked | Listed as "No API available"; no official public API/SDK for programmatic generation. |
| HiDream Vivago 2.0 | Blocked | Listed as "No API available"; no public API docs found. |
| Moonvalley Marey | Blocked | No public API docs found. |
| Runway Gen 3 Alpha / Gen 3 Alpha Turbo | Blocked as legacy rows | Runway has a public API, but current official model list should be used instead of unsupported legacy benchmark labels. |

## Source Links

- PixVerse Platform API: https://docs.platform.pixverse.ai/pixverse-api-llm-txt-2109771m0
- Pruna APIs: https://docs.api.pruna.ai/apis
- Pruna P-Video: https://docs.api.pruna.ai/guides/models/p-video
- LTX API docs: https://docs.ltx.video/
- LTX API reference: https://docs.ltx.video/api-reference
- LTX supported models: https://docs.ltx.video/models
- xAI video generation: https://docs.x.ai/developers/model-capabilities/video/generation
- Google Veo in Gemini API: https://ai.google.dev/gemini-api/docs/video
- OpenAI Sora video generation: https://platform.openai.com/docs/guides/video-generation
- Runway model list: https://docs.dev.runwayml.com/guides/models/
- Alibaba Cloud Wan video API: https://www.alibabacloud.com/help/en/model-studio/text-to-video-api-reference
- Vidu API image-to-video reference: https://platform.vidu.com/docs/image-to-video/
- MiniMax video generation docs: https://platform.minimax.io/docs/api-reference/video-generation-intro
