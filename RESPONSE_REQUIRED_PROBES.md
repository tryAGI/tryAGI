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

**What live traffic found that the audit could not.** Running these probes against a real Label
Studio container turned up two defects in `POST /api/projects/` - a core operation that could not
deserialize its own HTTP 201. Neither was in the candidate list: `UserSimple.username` is required
with **no default**, and `LseProjectCreate`'s counters are non-nullable integers the API sends as
null. So `required` + `default` is one slice of the defect, not the whole of it - the general shape
is "the spec demands something the service does not send", and only live traffic finds the rest.
Both are fixed in that SDK's `generate.sh`, and `autosdk generate --relax-response-required All`
now exists for the case where listing such fields is not worth it.

## The other half: names the spec spells differently from the server

A required field the server omits is one way a response fails. The other is a field whose *name* the
spec gets wrong — the generated model looks for a key that never arrives, and when the field is
required, deserializing a successful HTTP 200 throws. Milvus's `POST /v2/vectordb/roles/describe`
was unusable that way: the spec said `object_type`, `object_name`, `db_name`; the server sends
`objectType`, `objectName`, `dbName`.

`scripts/audit_property_casing.py` finds the static tell — a schema whose property names break the
casing convention its own document otherwise follows:

```bash
python3 scripts/audit_property_casing.py                    # whole workspace
python3 scripts/audit_property_casing.py --spec <spec>       # one spec
```

45 of 224 specs have at least one such schema. **That is not 45 defects.** The common innocent cause
is a schema mirroring a foreign protocol, where the deviation is correct: MCP is camelCase
(`MCPTool`, `ToolAnnotations` in Mistral, Letta, RetellAI, ElevenLabs), so is A2A (31 schemas in
Vectara) and OTLP (PromptLayer). Those are right as they stand.

The hits worth a probe are deviations with no protocol behind them, especially in error and status
wrappers — the shape nobody exercises, which is exactly where the Milvus bug lived:

| SDK | Schema | Deviating field |
|-----|--------|-----------------|
| Gladia | six `*ErrorResponse` schemas | `statusCode` |
| CsmAi | four envelopes | `statusCode` |
| E2B | `Error` | `error_code` (in a camelCase spec) |
| Polar | `error` | `corrId`, `errorType` |
| Algolia | `baseSearchResponse` | `facets_stats` |
| NariLabs | `ErrorResponseError` | `requestId` |

## Does `All` belong on the container-backed SDKs?

Measured 2026-11-10, per spec: how many response fields the spec actually enforces (`required`
minus discriminators), against how much of the surface the live tests touch.

| SDK | Enforced required response fields | Live tests | Operations | Verdict |
|-----|-----------------------------------|-----------|------------|---------|
| Qdrant | 257 | 4 | 72 | the one real exposure — most to enforce, least evidence |
| Chroma | 70 | 17 | 34 | half the surface covered live and clean |
| Ollama | 30 | 24 | 22 | covered live and clean |
| Milvus | 21 | 4 | 50 | little to enforce |
| Weaviate | 0 | 4 | 60 | `All` would do nothing at all |

None of the five has a single `required`-with-`default` candidate, so `Defaulted` has nothing to do
there either. `All` would be prophylactic: there is no observed failure on any of them, and it
trades the contract for resilience sight unseen. The cheaper move is more live coverage, which costs
nothing here — Qdrant enforces 257 response fields behind four tests, and its container needs no
key.

**Container-backed SDKs need no key at all.** Chroma, Qdrant, Weaviate, Milvus and Ollama all spin
up a real service through Testcontainers, so their responses can be settled with Docker alone. Run
on 2026-11-10: Chroma 17/17, Qdrant 4/4, Weaviate 4/4, Milvus 4/4 — 29 live tests, no failures and
no new defects. Ollama was skipped: its container pulls a model, which costs gigabytes rather than
seconds.

**Done:** all six bare probes — three in Ideogram (`GetApiProfilesResponse`, `ListDatasetsResponse`,
`ListModelsResponse`) and three in LabelStudio (`LseUserAPI`, `WhoAmIUser`, `Prediction`). They
compile and skip without a key; nobody has run them against the real services yet. Six is the whole
set: every other candidate either needs an id or creates something, which is why counting rows
without reading the operations overstates how much is one call away.

## Cleanup pattern for probes that create something

A third of the calls below create or change a resource, and a probe that leaves one behind turns
into litter in a real account - across a whole SDK's test run, that is the difference between a
probe and a liability. There is no test library shared between these repositories, so this is a
pattern to copy rather than a package to reference. The shape that matters is the `finally`: it must
run even when the assertion fails, and it must not mask the original failure.

```csharp
[TestMethod]
public async Task AgentResponseDeserializes()
{
    var client = GetAuthenticatedClient();

    // Name it so a leaked resource is obviously a test's, and unique so parallel runs don't collide.
    var created = await client.Agents.CreateAsync(new CreateAgentRequest
    {
        Name = $"tryagi-probe-{Guid.NewGuid():N}",
    });

    try
    {
        created.Should().NotBeNull();
    }
    finally
    {
        // Swallow only the cleanup's own failure: the test's verdict is the assertion above.
        try
        {
            await client.Agents.DeleteAsync(created.Id);
        }
        catch (ApiException)
        {
        }
    }
}
```

Two things this does not solve. A resource that cannot be deleted - a dispatched batch call, a
training session - should not be probed this way at all; cover it by reading an existing one
instead. And a run that is killed between create and `finally` still leaks, so a service you probe
often deserves a prefix (`tryagi-probe-`) that a periodic sweep can recognise.

### Bare read-only probes (6) — a call and an assertion, nothing else

✅ marks the ones already written.

| SDK | Key | Schema | Fields | Call |
|-----|-----|--------|--------|------|
| Ideogram | `IDEOGRAM_API_KEY` | `GetApiProfilesResponse` ✅ | `profiles` | `GET /manage/api/profiles` |
| Ideogram | `IDEOGRAM_API_KEY` | `ListDatasetsResponse` ✅ | `datasets` | `GET /datasets` |
| Ideogram | `IDEOGRAM_API_KEY` | `ListModelsResponse` ✅ | `models` | `GET /models` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `LseUserAPI` ✅ | `initials` | `GET /api/current-user` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `Prediction` ✅ | `created_ago` | `GET /api/predictions/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `WhoAmIUser` ✅ | `initials` | `GET /api/current-user/whoami` |

### Calls that need an id (32) — a fixture first

| SDK | Key | Schema | Fields | Call |
|-----|-----|--------|--------|------|
| Anthropic | `ANTHROPIC_API_KEY` | `BetaModelInfo` | `lifecycle` | `GET /v1/models/{model_id}?beta=true (needs model_id)` |
| Anthropic | `ANTHROPIC_API_KEY` | `BetaSelfHostedWorkQueueStats` | `pending` | `GET /v1/environments/{environment_id}/work/stats?beta=true (needs environment_id)` |
| Anthropic | `ANTHROPIC_API_KEY` | `ModelInfo` | `lifecycle` | `GET /v1/models/{model_id} (needs model_id)` |
| E2B | `E2B_API_KEY` | `SandboxLogsV2Response` | `logs` | `GET /v2/sandboxes/{sandboxID}/logs (needs sandboxID)` |
| E2B | `E2B_API_KEY` | `TemplateBuildInfo` | `logEntries, logs` | `GET /templates/{templateID}/builds/{buildID}/status (needs buildID, templateID)` |
| E2B | `E2B_API_KEY` | `TemplateBuildLogsResponse` | `logs` | `GET /templates/{templateID}/builds/{buildID}/logs (needs buildID, templateID)` |
| ElevenLabs | `ELEVENLABS_API_KEY` | `BatchCallDetailedResponse` | `retry_count, total_calls_dispatched, total_calls_finished, total_calls_scheduled` | `GET /v1/convai/batch-calling/{batch_id} (needs batch_id)` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetApiKeysV2Response` | `api_keys` | `GET /manage/api/organization/api_keys (needs organization_id)` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetApiOrganizationUserSuggestionsResponse` | `user_suggestions` | `GET /manage/api/organization/user_suggestions (needs organization_id)` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetDatasetResponse` | `custom_model_ids, files` | `GET /datasets/{dataset_id} (needs dataset_id)` |
| Ideogram | `IDEOGRAM_API_KEY` | `GetOrganizationMembersResponse` | `members` | `GET /manage/api/organization/members (needs organization_id)` |
| Ideogram | `IDEOGRAM_API_KEY` | `ListOrganizationInvoicesResponse` | `invoices` | `GET /manage/api/organization/list_invoices (needs organization_id)` |
| Julep | `JULEP_API_KEY` | `Chat.RenderResponse` | `docs` | `POST /sessions/{id}/render (needs id)` |
| Julep | `JULEP_API_KEY` | `Common.ResourceDeletedResponse` | `jobs` | `DELETE /agents/{id} (needs id)` |
| Julep | `JULEP_API_KEY` | `Docs.Doc` | `embeddings` | `POST /agents/{id}/docs (needs id)` |
| Julep | `JULEP_API_KEY` | `Jobs.JobStatus` | `has_progress, name, progress, reason, state` | `GET /jobs/{id} (needs id)` |
| Julep | `JULEP_API_KEY` | `Tasks.Task` | `description, inherit_tools, input_schema, tools` | `GET /agents/{id}/tasks (needs direction, id, limit, metadata_filter, offset, sort_by)` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `Annotation` | `created_ago, created_username` | `GET /api/annotations/{id}/ (needs id)` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `ModelInterfaceSerializerGET` | `runs_count, versions_count` | `GET /api/prompts/{id}/ (needs id)` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `TaskSimple` | `annotations, predictions` | `GET /api/projects/{id}/tasks/ (needs id)` |
| Neon | `NEON_API_KEY` | `NeonAuthMagicLinkConfig` | `disable_sign_up, enabled, expires_in` | `PATCH /projects/{project_id}/branches/{branch_id}/auth/plugins/magic-link (needs branch_id, project_id)` |
| Neon | `NEON_API_KEY` | `NeonAuthOAuthProviderConfig` | `enabled` | `GET /projects/{project_id}/branches/{branch_id}/auth/plugins/oauth-provider (needs branch_id, project_id)` |
| Neon | `NEON_API_KEY` | `NeonAuthOrganizationConfig` | `creator_role, enabled, membership_limit, organization_limit, send_invitation_email` | `PATCH /projects/{project_id}/branches/{branch_id}/auth/plugins/organization (needs branch_id, project_id)` |
| Neon | `NEON_API_KEY` | `NeonAuthPhoneNumberConfig` | `enabled` | `GET /projects/{project_id}/branches/{branch_id}/auth/plugins/phone-number (needs branch_id, project_id)` |
| OpenAI | `OPENAI_API_KEY` | `AutomationInvocationResource` | `skip_reason` | `POST /agents/automations/{automation_id}/invocations (needs automation_id)` |
| Together | `TOGETHER_API_KEY` | `DE.Endpoint` | `visibility` | `POST /v2/projects/{projectId}/endpoints (needs projectId)` |
| Together | `TOGETHER_API_KEY` | `DE.Model` | `visibility` | `POST /v2/projects/{projectId}/models (needs projectId)` |
| Vectara | `VECTARA_API_KEY` | `AgentConnector` | `enabled` | `POST /v2/agent_aliases/{alias_key}/connectors (needs alias_key)` |
| Vectara | `VECTARA_API_KEY` | `AgentSchedule` | `enabled` | `POST /v2/agents/{agent_key}/schedules (needs agent_key)` |
| Vectara | `VECTARA_API_KEY` | `AgentSession` | `enabled` | `POST /v2/agents/{agent_key}/sessions (needs agent_key)` |
| Vectara | `VECTARA_API_KEY` | `EndUserSession` | `enabled` | `POST /v2/agent_aliases/{alias_key}/end_user_sessions (needs alias_key)` |
| Vectara | `VECTARA_API_KEY` | `PipelineRun` | `records_failed, records_fetched, records_processed, records_skipped` | `POST /v2/pipelines/{pipeline_key}/trigger (needs pipeline_key)` |

### Calls that create or change something (27) — use the cleanup pattern above

| SDK | Key | Schema | Fields | Call |
|-----|-----|--------|--------|------|
| Anthropic | `ANTHROPIC_API_KEY` | `BetaMessage` | `container, context_management, diagnostics, stop_details, stop_sequence` | `POST /v1/messages?beta=true` |
| Anthropic | `ANTHROPIC_API_KEY` | `Message` | `container, diagnostics, stop_details, stop_sequence` | `POST /v1/messages` |
| ElevenLabs | `ELEVENLABS_API_KEY` | `BatchCallResponse` | `retry_count, total_calls_dispatched, total_calls_finished, total_calls_scheduled` | `POST /v1/convai/batch-calling/submit` |
| Julep | `JULEP_API_KEY` | `Agents.Agent` | `about, instructions, model` | `POST /agents` |
| Julep | `JULEP_API_KEY` | `Files.File` | `description, mime_type` | `POST /files` |
| Julep | `JULEP_API_KEY` | `Responses.Response` | `parallel_tool_calls, temperature, top_p` | `POST /responses` |
| Julep | `JULEP_API_KEY` | `Sessions.Session` | `auto_run_tools, context_overflow, forward_tool_calls, render_templates, situation, summary, token_budget` | `POST /sessions` |
| Julep | `JULEP_API_KEY` | `Users.User` | `about, name` | `POST /users` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `LseInterface` | `projects_count` | `POST /api/interfaces/` |
| LabelStudio | `LABEL_STUDIO_API_KEY` | `LseUser` | `initials` | `POST /api/users/` |
| OpenAI | `OPENAI_API_KEY` | `AssistantObject` | `tools` | `POST /assistants` |
| OpenAI | `OPENAI_API_KEY` | `RunObject` | `tools` | `POST /threads/runs` |
| Portkey | `PORTKEY_API_KEY` | `AssistantObject` | `tools` | `POST /assistants` |
| Portkey | `PORTKEY_API_KEY` | `RunObject` | `tools` | `POST /threads/runs` |
| Together | `TOGETHER_API_KEY` | `RL.TrainingSession` | `step` | `POST /v1/rl/training-sessions` |
| Vectara | `VECTARA_API_KEY` | `Agent` | `enabled` | `POST /v2/agents` |
| Vectara | `VECTARA_API_KEY` | `Pipeline` | `enabled` | `POST /v2/pipelines` |
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

No response names these directly, so a probe has to go through a parent schema. Worth covering
last.

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
