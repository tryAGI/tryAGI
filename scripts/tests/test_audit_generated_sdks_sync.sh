#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
cleanup() {
  if [[ -n "$test_root" && "$test_root" == /tmp/* || "$test_root" == /private/tmp/* || "$test_root" == /var/folders/* ]]; then
    rm -rf -- "$test_root"
  fi
}
trap cleanup EXIT

create_fixture() {
  local repo_dir="$1"

  git -C "$test_root" init -q "$repo_dir"
  git -C "$repo_dir" config user.email test@example.com
  git -C "$repo_dir" config user.name "SDK Audit Test"
  printf 'old\n' > "$repo_dir/already-upstream.txt"
  printf 'old\n' > "$repo_dir/remote-only.txt"
  git -C "$repo_dir" add already-upstream.txt remote-only.txt
  git -C "$repo_dir" commit -qm base
  fixture_base="$(git -C "$repo_dir" rev-parse HEAD)"

  printf 'new\n' > "$repo_dir/already-upstream.txt"
  printf 'new\n' > "$repo_dir/remote-only.txt"
  git -C "$repo_dir" commit -qam target
  fixture_target="$(git -C "$repo_dir" rev-parse HEAD)"

  git -C "$repo_dir" switch -q --detach "$fixture_base"
  git -C "$repo_dir" branch -f main "$fixture_base"
  git -C "$repo_dir" switch -q main
}

equivalent_repo="$test_root/equivalent"
create_fixture "$equivalent_repo"
printf 'new\n' > "$equivalent_repo/already-upstream.txt"
try_fast_forward_upstream_equivalent_dirty_checkout \
  "$equivalent_repo" "$fixture_target" "$test_root/equivalent.log"

[[ "$(git -C "$equivalent_repo" rev-parse HEAD)" == "$fixture_target" ]]
[[ -z "$(git -C "$equivalent_repo" status --porcelain)" ]]
[[ "$(git -C "$equivalent_repo" rev-list --count "$fixture_base..HEAD")" == "1" ]]
[[ "$(sed -n '1p' "$equivalent_repo/remote-only.txt")" == "new" ]]

different_repo="$test_root/different"
create_fixture "$different_repo"
printf 'local-only\n' > "$different_repo/already-upstream.txt"
if try_fast_forward_upstream_equivalent_dirty_checkout \
    "$different_repo" "$fixture_target" "$test_root/different.log"; then
  echo "non-equivalent dirty worktree unexpectedly fast-forwarded" >&2
  exit 1
fi

[[ "$(git -C "$different_repo" rev-parse HEAD)" == "$fixture_base" ]]
[[ "$(git -C "$different_repo" status --short)" == " M already-upstream.txt" ]]

echo "audit-generated-sdks sync equivalence tests passed"
