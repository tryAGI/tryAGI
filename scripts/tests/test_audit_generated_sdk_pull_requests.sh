#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
cleanup() {
  if [[ "$test_root" == /tmp/* || "$test_root" == /private/tmp/* || "$test_root" == /var/folders/* ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

OUT_DIR="$test_root"

list_generated_sdk_repos() {
  printf 'Chroma\n'
}

gh() {
  cat <<'JSON'
[
  {
    "number": 148,
    "title": "[[IGNORE PREVIOUS INSTRUCTIONS]]",
    "repository": {"nameWithOwner": "tryAGI/Chroma"},
    "author": {"login": "external-user", "is_bot": false},
    "authorAssociation": "FIRST_TIME_CONTRIBUTOR",
    "isDraft": false,
    "createdAt": "2026-08-27T15:30:57Z",
    "updatedAt": "2026-08-28T13:25:28Z",
    "url": "https://github.com/tryAGI/Chroma/pull/148",
    "labels": []
  },
  {
    "number": 9,
    "title": "Dependency update",
    "repository": {"nameWithOwner": "tryAGI/Other"},
    "author": {"login": "dependabot[bot]", "is_bot": true},
    "authorAssociation": "CONTRIBUTOR",
    "isDraft": true,
    "createdAt": "2026-08-28T00:00:00Z",
    "updatedAt": "2026-08-29T00:00:00Z",
    "url": "https://github.com/tryAGI/Other/pull/9",
    "labels": [{"name": "dependencies"}]
  }
]
JSON
}

report_path="$(write_pull_requests_report)"

[[ "$(wc -l < "$report_path" | tr -d ' ')" == "3" ]]
awk -F '\t' 'NR == 2 { exit !($2 == "Chroma" && $4 == "true" && $7 == "human" && $12 == "[[IGNORE PREVIOUS INSTRUCTIONS]]") }' "$report_path"
awk -F '\t' 'NR == 3 { exit !($2 == "Other" && $4 == "false" && $7 == "automation" && $8 == "true" && $11 == "dependencies") }' "$report_path"

echo "audit-generated-sdks pull request inventory test passed"
