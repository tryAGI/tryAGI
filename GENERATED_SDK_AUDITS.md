# Generated SDK Audits

Use [`scripts/audit-generated-sdks.sh`](scripts/audit-generated-sdks.sh) from the workspace root to get a repeatable snapshot of generated SDK health across the `tryAGI` organization.

Tracked defaults live in [`config/generated-sdk-audit.json`](config/generated-sdk-audit.json). Prefer changing that file when you want to extend the workspace-wide audit policy.

## What it checks

- Generated SDK repo detection by scanning local repos for `src/libs/*/generate.sh`
- GitHub repo settings required for bot PR auto-merge:
  - `allow_auto_merge`
  - `delete_branch_on_merge`
  - `allow_update_branch`
- Latest GitHub Actions runs for:
  - `.github/workflows/auto-update.yml`
  - `.github/workflows/dotnet.yml`
- Open issues for generated SDK repos
- Heuristic warning signals from the latest completed publish runs:
  - warning lines
  - skipped tests
  - inconclusive-test markers
- Optional local validation for generated SDKs:
  - `dotnet build -c Release`
  - `autosdk trim` for NativeAOT/trimming compatibility
- A machine-readable summary rollup in `generated-sdk-summary.tsv`
- A daily text briefing

## Commands

```bash
# Full summary plus TSV outputs in /tmp/tryagi-sdk-audit
./scripts/audit-generated-sdks.sh summary

# Only repo settings
./scripts/audit-generated-sdks.sh settings

# Only latest workflow runs
./scripts/audit-generated-sdks.sh workflows

# Open issues across generated SDK repos
./scripts/audit-generated-sdks.sh issues

# Warning / skipped-test signals from the latest completed Publish runs
./scripts/audit-generated-sdks.sh signals

# Local Release builds across generated SDK repos
./scripts/audit-generated-sdks.sh local-builds

# Local autosdk trim checks across generated SDK projects
./scripts/audit-generated-sdks.sh local-trims

# All reports plus daily text briefing
./scripts/audit-generated-sdks.sh briefing

# Optional: suppress skipped/inconclusive noise from known noisy repos in summaries
TRYAGI_SIGNAL_SKIP_IGNORE_REGEX='^(OpenAI)$' ./scripts/audit-generated-sdks.sh briefing

# Optional: use a different config file for experiments
./scripts/audit-generated-sdks.sh --config /tmp/generated-sdk-audit.json briefing

# Limit to a subset of repos
./scripts/audit-generated-sdks.sh --repo '^(OpenAI|Anthropic|Cohere)$' summary
```

## Outputs

- `generated-sdk-settings.tsv`
  - One row per detected generated SDK repo
  - `true/false` flags for the three auto-merge related settings
  - `autosdk_bootstrap_status` reports whether every `src/libs/*/generate.sh` script bootstraps `autosdk.cli`
  - `autosdk_bootstrap_details` lists any generate scripts that are missing the bootstrap step
- `generated-sdk-workflows.tsv`
  - Two rows per repo: `auto-update` and `publish`
  - Includes latest run id, conclusion, timestamp, branch, URL, plus `repo_created_at` and `repo_age_days`
  - `repo_created_at` and `repo_age_days` are populated for `new-repo-no-runs` and mature `no-runs` rows to explain the classification
  - `new-repo-no-runs` marks a new repo that still needs its first workflow run during onboarding
- `generated-sdk-open-issues.tsv`
  - One row per open issue
  - Includes repo, issue number, title, labels, and URL
- `generated-sdk-log-signals.tsv`
  - One row per repo for the latest completed `Publish` run
  - Includes raw warning-line counts, skipped-test counts, and inconclusive-test hits
- `generated-sdk-local-builds.tsv`
  - One row per detected generated SDK repo
  - Includes solution path, status, exit code, duration, and the local build log path
- `generated-sdk-local-trims.tsv`
  - One row per detected generated SDK project
  - Includes project path, status, exit code, duration, and the local trim log path
- `generated-sdk-summary.tsv`
  - One summary row that rolls up the latest counts currently available in the output directory
  - Refreshes on every mode, so separate `settings`, `workflows`, `issues`, `signals`, `local-builds`, and `local-trims` runs converge into one machine-readable status snapshot
  - Includes aggregate counts plus the source report paths that produced them
- `daily-briefing.txt`
  - Short human-readable daily summary
By default both files are written to `/tmp/tryagi-sdk-audit/`. Override that path with `--out-dir`.

Environment knobs:
- `CODEX_HOME`
  - If unset, the script exports `$HOME/.codex` before loading env files so automation shells can resolve Codex-relative paths consistently
- `TRYAGI_AUDIT_CONFIG_PATH`
  - Override the config file path. Default: `config/generated-sdk-audit.json`
- `TRYAGI_AUDIT_ENV_FILE`
  - Source an env file before the audit runs; values from that file now apply to the script's `TRYAGI_*` settings as well as downstream tools such as `gh`
- `TRYAGI_AUTO_UPDATE_WORKFLOW_FILE`
  - Override the auto-update workflow filename without editing the tracked config
- `TRYAGI_PUBLISH_WORKFLOW_FILE`
  - Override the publish workflow filename without editing the tracked config
- `TRYAGI_NEW_REPO_DAYS`
  - Repo age threshold for classifying `new-repo-no-runs` onboarding gaps instead of mature `no-runs`
- `TRYAGI_SIGNAL_RUN_LIMIT`
  - How many recent `Publish` runs are searched to find the latest completed run for log inspection
- `TRYAGI_SIGNAL_SKIP_IGNORE_REGEX`
  - Regex for repos whose skipped/inconclusive test counts should be ignored in summaries and briefings
  - Raw counts remain in `generated-sdk-log-signals.tsv`

## Config File

The tracked config file currently controls:

- `issue_limit`
- `workflows.auto_update_file`
- `workflows.publish_file`
- `workflows.new_repo_days`
- `signals.run_limit`
- `signals.ignored_skip_signal_repos`

Add new keys there when the audit grows. The script treats the config as the default policy layer, and environment variables or `--config` are the escape hatches for temporary overrides.

## How to read failures

- `allow_auto_merge=false`
  - Bot PRs cannot be queued for auto-merge
- `delete_branch_on_merge=false`
  - Bot branches will accumulate after merges
- `allow_update_branch=false`
  - GitHub will not offer the standard branch update flow on PRs
- `missing-bootstrap`
  - A repo has at least one `src/libs/*/generate.sh` script without a `dotnet tool install/update --global autosdk.cli` bootstrap step, so scheduled regeneration may fail on a clean GitHub Actions runner
- `auto-update` latest run failed
  - Usually spec download drift, generator breakage, or transient upstream/network issues
- `publish` latest run failed
  - Usually build/test regressions, package id collisions, or NuGet credential/package ownership issues
- `api-error` in workflow or signal reports
  - GitHub API lookup failed, often because of rate limits or a transient GitHub-side error
- `new-repo-no-runs`
  - Workflow file exists, but the repository is still within the onboarding age window and has not recorded its first run yet; see `repo_created_at` and `repo_age_days` in the workflow TSV
- `no-runs`
  - Workflow file exists, but a mature repository still has no recorded runs and needs attention; see `repo_created_at` and `repo_age_days` in the workflow TSV
- Non-zero `warning_lines`
  - The latest publish run emitted warning lines worth checking
- Non-zero `skipped_tests`
  - The latest completed publish run skipped tests; often expected for credential-gated tests, but still worth tracking
- Non-zero `inconclusive_hits`
  - The latest completed publish run contains inconclusive-test markers or skipped-by-design test paths
- `local-builds` failure
  - The SDK does not build locally in Release configuration; inspect the referenced log under `/tmp/tryagi-sdk-audit/local-build-logs/`
- `local-trims` failure
  - The SDK is not currently NativeAOT/trimming compatible under `autosdk trim`; inspect the referenced log under `/tmp/tryagi-sdk-audit/local-trim-logs/`

## Follow-up workflow

1. Run `./scripts/audit-generated-sdks.sh summary`.
2. Run `./scripts/audit-generated-sdks.sh briefing` when you want the full daily text pass.
3. Run `./scripts/audit-generated-sdks.sh local-trims` when checking NativeAOT/trimming health.
4. Open the failing repo locally.
5. Fix the repo or org setting.
6. Commit and push on `main`.
7. Check any triggered GitHub Actions workflows and wait for them to finish successfully.
