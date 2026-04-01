# Generated SDK Audits

Use [`scripts/audit-generated-sdks.sh`](scripts/audit-generated-sdks.sh) from the workspace root to get a repeatable snapshot of generated SDK health across the `tryAGI` organization.

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

# All reports plus daily text briefing
./scripts/audit-generated-sdks.sh briefing

# Optional: suppress skipped/inconclusive noise from known noisy repos in summaries
TRYAGI_SIGNAL_SKIP_IGNORE_REGEX='^(OpenAI)$' ./scripts/audit-generated-sdks.sh briefing

# Limit to a subset of repos
./scripts/audit-generated-sdks.sh --repo '^(OpenAI|Anthropic|Cohere)$' summary
```

## Outputs

- `generated-sdk-settings.tsv`
  - One row per detected generated SDK repo
  - `true/false` flags for the three auto-merge related settings
- `generated-sdk-workflows.tsv`
  - Two rows per repo: `auto-update` and `publish`
  - Includes latest run id, conclusion, timestamp, branch, and URL
- `generated-sdk-open-issues.tsv`
  - One row per open issue
  - Includes repo, issue number, title, labels, and URL
- `generated-sdk-log-signals.tsv`
  - One row per repo for the latest completed `Publish` run
  - Includes raw warning-line counts, skipped-test counts, and inconclusive-test hits
- `daily-briefing.txt`
  - Short human-readable daily summary
By default both files are written to `/tmp/tryagi-sdk-audit/`. Override that path with `--out-dir`.

Environment knobs:
- `TRYAGI_SIGNAL_RUN_LIMIT`
  - How many recent `Publish` runs are searched to find the latest completed run for log inspection
- `TRYAGI_SIGNAL_SKIP_IGNORE_REGEX`
  - Regex for repos whose skipped/inconclusive test counts should be ignored in summaries and briefings
  - Raw counts remain in `generated-sdk-log-signals.tsv`

## How to read failures

- `allow_auto_merge=false`
  - Bot PRs cannot be queued for auto-merge
- `delete_branch_on_merge=false`
  - Bot branches will accumulate after merges
- `allow_update_branch=false`
  - GitHub will not offer the standard branch update flow on PRs
- `auto-update` latest run failed
  - Usually spec download drift, generator breakage, or transient upstream/network issues
- `publish` latest run failed
  - Usually build/test regressions, package id collisions, or NuGet credential/package ownership issues
- `api-error` in workflow or signal reports
  - GitHub API lookup failed, often because of rate limits or a transient GitHub-side error
- Non-zero `warning_lines`
  - The latest publish run emitted warning lines worth checking
- Non-zero `skipped_tests`
  - The latest completed publish run skipped tests; often expected for credential-gated tests, but still worth tracking
- Non-zero `inconclusive_hits`
  - The latest completed publish run contains inconclusive-test markers or skipped-by-design test paths

## Follow-up workflow

1. Run `./scripts/audit-generated-sdks.sh summary`.
2. Run `./scripts/audit-generated-sdks.sh briefing` when you want the full daily text pass.
3. Open the failing repo locally.
4. Fix the repo or org setting.
5. Commit and push on `main`.
6. Check any triggered GitHub Actions workflows and wait for them to finish successfully.
