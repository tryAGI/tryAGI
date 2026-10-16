#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../audit-generated-sdks.sh
source "$script_dir/../audit-generated-sdks.sh"

test_root="$(mktemp -d)"
trap 'rm -rf -- "$test_root"' EXIT
OUT_DIR="$test_root/output"
ROOT_DIR="$test_root/workspace"
mkdir -p "$ROOT_DIR/SafeSdk/.github/workflows"
touch "$ROOT_DIR/SafeSdk/.github/workflows/dotnet.yml"
download_count_path="$test_root/downloads"
MOCK_ATTEMPT=1
MOCK_MODE=normal

repo_api_target() { printf 'tryAGI/%s\n' "$1"; }
list_generated_sdk_repos() { printf 'SafeSdk\n'; }
latest_completed_run_json() {
  printf '[{"databaseId":42,"conclusion":"success","status":"completed","url":"https://example.test/run/42"}]\n'
}

gh() {
  [[ "$1" == api ]] || { echo "Unexpected gh command" >&2; return 1; }
  case "$2" in
    repos/tryAGI/SafeSdk/actions/runs/42)
      printf '%s\n' "$MOCK_ATTEMPT"
      ;;
    repos/tryAGI/SafeSdk/actions/runs/42/attempts/*/logs)
      printf 'download\n' >> "$download_count_path"
      [[ "$MOCK_MODE" != unavailable ]] || return 1
      python3 - "$MOCK_MODE" "$MOCK_ATTEMPT" <<'PY'
import io
import sys
from zipfile import ZipFile

mode, attempt = sys.argv[1:]
if mode == "invalid":
    sys.stdout.buffer.write(b"not an archive")
    sys.exit()
buffer = io.BytesIO()
with ZipFile(buffer, "w") as archive:
    log = "warning CS8602: test warning\n" * int(attempt)
    log += "Passed! - Failed: 0, Passed: 2, Skipped: 3, Total: 5\n"
    if mode == "normal":
        archive.writestr("0_Build.txt", log)
        archive.writestr("Build/1_Build.txt", log)  # Duplicate must not be counted.
        archive.writestr("1_Test.txt", "Passed! - Skipped: 2\n")
    elif mode == "steps-only":
        archive.writestr("Build/1_Build.txt", log)
    elif mode == "empty-job":
        archive.writestr("0_Build.txt", " \n")
    elif mode == "empty":
        archive.writestr("Build/", "")
sys.stdout.buffer.write(buffer.getvalue())
PY
      ;;
    *) echo "Unexpected API endpoint: $2" >&2; return 1 ;;
  esac
}

# Old empty cache files and duplicate per-step entries must not produce false zeroes.
mkdir -p "$OUT_DIR/logs"
touch "$OUT_DIR/logs/SafeSdk-42.log"
log_path="$(fetch_run_log SafeSdk 42)"
[[ -s "$log_path" ]]
[[ "$(parse_log_signals "$log_path")" == $'1\t5\t0' ]]
[[ "$(fetch_run_log SafeSdk 42)" == "$log_path" ]]
[[ "$(wc -l < "$download_count_path" | tr -d ' ')" == 1 ]]

# A rerun of the same run gets a different cache and new warning counts.
MOCK_ATTEMPT=2
rerun_path="$(fetch_run_log SafeSdk 42)"
[[ "$rerun_path" != "$log_path" ]]
[[ "$(parse_log_signals "$rerun_path")" == $'2\t5\t0' ]]
[[ "$(wc -l < "$download_count_path" | tr -d ' ')" == 2 ]]

# An empty current-attempt cache also needs to be downloaded again.
MOCK_ATTEMPT=3
touch "$OUT_DIR/logs/SafeSdk-42-attempt-3.log"
log_path="$(fetch_run_log SafeSdk 42)"
[[ "$(parse_log_signals "$log_path")" == $'3\t5\t0' ]]

# Archives with only individual step logs are still useful.
MOCK_ATTEMPT=4
MOCK_MODE=steps-only
log_path="$(fetch_run_log SafeSdk 42)"
[[ "$(parse_log_signals "$log_path")" == $'4\t3\t0' ]]

# Failure must be visible in the report, with blank counts and no cached success.
for MOCK_MODE in empty empty-job invalid unavailable; do
  MOCK_ATTEMPT=$((MOCK_ATTEMPT + 1))
  report_path="$(write_signals_report 2> "$test_root/expected-errors.log")"
  awk -F '\t' 'NR == 2 { exit !($6 == "log-unavailable" && $7 == "" && $8 == "" && $9 == "") }' "$report_path"
  [[ ! -e "$OUT_DIR/logs/SafeSdk-42-attempt-$MOCK_ATTEMPT.log" ]]
done
[[ -z "$(find "$OUT_DIR/logs" -name '.run-*' -print)" ]]

MOCK_ATTEMPT=null
if fetch_run_log SafeSdk 42 >/dev/null; then
  echo "Invalid attempt metadata was accepted" >&2
  exit 1
fi

echo "audit-generated-sdks log signal retrieval tests passed"
