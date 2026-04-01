# tryAGI Workspace

This repository tracks the workspace-level operational files for the `tryAGI` organization.

It does **not** manage the individual SDK repositories inside this folder. Each SDK remains an independent git repository in its own subdirectory, and the root workspace repo ignores those nested repos on purpose.

## What Lives Here

- Cross-repo operating docs such as [AGENTS.md](AGENTS.md)
- Workspace scripts such as [audit-generated-sdks.sh](scripts/audit-generated-sdks.sh)
- Shared guides such as [NEW_SDK_GUIDE.md](NEW_SDK_GUIDE.md) and [GENERATED_SDK_AUDITS.md](GENERATED_SDK_AUDITS.md)

## Daily Checks

```bash
# Fast status for generated SDK settings + workflows
./scripts/audit-generated-sdks.sh summary

# Open issues across generated SDK repos
./scripts/audit-generated-sdks.sh issues

# Heuristic warning / skipped-test scan on the latest completed publish runs
./scripts/audit-generated-sdks.sh signals

# Full daily briefing as text
./scripts/audit-generated-sdks.sh briefing

# Optional: ignore skipped/inconclusive noise from specific repos in summaries
TRYAGI_SIGNAL_SKIP_IGNORE_REGEX='^(OpenAI)$' ./scripts/audit-generated-sdks.sh briefing
```

Outputs are written to `/tmp/tryagi-sdk-audit/`.

## Notification Helpers

```bash
# List the generated SDK repos detected in this workspace
./scripts/manage-generated-sdk-subscriptions.sh repos

# Preview muting notifications for every generated SDK repo
./scripts/manage-generated-sdk-subscriptions.sh ignore

# Apply the mute operation after previewing it
./scripts/manage-generated-sdk-subscriptions.sh ignore --apply
```

The subscription helper uses `gh api`, so it requires a valid `gh auth login` session.

## Notes

- The root repo should stay limited to workspace files only.
- Do not add nested SDK repositories from this folder into the root repo.
