#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
OUT_DIR="$test_root/reports"
test_config=0
test_bot_pr=0

gh_api_with_retries() {
  case "$*" in
    *orgs/*/repos*)
      printf 'tryAGI/Archived\tArchived\tmain\n'
      ;;
    *git/trees/main*)
      if [[ "$test_config" == "1" ]]; then
        printf '{"tree":[{"path":".github/dependabot.yml"}]}\n'
      else
        printf '{"tree":[]}\n'
      fi
      ;;
    *pulls*)
      if [[ "$test_bot_pr" == "1" ]]; then
        printf '24\n'
      fi
      ;;
    *)
      return 1
      ;;
  esac
}

report="$(write_archived_dependabot_report)"
! archived_dependabot_has_failures "$report"
grep -q $'tryAGI/Archived\tmain\t\t\tok\t' "$report"

test_config=1
report="$(write_archived_dependabot_report)"
archived_dependabot_has_failures "$report"
grep -q $'tryAGI/Archived\tmain\t.github/dependabot.yml\t\tconfig-present\t' "$report"

test_config=0
test_bot_pr=1
report="$(write_archived_dependabot_report)"
archived_dependabot_has_failures "$report"
grep -q $'tryAGI/Archived\tmain\t\t24\topen-bot-prs\t' "$report"

echo "archived Dependabot guard tests passed"
