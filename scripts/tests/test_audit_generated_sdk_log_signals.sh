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
    repos/tryAGI/SafeSdk/actions/runs/42/attempts/*/jobs\?per_page=100)
      [[ "$3" == --paginate ]]
      [[ "$5" == *'select(.conclusion != "skipped")'* ]]
      case "$MOCK_MODE" in
        unavailable) return 1 ;;
        empty) return 0 ;;
        invalid) printf 'invalid-id\tcompleted\n'; return 0 ;;
        pending-job) printf '101\tin_progress\n'; return 0 ;;
        duplicate-job) printf '101\tcompleted\n101\tcompleted\n'; return 0 ;;
      esac
      printf '101\tcompleted\n102\tcompleted\n'
      ;;
    repos/tryAGI/SafeSdk/actions/jobs/*/logs)
      printf 'download\n' >> "$download_count_path"
      [[ "$MOCK_MODE" != job-unavailable ]] || return 1
      if [[ "$MOCK_MODE" == empty-job ]]; then printf ' \n'; return 0; fi
      if [[ "$2" == */101/logs ]]; then
        if [[ "$MOCK_MODE" == retained ]]; then
          printf 'warning CS8602: retained build warning\nPassed! - Skipped: 7\n'
        else
          for ((i = 0; i < MOCK_ATTEMPT; i++)); do printf 'warning CS8602: test warning\n'; done
          printf 'Passed! - Failed: 0, Passed: 2, Skipped: 3, Total: 5\n'
        fi
      else
        [[ "$MOCK_MODE" != partial-job-failure ]] || return 1
        if [[ "$MOCK_MODE" == retained ]]; then
          printf 'Rerun trimming job succeeded without warnings.\n'
        else
          printf 'Passed! - Skipped: 2\n'
        fi
      fi
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
    elif mode == "retained":
        # GitHub omits the old successful build from a failed-job rerun archive.
        archive.writestr("0_Trim.txt", "Rerun trimming job succeeded without warnings.\n")
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

# A rerun is assembled once from its current jobs, with no archive duplicates.
MOCK_ATTEMPT=2
rerun_path="$(fetch_run_log SafeSdk 42)"
[[ "$rerun_path" != "$log_path" ]]
[[ "$(parse_log_signals "$rerun_path")" == $'2\t5\t0' ]]
[[ "$(fetch_run_log SafeSdk 42)" == "$rerun_path" ]]
[[ "$(wc -l < "$download_count_path" | tr -d ' ')" == 3 ]]

# An empty current-attempt cache also needs to be downloaded again.
MOCK_ATTEMPT=3
touch "$OUT_DIR/logs/SafeSdk-42-attempt-3-jobs-v1.log"
log_path="$(fetch_run_log SafeSdk 42)"
[[ "$(parse_log_signals "$log_path")" == $'3\t5\t0' ]]

# Archives with only individual step logs are still useful for first attempts.
MOCK_ATTEMPT=1
MOCK_MODE=steps-only
rm -f "$OUT_DIR/logs/SafeSdk-42-attempt-1.log"
log_path="$(fetch_run_log SafeSdk 42)"
[[ "$(parse_log_signals "$log_path")" == $'1\t3\t0' ]]

# A retained build must not disappear, and an incomplete archive cache is stale.
MOCK_ATTEMPT=4
MOCK_MODE=retained
printf 'Old archive contains only the new trimming job.\n' > "$OUT_DIR/logs/SafeSdk-42-attempt-4.log"
log_path="$(fetch_run_log SafeSdk 42)"
[[ "$log_path" == *-attempt-4-jobs-v1.log ]]
[[ "$(parse_log_signals "$log_path")" == $'1\t7\t0' ]]

# Failure is visible with blank counts; a partial aggregate is never cached.
for kind in archive jobs; do
  for MOCK_MODE in empty empty-job invalid unavailable job-unavailable partial-job-failure pending-job duplicate-job; do
    if [[ "$kind" == archive ]]; then
      case "$MOCK_MODE" in job-unavailable|partial-job-failure|pending-job|duplicate-job) continue ;; esac
      MOCK_ATTEMPT=1
      expected_cache="$OUT_DIR/logs/SafeSdk-42-attempt-1.log"
    else
      MOCK_ATTEMPT=$((MOCK_ATTEMPT + 1))
      expected_cache="$OUT_DIR/logs/SafeSdk-42-attempt-$MOCK_ATTEMPT-jobs-v1.log"
    fi
    rm -f "$expected_cache"
    report_path="$(write_signals_report 2> "$test_root/expected-errors.log")"
    awk -F '\t' 'NR == 2 { exit !($6 == "log-unavailable" && $7 == "" && $8 == "" && $9 == "") }' "$report_path"
    [[ ! -e "$expected_cache" ]]
  done
done
[[ -z "$(find "$OUT_DIR/logs" -name '.run-*' -print)" ]]

MOCK_ATTEMPT=null
if fetch_run_log SafeSdk 42 >/dev/null; then
  echo "Invalid attempt metadata was accepted" >&2
  exit 1
fi

echo "audit-generated-sdks log signal retrieval tests passed"
