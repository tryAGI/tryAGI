#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ORG="${TRYAGI_ORG:-tryAGI}"
CONFIG_PATH="${TRYAGI_AUDIT_CONFIG_PATH:-$ROOT_DIR/config/generated-sdk-audit.json}"
OUT_DIR="${TRYAGI_AUDIT_OUT_DIR:-/tmp/tryagi-sdk-audit}"
ISSUE_LIMIT="${TRYAGI_ISSUE_LIMIT:-100}"
AUTO_UPDATE_WORKFLOW_FILE="${TRYAGI_AUTO_UPDATE_WORKFLOW_FILE:-auto-update.yml}"
PUBLISH_WORKFLOW_FILE="${TRYAGI_PUBLISH_WORKFLOW_FILE:-dotnet.yml}"
SIGNAL_RUN_LIMIT="${TRYAGI_SIGNAL_RUN_LIMIT:-5}"
SIGNAL_SKIP_IGNORE_REGEX="${TRYAGI_SIGNAL_SKIP_IGNORE_REGEX:-^(OpenAI)$}"
MODE="summary"
REPO_FILTER=""

usage() {
  cat <<'EOF'
Usage: ./scripts/audit-generated-sdks.sh [summary|settings|workflows|issues|signals|briefing|repos] [--repo REGEX] [--out-dir PATH] [--config PATH]

Modes:
  summary    Write settings + workflow TSV reports and print a short summary.
  settings   Write generated-sdk-settings.tsv with auto-merge related repo settings.
  workflows  Write generated-sdk-workflows.tsv with latest auto-update and Publish runs.
  issues     Write generated-sdk-open-issues.tsv with open issues for generated SDK repos.
  signals    Write generated-sdk-log-signals.tsv by scanning the latest completed Publish logs.
  briefing   Write all reports plus daily-briefing.txt.
  repos      Print the generated SDK repos detected in the current workspace.

Options:
  --repo REGEX   Only include repo names matching the regular expression.
  --out-dir PATH Override the output directory. Default: /tmp/tryagi-sdk-audit
  --config PATH  Override the audit config file. Default: config/generated-sdk-audit.json

Environment:
  TRYAGI_AUDIT_CONFIG_PATH         Override the audit config file path.
  TRYAGI_AUTO_UPDATE_WORKFLOW_FILE Override the auto-update workflow file. Default: auto-update.yml
  TRYAGI_PUBLISH_WORKFLOW_FILE     Override the publish workflow file. Default: dotnet.yml
  TRYAGI_SIGNAL_RUN_LIMIT           How many recent Publish runs to inspect when finding the latest completed run. Default: 5
  TRYAGI_SIGNAL_SKIP_IGNORE_REGEX   Regex for repos whose skipped/inconclusive test counts should be ignored in summaries. Default: ^(OpenAI)$
EOF
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      summary|settings|workflows|issues|signals|briefing|repos)
        MODE="$1"
        shift
        ;;
      --repo)
        REPO_FILTER="${2:-}"
        shift 2
        ;;
      --out-dir)
        OUT_DIR="${2:-}"
        shift 2
        ;;
      --config)
        CONFIG_PATH="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "Unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

list_generated_sdk_repos() {
  local repo_dir
  local repo_name

  for repo_dir in "$ROOT_DIR"/*; do
    [[ -d "$repo_dir/.git" ]] || continue
    repo_name="${repo_dir##*/}"

    if [[ -n "$REPO_FILTER" ]] && ! [[ "$repo_name" =~ $REPO_FILTER ]]; then
      continue
    fi

    if compgen -G "$repo_dir/src/libs/*/generate.sh" >/dev/null; then
      printf '%s\n' "$repo_name"
    fi
  done | sort
}

repo_api_target() {
  local repo="$1"
  local remote_url

  remote_url="$(git -C "$ROOT_DIR/$repo" remote get-url origin 2>/dev/null || true)"
  if [[ -z "$remote_url" ]]; then
    printf '%s/%s\n' "$ORG" "$repo"
    return
  fi

  python3 - <<'PY' "$remote_url" "$ORG" "$repo"
import re
import sys

remote_url, org, repo = sys.argv[1:]
patterns = [
    r"^https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$",
    r"^git@github\.com:([^/]+)/([^/]+?)(?:\.git)?$",
]

for pattern in patterns:
    match = re.match(pattern, remote_url)
    if match:
        print(f"{match.group(1)}/{match.group(2)}")
        raise SystemExit(0)

print(f"{org}/{repo}")
PY
}

latest_run_json() {
  local repo="$1"
  local workflow_file="$2"
  local limit="${3:-1}"
  local api_target
  local response

  api_target="$(repo_api_target "$repo")"

  if ! response="$(
    gh api "repos/$api_target/actions/workflows/$workflow_file/runs?per_page=$limit" 2>/dev/null
  )"; then
    return 1
  fi

  jq -c '
    (.workflow_runs // [])
    | map(
        {
          databaseId: .id,
          workflowName: (.name // ""),
          status: (.status // ""),
          conclusion: (.conclusion // ""),
          createdAt: (.created_at // ""),
          updatedAt: (.updated_at // ""),
          headBranch: (.head_branch // ""),
          url: (.html_url // "")
        }
      )
  ' <<< "$response"
}

latest_completed_run_json() {
  local repo="$1"
  local workflow_file="$2"
  local run_json

  run_json="$(latest_run_json "$repo" "$workflow_file" "$SIGNAL_RUN_LIMIT")" || return 1
  jq -c '[.[] | select(.status == "completed")][0:1]' <<< "$run_json"
}

config_value() {
  local jq_path="$1"

  jq -er "$jq_path // empty" "$CONFIG_PATH" 2>/dev/null || true
}

config_repo_regex() {
  local jq_path="$1"

  python3 - <<'PY' "$CONFIG_PATH" "$jq_path"
import json
import re
import sys

config_path, jq_path = sys.argv[1:]
with open(config_path, encoding="utf-8") as f:
    data = json.load(f)

value = data
for part in jq_path.split("."):
    if not isinstance(value, dict):
        value = None
        break
    value = value.get(part)

if not value:
    raise SystemExit(1)

print("^(" + "|".join(re.escape(str(item)) for item in value) + ")$")
PY
}

load_config() {
  local value

  if [[ ! -f "$CONFIG_PATH" ]]; then
    return
  fi

  if ! jq empty "$CONFIG_PATH" >/dev/null 2>&1; then
    echo "Invalid audit config: $CONFIG_PATH" >&2
    exit 1
  fi

  if [[ -z "${TRYAGI_ISSUE_LIMIT+x}" ]]; then
    value="$(config_value '.issue_limit')"
    if [[ -n "$value" ]]; then
      ISSUE_LIMIT="$value"
    fi
  fi

  if [[ -z "${TRYAGI_AUTO_UPDATE_WORKFLOW_FILE+x}" ]]; then
    value="$(config_value '.workflows.auto_update_file')"
    if [[ -n "$value" ]]; then
      AUTO_UPDATE_WORKFLOW_FILE="$value"
    fi
  fi

  if [[ -z "${TRYAGI_PUBLISH_WORKFLOW_FILE+x}" ]]; then
    value="$(config_value '.workflows.publish_file')"
    if [[ -n "$value" ]]; then
      PUBLISH_WORKFLOW_FILE="$value"
    fi
  fi

  if [[ -z "${TRYAGI_SIGNAL_RUN_LIMIT+x}" ]]; then
    value="$(config_value '.signals.run_limit')"
    if [[ -n "$value" ]]; then
      SIGNAL_RUN_LIMIT="$value"
    fi
  fi

  if [[ -z "${TRYAGI_SIGNAL_SKIP_IGNORE_REGEX+x}" ]]; then
    value="$(config_repo_regex 'signals.ignored_skip_signal_repos' || true)"
    if [[ -n "$value" ]]; then
      SIGNAL_SKIP_IGNORE_REGEX="$value"
    fi
  fi
}

write_settings_report() {
  local output_path="$OUT_DIR/generated-sdk-settings.tsv"
  local repo
  local api_target

  mkdir -p "$OUT_DIR"
  printf 'repo\tallow_auto_merge\tdelete_branch_on_merge\tallow_update_branch\n' > "$output_path"

  while IFS= read -r repo; do
    api_target="$(repo_api_target "$repo")"
    if ! gh api "repos/$api_target" --jq '[.name, .allow_auto_merge, .delete_branch_on_merge, .allow_update_branch] | @tsv' >> "$output_path" 2>/dev/null; then
      printf '%s\tunknown\tunknown\tunknown\n' "$repo" >> "$output_path"
    fi
  done < <(list_generated_sdk_repos)

  printf '%s\n' "$output_path"
}

write_workflow_line() {
  local repo="$1"
  local kind="$2"
  local workflow_file="$3"
  local workflow_path="$ROOT_DIR/$repo/.github/workflows/$workflow_file"
  local run_json

  if [[ ! -f "$workflow_path" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$kind" "$workflow_file" "" "missing-workflow" "" "" "" ""
    return
  fi

  if ! run_json="$(latest_run_json "$repo" "$workflow_file")"; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$kind" "$workflow_file" "" "api-error" "" "" "" ""
    return
  fi

  jq -r \
    --arg repo "$repo" \
    --arg kind "$kind" \
    --arg workflow_file "$workflow_file" \
    '
      if length == 0 then
        [$repo, $kind, $workflow_file, "", "no-runs", "", "", "", ""] | @tsv
      else
        .[0] |
        [
          $repo,
          $kind,
          $workflow_file,
          (.databaseId | tostring),
          (.conclusion // ""),
          (.status // ""),
          (.createdAt // ""),
          (.headBranch // ""),
          (.url // "")
        ] | @tsv
      end
    ' <<< "$run_json"
}

write_workflows_report() {
  local output_path="$OUT_DIR/generated-sdk-workflows.tsv"
  local repo

  mkdir -p "$OUT_DIR"
  printf 'repo\tkind\tworkflow_file\trun_id\tconclusion\tstatus\tcreated_at\thead_branch\turl\n' > "$output_path"

  while IFS= read -r repo; do
    write_workflow_line "$repo" "auto-update" "$AUTO_UPDATE_WORKFLOW_FILE" >> "$output_path"
    write_workflow_line "$repo" "publish" "$PUBLISH_WORKFLOW_FILE" >> "$output_path"
  done < <(list_generated_sdk_repos)

  printf '%s\n' "$output_path"
}

write_issues_report() {
  local output_path="$OUT_DIR/generated-sdk-open-issues.tsv"
  local repo
  local api_target
  local issues_json

  mkdir -p "$OUT_DIR"
  printf 'repo\tissue_number\ttitle\tupdated_at\tlabels\turl\n' > "$output_path"

  while IFS= read -r repo; do
    api_target="$(repo_api_target "$repo")"
    issues_json="$(gh issue list --repo "$api_target" --state open --limit "$ISSUE_LIMIT" --json number,title,updatedAt,url,labels 2>/dev/null || printf '[]\n')"
    jq -r \
      --arg repo "$repo" \
      '
        .[] |
        [
          $repo,
          (.number | tostring),
          (.title // ""),
          (.updatedAt // ""),
          ((.labels // []) | map(.name) | join(",")),
          (.url // "")
        ] | @tsv
      ' <<< "$issues_json" >> "$output_path"
  done < <(list_generated_sdk_repos)

  printf '%s\n' "$output_path"
}

fetch_run_log() {
  local repo="$1"
  local run_id="$2"
  local api_target
  local log_dir="$OUT_DIR/logs"
  local log_path="$log_dir/$repo-$run_id.log"

  mkdir -p "$log_dir"
  api_target="$(repo_api_target "$repo")"

  if [[ ! -f "$log_path" ]]; then
    if ! gh run view "$run_id" --repo "$api_target" --log > "$log_path" 2>/dev/null; then
      rm -f "$log_path"
      return 1
    fi
  fi

  printf '%s\n' "$log_path"
}

parse_log_signals() {
  local log_path="$1"

  python3 - <<'PY' "$log_path"
import re
import sys

path = sys.argv[1]
with open(path, encoding="utf-8", errors="replace") as f:
    text = f.read()

warning_lines = 0
for line in text.splitlines():
    if re.search(r"##\[warning\]", line, re.IGNORECASE):
        warning_lines += 1
        continue
    if re.search(r"\bwarning\s+[A-Z]{2,}\d{2,}:", line):
        warning_lines += 1
        continue
    if re.search(r":\s*warning\s+[A-Z]{2,}\d{2,}:", line):
        warning_lines += 1

summary_skips = sum(int(match.group(1)) for match in re.finditer(r"Skipped:\s*([0-9]+)", text))
if summary_skips > 0:
    skipped_tests = summary_skips
else:
    skipped_tests = sum(1 for line in text.splitlines() if re.search(r"^\s*Skipped\s+\S", line))

inconclusive_hits = len(re.findall(r"AssertInconclusiveException|Assert\.Inconclusive", text))
print(f"{warning_lines}\t{skipped_tests}\t{inconclusive_hits}")
PY
}

write_signals_report() {
  local output_path="$OUT_DIR/generated-sdk-log-signals.tsv"
  local repo
  local workflow_path
  local run_json
  local run_id
  local conclusion
  local status
  local url
  local log_path
  local counts

  mkdir -p "$OUT_DIR"
  printf 'repo\tworkflow_file\trun_id\tconclusion\tstatus\tsignal_status\twarning_lines\tskipped_tests\tinconclusive_hits\turl\n' > "$output_path"

  while IFS= read -r repo; do
    workflow_path="$ROOT_DIR/$repo/.github/workflows/$PUBLISH_WORKFLOW_FILE"
    if [[ ! -f "$workflow_path" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo" "$PUBLISH_WORKFLOW_FILE" "" "" "" "missing-workflow" "" "" "" "" >> "$output_path"
      continue
    fi

    if ! run_json="$(latest_completed_run_json "$repo" "$PUBLISH_WORKFLOW_FILE")"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo" "$PUBLISH_WORKFLOW_FILE" "" "" "" "api-error" "" "" "" "" >> "$output_path"
      continue
    fi

    if [[ "$(jq 'length' <<< "$run_json")" == "0" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo" "$PUBLISH_WORKFLOW_FILE" "" "" "" "no-completed-runs" "" "" "" "" >> "$output_path"
      continue
    fi

    run_id="$(jq -r '.[0].databaseId' <<< "$run_json")"
    conclusion="$(jq -r '.[0].conclusion // ""' <<< "$run_json")"
    status="$(jq -r '.[0].status // ""' <<< "$run_json")"
    url="$(jq -r '.[0].url // ""' <<< "$run_json")"

    if ! log_path="$(fetch_run_log "$repo" "$run_id")"; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo" "$PUBLISH_WORKFLOW_FILE" "$run_id" "$conclusion" "$status" "log-unavailable" "" "" "" "$url" >> "$output_path"
      continue
    fi

    counts="$(parse_log_signals "$log_path")"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$PUBLISH_WORKFLOW_FILE" "$run_id" "$conclusion" "$status" "ok" \
      "$(cut -f1 <<< "$counts")" \
      "$(cut -f2 <<< "$counts")" \
      "$(cut -f3 <<< "$counts")" \
      "$url" >> "$output_path"
  done < <(list_generated_sdk_repos)

  printf '%s\n' "$output_path"
}

render_briefing_text() {
  local settings_path="$1"
  local workflows_path="$2"
  local issues_path="$3"
  local signals_path="$4"
  local output_path="$5"

  python3 - <<'PY' "$settings_path" "$workflows_path" "$issues_path" "$signals_path" "$output_path"
import csv
import os
import re
import sys
from collections import Counter
from datetime import datetime

settings_path, workflows_path, issues_path, signals_path, output_path = sys.argv[1:]
signal_skip_ignore_regex = os.environ.get("TRYAGI_SIGNAL_SKIP_IGNORE_REGEX", "^(OpenAI)$")

def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))

settings = read_tsv(settings_path)
workflows = read_tsv(workflows_path)
issues = read_tsv(issues_path)
signals = read_tsv(signals_path)

repo_count = len(settings)
non_compliant = sum(
    1
    for row in settings
    if row["allow_auto_merge"] != "true"
    or row["delete_branch_on_merge"] != "true"
    or row["allow_update_branch"] != "true"
)

workflow_failures = [
    row for row in workflows
    if row["conclusion"] not in {"success", "no-runs", "missing-workflow", ""}
]

issue_counts = Counter(row["repo"] for row in issues if row["repo"])
total_issues = sum(issue_counts.values())
top_issue_repos = issue_counts.most_common(5)

def parse_dt(value):
    if not value:
        return datetime.min
    return datetime.fromisoformat(value.replace("Z", "+00:00"))

def effective_skipped_tests(row):
    raw_value = int(row["skipped_tests"] or 0)
    if raw_value == 0:
        return 0
    return 0 if re.search(signal_skip_ignore_regex, row["repo"] or "") else raw_value

def effective_inconclusive_hits(row):
    raw_value = int(row["inconclusive_hits"] or 0)
    if raw_value == 0:
        return 0
    return 0 if re.search(signal_skip_ignore_regex, row["repo"] or "") else raw_value

recent_issues = sorted(
    [row for row in issues if row["repo"]],
    key=lambda row: parse_dt(row["updated_at"]),
    reverse=True,
)[:8]

signal_rows = [
    row for row in signals
    if row["signal_status"] == "ok" and (
        int(row["warning_lines"] or 0) > 0
        or effective_skipped_tests(row) > 0
        or effective_inconclusive_hits(row) > 0
    )
]

lines = []
lines.append("Daily try A.G.I. generated S.D.K. briefing.")
lines.append(f"The audit covered {repo_count} generated S.D.K. repositories.")

if non_compliant == 0:
    lines.append("Repository settings are fully compliant for auto merge.")
else:
    lines.append(f"{non_compliant} repositories still have non compliant auto merge settings.")

if workflow_failures:
    lines.append(f"There are {len(workflow_failures)} latest workflow failures that still need attention.")
    for row in workflow_failures[:6]:
        lines.append(
            f"{row['repo']} has a failed {row['kind']} run."
        )
else:
    lines.append("Latest regeneration and publish runs are clean.")

if total_issues == 0:
    lines.append("There are no open issues in the generated S.D.K. repositories.")
else:
    lines.append(f"There are {total_issues} open issues across {len(issue_counts)} repositories.")
    if top_issue_repos:
        repo_bits = [f"{repo} with {count}" for repo, count in top_issue_repos]
        lines.append("The busiest issue queues are " + ", ".join(repo_bits) + ".")
    if recent_issues:
        lines.append("Most recently updated open issues are:")
        for row in recent_issues:
            lines.append(f"{row['repo']} issue {row['issue_number']}: {row['title']}.")

if signal_rows:
    lines.append("The latest completed publish logs also showed warning or skip signals.")
    for row in signal_rows[:8]:
        bits = []
        if int(row["warning_lines"] or 0) > 0:
            bits.append(f"{row['warning_lines']} warning lines")
        if effective_skipped_tests(row) > 0:
            bits.append(f"{effective_skipped_tests(row)} skipped tests")
        if effective_inconclusive_hits(row) > 0:
            bits.append(f"{effective_inconclusive_hits(row)} inconclusive hits")
        lines.append(f"{row['repo']} reported " + ", ".join(bits) + ".")
else:
    lines.append("No warning or skipped test signals were detected in the latest completed publish logs.")

lines.append("End of briefing.")

with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY
}

print_summary() {
  local settings_path="$1"
  local workflows_path="$2"
  local issues_path="${3:-}"
  local signals_path="${4:-}"
  local repo_count
  local settings_non_compliant
  local auto_update_failures
  local publish_failures

  repo_count="$(list_generated_sdk_repos | wc -l | tr -d ' ')"
  settings_non_compliant="$(
    awk -F '\t' 'NR > 1 && $1 != "" && ($2 != "true" || $3 != "true" || $4 != "true") { count++ } END { print count + 0 }' "$settings_path"
  )"
  auto_update_failures="$(
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 != "success" && $5 != "no-runs" && $5 != "missing-workflow" { count++ } END { print count + 0 }' "$workflows_path"
  )"
  publish_failures="$(
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 != "success" && $5 != "no-runs" && $5 != "missing-workflow" { count++ } END { print count + 0 }' "$workflows_path"
  )"

  printf 'Generated SDK repos: %s\n' "$repo_count"
  printf 'Non-compliant repo settings: %s\n' "$settings_non_compliant"
  printf 'Latest auto-update failures: %s\n' "$auto_update_failures"
  printf 'Latest publish failures: %s\n' "$publish_failures"
  printf 'Settings report: %s\n' "$settings_path"
  printf 'Workflow report: %s\n' "$workflows_path"

  if [[ -n "$issues_path" ]]; then
    printf 'Open issues report: %s\n' "$issues_path"
    printf 'Open issue count: %s\n' "$(awk -F '\t' 'NR > 1 && $1 != "" { count++ } END { print count + 0 }' "$issues_path")"
  fi

  if [[ -n "$signals_path" ]]; then
    printf 'Log signal report: %s\n' "$signals_path"
    printf 'Repos with warning / skip signals: %s\n' "$(
      awk -F '\t' -v ignore_regex="$SIGNAL_SKIP_IGNORE_REGEX" '
        NR > 1 && $6 == "ok" {
          warning_lines = $7 + 0
          skipped_tests = $8 + 0
          inconclusive_hits = $9 + 0
          if (ignore_regex != "" && $1 ~ ignore_regex) {
            skipped_tests = 0
            inconclusive_hits = 0
          }
          if (warning_lines > 0 || skipped_tests > 0 || inconclusive_hits > 0) {
            count++
          }
        }
        END { print count + 0 }
      ' "$signals_path"
    )"
  fi

  if [[ "$auto_update_failures" != "0" ]]; then
    echo
    echo "Latest auto-update failures:"
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 != "success" && $5 != "no-runs" && $5 != "missing-workflow" { printf "  %s\t%s\t%s\n", $1, $5, $9 }' "$workflows_path"
  fi

  if [[ "$publish_failures" != "0" ]]; then
    echo
    echo "Latest publish failures:"
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 != "success" && $5 != "no-runs" && $5 != "missing-workflow" { printf "  %s\t%s\t%s\n", $1, $5, $9 }' "$workflows_path"
  fi
}

main() {
  local settings_path
  local workflows_path
  local issues_path
  local signals_path
  local briefing_path

  require_command gh
  require_command jq
  require_command python3
  parse_args "$@"
  load_config

  case "$MODE" in
    repos)
      list_generated_sdk_repos
      ;;
    settings)
      write_settings_report
      ;;
    workflows)
      write_workflows_report
      ;;
    issues)
      write_issues_report
      ;;
    signals)
      write_signals_report
      ;;
    summary)
      settings_path="$(write_settings_report)"
      workflows_path="$(write_workflows_report)"
      print_summary "$settings_path" "$workflows_path"
      ;;
    briefing)
      settings_path="$(write_settings_report)"
      workflows_path="$(write_workflows_report)"
      issues_path="$(write_issues_report)"
      signals_path="$(write_signals_report)"
      briefing_path="$OUT_DIR/daily-briefing.txt"
      render_briefing_text "$settings_path" "$workflows_path" "$issues_path" "$signals_path" "$briefing_path"
      print_summary "$settings_path" "$workflows_path" "$issues_path" "$signals_path"
      printf 'Briefing text: %s\n' "$briefing_path"
      ;;
  esac
}

main "$@"
