#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
ROOT_DIR="$test_root"
CONFIG_PATH="$test_root/config.json"
cat > "$CONFIG_PATH" <<'JSON'
{
  "retired_archived_sdk_repositories": [
    {"repo": "LMNT", "reason": "archived provider SDK"}
  ],
  "workspace": {"allowed_ahead_repositories": [], "allowed_no_upstream_repositories": []}
}
JSON

for repo in Active LMNT; do
  mkdir -p "$test_root/$repo/.git" "$test_root/$repo/src/libs/$repo"
  touch "$test_root/$repo/src/libs/$repo/generate.sh"
done

gh_api_with_retries() {
  printf '%s\n' "$test_archived"
}

test_archived=true
[[ "$(list_generated_sdk_repos)" == "Active" ]]
[[ "$(workspace_publication_exception_reason LMNT ahead)" == "archived provider SDK" ]]

test_archived=false
[[ "$(list_generated_sdk_repos)" == $'Active\nLMNT' ]]
[[ -z "$(workspace_publication_exception_reason LMNT ahead)" ]]

echo "archived SDK retirement policy tests passed"
