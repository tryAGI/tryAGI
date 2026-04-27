# 3D AI API Coverage

Coverage audit for the 3D AI generation tools requested on 2026-04-27.

The goal is to have a typed SDK wherever a stable public API contract can be
identified. For providers with public endpoint documentation but no downloadable
OpenAPI document, the SDK uses a manually maintained `openapi.yaml`. Providers
without endpoint/auth/request/response documentation are tracked here but were
not reverse engineered from private web-app traffic.

| Listed provider | Coverage | Notes |
|-----------------|----------|-------|
| Tripo AI | `Tripo/` | Existing direct SDK. |
| Hitem3D (Sparc3D) | `Hitem3D/` | New direct SDK from public API docs and manual OpenAPI. |
| Hyper3D (Rodin) | `Hyper3D/` | New direct SDK from Rodin API docs and manual OpenAPI. |
| VARCO 3D (NC AI / NCSoft) | Blocked | Public reference page exists, but endpoint/auth/body schemas were not accessible enough for a typed SDK. |
| Prism (3D AI Studio) | `ThreeDAIStudio/` | New direct SDK for 3D AI Studio REST API. |
| Hunyuan 3D | `ThreeDAIStudio/`, `Fal/`, `Replicate/`, `HuggingFace/`, `WaveSpeedAI/` | Covered through hosted APIs rather than a direct Tencent SaaS API. |
| YVO3D | Blocked | No stable public endpoint-level API documentation found. |
| Lychee | Blocked | No stable public endpoint-level API documentation found. |
| Neural4D (DreamTech) | `Neural4D/` | New direct SDK from public API page/PDF and manual OpenAPI. |
| TRELLIS (Microsoft) | `ThreeDAIStudio/`, `Fal/`, `Replicate/`, `HuggingFace/` | Covered through hosted APIs for the open model. |
| Hunyuan 3D v2.1 (Comfy) | `ThreeDAIStudio/`, `Fal/`, `Replicate/`, `HuggingFace/`, `WaveSpeedAI/` | Covered through hosted APIs; ComfyUI itself is not a first-party SaaS API. |
| ByteDance Seed3D | `DoubaoSeed3D/` | New direct SDK for the Volcano Ark task API surface used by Doubao Seed3D. |
| Meshy AI | `Meshy/` | Existing direct SDK. |
| SAM 3D (Meta) | `Runware/`, `Fal/`, `Replicate/`, `HuggingFace/` | New Runware SDK covers Meta SAM 3D Objects; generic hosted model SDKs also apply. |
| Common Sense Machines (CSM) | `CsmAi/` | Existing direct SDK. |
| Sloyd.ai | `Sloyd/` | New SDK for the documented legacy API; Sloyd currently says new API clients are paused. |
| Spline AI | Blocked | No stable public endpoint-level API documentation found for Spline AI generation. |
| Autodesk | Blocked | No public Autodesk AI 3D generation endpoint contract found for this specific listed tool. |
| Alpha3D | Blocked | Public API marketing page exists, but no stable endpoint/auth/body schemas were available without relying on private web-app internals. |
| Triverse AI | `Triverse/` | New direct SDK from public API docs and manual OpenAPI. |

## Source References

- Hitem3D API docs: <https://docs.hitem3d.ai/en/api/api-reference/overview>
- Hyper3D Rodin API docs: <https://developer.hyper3d.ai/api-specification/overview>
- Triverse API docs: <https://docs.triverse.ai/>
- 3D AI Studio API docs: <https://www.3daistudio.com/Platform/API/Documentation/overview>
- Neural4D API page: <https://www.neural4d.com/api>
- Neural4D API PDF: <https://blog.neural4d.com/wp-content/uploads/2026/01/Neural4D-API-Documentation.pdf>
- Runware authentication docs: <https://runware.ai/docs/platform/authentication>
- Runware SAM 3D Objects docs: <https://runware.ai/docs/models/meta-sam-3d-objects>
- Sloyd API docs: <https://sloyd.gitbook.io/documentation/other-products/deprecated-products/api>
- ByteDance Seed3D release post: <https://seed.bytedance.com/en/blog/seed3d-2-0-released-higher-precision-and-greater-usability>
- Doubao Seed3D task API example in SketchKit: <https://cislab.hkust-gz.edu.cn/projects/sketchkit/docs/_modules/sketchkit/sketch2model/methods/doubao.html>
- Meshy API docs: <https://docs.meshy.ai/en/api/image-to-3d>
- fal 3D model API docs: <https://fal.ai/docs/model-api-reference/3d-api/overview>
- VARCO API reference shell: <https://api.varco.ai/en/reference/3d-image-to-3d>
- Alpha3D API page: <https://www.alpha3d.io/docs>
