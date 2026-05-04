# Image API Coverage Audit

Audit date: 2026-05-04

Scope: image-generation and image-editing models from the supplied leaderboard. This audit records direct SDK coverage first, then aggregator/open-weight coverage, then providers that are blocked because the exact model/API is unavailable, private, or not exposed by official docs.

## Added Or Updated In This Pass

| Provider | SDK | Coverage | Source |
| --- | --- | --- | --- |
| Reve | `Reve` | Added a new SDK from a manual OpenAPI spec for `/v1/image/create/`, `/v1/image/remix/`, `/v1/image/edit/`, balance, and effects. Covers Reve V1. | Official [`reve-ai/reve-sdk`](https://github.com/reve-ai/reve-sdk) and [Python SDK docs](https://raw.githubusercontent.com/reve-ai/reve-sdk/main/python/README.md). |
| EigenAI | `EigenAI` | Added a new SDK from official docs because EigenAI's advertised OpenAPI URL currently serves a Mintlify sample spec. Covers the JSON `/api/v1/generate` image endpoint for Eigen Image style models. | [EigenAI image generation docs](https://docs.eigenai.com/products/model-api/api-reference/generate-image.md). |
| BytePlus ModelArk | `BytePlusModelArk` | Added a new SDK for `POST /api/v3/images/generations`, covering direct Seedream image models where available by model id. | [BytePlus ModelArk quick start / image generation docs](https://docs.byteplus.com/en/docs/ModelArk/1824121). |
| Alibaba DashScope | `DashScope` | Updated docs/examples for Qwen Image Edit and Wan 2.6 Image through the existing multimodal generation endpoint. | [Wan 2.6 image API](https://help.aliyun.com/zh/model-studio/wan-image-generation-api-reference) and [Qwen Image Edit API](https://help.aliyun.com/zh/model-studio/qwen-image-edit-api). |

## Existing Direct SDK Coverage

| Leaderboard provider/models | SDK | Notes |
| --- | --- | --- |
| OpenAI GPT Image 1.5, GPT Image 1, GPT Image 1 Mini | `OpenAI` | Existing `/images/generations` and `/images/edits` coverage. `gpt-image-2` was not present in the local official OpenAI spec snapshot. |
| Google Nano Banana / Gemini image models | `Google.Gemini` | Existing Gemini `generateContent` SDK covers image generation/editing through native image models such as `gemini-3.1-flash-image-preview`, `gemini-3-pro-image-preview`, and `gemini-2.5-flash-image`. |
| xAI grok-imagine-image | `Xai` | Existing `/images/generations` and `/images/edits` coverage. |
| Black Forest Labs FLUX.2 and FLUX.1 Kontext | `BlackForestLabs` | Existing official BFL OpenAPI covers FLUX.2 max/pro/flex/klein and FLUX.1 Kontext pro/max/dev endpoints. |
| Alibaba Wan Image and Qwen Image Edit | `DashScope` | Direct Alibaba Model Studio coverage via `/services/aigc/multimodal-generation/generation`. |
| ByteDance Seedream | `BytePlusModelArk` | Direct BytePlus ModelArk image generation endpoint; exact model availability is controlled by ModelArk account/region/model activation. |
| Pruna P-Image-Edit | `Pruna` | Existing generic prediction API includes `p-image-edit` and related hosted image models. |
| Z AI GLM-Image | `ZAI` | Existing image generation endpoints cover `glm-image`. |
| Krea-hosted image models | `Krea` | Existing Krea SDK covers hosted endpoints for Nano Banana, Seedream, OpenAI GPT Image, Qwen, Flux/Kontext, and Z-Image variants. |
| Reve V1 | `Reve` | New direct SDK from official SDK docs. |
| Eigen Image | `EigenAI` | New direct SDK from official image generation docs. |

## Aggregator Or Open-Weight Coverage

| Models | SDKs | Notes |
| --- | --- | --- |
| FLUX.2 dev/dev turbo/dev flash/klein open-weight variants | `BlackForestLabs`, `Fal`, `Replicate`, `HuggingFace`, `Krea` | Direct BFL covers managed endpoints; hosted/open-weight variants are reachable through model platforms. |
| Tencent HunyuanImage 3.0 Instruct | `Fal`, `HuggingFace`, `Replicate` | Open-weight/hosted model coverage; no separate Tencent direct image SDK added. |
| Qwen Image Edit open-weight variants | `DashScope`, `Pruna`, `HuggingFace`, `Fal`, `Krea` | Direct DashScope covers Alibaba-hosted Qwen Image Edit; hosted/open-weight routes remain covered by model platforms. |
| StepFun Step1X Edit variants | `HuggingFace`, `Fal`, `Replicate` | Open-weight or hosted coverage only; no public direct StepFun image API found for the exact leaderboard rows. |
| Bria FIBO Edit | `HuggingFace`, `Fal`, `Replicate` | Open-weight/hosted coverage. No official direct Bria OpenAPI was added in this pass. |
| HiDream, LongCat Image, OmniGen V2, Bagel | `HuggingFace`, `Fal`, `Replicate` | Open-weight/hosted coverage through generic model platform SDKs. |
| Seedream via Krea | `Krea` | Krea has provider-specific endpoints such as `/generate/image/bytedance/seedream-5-lite` and `/generate/image/bytedance/seedream-4`. |

## Blocked Or Not Directly Added

| Provider/model | Status | Reason |
| --- | --- | --- |
| GPT Image 2 | Blocked exact-model refresh | Existing OpenAI SDK covers image endpoints, but the local official spec snapshot does not list `gpt-image-2`; avoid inventing a model enum until official spec/docs expose it. |
| Adobe Firefly Image 5 Preview | Blocked exact model | Adobe Firefly Services APIs exist, but the leaderboard row is a preview model and was listed as no API available; official changelog references Firefly API versions but not this exact public model endpoint. |
| Kling Image 3.0 / Kling Image O1 | Blocked exact direct model | Existing `KlingAI` SDK has image endpoints, but the checked spec only listed older image model names. Need an official updated Kling spec/docs before adding exact 3.0/O1 aliases. |
| Vidu Q2 image row | Blocked direct model | Existing `Vidu` SDK is video-oriented; no official direct image-generation endpoint was found in the local Vidu spec during this pass. |
| Direct StepFun image API | Blocked direct model | Leaderboard rows are open-weight/coming-soon style entries; no public direct StepFun image API docs/spec were found. |
| Direct Bria FIBO Edit API | Blocked direct SDK | Hosted/open-weight coverage exists; no official direct OpenAPI suitable for a provider SDK was found in this pass. |
| Adobe/closed UI-only entries and preview-only rows | Blocked | Public API docs/specs did not expose the exact leaderboard model, or the row explicitly indicated no API/coming soon. |

## Sources Used

- [OpenAI Images API reference](https://platform.openai.com/docs/api-reference/images/overview)
- [Google Gemini Nano Banana image generation docs](https://ai.google.dev/gemini-api/docs/image-generation)
- [xAI image generation docs](https://docs.x.ai/docs/guides/image-generation)
- [Black Forest Labs FLUX.2 docs](https://docs.bfl.ai/flux_2)
- [Krea developer docs](https://docs.krea.ai/developers/introduction)
- [Krea Seedream 5 Lite API reference](https://docs.krea.ai/api-reference/image/seedream-5-lite)
- [BytePlus ModelArk image generation docs](https://docs.byteplus.com/en/docs/ModelArk/1824121)
- [Alibaba Wan 2.6 image API](https://help.aliyun.com/zh/model-studio/wan-image-generation-api-reference)
- [Alibaba Qwen Image Edit API](https://help.aliyun.com/zh/model-studio/qwen-image-edit-api)
- [EigenAI image generation docs](https://docs.eigenai.com/products/model-api/api-reference/generate-image.md)
- [Reve official SDK](https://github.com/reve-ai/reve-sdk)
- [Adobe Firefly API changelog](https://developer.adobe.com/firefly-services/docs/firefly-api/getting-started/changelog/)
