# Image API Coverage Audit

Audit date: 2026-05-04

Scope: image-generation and image-editing models from the supplied leaderboards. This audit records direct SDK coverage first, then aggregator/open-weight coverage, then providers that are blocked because the exact model/API is unavailable, private, coming soon, or not exposed by official docs.

## Added Or Updated In This Pass

| Provider | SDK | Coverage | Source |
| --- | --- | --- | --- |
| Stability AI | `StabilityAI` | Updated the SDK generator to merge the legacy REST v1 spec with the official REST v2beta Stable Image API. Covers Stable Diffusion 3.5 Large/Turbo/Medium through `/v2beta/stable-image/generate/sd3`, plus current Stable Image Core/Ultra/edit/upscale/control endpoints. | Official v1 spec and official Stable Image OpenAPI at `https://api.stability.ai/v2alpha/openapi`. |
| ImagineArt | `ImagineArt` | Added a new SDK from a manual OpenAPI spec for `POST /image/generations`, transparent PNG generation, background removal, and image upscale. Covers ImagineArt 2.0 where the public API exposes it through the documented style-based generation endpoint. | Official [Text to Image API](https://reference.imagine.art/api-10672910), [Text to PNG API](https://reference.imagine.art/api-11959030), [Background Remover API](https://reference.imagine.art/api-10690786), and [Image Upscale API](https://reference.imagine.art/api-10695409). |
| Microsoft Foundry | `MicrosoftFoundry` | Added a new SDK from Microsoft Learn docs for `POST /mai/v1/images/generations`, covering deployed MAI-Image-2 and MAI-Image-2e models in Azure AI Foundry. | Official [Microsoft Foundry MAI image generation docs](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/use-foundry-models-mai). |

## Existing Direct SDK Coverage

| Leaderboard provider/models | SDK | Notes |
| --- | --- | --- |
| OpenAI GPT Image 2, GPT Image 1.5, GPT Image 1, GPT Image 1 Mini, DALL-E 3 | `OpenAI` | Existing `/images/generations` and `/images/edits` coverage. The generated request accepts arbitrary model strings, so `gpt-image-2` can be used even though the current official OpenAPI enum still lags the guide. |
| Google Nano Banana / Gemini image models and Imagen 3/4 | `Google.Gemini` | Existing Gemini generation SDK accepts model ids such as Gemini image models and Imagen model ids exposed by Google docs. Vertex-specific deployment/auth is still outside this SDK. |
| xAI grok-imagine-image and grok-imagine-image-pro | `Xai` | Existing image generation/edit endpoints cover Grok image models. |
| Black Forest Labs FLUX.2 and FLUX.1 Kontext | `BlackForestLabs` | Existing BFL SDK covers managed FLUX endpoints; open-weight/dev variants are also available through generic model-hosting SDKs. |
| Recraft V3/V4/V4 Pro and hosted external image models | `Recraft` | Existing SDK covers Recraft image generation/editing and currently includes many exact external model ids such as `gpt_image_2_high`, `flux2_max`, `imagen4_ultra`, `imagineart_2`, `qwen_image`, and Seedream variants. |
| ByteDance/BytePlus Seedream | `BytePlusModelArk` | Direct BytePlus ModelArk image generation endpoint; exact availability depends on region/account/model activation. |
| Alibaba Wan/Qwen image models | `DashScope` | Direct Alibaba Model Studio multimodal-generation coverage for Wan/Qwen image models where DashScope exposes them by model id. |
| KlingAI image generation | `KlingAI` | Existing image-generation endpoints cover the documented Kling image models in the local spec (`kling-v1`, `kling-v1-5`, `kling-v2`) and Kolors virtual try-on. Newer exact rows remain blocked below. |
| Leonardo Phoenix/Lucid image models | `Leonardo` | Existing image generation, platform model listing, realtime canvas, upscale, and variation endpoints. Exact model ids are provider-controlled. |
| Luma Photon / Photon Flash | `Luma` | Existing `/generations/image` coverage with `photon-1` and `photon-flash-1`. |
| Runway Gen-4 Image | `Runway` | Existing `CreateTextToImage` coverage for `gen4_image`. |
| Ideogram v2/v3 | `Ideogram` | Existing generate/edit/remix/upscale image coverage. |
| Eigen Image | `EigenAI` | Direct SDK from official EigenAI image generation docs. |
| Reve V1 | `Reve` | Direct SDK from official Reve SDK/docs. |
| Pruna P-Image / P-Image-Edit | `Pruna` | Existing generic prediction API covers Pruna hosted image models. |
| Z AI GLM-Image | `ZAI` | Existing image generation coverage for `glm-image` style rows. |
| Amazon Titan G1 v2 | `AwsBedrock` | Covered through generic Bedrock model invocation with the Amazon Titan image model id. |
| Krea-hosted image models | `Krea` | Existing Krea SDK covers many hosted image/video/enhancement endpoints, including Nano Banana, Seedream, OpenAI GPT Image, Qwen, FLUX/Kontext, and Z-Image variants where Krea exposes them. |

## Aggregator Or Open-Weight Coverage

| Models | SDKs | Notes |
| --- | --- | --- |
| FLUX.2 dev/dev turbo/dev flash/klein and FLUX.1 dev/schnell/Krea dev | `BlackForestLabs`, `Fal`, `Replicate`, `HuggingFace`, `Krea`, `Recraft` | Direct BFL covers managed endpoints; open-weight/dev variants are reachable through model platforms. |
| Tencent HunyuanImage / SRPO / HunyuanImage Instruct | `Fal`, `HuggingFace`, `Replicate`, `Recraft` | Open-weight/hosted model coverage; no separate Tencent direct image SDK was added. |
| HiDream, LongCat Image, OmniGen V2, Bagel, Lumina Image v2, NVIDIA Sana, DeepSeek Janus | `HuggingFace`, `Fal`, `Replicate` | Open-weight/hosted coverage through generic model platform SDKs. |
| Bria FIBO / Bria 3.2 | `HuggingFace`, `Fal`, `Replicate` | Open-weight/hosted coverage. No official direct Bria OpenAPI suitable for a provider SDK was found in this pass. |
| Playground v2.5 and other open-weight image rows | `HuggingFace`, `Fal`, `Replicate` | Covered as hosted/open-weight models, not as a direct Playground API. |
| Stability open-weight SDXL/SD 3.x variants | `StabilityAI`, `HuggingFace`, `Fal`, `Replicate` | Direct Stability REST covers hosted Stable Image/SD3.5 endpoints; open weights also remain available through model hosts. |

## Blocked Or Not Directly Added

| Provider/model | Status | Reason |
| --- | --- | --- |
| Adobe Firefly Image 4 / Firefly Image 5 Preview | Blocked exact direct model | Firefly APIs exist, and Adobe documents Image5 migration, but model selection is not exposed as the exact leaderboard model ids; the rows were marked no API/private/preview-style, so no direct SDK was added. |
| Midjourney v7 Alpha | Blocked | No official public API for the exact model. |
| API Airforce `image-1` | Blocked | No official provider OpenAPI/docs suitable for a direct SDK were found. |
| Microsoft MAI Image 1 | Blocked exact model | Microsoft Learn currently documents MAI-Image-2 and MAI-Image-2e in Foundry. No equivalent public MAI Image 1 API doc/spec was found. |
| MiniMax Image-01 | Blocked exact direct model | Existing `MiniMax` SDK is video/file oriented and the local official spec does not expose the Image-01 text-to-image API. |
| Vidu Q2 image row | Blocked direct model | Existing `Vidu` SDK is video-oriented; no official direct image-generation endpoint was found in the local Vidu spec. |
| Kling Kolors 2.1 / newer Kling Image rows | Blocked exact direct model | Existing `KlingAI` SDK has image endpoints, but the checked spec only lists older image model names. Need official updated Kling docs/spec before adding exact aliases. |
| Krea 1 | Blocked exact model | Existing Krea SDK covers public hosted generation APIs, but the exact `Krea 1` leaderboard model row is not exposed as a direct public API model in the checked docs/spec. |
| Reve Image Halfmoon | Blocked exact model | `Reve` SDK covers the current public image API; the Halfmoon row was listed as no API available. |
| HiDream Vivago 2.0/2.1 direct API | Blocked direct model | Hosted/open-weight alternatives exist, but no official direct HiDream/Vivago API spec was added. |
| Closed UI-only, preview-only, or coming-soon rows | Blocked | Public API docs/specs did not expose the exact leaderboard model, or the row explicitly indicated no API/coming soon. |

## Sources Used

- [OpenAI Images API reference](https://platform.openai.com/docs/api-reference/images/overview) and [OpenAI image generation guide](https://platform.openai.com/docs/guides/image-generation)
- [Google Gemini image generation docs](https://ai.google.dev/gemini-api/docs/image-generation) and [Imagen 4 on Vertex AI](https://cloud.google.com/vertex-ai/generative-ai/docs/models/imagen/4-0-ultra-generate-preview-06-06)
- [Microsoft Foundry MAI image generation docs](https://learn.microsoft.com/en-us/azure/foundry/foundry-models/how-to/use-foundry-models-mai)
- [ImagineArt Text to Image API](https://reference.imagine.art/api-10672910)
- [Stability AI Stable Image OpenAPI](https://api.stability.ai/v2alpha/openapi)
- [Black Forest Labs FLUX.2 docs](https://docs.bfl.ai/flux_2)
- [Recraft API docs](https://www.recraft.ai/docs/api-reference/getting-started)
- [Adobe Firefly API changelog](https://developer.adobe.com/firefly-services/docs/firefly-api/getting-started/changelog/) and [Image5 migration guide](https://developer.adobe.com/firefly-services/docs/firefly-api/guides/how-tos/cm-generate-image/breaking-changes)
- [BytePlus ModelArk image generation docs](https://docs.byteplus.com/en/docs/ModelArk/1824121)
- [Alibaba Wan image API](https://help.aliyun.com/zh/model-studio/wan-image-generation-api-reference) and [Qwen Image Edit API](https://help.aliyun.com/zh/model-studio/qwen-image-edit-api)
