#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
ROOT_DIR="$test_root/workspace"
OUT_DIR="$test_root/reports"
mkdir -p "$ROOT_DIR/Fixture/src/libs/Fixture" "$OUT_DIR"
git -C "$ROOT_DIR/Fixture" init -q -b main
git -C "$ROOT_DIR/Fixture" config user.name "Audit Test"
git -C "$ROOT_DIR/Fixture" config user.email "audit-test@example.invalid"
touch "$ROOT_DIR/Fixture/src/libs/Fixture/generate.sh"
printf '<Project Sdk="Microsoft.NET.Sdk" />\n' > "$ROOT_DIR/Fixture/src/libs/Fixture/Fixture.csproj"
git -C "$ROOT_DIR/Fixture" add src/libs/Fixture/generate.sh src/libs/Fixture/Fixture.csproj
git -C "$ROOT_DIR/Fixture" commit -qm initial

list_generated_sdk_repos() { printf 'Fixture\n'; }
test_autosdk_version="fixture-1"
test_trim_failure=0
autosdk() {
  if [[ "$1" == "--version" ]]; then
    printf '%s\n' "$test_autosdk_version"
    return
  fi
  [[ "$1" == "trim" ]]
  local count=0
  [[ ! -f "$test_root/calls" ]] || count="$(cat "$test_root/calls")"
  printf '%s\n' "$((count + 1))" > "$test_root/calls"
  if [[ "$test_trim_failure" == "1" ]]; then
    printf 'Trimming failed\n'
    return 1
  fi
  printf 'No trimming warnings found. The project is trimming-compatible.\n'
}
dotnet() { printf '10.0-test\n'; }

write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "1" ]]
grep -q $'Fixture\t.*\tsuccess\t0\t.*\tfresh\t' "$OUT_DIR/generated-sdk-local-trims.tsv"
[[ "$(print_local_trim_summary "$OUT_DIR/generated-sdk-local-trims.tsv" | grep -F 'Local trims run:')" == "Local trims run: 1" ]]

write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "1" ]]
grep -q $'Fixture\t.*\tsuccess\t0\t.*\treused\t' "$OUT_DIR/generated-sdk-local-trims.tsv"
[[ "$(print_local_trim_summary "$OUT_DIR/generated-sdk-local-trims.tsv" | grep -F 'Local trims reused from cache:')" == "Local trims reused from cache: 1" ]]

printf '\n<!-- new HEAD -->\n' >> "$ROOT_DIR/Fixture/src/libs/Fixture/Fixture.csproj"
git -C "$ROOT_DIR/Fixture" add src/libs/Fixture/Fixture.csproj
git -C "$ROOT_DIR/Fixture" commit -qm update
write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "2" ]]

printf 'Corrupted log\n' > "$OUT_DIR/local-trim-logs/Fixture-1.log"
write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "3" ]]

test_autosdk_version="fixture-2"
write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "4" ]]

TRYAGI_LOCAL_TRIM_FORCE=1 write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "5" ]]

test_trim_failure=1
TRYAGI_LOCAL_TRIM_FORCE=1 write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "6" ]]
grep -q $'Fixture\t.*\tfailed\t1\t' "$OUT_DIR/generated-sdk-local-trims.tsv"

test_trim_failure=0
write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "7" ]]

python3 - "$OUT_DIR/generated-sdk-local-trims.tsv" <<'PY'
import csv
from pathlib import Path
import sys

path = Path(sys.argv[1])
with path.open(newline="") as stream:
    row = next(csv.DictReader(stream, delimiter="\t"))
assert row["head_sha"] and row["log_sha256"]
path.write_text("repo\tproject\tstatus\texit_code\tduration_seconds\tlog_path\thead_sha\tevidence\n"
                f"{row['repo']}\t{row['project']}\tsuccess\t0\t\t{row['log_path']}\t{row['head_sha']}\tlegacy\n")
PY
write_local_trims_report >/dev/null
[[ "$(cat "$test_root/calls")" == "8" ]]

echo "generated SDK trimming cache tests passed"
