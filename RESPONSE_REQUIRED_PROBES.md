# Live probes for response fields that are required *and* defaulted

The generated deserializers enforce `required`, so a response field the service omits turns a
successful HTTP 200 into a `JsonException`. A property that declares a `default` is the spec saying
the producer may omit it, which makes the pair a contradiction the service resolves in its own
favour.

Anthropic's spec marked `caller` that way on 52 response block schemas and the API never sends it,
so every response that used a server tool — web search, web fetch, code execution — failed to
deserialize. It went unnoticed because nothing exercised those surfaces against the real API.

A finding is a **candidate, not a defect**: plenty of services do send a field that has a default
(`UsageInfo.prompt_tokens`). Only a real response settles it, which is what this list is for. Every
SDK below already has live-key integration tests, so each row is a test to write, not plumbing to
build.

Regenerate this list with:

```bash
python3 scripts/audit_response_required_defaults.py --spec <spec> --endpoints
```

A probe is just a call plus an assertion that it deserialized — reaching the typed response at all
is the whole point, so asserting on one field of it is enough.

**Already settled.** Anthropic's own candidates were checked against the live API on 2026-11-10:
`citations`, `diagnostics`/`cache_miss_reason` and `container` all arrive, and `Message`'s
`stop_details` / `stop_sequence` arrive as JSON `null`, which satisfies `required`. Its rows stay
below only so the list stays complete. Shotstack has 11 candidates and none of them is named
directly by a response, so it has no direct probe.

### Read-only probes — safe to add as a test

| SDK | Key | Schema | Fields | Call |
|-----|-----|--------|--------|------|
| Anthropic | `ANTHROPIC_API_KEY` | `BetaModelInfo` | `lifecycle` | `GET /v1/models/{model_id}?beta=true` |
| Anthropic | `ANTHROPIC_API_KEY` | `BetaSelfHostedWorkQueueStats` | `pending` | `GET /v1/environments/{environment_id}/work/stats?beta=true` |
| Anthropic | `ANTHROPIC_API_KEY` | `ModelInfo` | `lifecycle` | `GET /v1/models/{model_id}` |
| E2B | `E2B_API_KEY` | `SandboxLogsV2Response` | `logs` | `GET /v2/sandboxes/{sandboxID}/logs` |
| E2B | `E2B_API_KEY` | `TemplateBuildInfo` | `logEntries, logs` | `GET /templates/{templateID}/builds/{buildID}/status` |
| E2B | `E2B_API_KEY` | `TemplateBuildLogsResponse` | `logs` | `GET /templates/{templateID}/builds/{buildID}/logs` |
| ElevenLabs | `ELEVENLABS_API_KEY` | `BatchCallDetailedResponse` | `retry_count, total_calls_dispatched, total_calls_finished, total_calls_scheduled` | `GET /v1/convai/batch-calling/{batch_id}` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetApiKeysV2Response` | `api_keys` | `GET /manage/api/organization/api_keys` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetApiOrganizationUserSuggestionsResponse` | `user_suggestions` | `GET /manage/api/organization/user_suggestions` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetApiProfilesResponse` | `profiles` | `GET /manage/api/profiles` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetDatasetResponse` | `custom_model_ids, files` | `GET /datasets/{dataset_id}` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetOrganizationMembersResponse` | `members` | `GET /manage/api/organization/members` |
| Ideogram | `IDEOGRAM_API_KEY` | `ListDatasetsResponse` | `datasets` | `GET /datasets` |
| Ideogram | `IDEOGRAM_API_KEY` | `ListModelsResponse` | `models` | `GET /models` |
| Ideogram | `IDEOGRAM_API_KEY` | `ListOrganizationInvoicesResponse` | `invoices` | `GET /manage/api/organization/list_invoices` |
| Julep | `JULEP_API_KEY` | `Agents.Agent` | `about, instructions, model` | `GET /agents` |
| Julep | `JULEP_API_KEY` | `Jobs.JobStatus` | `has_progress, name, progress, reason, state` | `GET /jobs/{id}` |
| Julep | `JULEP_API_KEY` | `Sessions.Session` | `auto_run_tools, context_overflow, forward_tool_calls, render_templates, situation, summary, token_budget` | `GET /sessions` |
| Julep | `JULEP_API_KEY` | `Tasks.Task` | `description, inherit_tools, input_schema, tools` | `GET /agents/{id}/tasks` |
| Julep | `JULEP_API_KEY` | `Users.User` | `about, name` | `GET /users` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `Annotation` | `created_ago, created_username` | `GET /api/annotations/{id}/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `LseUser` | `initials` | `GET /api/projects/{id}/members/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `LseUserAPI` | `initials` | `GET /api/current-user` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `ModelInterfaceSerializerGET` | `runs_count, versions_count` | `GET /api/prompts/{id}/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `Prediction` | `created_ago` | `GET /api/predictions/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `TaskSimple` | `annotations, predictions` | `GET /api/projects/{id}/tasks/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `WhoAmIUser` | `initials` | `GET /api/current-user/whoami` |
| Neon | `NEON_API_KEY` | `NeonAuthOAuthProviderConfig` | `enabled` | `GET /projects/{project_id}/branches/{branch_id}/auth/plugins/oauth-provider` |
| Neon | `NEON_API_KEY` | `NeonAuthPhoneNumberConfig` | `enabled` | `GET /projects/{project_id}/branches/{branch_id}/auth/plugins/phone-number` |

### Probes that create or change something — needs a throwaway resource or a cleanup step

| SDK | Key | Schema | Fields | Call |
|-----|-----|--------|--------|------|
| Anthropic | `ANTHROPIC_API_KEY` | `BetaMessage` | `container, context_management, diagnostics, stop_details, stop_sequence` | `POST /v1/messages?beta=true` |
| Anthropic | `ANTHROPIC_API_KEY` | `Message` | `container, diagnostics, stop_details, stop_sequence` | `POST /v1/messages` |
| ElevenLabs | `ELEVENLABS_API_KEY` | `BatchCallResponse` | `retry_count, total_calls_dispatched, total_calls_finished, total_calls_scheduled` | `POST /v1/convai/batch-calling/submit` |
| Julep | `JULEP_API_KEY` | `Chat.RenderResponse` | `docs` | `POST /sessions/{id}/render` |
| Julep | `JULEP_API_KEY` | `Common.ResourceDeletedResponse` | `jobs` | `DELETE /agents/{id}` |
| Julep | `JULEP_API_KEY` | `Docs.Doc` | `embeddings` | `POST /agents/{id}/docs` |
| Julep | `JULEP_API_KEY` | `Files.File` | `description, mime_type` | `POST /files` |
| Julep | `JULEP_API_KEY` | `Responses.Response` | `parallel_tool_calls, temperature, top_p` | `POST /responses` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `LseInterface` | `projects_count` | `POST /api/interfaces/` |
| Neon | `NEON_API_KEY` | `NeonAuthMagicLinkConfig` | `disable_sign_up, enabled, expires_in` | `PATCH /projects/{project_id}/branches/{branch_id}/auth/plugins/magic-link` |
| Neon | `NEON_API_KEY` | `NeonAuthOrganizationConfig` | `creator_role, enabled, membership_limit, organization_limit, send_invitation_email` | `PATCH /projects/{project_id}/branches/{branch_id}/auth/plugins/organization` |
| OpenAI | `OPENAI_API_KEY` | `AssistantObject` | `tools` | `POST /assistants` |
| OpenAI | `OPENAI_API_KEY` | `AutomationInvocationResource` | `skip_reason` | `POST /agents/automations/{automation_id}/invocations` |
| OpenAI | `OPENAI_API_KEY` | `RunObject` | `tools` | `POST /threads/runs` |
| Portkey | `PORTKEY_API_KEY` | `AssistantObject` | `tools` | `POST /assistants` |
| Portkey | `PORTKEY_API_KEY` | `RunObject` | `tools` | `POST /threads/runs` |
| Together | `TOGETHER_API_KEY` | `DE.Endpoint` | `visibility` | `POST /v2/projects/{projectId}/endpoints` |
| Together | `TOGETHER_API_KEY` | `DE.Model` | `visibility` | `POST /v2/projects/{projectId}/models` |
| Together | `TOGETHER_API_KEY` | `RL.TrainingSession` | `step` | `POST /v1/rl/training-sessions` |
| Vectara | `VECTARA_API_KEY` | `Agent` | `enabled` | `POST /v2/agents` |
| Vectara | `VECTARA_API_KEY` | `AgentConnector` | `enabled` | `POST /v2/agent_aliases/{alias_key}/connectors` |
| Vectara | `VECTARA_API_KEY` | `AgentSchedule` | `enabled` | `POST /v2/agents/{agent_key}/schedules` |
| Vectara | `VECTARA_API_KEY` | `AgentSession` | `enabled` | `POST /v2/agents/{agent_key}/sessions` |
| Vectara | `VECTARA_API_KEY` | `EndUserSession` | `enabled` | `POST /v2/agent_aliases/{alias_key}/end_user_sessions` |
| Vectara | `VECTARA_API_KEY` | `Pipeline` | `enabled` | `POST /v2/pipelines` |
| Vectara | `VECTARA_API_KEY` | `PipelineRun` | `records_failed, records_fetched, records_processed, records_skipped` | `POST /v2/pipelines/{pipeline_key}/trigger` |
| Vectara | `VECTARA_API_KEY` | `ToolServer` | `enabled, transport` | `POST /v2/tool_servers` |
| Vectara | `VECTARA_API_KEY` | `TrustedTokenIssuer` | `enabled` | `POST /v2/trusted_token_issuers` |
| Weave | `WEAVE_API_KEY` | `AgentConversationChatRes` | `has_more, limit, offset, total_turns` | `POST /agents/conversations/chat` |
| Weave | `WEAVE_API_KEY` | `AgentCustomAttrsSchemaRes` | `has_more, limit, offset` | `POST /agents/spans/custom-attrs/schema` |
| Weave | `WEAVE_API_KEY` | `AgentSearchRes` | `total_conversations` | `POST /agents/search` |
| Weave | `WEAVE_API_KEY` | `AgentSpanStatsRes` | `bucket_type` | `POST /agents/spans/stats` |
| Weave | `WEAVE_API_KEY` | `AgentSpansQueryRes` | `total_count` | `POST /agents/spans/query` |
| Weave | `WEAVE_API_KEY` | `AgentTraceChatRes` | `total_cache_creation_input_tokens, total_cache_read_input_tokens, total_input_tokens, total_output_tokens, total_reasoning_tokens` | `POST /agents/traces/chat` |
| Weave | `WEAVE_API_KEY` | `AgentVersionsQueryRes` | `total_count` | `POST /agents/agent-versions/query` |
| Weave | `WEAVE_API_KEY` | `AgentsQueryRes` | `total_count` | `POST /agents/query` |

### Reached only through another schema (143)

These have no response that names them directly, so a probe has to go through a parent schema.
Worth covering only once the direct ones are done.

- **Anthropic**: 74 schemas, e.g. `APIError`
- **E2B**: 1 schema, e.g. `TeamUser`
- **ElevenLabs**: 10 schemas, e.g. `AgentWorkflowResponseModel`
- **Ideogram**: 2 schemas, e.g. `ApiProfile`
- **Julep**: 18 schemas, e.g. `Chat.BaseChatOutput`
- **LabelStudio**: 4 schemas, e.g. `LseInterfaceList`
- **OpenAI**: 1 schema, e.g. `CompletionUsage`
- **Portkey**: 6 schemas, e.g. `ContainsParameters`
- **Shotstack**: 11 schemas, e.g. `AkamaiNetStorageDestination`
- **Together**: 2 schemas, e.g. `CosineLRSchedulerArgs`
- **Vectara**: 5 schemas, e.g. `AgentStep`
- **Weave**: 9 schemas, e.g. `AgentConversationMessagePreview`
