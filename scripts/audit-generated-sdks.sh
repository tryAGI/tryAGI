#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ORG="${TRYAGI_ORG:-tryAGI}"
CONFIG_PATH="${TRYAGI_AUDIT_CONFIG_PATH:-$ROOT_DIR/config/generated-sdk-audit.json}"
OUT_DIR="${TRYAGI_AUDIT_OUT_DIR:-/tmp/tryagi-sdk-audit}"
AUDIT_ENV_FILE="${TRYAGI_AUDIT_ENV_FILE:-}"
ISSUE_LIMIT="${TRYAGI_ISSUE_LIMIT:-100}"
PULL_REQUEST_LIMIT="${TRYAGI_PULL_REQUEST_LIMIT:-1000}"
AUTO_UPDATE_WORKFLOW_FILE="${TRYAGI_AUTO_UPDATE_WORKFLOW_FILE:-auto-update.yml}"
PUBLISH_WORKFLOW_FILE="${TRYAGI_PUBLISH_WORKFLOW_FILE:-dotnet.yml}"
NEW_REPO_DAYS="${TRYAGI_NEW_REPO_DAYS:-7}"
SIGNAL_RUN_LIMIT="${TRYAGI_SIGNAL_RUN_LIMIT:-5}"
SIGNAL_SKIP_IGNORE_REGEX="${TRYAGI_SIGNAL_SKIP_IGNORE_REGEX:-^(OpenAI)$}"
GH_API_RETRIES="${TRYAGI_GH_API_RETRIES:-3}"
GH_API_RETRY_DELAY_SECONDS="${TRYAGI_GH_API_RETRY_DELAY_SECONDS:-2}"
SYNC_MAX_AGE_SECONDS="${TRYAGI_SYNC_MAX_AGE_SECONDS:-21600}"
MODE="summary"
REPO_FILTER=""

usage() {
  cat <<'EOF'
Usage: ./scripts/audit-generated-sdks.sh [sync|summary|settings|workflows|issues|pull-requests|signals|visibility|representations|briefing|repos|local-builds|local-trims|local-smoke] [--repo REGEX] [--out-dir PATH] [--config PATH]

Modes:
  sync       Fetch origin/main, safely fast-forward clean main checkouts, and verify workspace hygiene.
  summary    Write settings + workflow TSV reports and print a short summary.
  settings   Write generated-sdk-settings.tsv with auto-merge, bootstrap, and dependency-policy settings.
  workflows  Write generated-sdk-workflows.tsv with latest auto-update and Publish runs.
  issues     Write generated-sdk-open-issues.tsv with open issues for generated SDK repos.
  pull-requests Write workspace-open-pull-requests.tsv with every open PR in the GitHub organization.
  signals    Write generated-sdk-log-signals.tsv by scanning the latest completed Publish logs.
  visibility Audit configured operations that must remain public in normalized OpenAPI specs.
  representations Audit OpenAPI media representations and write generated-sdk-representations.tsv.
  briefing   Write all reports plus daily-briefing.txt.
  repos      Print the generated SDK repos detected in the current workspace.
  local-builds Build each detected generated SDK solution locally and write generated-sdk-local-builds.tsv.
  local-trims Run autosdk trim for each detected generated SDK project and write generated-sdk-local-trims.tsv.
  local-smoke Run explicitly allowlisted local/container tests that cannot consume paid API credits.

Options:
  --repo REGEX   Only include repo names matching the regular expression.
  --out-dir PATH Override the output directory. Default: /tmp/tryagi-sdk-audit
  --config PATH  Override the audit config file. Default: config/generated-sdk-audit.json

Environment:
  TRYAGI_AUDIT_ENV_FILE            Optional env file to source before running the audit.
  TRYAGI_AUDIT_CONFIG_PATH         Override the audit config file path.
  TRYAGI_AUTO_UPDATE_WORKFLOW_FILE Override the auto-update workflow file. Default: auto-update.yml
  TRYAGI_PUBLISH_WORKFLOW_FILE     Override the publish workflow file. Default: dotnet.yml
  TRYAGI_PULL_REQUEST_LIMIT        Maximum organization-wide open PRs to collect. Default: 1000
  TRYAGI_NEW_REPO_DAYS             Repo age threshold for classifying no-runs as onboarding gaps. Default: 7
  TRYAGI_SIGNAL_RUN_LIMIT           How many recent Publish runs to inspect when finding the latest completed run. Default: 5
  TRYAGI_SIGNAL_SKIP_IGNORE_REGEX   Regex for repos whose skipped/inconclusive test counts should be ignored in summaries. Default: ^(OpenAI)$
  TRYAGI_GH_API_RETRIES             How many times to retry transient GitHub API calls. Default: 3
  TRYAGI_GH_API_RETRY_DELAY_SECONDS Delay between GitHub API retry attempts. Default: 2
  TRYAGI_SYNC_MAX_AGE_SECONDS       Maximum accepted age for a sync snapshot. Default: 21600 (6 hours)
EOF
}

require_command() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Missing required command: $name" >&2
    exit 1
  fi
}

load_env_file() {
  local env_path="$1"

  [[ -n "$env_path" ]] || return 0
  [[ -f "$env_path" ]] || return 0

  set -a
  # shellcheck disable=SC1090
  source "$env_path"
  set +a
}

ensure_codex_home() {
  if [[ -n "${CODEX_HOME:-}" ]]; then
    return
  fi

  if [[ -n "${HOME:-}" ]]; then
    export CODEX_HOME="${HOME%/}/.codex"
  fi
}

load_automation_env() {
  ensure_codex_home

  if [[ -n "$AUDIT_ENV_FILE" ]]; then
    load_env_file "$AUDIT_ENV_FILE"
    return
  fi

  load_env_file "$ROOT_DIR/.env.audit"
  load_env_file "$ROOT_DIR/.env"
}

apply_env_overrides() {
  ORG="${TRYAGI_ORG:-$ORG}"
  CONFIG_PATH="${TRYAGI_AUDIT_CONFIG_PATH:-$CONFIG_PATH}"
  OUT_DIR="${TRYAGI_AUDIT_OUT_DIR:-$OUT_DIR}"
  ISSUE_LIMIT="${TRYAGI_ISSUE_LIMIT:-$ISSUE_LIMIT}"
  PULL_REQUEST_LIMIT="${TRYAGI_PULL_REQUEST_LIMIT:-$PULL_REQUEST_LIMIT}"
  AUTO_UPDATE_WORKFLOW_FILE="${TRYAGI_AUTO_UPDATE_WORKFLOW_FILE:-$AUTO_UPDATE_WORKFLOW_FILE}"
  PUBLISH_WORKFLOW_FILE="${TRYAGI_PUBLISH_WORKFLOW_FILE:-$PUBLISH_WORKFLOW_FILE}"
  NEW_REPO_DAYS="${TRYAGI_NEW_REPO_DAYS:-$NEW_REPO_DAYS}"
  SIGNAL_RUN_LIMIT="${TRYAGI_SIGNAL_RUN_LIMIT:-$SIGNAL_RUN_LIMIT}"
  SIGNAL_SKIP_IGNORE_REGEX="${TRYAGI_SIGNAL_SKIP_IGNORE_REGEX:-$SIGNAL_SKIP_IGNORE_REGEX}"
  GH_API_RETRIES="${TRYAGI_GH_API_RETRIES:-$GH_API_RETRIES}"
  GH_API_RETRY_DELAY_SECONDS="${TRYAGI_GH_API_RETRY_DELAY_SECONDS:-$GH_API_RETRY_DELAY_SECONDS}"
  SYNC_MAX_AGE_SECONDS="${TRYAGI_SYNC_MAX_AGE_SECONDS:-$SYNC_MAX_AGE_SECONDS}"
}

gh_api_with_retries() {
  local attempt=1
  local response

  while (( attempt <= GH_API_RETRIES )); do
    if response="$(gh api "$@" 2>/dev/null)"; then
      printf '%s\n' "$response"
      return 0
    fi

    if (( attempt < GH_API_RETRIES )); then
      sleep "$GH_API_RETRY_DELAY_SECONDS"
    fi

    ((attempt++))
  done

  return 1
}

require_github_auth() {
  if gh auth status >/dev/null 2>&1; then
    return
  fi

  cat >&2 <<EOF
GitHub CLI authentication is unavailable for this audit run.
The audit requires either:
  - a working 'gh auth login' session in this execution context, or
  - a token such as GH_TOKEN provided via the environment or an env file.

For scheduled automations, do not rely on an interactive login shell implicitly loading .env.
Prefer setting TRYAGI_AUDIT_ENV_FILE to a file that exports GH_TOKEN, or make sure the automation
can access the same authenticated gh context as your interactive session.
EOF
  exit 1
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      sync|summary|settings|workflows|issues|pull-requests|signals|visibility|representations|briefing|repos|local-builds|local-trims|local-smoke)
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

list_workspace_repos() {
  printf '.\n'
  find "$ROOT_DIR" -mindepth 2 -maxdepth 2 -type d -name .git -print \
    | sed -e "s#^$ROOT_DIR/##" -e 's#/.git$##' \
    | sort
}

tracked_environment_files() {
  local repo="$1"
  local repo_dir="$ROOT_DIR"

  if [[ "$repo" != "." ]]; then
    repo_dir="$ROOT_DIR/$repo"
  fi

  git -C "$repo_dir" ls-files | python3 -c '
import os
import sys

safe_templates = {".env.example", ".env.sample", ".env.template"}
for line in sys.stdin:
    path = line.rstrip("\n")
    name = os.path.basename(path)
    if name in safe_templates:
        continue
    if name == ".env" or name.startswith(".env.") or name.endswith(".env"):
        print(path)
'
}

workspace_publication_exception_reason() {
  local repo="$1"
  local exception_kind="$2"
  local config_key

  case "$exception_kind" in
    ahead)
      config_key="allowed_ahead_repositories"
      ;;
    no-upstream)
      config_key="allowed_no_upstream_repositories"
      ;;
    *)
      return 1
      ;;
  esac

  jq -r --arg repo "$repo" --arg config_key "$config_key" '
    .workspace[$config_key][]? | select(.repo == $repo) | .reason
  ' "$CONFIG_PATH" | sed -n '1p'
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

try_fast_forward_upstream_equivalent_dirty_checkout() {
  local repo_dir="$1"
  local target_ref="$2"
  local log_path="$3"
  local path
  local -a modified_paths=()

  # This recovery is deliberately narrow. Staged or untracked work may carry
  # intent that cannot be proven from the fetched target and must remain a
  # blocker for manual inspection.
  if ! git -C "$repo_dir" diff --cached --quiet --exit-code; then
    return 1
  fi
  if [[ -n "$(git -C "$repo_dir" ls-files --others --exclude-standard)" ]]; then
    return 1
  fi

  while IFS= read -r -d '' path; do
    modified_paths+=("$path")
  done < <(git -C "$repo_dir" diff --name-only -z)
  if [[ "${#modified_paths[@]}" == "0" ]]; then
    return 1
  fi

  # Compare each locally modified path with the fetched tree. Remote-only
  # changes elsewhere are expected and will be applied by the fast-forward.
  for path in "${modified_paths[@]}"; do
    if ! git -C "$repo_dir" diff --quiet --no-ext-diff "$target_ref" -- "$path"; then
      return 1
    fi
  done

  # Git refuses an ordinary fast-forward when equivalent target content is
  # merely unstaged. Temporarily staging those exact paths lets Git prove and
  # consume the equivalence without a preservation commit or history rewrite.
  git -C "$repo_dir" add -- "${modified_paths[@]}"
  if git -C "$repo_dir" merge --ff-only "$target_ref" >> "$log_path" 2>&1; then
    return 0
  fi

  # Restore the original unstaged/index shape if an unexpected merge failure
  # occurs. The worktree content is never changed by this rollback.
  if ! git -C "$repo_dir" diff --cached --binary HEAD -- "${modified_paths[@]}" |
      git -C "$repo_dir" apply --cached --reverse; then
    echo "failed to restore the index after equivalent-dirty fast-forward failure" >> "$log_path"
  fi
  return 1
}

write_sync_report() {
  local output_path="$OUT_DIR/generated-sdk-sync.tsv"
  local log_dir="$OUT_DIR/sync-logs"
  local local_targets_path="$OUT_DIR/.generated-sdk-local-api-targets.txt"
  local remote_candidates_path="$OUT_DIR/.generated-sdk-remote-autosdk-repos.tsv"
  local repo
  local repo_dir
  local api_target
  local canonical_target
  local branch
  local dirty
  local head_before
  local origin_main
  local head_after
  local ahead
  local behind
  local status
  local action
  local details
  local fetched_at
  local log_path
  local remote_name
  local remote_target
  local default_branch
  local tree_json

  mkdir -p "$OUT_DIR" "$log_dir"
  : > "$local_targets_path"
  printf 'repo\tapi_target\tlocal_path\tstatus\taction\tbranch\tdirty\thead_before\torigin_main\thead_after\tahead\tbehind\tfetched_at\tdetails\n' > "$output_path"

  while IFS= read -r repo; do
    repo_dir="$ROOT_DIR/$repo"
    api_target="$(repo_api_target "$repo")"
    canonical_target="$(gh_api_with_retries "repos/$api_target" --jq '.full_name // empty' || true)"
    if [[ -n "$canonical_target" ]]; then
      api_target="$canonical_target"
    fi
    printf '%s\n' "$api_target" >> "$local_targets_path"
    log_path="$log_dir/$repo.log"
    branch="$(git -C "$repo_dir" symbolic-ref --short -q HEAD 2>/dev/null || printf 'detached')"
    dirty="false"
    if [[ -n "$(git -C "$repo_dir" status --porcelain 2>/dev/null)" ]]; then
      dirty="true"
    fi
    head_before="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    origin_main=""
    head_after="$head_before"
    ahead=""
    behind=""
    status="fetch-failed"
    action="none"
    details=""

    if git -C "$repo_dir" fetch --prune origin main > "$log_path" 2>&1; then
      action="fetched"
      origin_main="$(git -C "$repo_dir" rev-parse --verify refs/remotes/origin/main 2>/dev/null || true)"
      if [[ -z "$origin_main" ]]; then
        status="missing-origin-main"
        details="fetch completed but refs/remotes/origin/main is missing"
      else
        read -r ahead behind <<< "$(git -C "$repo_dir" rev-list --left-right --count HEAD...refs/remotes/origin/main)"
        if [[ "$dirty" == "true" ]]; then
          if [[ "$branch" == "main" && "$ahead" == "0" && "$behind" != "0" ]] &&
              try_fast_forward_upstream_equivalent_dirty_checkout \
                "$repo_dir" refs/remotes/origin/main "$log_path"; then
            status="fast-forwarded"
            action="staged-equivalent-and-fast-forwarded"
            details="modified tracked paths already matched origin/main; fast-forwarded without creating a preservation commit"
            head_after="$(git -C "$repo_dir" rev-parse HEAD)"
            ahead="0"
            behind="0"
          else
            status="dirty"
            details="working tree has local changes not proven equivalent to origin/main; no fast-forward attempted"
          fi
        elif [[ "$branch" != "main" ]]; then
          status="wrong-branch"
          details="checkout is not on main; no fast-forward attempted"
        elif [[ "$ahead" != "0" && "$behind" != "0" ]]; then
          status="diverged"
          details="main and origin/main have diverged; no history rewrite attempted"
        elif [[ "$ahead" != "0" ]]; then
          status="ahead"
          details="local main contains commits not present on origin/main"
        elif [[ "$behind" != "0" ]]; then
          if git -C "$repo_dir" merge --ff-only refs/remotes/origin/main >> "$log_path" 2>&1; then
            status="fast-forwarded"
            action="fast-forwarded"
            head_after="$(git -C "$repo_dir" rev-parse HEAD)"
            ahead="0"
            behind="0"
          else
            status="fast-forward-failed"
            details="clean main could not be fast-forwarded; inspect the sync log"
          fi
        else
          status="current"
        fi
      fi
    else
      details="git fetch --prune origin main failed; inspect the sync log"
    fi

    head_after="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null || true)"
    fetched_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$api_target" "$repo" "$status" "$action" "$branch" "$dirty" \
      "$head_before" "$origin_main" "$head_after" "$ahead" "$behind" "$fetched_at" "$details" >> "$output_path"
  done < <(list_generated_sdk_repos)

  sort -u -o "$local_targets_path" "$local_targets_path"
  if gh api --paginate "orgs/$ORG/repos?per_page=100&type=all" \
      --jq '.[] | select((.archived | not) and (.topics | index("autosdk"))) | [.name, .full_name, .default_branch] | @tsv' \
      > "$remote_candidates_path" 2> "$log_dir/remote-inventory.log"; then
    while IFS=$'\t' read -r remote_name remote_target default_branch; do
      if [[ -n "$REPO_FILTER" ]] && ! [[ "$remote_name" =~ $REPO_FILTER ]]; then
        continue
      fi
      if grep -Fqx "$remote_target" "$local_targets_path"; then
        continue
      fi

      if ! tree_json="$(gh_api_with_retries "repos/$remote_target/git/trees/$default_branch?recursive=1")"; then
        printf '%s\t%s\t\tremote-inventory-error\tnone\t\t\t\t\t\t\t\t%s\t%s\n' \
          "$remote_name" "$remote_target" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          "could not inspect remote repository tree" >> "$output_path"
        continue
      fi

      if jq -e 'any(.tree[]?; (.path // "") | test("^src/libs/[^/]+/generate\\.sh$"))' \
          <<< "$tree_json" >/dev/null; then
        printf '%s\t%s\t\tmissing-local\tnone\t%s\t\t\t\t\t\t\t%s\t%s\n' \
          "$remote_name" "$remote_target" "$default_branch" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          "remote AutoSDK repository contains generate.sh but has no local checkout" >> "$output_path"
      fi
    done < "$remote_candidates_path"
  else
    printf '%s\t%s\t\tremote-inventory-failed\tnone\t\t\t\t\t\t\t\t%s\t%s\n' \
      "__inventory__" "$ORG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      "failed to list organization AutoSDK repositories" >> "$output_path"
  fi

  printf '%s\n' "$output_path"
}

write_workspace_hygiene_report() {
  local output_path="$OUT_DIR/workspace-repository-hygiene.tsv"
  local repo
  local repo_dir
  local branch
  local dirty_count
  local staged_count
  local tracked_env_files
  local upstream
  local ahead
  local behind
  local publication_status
  local publication_details
  local exception_reason
  local status
  local details

  mkdir -p "$OUT_DIR"
  printf 'repo\tbranch\tdirty_paths\tstaged_paths\ttracked_environment_files\tstatus\tdetails\tupstream\tahead\tbehind\tpublication_status\tpublication_details\n' > "$output_path"

  while IFS= read -r repo; do
    repo_dir="$ROOT_DIR"
    if [[ "$repo" != "." ]]; then
      repo_dir="$ROOT_DIR/$repo"
    fi

    branch="$(git -C "$repo_dir" symbolic-ref --short -q HEAD 2>/dev/null || printf 'detached')"
    dirty_count="$(git -C "$repo_dir" status --porcelain | awk 'END { print NR + 0 }')"
    staged_count="$(git -C "$repo_dir" diff --cached --name-only | awk 'END { print NR + 0 }')"
    tracked_env_files="$(tracked_environment_files "$repo" | paste -sd ',' -)"
    upstream="$(git -C "$repo_dir" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
    ahead=""
    behind=""
    publication_status="published"
    publication_details=""
    exception_reason=""

    if [[ -z "$upstream" ]]; then
      exception_reason="$(workspace_publication_exception_reason "$repo" "no-upstream")"
      if [[ -n "$exception_reason" ]]; then
        publication_status="allowed-no-upstream"
        publication_details="$exception_reason"
      else
        publication_status="no-upstream"
        publication_details="repository has no configured upstream branch"
      fi
    else
      read -r ahead behind <<< "$(git -C "$repo_dir" rev-list --left-right --count HEAD..."$upstream")"
      if [[ "$ahead" != "0" && "$behind" != "0" ]]; then
        publication_status="diverged"
        publication_details="local branch and upstream have diverged"
      elif [[ "$ahead" != "0" ]]; then
        exception_reason="$(workspace_publication_exception_reason "$repo" "ahead")"
        if [[ -n "$exception_reason" ]]; then
          publication_status="allowed-ahead"
          publication_details="$exception_reason"
        else
          publication_status="unpublished-commits"
          publication_details="local branch contains commits absent from upstream"
        fi
      elif [[ "$behind" != "0" ]]; then
        publication_status="behind-upstream"
        publication_details="local branch is behind its upstream tracking branch"
      fi
    fi

    status="clean"
    details=""

    if [[ -n "$tracked_env_files" ]]; then
      status="tracked-environment-file"
      details="tracked secret-bearing environment filenames are forbidden; templates such as .env.example are allowed"
    elif [[ "$dirty_count" != "0" ]]; then
      status="dirty"
      details="working tree contains staged, modified, or untracked paths"
    elif [[ "$branch" == "detached" ]]; then
      status="detached"
      details="repository is not on a named branch"
    elif [[ "$publication_status" == "no-upstream" ||
            "$publication_status" == "unpublished-commits" ||
            "$publication_status" == "behind-upstream" ||
            "$publication_status" == "diverged" ]]; then
      status="$publication_status"
      details="$publication_details"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$branch" "$dirty_count" "$staged_count" "$tracked_env_files" "$status" "$details" \
      "$upstream" "$ahead" "$behind" "$publication_status" "$publication_details" >> "$output_path"
  done < <(list_workspace_repos)

  printf '%s\n' "$output_path"
}

workspace_hygiene_has_failures() {
  local hygiene_path="$1"

  awk -F '\t' 'NR > 1 && $6 != "clean" { found = 1 } END { exit found ? 0 : 1 }' "$hygiene_path"
}

print_workspace_hygiene_summary() {
  local hygiene_path="$1"

  printf 'Workspace hygiene report: %s\n' "$hygiene_path"
  printf 'Clean repositories: %s\n' "$(awk -F '\t' 'NR > 1 && $6 == "clean" { count++ } END { print count + 0 }' "$hygiene_path")"
  printf 'Repositories requiring attention: %s\n' "$(awk -F '\t' 'NR > 1 && $6 != "clean" { count++ } END { print count + 0 }' "$hygiene_path")"
  printf 'Allowed publication exceptions: %s\n' "$(awk -F '\t' 'NR > 1 && $11 ~ /^allowed-/ { count++ } END { print count + 0 }' "$hygiene_path")"

  if workspace_hygiene_has_failures "$hygiene_path"; then
    awk -F '\t' 'NR > 1 && $6 != "clean" { printf "  %s\t%s\t%s\n", $1, $6, $7 }' "$hygiene_path"
  fi

  awk -F '\t' 'NR > 1 && $11 ~ /^allowed-/ { printf "  %s\t%s\t%s\n", $1, $11, $12 }' "$hygiene_path"
}

sync_report_has_failures() {
  local sync_path="$1"

  awk -F '\t' '
    NR > 1 && $4 != "current" && $4 != "fast-forwarded" { found = 1 }
    END { exit found ? 0 : 1 }
  ' "$sync_path"
}

print_sync_summary() {
  local sync_path="$1"

  printf 'Repository sync report: %s\n' "$sync_path"
  printf 'Current repositories: %s\n' "$({ awk -F '\t' 'NR > 1 && $4 == "current" { count++ } END { print count + 0 }' "$sync_path"; })"
  printf 'Fast-forwarded repositories: %s\n' "$({ awk -F '\t' 'NR > 1 && $4 == "fast-forwarded" { count++ } END { print count + 0 }' "$sync_path"; })"
  printf 'Unsynchronized repositories: %s\n' "$({ awk -F '\t' 'NR > 1 && $4 != "current" && $4 != "fast-forwarded" { count++ } END { print count + 0 }' "$sync_path"; })"

  if sync_report_has_failures "$sync_path"; then
    echo
    echo "Repositories requiring attention:"
    awk -F '\t' '
      NR > 1 && $4 != "current" && $4 != "fast-forwarded" {
        printf "  %s\t%s\t%s\n", $1, $4, $14
      }
    ' "$sync_path"
  fi
}

require_ready_sync_report() {
  local sync_path="$OUT_DIR/generated-sdk-sync.tsv"
  local hygiene_path="$OUT_DIR/workspace-repository-hygiene.tsv"
  local repo
  local repo_dir
  local row
  local status
  local recorded_head
  local current_head

  if [[ ! -f "$sync_path" ]]; then
    echo "Missing repository sync report: $sync_path" >&2
    echo "Run './scripts/audit-generated-sdks.sh sync' before audit checks." >&2
    exit 1
  fi

  if ! python3 - <<'PY' "$sync_path" "$SYNC_MAX_AGE_SECONDS"
import os
import sys
import time

path, max_age = sys.argv[1:]
age = time.time() - os.path.getmtime(path)
raise SystemExit(0 if age <= int(max_age) else 1)
PY
  then
    echo "Repository sync report is older than $SYNC_MAX_AGE_SECONDS seconds: $sync_path" >&2
    echo "Run './scripts/audit-generated-sdks.sh sync' again." >&2
    exit 1
  fi

  if sync_report_has_failures "$sync_path"; then
    echo "Repository sync report contains unsafe or missing checkouts: $sync_path" >&2
    print_sync_summary "$sync_path" >&2
    exit 1
  fi

  write_workspace_hygiene_report >/dev/null
  if workspace_hygiene_has_failures "$hygiene_path"; then
    echo "Workspace repository hygiene is missing or contains blockers: $hygiene_path" >&2
    [[ ! -f "$hygiene_path" ]] || print_workspace_hygiene_summary "$hygiene_path" >&2
    exit 1
  fi

  while IFS= read -r repo; do
    repo_dir="$ROOT_DIR"
    if [[ "$repo" != "." ]]; then
      repo_dir="$ROOT_DIR/$repo"
    fi
    if [[ -n "$(git -C "$repo_dir" status --porcelain)" ]]; then
      echo "Workspace repository $repo became dirty after the sync snapshot." >&2
      exit 1
    fi
    if [[ -n "$(tracked_environment_files "$repo")" ]]; then
      echo "Workspace repository $repo tracks a forbidden environment file." >&2
      exit 1
    fi
  done < <(list_workspace_repos)

  while IFS= read -r repo; do
    row="$(awk -F '\t' -v repo="$repo" 'NR > 1 && $1 == repo { print; exit }' "$sync_path")"
    if [[ -z "$row" ]]; then
      echo "Repository $repo is absent from the current sync snapshot." >&2
      exit 1
    fi
    status="$(cut -f4 <<< "$row")"
    recorded_head="$(cut -f10 <<< "$row")"
    current_head="$(git -C "$ROOT_DIR/$repo" rev-parse HEAD 2>/dev/null || true)"
    if [[ "$status" != "current" && "$status" != "fast-forwarded" ]]; then
      echo "Repository $repo is not synchronized: $status" >&2
      exit 1
    fi
    if [[ "$recorded_head" != "$current_head" ]]; then
      echo "Repository $repo changed after the sync snapshot." >&2
      exit 1
    fi
    if [[ "$(git -C "$ROOT_DIR/$repo" symbolic-ref --short -q HEAD 2>/dev/null || true)" != "main" ]]; then
      echo "Repository $repo is no longer on main." >&2
      exit 1
    fi
    if [[ -n "$(git -C "$ROOT_DIR/$repo" status --porcelain 2>/dev/null)" ]]; then
      echo "Repository $repo became dirty after the sync snapshot." >&2
      exit 1
    fi
  done < <(list_generated_sdk_repos)
}

latest_run_json() {
  local repo="$1"
  local workflow_file="$2"
  local limit="${3:-1}"
  local api_target
  local response

  api_target="$(repo_api_target "$repo")"

  if ! response="$(gh_api_with_retries "repos/$api_target/actions/workflows/$workflow_file/runs?per_page=$limit")"; then
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

repo_created_at() {
  local repo="$1"
  local api_target
  local cache_dir="$OUT_DIR/.cache"
  local cache_path="$cache_dir/repo-created-at-$repo.txt"

  mkdir -p "$cache_dir"

  if [[ ! -f "$cache_path" ]]; then
    api_target="$(repo_api_target "$repo")"
    if ! gh_api_with_retries "repos/$api_target" --jq '.created_at // ""' > "$cache_path"; then
      rm -f "$cache_path"
      return 1
    fi
  fi

  cat "$cache_path"
}

repo_age_days() {
  local created_at="$1"

  [[ -n "$created_at" ]] || return 1

  python3 - <<'PY' "$created_at"
from datetime import datetime, timezone
import sys

created_at = sys.argv[1]
created_dt = datetime.fromisoformat(created_at.replace("Z", "+00:00"))
age_days = (datetime.now(timezone.utc) - created_dt).total_seconds() / 86400
print(f"{age_days:.2f}")
PY
}

repo_is_new() {
  local repo="$1"
  local created_at="${2:-}"
  local age_days

  if [[ -z "$created_at" ]]; then
    created_at="$(repo_created_at "$repo" 2>/dev/null || true)"
  fi
  [[ -n "$created_at" ]] || return 1

  age_days="$(repo_age_days "$created_at" 2>/dev/null || true)"
  [[ -n "$age_days" ]] || return 1

  python3 - <<'PY' "$age_days" "$NEW_REPO_DAYS"
import sys

age_days, max_age_days = sys.argv[1:]

try:
    age_days = float(age_days)
    max_age_days = float(max_age_days)
except ValueError:
    raise SystemExit(1)

raise SystemExit(0 if age_days <= max_age_days else 1)
PY
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

  if [[ -z "${TRYAGI_NEW_REPO_DAYS+x}" ]]; then
    value="$(config_value '.workflows.new_repo_days')"
    if [[ -n "$value" ]]; then
      NEW_REPO_DAYS="$value"
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

resolve_report_path() {
  local explicit_path="$1"
  local filename="$2"
  local candidate_path

  if [[ -n "$explicit_path" ]]; then
    printf '%s\n' "$explicit_path"
    return
  fi

  candidate_path="$OUT_DIR/$filename"
  if [[ -f "$candidate_path" ]]; then
    printf '%s\n' "$candidate_path"
  fi
}

repo_autosdk_bootstrap_info() {
  local repo="$1"

  python3 - <<'PY' "$ROOT_DIR" "$repo"
from pathlib import Path
import re
import sys

root_dir, repo = sys.argv[1:]
repo_dir = Path(root_dir) / repo
scripts = sorted(repo_dir.glob("src/libs/*/generate.sh"))

if not scripts:
    print("missing-generate-script\t")
    raise SystemExit(0)

pattern = re.compile(
    r"dotnet\s+tool\s+(install|update)\s+--global\s+autosdk\.cli\b",
    re.IGNORECASE | re.DOTALL,
)
missing = []

for script in scripts:
    text = script.read_text(encoding="utf-8", errors="replace")
    if not pattern.search(text):
        missing.append(str(script.relative_to(repo_dir)))

status = "ok" if not missing else "missing-bootstrap"
details = ",".join(missing)
print(f"{status}\t{details}")
PY
}

repo_dependabot_nuget_info() {
  local repo="$1"

  python3 - <<'PY' "$ROOT_DIR" "$repo"
from pathlib import Path
import re
import sys

root_dir, repo = sys.argv[1:]
config_path = Path(root_dir) / repo / ".github" / "dependabot.yml"
if not config_path.is_file():
    print("missing-config\t.github/dependabot.yml")
    raise SystemExit(0)

text = config_path.read_text(encoding="utf-8", errors="replace")
sections = re.split(r"(?m)^\s*-\s*package-ecosystem\s*:", text)
nuget_section = next(
    (section for section in sections[1:] if re.match(r"\s*['\"]?nuget['\"]?", section)),
    None,
)
if nuget_section is None:
    print("missing-nuget\tNuGet update entry is missing")
elif not re.search(r"(?m)^\s*interval\s*:\s*['\"]?weekly['\"]?\s*(?:#.*)?$", nuget_section):
    print("not-weekly\tNuGet updates must run weekly")
elif not re.search(r"(?m)^\s*-\s*['\"]?\*['\"]?\s*(?:#.*)?$", nuget_section):
    print("not-grouped-all\tNuGet dependency group must include *")
else:
    print("ok\t")
PY
}

write_settings_report() {
  local output_path="$OUT_DIR/generated-sdk-settings.tsv"
  local repo
  local api_target
  local settings_row
  local bootstrap_info
  local bootstrap_status
  local bootstrap_details
  local dependabot_info
  local dependabot_status
  local dependabot_details

  mkdir -p "$OUT_DIR"
  printf 'repo\tallow_auto_merge\tdelete_branch_on_merge\tallow_update_branch\tautosdk_bootstrap_status\tautosdk_bootstrap_details\tdependabot_nuget_status\tdependabot_nuget_details\n' > "$output_path"

  while IFS= read -r repo; do
    api_target="$(repo_api_target "$repo")"
    bootstrap_info="$(repo_autosdk_bootstrap_info "$repo")"
    bootstrap_status="$(cut -f1 <<< "$bootstrap_info")"
    bootstrap_details="$(cut -f2- <<< "$bootstrap_info")"
    dependabot_info="$(repo_dependabot_nuget_info "$repo")"
    dependabot_status="$(cut -f1 <<< "$dependabot_info")"
    dependabot_details="$(cut -f2- <<< "$dependabot_info")"

    if settings_row="$(gh_api_with_retries "repos/$api_target" --jq '[.name, .allow_auto_merge, .delete_branch_on_merge, .allow_update_branch] | @tsv')"; then
      printf '%s\t%s\t%s\t%s\t%s\n' "$settings_row" "$bootstrap_status" "$bootstrap_details" "$dependabot_status" "$dependabot_details" >> "$output_path"
    else
      printf '%s\tunknown\tunknown\tunknown\t%s\t%s\t%s\t%s\n' "$repo" "$bootstrap_status" "$bootstrap_details" "$dependabot_status" "$dependabot_details" >> "$output_path"
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
  local no_run_conclusion="no-runs"
  local repo_created_at_value=""
  local repo_age_days_value=""

  if [[ ! -f "$workflow_path" ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$kind" "$workflow_file" "" "missing-workflow" "" "" "" "" "" ""
    return
  fi

  if ! run_json="$(latest_run_json "$repo" "$workflow_file")"; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$kind" "$workflow_file" "" "api-error" "" "" "" "" "" ""
    return
  fi

  if [[ "$(jq 'length' <<< "$run_json")" == "0" ]]; then
    repo_created_at_value="$(repo_created_at "$repo" 2>/dev/null || true)"
    if [[ -n "$repo_created_at_value" ]]; then
      repo_age_days_value="$(repo_age_days "$repo_created_at_value" 2>/dev/null || true)"
    fi

    if repo_is_new "$repo" "$repo_created_at_value"; then
      no_run_conclusion="new-repo-no-runs"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$kind" "$workflow_file" "" "$no_run_conclusion" "" "" "" "" "$repo_created_at_value" "$repo_age_days_value"
    return
  fi

  jq -r \
    --arg repo "$repo" \
    --arg kind "$kind" \
    --arg workflow_file "$workflow_file" \
    --arg repo_created_at_value "$repo_created_at_value" \
    --arg repo_age_days_value "$repo_age_days_value" \
    '
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
        (.url // ""),
        $repo_created_at_value,
        $repo_age_days_value
      ] | @tsv
    ' <<< "$run_json"
}

write_workflows_report() {
  local output_path="$OUT_DIR/generated-sdk-workflows.tsv"
  local repo

  mkdir -p "$OUT_DIR"
  printf 'repo\tkind\tworkflow_file\trun_id\tconclusion\tstatus\tcreated_at\thead_branch\turl\trepo_created_at\trepo_age_days\n' > "$output_path"

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
  printf 'repo\tissue_number\tuntrusted_external_title\tupdated_at\tlabels\turl\n' > "$output_path"

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

write_pull_requests_report() {
  local output_path="$OUT_DIR/workspace-open-pull-requests.tsv"
  local generated_repos_json
  local pull_requests_json

  mkdir -p "$OUT_DIR"
  printf 'repository\trepo\tpull_request_number\tgenerated_sdk\tauthor\tauthor_association\tsource_kind\tis_draft\tcreated_at\tupdated_at\tlabels\tuntrusted_external_title\turl\n' > "$output_path"

  generated_repos_json="$(list_generated_sdk_repos | jq -R -s 'split("\n") | map(select(length > 0))')"
  pull_requests_json="$(gh search prs \
    --owner "$ORG" \
    --state open \
    --limit "$PULL_REQUEST_LIMIT" \
    --json number,title,repository,author,authorAssociation,isDraft,createdAt,updatedAt,url,labels)"

  jq -r \
    --argjson generated_repos "$generated_repos_json" \
    '
      sort_by(.repository.nameWithOwner, .number)[] |
      (.repository.nameWithOwner // "") as $repository |
      ($repository | split("/") | last) as $repo |
      (.author.login // "") as $author |
      [
        $repository,
        $repo,
        (.number | tostring),
        (if $generated_repos | index($repo) then "true" else "false" end),
        $author,
        (.authorAssociation // ""),
        (if ((.author.is_bot // false) or ($author | test("\\[bot\\]$"))) then "automation" else "human" end),
        (.isDraft | tostring),
        (.createdAt // ""),
        (.updatedAt // ""),
        ((.labels // []) | map(.name) | join(",")),
        (.title // ""),
        (.url // "")
      ] | @tsv
    ' <<< "$pull_requests_json" >> "$output_path"

  printf '%s\n' "$output_path"
}

fetch_run_log() {
  local repo="$1"
  local run_id="$2"
  local api_target
  local log_dir="$OUT_DIR/logs"
  local cache_dir="$OUT_DIR/.cache"
  local log_path="$log_dir/$repo-$run_id.log"

  mkdir -p "$log_dir" "$cache_dir"
  api_target="$(repo_api_target "$repo")"

  if [[ ! -f "$log_path" ]]; then
    if ! XDG_CACHE_HOME="$cache_dir" gh run view "$run_id" --repo "$api_target" --log > "$log_path" 2>/dev/null; then
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

find_solution_path() {
  local repo="$1"
  local repo_dir="$ROOT_DIR/$repo"
  local solution_path

  solution_path="$(find "$repo_dir" -maxdepth 1 -type f -name '*.slnx' -print | sort | head -n 1)"
  if [[ -n "$solution_path" ]]; then
    printf '%s\n' "$solution_path"
    return
  fi

  solution_path="$(find "$repo_dir" -maxdepth 1 -type f -name '*.sln' -print | sort | head -n 1)"
  if [[ -n "$solution_path" ]]; then
    printf '%s\n' "$solution_path"
  fi
}

find_generated_project_paths() {
  local repo="$1"
  local repo_dir="$ROOT_DIR/$repo"
  local generate_script
  local project_path

  while IFS= read -r generate_script; do
    project_path="$(find "$(dirname "$generate_script")" -maxdepth 1 -type f -name '*.csproj' -print | sort | head -n 1)"
    if [[ -n "$project_path" ]]; then
      printf '%s\n' "$project_path"
    fi
  done < <(find "$repo_dir/src/libs" -mindepth 2 -maxdepth 2 -type f -name generate.sh -print 2>/dev/null | sort)
}

write_local_builds_report() {
  local output_path="$OUT_DIR/generated-sdk-local-builds.tsv"
  local log_dir="$OUT_DIR/local-build-logs"
  local repo
  local solution_path
  local relative_solution_path
  local log_path
  local started_at
  local ended_at
  local duration_seconds
  local exit_code
  local status

  mkdir -p "$OUT_DIR" "$log_dir"
  printf 'repo\tsolution\tstatus\texit_code\tduration_seconds\tlog_path\n' > "$output_path"

  while IFS= read -r repo; do
    solution_path="$(find_solution_path "$repo")"
    if [[ -z "$solution_path" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "" "missing-solution" "" "" "" >> "$output_path"
      continue
    fi

    relative_solution_path="${solution_path#"$ROOT_DIR/$repo/"}"
    log_path="$log_dir/$repo.log"
    started_at="$(date +%s)"

    set +e
    dotnet build "$solution_path" -c Release --nologo > "$log_path" 2>&1
    exit_code="$?"
    set -e

    ended_at="$(date +%s)"
    duration_seconds="$((ended_at - started_at))"
    status="success"
    if [[ "$exit_code" != "0" ]]; then
      status="failed"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$relative_solution_path" "$status" "$exit_code" "$duration_seconds" "$log_path" >> "$output_path"
  done < <(list_generated_sdk_repos)

  printf '%s\n' "$output_path"
}

write_local_trims_report() {
  local output_path="$OUT_DIR/generated-sdk-local-trims.tsv"
  local log_dir="$OUT_DIR/local-trim-logs"
  local repo
  local project_path
  local relative_project_path
  local log_path
  local started_at
  local ended_at
  local duration_seconds
  local exit_code
  local status
  local project_count

  mkdir -p "$OUT_DIR" "$log_dir"
  printf 'repo\tproject\tstatus\texit_code\tduration_seconds\tlog_path\n' > "$output_path"

  while IFS= read -r repo; do
    project_count=0
    while IFS= read -r project_path; do
      project_count=$((project_count + 1))
      relative_project_path="${project_path#"$ROOT_DIR/$repo/"}"
      log_path="$log_dir/$repo-${project_count}.log"
      started_at="$(date +%s)"

      set +e
      autosdk trim "$project_path" > "$log_path" 2>&1
      exit_code="$?"
      set -e

      ended_at="$(date +%s)"
      duration_seconds="$((ended_at - started_at))"
      status="success"
      if [[ "$exit_code" != "0" ]]; then
        status="failed"
      fi

      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo" "$relative_project_path" "$status" "$exit_code" "$duration_seconds" "$log_path" >> "$output_path"
    done < <(find_generated_project_paths "$repo")

    if [[ "$project_count" == "0" ]]; then
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "" "missing-project" "" "" "" >> "$output_path"
    fi
  done < <(list_generated_sdk_repos)

  printf '%s\n' "$output_path"
}

list_local_smoke_targets() {
  jq -r '.smoke.local_container_repositories[]? | [.repo, (.environment_name // "-"), (.environment_value // "-"), (.test_filter // "-")] | @tsv' \
    "$CONFIG_PATH" | while IFS=$'\t' read -r repo environment_name environment_value test_filter; do
      if [[ -n "$REPO_FILTER" ]] && ! [[ "$repo" =~ $REPO_FILTER ]]; then
        continue
      fi
      printf '%s\t%s\t%s\t%s\n' "$repo" "$environment_name" "$environment_value" "$test_filter"
    done
}

write_local_smoke_report() {
  local output_path="$OUT_DIR/generated-sdk-local-smoke.tsv"
  local log_dir="$OUT_DIR/local-smoke-logs"
  local repo
  local environment_name
  local environment_value
  local environment_display
  local test_filter
  local project_path
  local relative_project_path
  local log_path
  local started_at
  local ended_at
  local duration_seconds
  local exit_code
  local status
  local -a test_args

  mkdir -p "$OUT_DIR" "$log_dir"
  printf 'repo\tproject\tenvironment\tstatus\texit_code\tduration_seconds\tlog_path\tdetails\ttest_filter\n' > "$output_path"

  while IFS=$'\t' read -r repo environment_name environment_value test_filter; do
    environment_display="Release-default-container"
    if [[ "$environment_name" != "-" ]]; then
      environment_display="$environment_name=$environment_value"
    fi
    project_path="$(find "$ROOT_DIR/$repo/src/tests" -type f -name '*.csproj' -print 2>/dev/null | sort | sed -n '1p')"
    if [[ -z "$project_path" ]]; then
      printf '%s\t\t%s\tmissing-project\t\t\t\tconfigured smoke test project is missing\t%s\n' \
        "$repo" "$environment_display" "$test_filter" >> "$output_path"
      continue
    fi

    relative_project_path="${project_path#"$ROOT_DIR/$repo/"}"
    log_path="$log_dir/$repo.log"
    started_at="$(date +%s)"

    set +e
    test_args=(dotnet test "$project_path" -c Release --nologo)
    if [[ "$test_filter" != "-" ]]; then
      test_args+=(--filter "$test_filter")
    fi
    if [[ "$environment_name" == "-" ]]; then
      "${test_args[@]}" > "$log_path" 2>&1
    else
      env "$environment_name=$environment_value" "${test_args[@]}" > "$log_path" 2>&1
    fi
    exit_code="$?"
    set -e

    ended_at="$(date +%s)"
    duration_seconds="$((ended_at - started_at))"
    status="success"
    if [[ "$exit_code" != "0" ]]; then
      status="failed"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo" "$relative_project_path" "$environment_display" \
      "$status" "$exit_code" "$duration_seconds" "$log_path" \
      "allowlisted local container; no provider credentials or paid endpoints" "$test_filter" >> "$output_path"
  done < <(list_local_smoke_targets)

  printf '%s\n' "$output_path"
}

print_local_smoke_summary() {
  local smoke_path="$1"

  printf 'Local smoke report: %s\n' "$smoke_path"
  printf 'Local smoke successes: %s\n' "$(awk -F '\t' 'NR > 1 && $4 == "success" { count++ } END { print count + 0 }' "$smoke_path")"
  printf 'Local smoke failures: %s\n' "$(awk -F '\t' 'NR > 1 && $4 != "success" { count++ } END { print count + 0 }' "$smoke_path")"

  if awk -F '\t' 'NR > 1 && $4 != "success" { found = 1 } END { exit found ? 0 : 1 }' "$smoke_path"; then
    awk -F '\t' 'NR > 1 && $4 != "success" { printf "  %s\t%s\t%s\t%s\n", $1, $4, $5, $7 }' "$smoke_path"
  fi
}

write_operation_visibility_report() {
  local output_path="$OUT_DIR/generated-sdk-operation-visibility.tsv"
  local args=(
    --root "$ROOT_DIR"
    --config "$CONFIG_PATH"
    --output "$output_path"
  )

  mkdir -p "$OUT_DIR"
  if [[ -n "$REPO_FILTER" ]]; then
    args+=(--repo-regex "$REPO_FILTER")
  fi

  python3 "$ROOT_DIR/scripts/audit_required_public_operations.py" "${args[@]}"
  printf '%s\n' "$output_path"
}

print_operation_visibility_summary() {
  local visibility_path="$1"

  printf 'Required public operation report: %s\n' "$visibility_path"
  printf 'Required public operation checks: %s\n' "$(
    awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$visibility_path"
  )"
  printf 'Required public operation failures: %s\n' "$(
    awk -F '\t' 'NR > 1 && $8 != "ok" { count++ } END { print count + 0 }' "$visibility_path"
  )"

  if awk -F '\t' 'NR > 1 && $8 != "ok" { found = 1 } END { exit found ? 0 : 1 }' "$visibility_path"; then
    awk -F '\t' 'NR > 1 && $8 != "ok" { printf "  %s\t%s %s\t%s\t%s\n", $1, $2, $3, $8, $10 }' "$visibility_path"
  fi
}

write_representations_report() {
  local output_path="$OUT_DIR/generated-sdk-representations.tsv"
  local all_output_path="$OUT_DIR/.generated-sdk-representations-all.tsv"
  local repos_path="$OUT_DIR/.generated-sdk-representation-repos.txt"
  local log_path="$OUT_DIR/generated-sdk-representations.log"

  mkdir -p "$OUT_DIR"
  list_generated_sdk_repos > "$repos_path"
  autosdk audit-representations "$ROOT_DIR" \
    --format tsv \
    --output "$all_output_path" > "$log_path" 2>&1

  python3 - <<'PY' "$all_output_path" "$repos_path" "$output_path"
import csv
import sys

all_output_path, repos_path, output_path = sys.argv[1:]
with open(repos_path, encoding="utf-8") as f:
    repos = {line.strip() for line in f if line.strip()}

with open(all_output_path, encoding="utf-8", newline="") as source_file:
    reader = csv.DictReader(source_file, delimiter="\t")
    fieldnames = reader.fieldnames or []
    rows = []
    for row in reader:
        source = (row.get("source") or "").replace("\\", "/")
        repo = source.split("/", 1)[0]
        if repo in repos:
            rows.append(row)

with open(output_path, "w", encoding="utf-8", newline="") as output_file:
    writer = csv.DictWriter(output_file, fieldnames=fieldnames, delimiter="\t")
    writer.writeheader()
    writer.writerows(rows)
PY

  printf '%s\n' "$output_path"
}

print_representation_summary() {
  local representations_path="$1"

  printf 'Representation report: %s\n' "$representations_path"
  printf 'Representation findings: %s\n' "$(awk -F '\t' 'NR > 1 { count++ } END { print count + 0 }' "$representations_path")"
  printf 'Representation errors: %s\n' "$(awk -F '\t' 'NR > 1 && $7 == "error" { count++ } END { print count + 0 }' "$representations_path")"
  printf 'Representation warnings: %s\n' "$(awk -F '\t' 'NR > 1 && $7 == "warning" { count++ } END { print count + 0 }' "$representations_path")"
}

print_local_build_summary() {
  local local_builds_path="$1"

  printf 'Local build report: %s\n' "$local_builds_path"
  printf 'Local build successes: %s\n' "$(
    awk -F '\t' 'NR > 1 && $3 == "success" { count++ } END { print count + 0 }' "$local_builds_path"
  )"
  printf 'Local build failures: %s\n' "$(
    awk -F '\t' 'NR > 1 && $3 == "failed" { count++ } END { print count + 0 }' "$local_builds_path"
  )"
  printf 'Missing solutions: %s\n' "$(
    awk -F '\t' 'NR > 1 && $3 == "missing-solution" { count++ } END { print count + 0 }' "$local_builds_path"
  )"

  if awk -F '\t' 'NR > 1 && $3 == "failed" { found = 1 } END { exit found ? 0 : 1 }' "$local_builds_path"; then
    echo
    echo "Local build failures:"
    awk -F '\t' 'NR > 1 && $3 == "failed" { printf "  %s\t%s\t%s\n", $1, $4, $6 }' "$local_builds_path"
  fi
}

print_local_trim_summary() {
  local local_trims_path="$1"

  printf 'Local trim report: %s\n' "$local_trims_path"
  printf 'Local trim successes: %s\n' "$(
    awk -F '\t' 'NR > 1 && $3 == "success" { count++ } END { print count + 0 }' "$local_trims_path"
  )"
  printf 'Local trim failures: %s\n' "$(
    awk -F '\t' 'NR > 1 && $3 == "failed" { count++ } END { print count + 0 }' "$local_trims_path"
  )"
  printf 'Missing projects: %s\n' "$(
    awk -F '\t' 'NR > 1 && $3 == "missing-project" { count++ } END { print count + 0 }' "$local_trims_path"
  )"

  if awk -F '\t' 'NR > 1 && $3 == "failed" { found = 1 } END { exit found ? 0 : 1 }' "$local_trims_path"; then
    echo
    echo "Local trim failures:"
    awk -F '\t' 'NR > 1 && $3 == "failed" { printf "  %s\t%s\t%s\t%s\n", $1, $2, $4, $6 }' "$local_trims_path"
  fi
}

render_briefing_text() {
  local settings_path="$1"
  local workflows_path="$2"
  local issues_path="$3"
  local signals_path="$4"
  local representations_path="$5"
  local visibility_path="$6"
  local output_path="$7"

  python3 - <<'PY' "$settings_path" "$workflows_path" "$issues_path" "$signals_path" "$representations_path" "$visibility_path" "$output_path"
import csv
import os
import re
import sys
from collections import Counter
from datetime import datetime

settings_path, workflows_path, issues_path, signals_path, representations_path, visibility_path, output_path = sys.argv[1:]
signal_skip_ignore_regex = os.environ.get("TRYAGI_SIGNAL_SKIP_IGNORE_REGEX", "^(OpenAI)$")

def read_tsv(path):
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))

settings = read_tsv(settings_path)
workflows = read_tsv(workflows_path)
issues = read_tsv(issues_path)
signals = read_tsv(signals_path)
representations = read_tsv(representations_path)
visibility = read_tsv(visibility_path)

repo_count = len(settings)
non_compliant = sum(
    1
    for row in settings
    if row["allow_auto_merge"] != "true"
    or row["delete_branch_on_merge"] != "true"
    or row["allow_update_branch"] != "true"
)
bootstrap_gaps = [
    row
    for row in settings
    if row.get("autosdk_bootstrap_status") not in {"", "ok"}
]
dependabot_gaps = [
    row
    for row in settings
    if row.get("dependabot_nuget_status") not in {"", "ok"}
]

workflow_failures = [
    row for row in workflows
    if row["conclusion"] not in {"success", "new-repo-no-runs", "no-runs", "missing-workflow", ""}
]
workflow_no_runs = [row for row in workflows if row["conclusion"] == "no-runs"]
workflow_onboarding_gaps = [row for row in workflows if row["conclusion"] == "new-repo-no-runs"]

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

if bootstrap_gaps:
    lines.append(f"{len(bootstrap_gaps)} repositories are missing an AutoSDK bootstrap step in generate.sh.")
    for row in bootstrap_gaps[:6]:
        details = row.get("autosdk_bootstrap_details") or "generate.sh"
        lines.append(f"{row['repo']} is missing AutoSDK bootstrap in {details}.")
else:
    lines.append("All generate scripts include an AutoSDK bootstrap step.")

if dependabot_gaps:
    lines.append(f"{len(dependabot_gaps)} repositories have a NuGet Dependabot policy gap.")
    for row in dependabot_gaps[:6]:
        details = row.get("dependabot_nuget_details") or row.get("dependabot_nuget_status")
        lines.append(f"{row['repo']} has a NuGet Dependabot policy gap: {details}.")
else:
    lines.append("All generated SDK repositories have weekly grouped NuGet Dependabot coverage.")

if workflow_failures:
    lines.append(f"There are {len(workflow_failures)} latest workflow failures that still need attention.")
    for row in workflow_failures[:6]:
        lines.append(
            f"{row['repo']} has a failed {row['kind']} run."
        )
if workflow_no_runs:
    lines.append(f"There are {len(workflow_no_runs)} mature workflow entries with no recorded runs yet.")
    for row in workflow_no_runs[:6]:
        lines.append(f"{row['repo']} has no runs yet for {row['kind']}.")
if workflow_onboarding_gaps:
    lines.append(f"There are {len(workflow_onboarding_gaps)} onboarding workflow gaps for newly created repositories.")
    for row in workflow_onboarding_gaps[:6]:
        lines.append(f"{row['repo']} is newly created and has no runs yet for {row['kind']}.")
if not workflow_failures and not workflow_no_runs and not workflow_onboarding_gaps:
    lines.append("Latest regeneration and publish runs are clean.")

if total_issues == 0:
    lines.append("There are no open issues in the generated S.D.K. repositories.")
else:
    lines.append(f"There are {total_issues} open issues across {len(issue_counts)} repositories.")
    if top_issue_repos:
        repo_bits = [f"{repo} with {count}" for repo, count in top_issue_repos]
        lines.append("The busiest issue queues are " + ", ".join(repo_bits) + ".")
    if recent_issues:
        lines.append("Most recently updated open issues are listed by repository and number; external issue text is intentionally omitted from this briefing:")
        for row in recent_issues:
            lines.append(f"{row['repo']} issue {row['issue_number']}: {row['url']}.")

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

representation_errors = [row for row in representations if row.get("severity") == "error"]
representation_warnings = [row for row in representations if row.get("severity") == "warning"]
representation_error_repos = Counter(
    (row.get("source") or "").replace("\\", "/").split("/", 1)[0]
    for row in representation_errors
)
lines.append(
    f"The representation audit found {len(representations)} media-type signals, "
    f"including {len(representation_errors)} errors and {len(representation_warnings)} warnings."
)
if representation_error_repos:
    repo_bits = [f"{repo} with {count}" for repo, count in representation_error_repos.most_common(5)]
    lines.append("The highest representation error counts are " + ", ".join(repo_bits) + ".")

visibility_failures = [row for row in visibility if row.get("status") != "ok"]
if visibility_failures:
    lines.append(
        f"{len(visibility_failures)} required public operations are hidden, missing, or changed."
    )
    for row in visibility_failures[:8]:
        lines.append(
            f"{row['repo']} {row['method']} {row['path']} reported {row['status']}."
        )
else:
    lines.append(
        f"All {len(visibility)} configured public operation visibility checks passed."
    )

lines.append("End of briefing.")

with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")
PY
}

write_summary_report() {
  local mode_name="${1:-$MODE}"
  local settings_path="${2:-}"
  local workflows_path="${3:-}"
  local issues_path="${4:-}"
  local signals_path="${5:-}"
  local local_builds_path="${6:-}"
  local local_trims_path="${7:-}"
  local representations_path="${8:-}"
  local visibility_path="${9:-}"
  local output_path="$OUT_DIR/generated-sdk-summary.tsv"
  local sync_path="$OUT_DIR/generated-sdk-sync.tsv"

  mkdir -p "$OUT_DIR"
  settings_path="$(resolve_report_path "$settings_path" "generated-sdk-settings.tsv")"
  workflows_path="$(resolve_report_path "$workflows_path" "generated-sdk-workflows.tsv")"
  issues_path="$(resolve_report_path "$issues_path" "generated-sdk-open-issues.tsv")"
  signals_path="$(resolve_report_path "$signals_path" "generated-sdk-log-signals.tsv")"
  local_builds_path="$(resolve_report_path "$local_builds_path" "generated-sdk-local-builds.tsv")"
  local_trims_path="$(resolve_report_path "$local_trims_path" "generated-sdk-local-trims.tsv")"
  representations_path="$(resolve_report_path "$representations_path" "generated-sdk-representations.tsv")"
  visibility_path="$(resolve_report_path "$visibility_path" "generated-sdk-operation-visibility.tsv")"

  python3 - <<'PY' \
    "$mode_name" \
    "$REPO_FILTER" \
    "$SIGNAL_SKIP_IGNORE_REGEX" \
    "$settings_path" \
    "$workflows_path" \
    "$issues_path" \
    "$signals_path" \
    "$local_builds_path" \
    "$local_trims_path" \
    "$representations_path" \
    "$visibility_path" \
    "$sync_path" \
    "$output_path"
import csv
import os
import re
import sys
from collections import Counter
from datetime import datetime, timezone

(
    mode_name,
    repo_filter,
    signal_skip_ignore_regex,
    settings_path,
    workflows_path,
    issues_path,
    signals_path,
    local_builds_path,
    local_trims_path,
    representations_path,
    visibility_path,
    sync_path,
    output_path,
) = sys.argv[1:]


def read_tsv(path):
    if not path or not os.path.exists(path):
        return []
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def unique_repo_count(*rows_sets):
    repos = set()
    for rows in rows_sets:
        for row in rows:
            repo = (row.get("repo") or "").strip()
            if repo:
                repos.add(repo)
    return len(repos)


def unique_representation_repo_count(rows):
    return len({
        (row.get("source") or "").replace("\\", "/").split("/", 1)[0]
        for row in rows
        if (row.get("source") or "").strip()
    })


def sync_repo_count(rows):
    return sum(1 for row in rows if row.get("repo") not in {"", "__inventory__"})


def effective_signal_value(repo, raw_value):
    try:
        value = int(raw_value or 0)
    except ValueError:
        value = 0
    if value == 0:
        return 0
    if signal_skip_ignore_regex and re.search(signal_skip_ignore_regex, repo or ""):
        return 0
    return value


settings = read_tsv(settings_path)
workflows = read_tsv(workflows_path)
issues = read_tsv(issues_path)
signals = read_tsv(signals_path)
local_builds = read_tsv(local_builds_path)
local_trims = read_tsv(local_trims_path)
representations = read_tsv(representations_path)
visibility = read_tsv(visibility_path)
sync_rows = read_tsv(sync_path)

repo_count = (
    len(settings)
    or unique_repo_count(workflows, signals, local_builds, local_trims)
    or unique_representation_repo_count(representations)
    or sync_repo_count(sync_rows)
)
settings_non_compliant = sum(
    1
    for row in settings
    if row.get("allow_auto_merge") != "true"
    or row.get("delete_branch_on_merge") != "true"
    or row.get("allow_update_branch") != "true"
)
autosdk_bootstrap_gaps = sum(
    1
    for row in settings
    if row.get("autosdk_bootstrap_status") not in {"", "ok"}
)
dependabot_nuget_gaps = sum(
    1
    for row in settings
    if row.get("dependabot_nuget_status") not in {"", "ok"}
)

auto_update_onboarding_gaps = sum(
    1
    for row in workflows
    if row.get("kind") == "auto-update" and row.get("conclusion") == "new-repo-no-runs"
)
auto_update_no_runs = sum(
    1
    for row in workflows
    if row.get("kind") == "auto-update" and row.get("conclusion") == "no-runs"
)
auto_update_failures = sum(
    1
    for row in workflows
    if row.get("kind") == "auto-update"
    and row.get("conclusion") not in {"success", "new-repo-no-runs", "no-runs", "missing-workflow", ""}
)
publish_onboarding_gaps = sum(
    1
    for row in workflows
    if row.get("kind") == "publish" and row.get("conclusion") == "new-repo-no-runs"
)
publish_no_runs = sum(
    1
    for row in workflows
    if row.get("kind") == "publish" and row.get("conclusion") == "no-runs"
)
publish_failures = sum(
    1
    for row in workflows
    if row.get("kind") == "publish"
    and row.get("conclusion") not in {"success", "new-repo-no-runs", "no-runs", "missing-workflow", ""}
)

issue_counts = Counter((row.get("repo") or "").strip() for row in issues if (row.get("repo") or "").strip())
open_issue_count = sum(issue_counts.values())
repos_with_open_issues = len(issue_counts)

signal_rows = [row for row in signals if row.get("signal_status") == "ok"]
signal_repos_with_findings = 0
signal_warning_repo_count = 0
signal_warning_line_total = 0
signal_skipped_test_repo_count = 0
signal_skipped_test_total = 0
signal_inconclusive_repo_count = 0
signal_inconclusive_hit_total = 0

for row in signal_rows:
    repo = row.get("repo") or ""
    warning_lines = int(row.get("warning_lines") or 0)
    skipped_tests = effective_signal_value(repo, row.get("skipped_tests"))
    inconclusive_hits = effective_signal_value(repo, row.get("inconclusive_hits"))

    if warning_lines > 0:
        signal_warning_repo_count += 1
        signal_warning_line_total += warning_lines
    if skipped_tests > 0:
        signal_skipped_test_repo_count += 1
        signal_skipped_test_total += skipped_tests
    if inconclusive_hits > 0:
        signal_inconclusive_repo_count += 1
        signal_inconclusive_hit_total += inconclusive_hits
    if warning_lines > 0 or skipped_tests > 0 or inconclusive_hits > 0:
        signal_repos_with_findings += 1

local_build_successes = sum(1 for row in local_builds if row.get("status") == "success")
local_build_failures = sum(1 for row in local_builds if row.get("status") == "failed")
local_build_missing_solutions = sum(1 for row in local_builds if row.get("status") == "missing-solution")

local_trim_successes = sum(1 for row in local_trims if row.get("status") == "success")
local_trim_failures = sum(1 for row in local_trims if row.get("status") == "failed")
local_trim_missing_projects = sum(1 for row in local_trims if row.get("status") == "missing-project")

representation_findings = len(representations)
representation_errors = sum(1 for row in representations if row.get("severity") == "error")
representation_warnings = sum(1 for row in representations if row.get("severity") == "warning")
public_operation_checks = len(visibility)
public_operation_failures = sum(1 for row in visibility if row.get("status") != "ok")
sync_current = sum(1 for row in sync_rows if row.get("status") == "current")
sync_fast_forwarded = sum(1 for row in sync_rows if row.get("status") == "fast-forwarded")
sync_unsynchronized = sum(
    1 for row in sync_rows if row.get("status") not in {"current", "fast-forwarded", ""}
)
sync_missing_local = sum(1 for row in sync_rows if row.get("status") == "missing-local")

fields = [
    "generated_at_utc",
    "mode",
    "repo_filter",
    "repo_count",
    "settings_non_compliant",
    "autosdk_bootstrap_gaps",
    "dependabot_nuget_gaps",
    "auto_update_onboarding_gaps",
    "auto_update_no_runs",
    "auto_update_failures",
    "publish_onboarding_gaps",
    "publish_no_runs",
    "publish_failures",
    "open_issue_count",
    "repos_with_open_issues",
    "signal_repos_with_findings",
    "signal_warning_repo_count",
    "signal_warning_line_total",
    "signal_skipped_test_repo_count",
    "signal_skipped_test_total",
    "signal_inconclusive_repo_count",
    "signal_inconclusive_hit_total",
    "local_build_successes",
    "local_build_failures",
    "local_build_missing_solutions",
    "local_trim_successes",
    "local_trim_failures",
    "local_trim_missing_projects",
    "representation_findings",
    "representation_errors",
    "representation_warnings",
    "public_operation_checks",
    "public_operation_failures",
    "sync_current",
    "sync_fast_forwarded",
    "sync_unsynchronized",
    "sync_missing_local",
    "settings_report",
    "workflows_report",
    "issues_report",
    "signals_report",
    "local_builds_report",
    "local_trims_report",
    "representations_report",
    "operation_visibility_report",
    "sync_report",
]

row = {
    "generated_at_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "mode": mode_name,
    "repo_filter": repo_filter,
    "repo_count": str(repo_count),
    "settings_non_compliant": str(settings_non_compliant),
    "autosdk_bootstrap_gaps": str(autosdk_bootstrap_gaps),
    "dependabot_nuget_gaps": str(dependabot_nuget_gaps),
    "auto_update_onboarding_gaps": str(auto_update_onboarding_gaps),
    "auto_update_no_runs": str(auto_update_no_runs),
    "auto_update_failures": str(auto_update_failures),
    "publish_onboarding_gaps": str(publish_onboarding_gaps),
    "publish_no_runs": str(publish_no_runs),
    "publish_failures": str(publish_failures),
    "open_issue_count": str(open_issue_count),
    "repos_with_open_issues": str(repos_with_open_issues),
    "signal_repos_with_findings": str(signal_repos_with_findings),
    "signal_warning_repo_count": str(signal_warning_repo_count),
    "signal_warning_line_total": str(signal_warning_line_total),
    "signal_skipped_test_repo_count": str(signal_skipped_test_repo_count),
    "signal_skipped_test_total": str(signal_skipped_test_total),
    "signal_inconclusive_repo_count": str(signal_inconclusive_repo_count),
    "signal_inconclusive_hit_total": str(signal_inconclusive_hit_total),
    "local_build_successes": str(local_build_successes),
    "local_build_failures": str(local_build_failures),
    "local_build_missing_solutions": str(local_build_missing_solutions),
    "local_trim_successes": str(local_trim_successes),
    "local_trim_failures": str(local_trim_failures),
    "local_trim_missing_projects": str(local_trim_missing_projects),
    "representation_findings": str(representation_findings),
    "representation_errors": str(representation_errors),
    "representation_warnings": str(representation_warnings),
    "public_operation_checks": str(public_operation_checks),
    "public_operation_failures": str(public_operation_failures),
    "sync_current": str(sync_current),
    "sync_fast_forwarded": str(sync_fast_forwarded),
    "sync_unsynchronized": str(sync_unsynchronized),
    "sync_missing_local": str(sync_missing_local),
    "settings_report": settings_path,
    "workflows_report": workflows_path,
    "issues_report": issues_path,
    "signals_report": signals_path,
    "local_builds_report": local_builds_path,
    "local_trims_report": local_trims_path,
    "representations_report": representations_path,
    "operation_visibility_report": visibility_path,
    "sync_report": sync_path,
}

with open(output_path, "w", encoding="utf-8", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields, delimiter="\t")
    writer.writeheader()
    writer.writerow(row)
PY

  printf '%s\n' "$output_path"
}

print_summary() {
  local mode_name="$1"
  local settings_path="$2"
  local workflows_path="$3"
  local issues_path="${4:-}"
  local signals_path="${5:-}"
  local visibility_path="${6:-}"
  local summary_path
  local repo_count
  local settings_non_compliant
  local autosdk_bootstrap_gaps
  local dependabot_nuget_gaps
  local auto_update_onboarding_gaps
  local auto_update_no_runs
  local auto_update_failures
  local publish_onboarding_gaps
  local publish_no_runs
  local publish_failures

  summary_path="$(write_summary_report "$mode_name" "$settings_path" "$workflows_path" "$issues_path" "$signals_path" "" "" "" "$visibility_path")"
  repo_count="$(awk -F '\t' 'NR == 2 { print $4 }' "$summary_path")"
  settings_non_compliant="$(
    awk -F '\t' 'NR > 1 && $1 != "" && ($2 != "true" || $3 != "true" || $4 != "true") { count++ } END { print count + 0 }' "$settings_path"
  )"
  autosdk_bootstrap_gaps="$(
    awk -F '\t' 'NR > 1 && $1 != "" && $5 != "ok" && $5 != "" { count++ } END { print count + 0 }' "$settings_path"
  )"
  dependabot_nuget_gaps="$(
    awk -F '\t' 'NR > 1 && $1 != "" && $7 != "ok" && $7 != "" { count++ } END { print count + 0 }' "$settings_path"
  )"
  auto_update_onboarding_gaps="$(
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 == "new-repo-no-runs" { count++ } END { print count + 0 }' "$workflows_path"
  )"
  auto_update_no_runs="$(
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 == "no-runs" { count++ } END { print count + 0 }' "$workflows_path"
  )"
  auto_update_failures="$(
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 != "success" && $5 != "new-repo-no-runs" && $5 != "no-runs" && $5 != "missing-workflow" && $5 != "" { count++ } END { print count + 0 }' "$workflows_path"
  )"
  publish_onboarding_gaps="$(
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 == "new-repo-no-runs" { count++ } END { print count + 0 }' "$workflows_path"
  )"
  publish_no_runs="$(
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 == "no-runs" { count++ } END { print count + 0 }' "$workflows_path"
  )"
  publish_failures="$(
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 != "success" && $5 != "new-repo-no-runs" && $5 != "no-runs" && $5 != "missing-workflow" && $5 != "" { count++ } END { print count + 0 }' "$workflows_path"
  )"

  printf 'Generated SDK repos: %s\n' "$repo_count"
  printf 'Non-compliant repo settings: %s\n' "$settings_non_compliant"
  printf 'AutoSDK bootstrap gaps: %s\n' "$autosdk_bootstrap_gaps"
  printf 'NuGet Dependabot policy gaps: %s\n' "$dependabot_nuget_gaps"
  printf 'Latest auto-update onboarding gaps: %s\n' "$auto_update_onboarding_gaps"
  printf 'Latest auto-update mature no-runs: %s\n' "$auto_update_no_runs"
  printf 'Latest auto-update failures: %s\n' "$auto_update_failures"
  printf 'Latest publish onboarding gaps: %s\n' "$publish_onboarding_gaps"
  printf 'Latest publish mature no-runs: %s\n' "$publish_no_runs"
  printf 'Latest publish failures: %s\n' "$publish_failures"
  printf 'Summary report: %s\n' "$summary_path"
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

  if [[ -n "$visibility_path" ]]; then
    print_operation_visibility_summary "$visibility_path"
  fi

  if [[ "$autosdk_bootstrap_gaps" != "0" ]]; then
    echo
    echo "AutoSDK bootstrap gaps:"
    awk -F '\t' 'NR > 1 && $5 != "ok" && $5 != "" { printf "  %s\t%s\t%s\n", $1, $5, $6 }' "$settings_path"
  fi

  if [[ "$dependabot_nuget_gaps" != "0" ]]; then
    echo
    echo "NuGet Dependabot policy gaps:"
    awk -F '\t' 'NR > 1 && $7 != "ok" && $7 != "" { printf "  %s\t%s\t%s\n", $1, $7, $8 }' "$settings_path"
  fi

  if [[ "$auto_update_onboarding_gaps" != "0" ]]; then
    echo
    echo "Latest auto-update onboarding gaps:"
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 == "new-repo-no-runs" { printf "  %s\t%s\t%s\n", $1, $2, $3 }' "$workflows_path"
  fi

  if [[ "$auto_update_no_runs" != "0" ]]; then
    echo
    echo "Latest auto-update mature no-runs:"
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 == "no-runs" { printf "  %s\t%s\t%s\n", $1, $2, $3 }' "$workflows_path"
  fi

  if [[ "$auto_update_failures" != "0" ]]; then
    echo
    echo "Latest auto-update failures:"
    awk -F '\t' 'NR > 1 && $2 == "auto-update" && $5 != "success" && $5 != "new-repo-no-runs" && $5 != "no-runs" && $5 != "missing-workflow" && $5 != "" { printf "  %s\t%s\t%s\n", $1, $5, $9 }' "$workflows_path"
  fi

  if [[ "$publish_onboarding_gaps" != "0" ]]; then
    echo
    echo "Latest publish onboarding gaps:"
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 == "new-repo-no-runs" { printf "  %s\t%s\t%s\n", $1, $2, $3 }' "$workflows_path"
  fi

  if [[ "$publish_no_runs" != "0" ]]; then
    echo
    echo "Latest publish mature no-runs:"
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 == "no-runs" { printf "  %s\t%s\t%s\n", $1, $2, $3 }' "$workflows_path"
  fi

  if [[ "$publish_failures" != "0" ]]; then
    echo
    echo "Latest publish failures:"
    awk -F '\t' 'NR > 1 && $2 == "publish" && $5 != "success" && $5 != "new-repo-no-runs" && $5 != "no-runs" && $5 != "missing-workflow" && $5 != "" { printf "  %s\t%s\t%s\n", $1, $5, $9 }' "$workflows_path"
  fi
}

main() {
  local sync_path
  local hygiene_path
  local settings_path
  local workflows_path
  local issues_path
  local pull_requests_path
  local signals_path
  local briefing_path
  local local_builds_path
  local local_trims_path
  local local_smoke_path
  local representations_path
  local visibility_path

  require_command jq
  require_command python3
  require_command git
  parse_args "$@"
  load_automation_env
  apply_env_overrides
  load_config

  if [[ "$MODE" == "sync" ]]; then
    require_command gh
    require_github_auth
  elif [[ "$MODE" == "local-builds" || "$MODE" == "local-trims" || "$MODE" == "local-smoke" ]]; then
    require_command dotnet
  else
    if [[ "$MODE" != "representations" && "$MODE" != "visibility" ]]; then
      require_command gh
      require_github_auth
    fi
  fi
  if [[ "$MODE" == "local-trims" || "$MODE" == "representations" || "$MODE" == "briefing" ]]; then
    require_command autosdk
  fi
  if [[ "$MODE" == "local-smoke" ]]; then
    require_command docker
    if ! docker info >/dev/null 2>&1; then
      echo "Docker is required for the non-paid local smoke lane." >&2
      exit 1
    fi
  fi

  if [[ "$MODE" != "sync" && "$MODE" != "repos" ]]; then
    require_ready_sync_report
  fi

  case "$MODE" in
    sync)
      sync_path="$(write_sync_report)"
      hygiene_path="$(write_workspace_hygiene_report)"
      write_summary_report "$MODE" >/dev/null
      print_sync_summary "$sync_path"
      print_workspace_hygiene_summary "$hygiene_path"
      if sync_report_has_failures "$sync_path" || workspace_hygiene_has_failures "$hygiene_path"; then
        exit 2
      fi
      ;;
    repos)
      list_generated_sdk_repos
      ;;
    settings)
      settings_path="$(write_settings_report)"
      write_summary_report "$MODE" "$settings_path" >/dev/null
      printf '%s\n' "$settings_path"
      ;;
    workflows)
      workflows_path="$(write_workflows_report)"
      write_summary_report "$MODE" "" "$workflows_path" >/dev/null
      printf '%s\n' "$workflows_path"
      ;;
    issues)
      issues_path="$(write_issues_report)"
      write_summary_report "$MODE" "" "" "$issues_path" >/dev/null
      printf '%s\n' "$issues_path"
      ;;
    pull-requests)
      pull_requests_path="$(write_pull_requests_report)"
      printf '%s\n' "$pull_requests_path"
      ;;
    signals)
      signals_path="$(write_signals_report)"
      write_summary_report "$MODE" "" "" "" "$signals_path" >/dev/null
      printf '%s\n' "$signals_path"
      ;;
    visibility)
      visibility_path="$(write_operation_visibility_report)"
      write_summary_report "$MODE" "" "" "" "" "" "" "" "$visibility_path" >/dev/null
      print_operation_visibility_summary "$visibility_path"
      if awk -F '\t' 'NR > 1 && $8 != "ok" { found = 1 } END { exit found ? 0 : 1 }' "$visibility_path"; then
        exit 2
      fi
      ;;
    representations)
      representations_path="$(write_representations_report)"
      write_summary_report "$MODE" "" "" "" "" "" "" "$representations_path" >/dev/null
      print_representation_summary "$representations_path"
      ;;
    local-builds)
      local_builds_path="$(write_local_builds_report)"
      write_summary_report "$MODE" "" "" "" "" "$local_builds_path" >/dev/null
      print_local_build_summary "$local_builds_path"
      ;;
    local-trims)
      local_trims_path="$(write_local_trims_report)"
      write_summary_report "$MODE" "" "" "" "" "" "$local_trims_path" >/dev/null
      print_local_trim_summary "$local_trims_path"
      ;;
    local-smoke)
      local_smoke_path="$(write_local_smoke_report)"
      print_local_smoke_summary "$local_smoke_path"
      ;;
    summary)
      settings_path="$(write_settings_report)"
      workflows_path="$(write_workflows_report)"
      visibility_path="$(write_operation_visibility_report)"
      print_summary "$MODE" "$settings_path" "$workflows_path" "" "" "$visibility_path"
      ;;
    briefing)
      settings_path="$(write_settings_report)"
      workflows_path="$(write_workflows_report)"
      issues_path="$(write_issues_report)"
      pull_requests_path="$(write_pull_requests_report)"
      signals_path="$(write_signals_report)"
      representations_path="$(write_representations_report)"
      visibility_path="$(write_operation_visibility_report)"
      briefing_path="$OUT_DIR/daily-briefing.txt"
      render_briefing_text "$settings_path" "$workflows_path" "$issues_path" "$signals_path" "$representations_path" "$visibility_path" "$briefing_path"
      print_summary "$MODE" "$settings_path" "$workflows_path" "$issues_path" "$signals_path" "$visibility_path"
      print_representation_summary "$representations_path"
      printf 'Open pull requests report: %s\n' "$pull_requests_path"
      printf 'Briefing text: %s\n' "$briefing_path"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
