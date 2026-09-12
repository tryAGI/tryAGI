#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh disable=SC1091
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
cleanup() {
  if [[ "$test_root" == /tmp/* || "$test_root" == /private/tmp/* || "$test_root" == /var/folders/* ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

cat > "$test_root/native.yml" <<'YAML'
name: Auto-merge
on:
  workflow_run:
    workflows:
      - Test
    types:
      - completed
jobs:
  auto-merge:
    uses: tryAGI/workflows/.github/workflows/auto-merge.yml@main
    secrets: inherit
YAML

cat > "$test_root/github-token.yml" <<'YAML'
name: Auto-merge
on:
  workflow_run:
    workflows:
      - Build and test
    types:
      - completed
jobs:
  auto-merge:
    uses: tryAGI/workflows/.github/workflows/auto-merge.yml@main
    with:
      allow-github-token-fallback: true
    secrets: inherit
YAML

cat > "$test_root/unsafe.yml" <<'YAML'
name: Auto-merge
on:
  pull_request:
jobs:
  auto-merge:
    uses: tryAGI/workflows/.github/workflows/auto-merge.yml@main
    secrets: inherit
YAML

native_info="$(dependency_auto_merge_workflow_info "$test_root/native.yml")"
[[ "$(cut -f1 <<< "$native_info")" == "ok" ]]
[[ "$(cut -f2 <<< "$native_info")" == "Test" ]]
[[ "$(cut -f3 <<< "$native_info")" == "false" ]]

github_token_info="$(dependency_auto_merge_workflow_info "$test_root/github-token.yml")"
[[ "$(cut -f1 <<< "$github_token_info")" == "ok" ]]
[[ "$(cut -f2 <<< "$github_token_info")" == "Build and test" ]]
[[ "$(cut -f3 <<< "$github_token_info")" == "true" ]]

[[ "$(dependency_auto_merge_workflow_info "$test_root/unsafe.yml" | cut -f1)" == "missing-workflow-run-trigger" ]]
[[ "$(dependency_auto_merge_workflow_info "$test_root/missing.yml" | cut -f1)" == "missing-workflow" ]]

echo "audit-generated-sdks dependency auto-merge test passed"
