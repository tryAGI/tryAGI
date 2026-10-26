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
  local upstream_dir="$repo_dir-upstream.git"

  git init -q --bare "$upstream_dir"
  git init -q -b main "$repo_dir"
  git -C "$repo_dir" config user.email test@example.com
  git -C "$repo_dir" config user.name "SDK Audit Test"
  git -C "$repo_dir" remote add origin "$upstream_dir"
  printf 'old\n' > "$repo_dir/already-upstream.txt"
  printf 'old\n' > "$repo_dir/remote-only.txt"
  git -C "$repo_dir" add already-upstream.txt remote-only.txt
  git -C "$repo_dir" commit -qm base
  fixture_base="$(git -C "$repo_dir" rev-parse HEAD)"

  printf 'new\n' > "$repo_dir/already-upstream.txt"
  printf 'new\n' > "$repo_dir/remote-only.txt"
  git -C "$repo_dir" commit -qam target
  fixture_target="$(git -C "$repo_dir" rev-parse HEAD)"
  git -C "$repo_dir" push -q origin main

  # Only isolated disposable test repositories change branches.
  git -C "$repo_dir" switch -q --detach "$fixture_base"
  git -C "$repo_dir" branch -f main "$fixture_base"
  git -C "$repo_dir" switch -q main
}

ROOT_DIR="$test_root"
OUT_DIR="$test_root/reports"
mkdir -p "$OUT_DIR"
for repo in clean equivalent different staged untracked; do
  create_fixture "$test_root/$repo"
done
printf 'new\n' > "$test_root/equivalent/already-upstream.txt"
printf 'local-only\n' > "$test_root/different/already-upstream.txt"
printf 'new\n' > "$test_root/staged/already-upstream.txt"
git -C "$test_root/staged" add -- already-upstream.txt
printf 'local-only\n' > "$test_root/untracked/local-only.txt"

list_generated_sdk_repos() {
  printf '%s\n' clean equivalent different staged untracked
}
repo_api_target() { printf 'test/%s\n' "$1"; }
gh_api_with_retries() { printf '%s\n' "${1#repos/}"; }
# The remote-inventory call returns no additional repositories; no network API.
gh() { return 0; }

snapshot_dirty_fixtures() {
  local repo
  for repo in equivalent different staged untracked; do
    git -C "$test_root/$repo" rev-parse HEAD
    git -C "$test_root/$repo" status --porcelain
    git -C "$test_root/$repo" diff --binary
    git -C "$test_root/$repo" diff --cached --binary
    cat "$test_root/$repo/already-upstream.txt" "$test_root/$repo/remote-only.txt"
  done
  cat "$test_root/untracked/local-only.txt"
}
snapshot_dirty_fixtures > "$test_root/before.txt"
report="$(write_sync_report)"
snapshot_dirty_fixtures > "$test_root/after.txt"
cmp "$test_root/before.txt" "$test_root/after.txt"
[[ "$(git -C "$test_root/clean" log -1 --format=%s)" == "target" ]]
[[ -z "$(git -C "$test_root/clean" status --porcelain)" ]]
[[ "$(cat "$test_root/clean/remote-only.txt")" == "new" ]]
python3 - "$report" <<'CHECK'
import csv, sys
rows = {row["repo"]: row for row in csv.DictReader(open(sys.argv[1]), delimiter="\t")}
assert rows["clean"]["status"] == "fast-forwarded", rows["clean"]
for name in ("equivalent", "different", "staged", "untracked"):
    row = rows[name]
    assert row["status"] == "dirty" and row["action"] == "fetched", row
    assert row["head_before"] == row["head_after"], row
    assert row["origin_main"] != row["head_after"] and row["behind"] == "1", row
CHECK

# Restore production discovery for the existing finalized-report inventory test.
unset -f list_generated_sdk_repos
source "$script_dir/../audit-generated-sdks.sh"
OUT_DIR="$test_root/reports"
mkdir -p "$OUT_DIR"
printf 'repo\tstatus\nActive\tcurrent\n__inventory__\tok\n' > "$OUT_DIR/generated-sdk-sync.tsv"
MODE=local-trims
[[ "$(list_generated_sdk_repos)" == "Active" ]]
REPO_FILTER='^Other$'
[[ -z "$(list_generated_sdk_repos)" ]]

echo "audit-generated-sdks sync dirty-worktree preservation tests passed"
