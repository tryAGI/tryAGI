#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ORG="${TRYAGI_ORG:-tryAGI}"
MODE="ignore"
REPO_FILTER=""
APPLY=false

usage() {
  cat <<'EOF'
Usage: ./scripts/manage-generated-sdk-subscriptions.sh [repos|ignore|watch|unwatch] [--repo REGEX] [--apply]

Modes:
  repos     Print the generated SDK repos detected in the current workspace.
  ignore    Mute notifications for generated SDK repos via the repo subscription API.
  watch     Re-enable repo notifications for generated SDK repos.
  unwatch   Remove repo subscriptions for generated SDK repos.

Options:
  --repo REGEX   Only include repo names matching the regular expression.
  --apply        Execute changes. Without this flag, mutating modes print a dry-run plan.

Environment:
  TRYAGI_ORG     Default owner to use when a repo remote cannot be parsed. Default: tryAGI

Examples:
  ./scripts/manage-generated-sdk-subscriptions.sh repos
  ./scripts/manage-generated-sdk-subscriptions.sh ignore
  ./scripts/manage-generated-sdk-subscriptions.sh ignore --repo '^(Braintrust|GroundX)$' --apply
  ./scripts/manage-generated-sdk-subscriptions.sh watch --repo '^(OpenAI|Anthropic)$' --apply
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
      repos|ignore|watch|unwatch)
        MODE="$1"
        shift
        ;;
      --repo)
        REPO_FILTER="${2:-}"
        shift 2
        ;;
      --apply)
        APPLY=true
        shift
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

require_gh_auth() {
  local status_output

  if ! status_output="$(gh auth status 2>&1)"; then
    echo "gh authentication is required for '$MODE'." >&2
    echo "Re-authenticate with: gh auth login -h github.com" >&2
    echo >&2
    echo "$status_output" >&2
    exit 1
  fi
}

run_repo_mode() {
  list_generated_sdk_repos
}

run_mutating_mode() {
  local repo
  local api_target
  local repo_count=0

  if [[ "$APPLY" == true ]]; then
    require_gh_auth
  fi

  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    repo_count=$((repo_count + 1))
    api_target="$(repo_api_target "$repo")"

    case "$MODE" in
      ignore)
        if [[ "$APPLY" == true ]]; then
          gh api -X PUT "repos/$api_target/subscription" -F ignored=true >/dev/null
          printf 'ignored\t%s\n' "$api_target"
        else
          printf 'dry-run\tgh api -X PUT repos/%s/subscription -F ignored=true\n' "$api_target"
        fi
        ;;
      watch)
        if [[ "$APPLY" == true ]]; then
          gh api -X PUT "repos/$api_target/subscription" -F subscribed=true -F ignored=false >/dev/null
          printf 'watching\t%s\n' "$api_target"
        else
          printf 'dry-run\tgh api -X PUT repos/%s/subscription -F subscribed=true -F ignored=false\n' "$api_target"
        fi
        ;;
      unwatch)
        if [[ "$APPLY" == true ]]; then
          gh api -X DELETE "repos/$api_target/subscription" >/dev/null
          printf 'unwatched\t%s\n' "$api_target"
        else
          printf 'dry-run\tgh api -X DELETE repos/%s/subscription\n' "$api_target"
        fi
        ;;
    esac
  done < <(list_generated_sdk_repos)

  if [[ "$repo_count" -eq 0 ]]; then
    echo "No generated SDK repos matched the current filter." >&2
    return
  fi

  if [[ "$APPLY" == false ]]; then
    echo >&2
    echo "Dry run only. Re-run with --apply to execute the $MODE operation." >&2
  fi
}

main() {
  require_command gh
  require_command python3
  parse_args "$@"

  case "$MODE" in
    repos)
      run_repo_mode
      ;;
    ignore|watch|unwatch)
      run_mutating_mode
      ;;
  esac
}

main "$@"
