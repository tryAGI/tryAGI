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

# Consumed by the sourced audit function.
# shellcheck disable=SC2034
ROOT_DIR="$test_root"
mkdir -p "$test_root/Compliant/.github" "$test_root/Ungrouped/.github"

cat > "$test_root/Compliant/.github/dependabot.yml" <<'YAML'
version: 2
updates:
  - package-ecosystem: "nuget"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      all:
        patterns:
          - "*"
YAML

cat > "$test_root/Ungrouped/.github/dependabot.yml" <<'YAML'
version: 2
updates:
  - package-ecosystem: nuget
    directory: "/"
    schedule:
      interval: weekly
YAML

[[ "$(repo_dependabot_nuget_info Compliant | cut -f1)" == "ok" ]]
[[ "$(repo_dependabot_nuget_info Ungrouped | cut -f1)" == "not-grouped-all" ]]
[[ "$(repo_dependabot_nuget_info Missing | cut -f1)" == "missing-config" ]]

echo "audit-generated-sdks Dependabot policy test passed"
