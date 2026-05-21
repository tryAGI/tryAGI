#!/usr/bin/env bash

set -euo pipefail

workspace_root=${WORKSPACE_ROOT:-/Users/havendv/GitHub/tryAGI}

usage() {
  cat <<'EOF'
Usage:
  scripts/migrate-generated-sdk-workflows.sh list
  scripts/migrate-generated-sdk-workflows.sh apply /absolute/path/to/repo
EOF
}

job_ids() {
  local file="$1"

  awk '
    /^jobs:/ {
      in_jobs = 1
      next
    }
    in_jobs && /^[^[:space:]]/ {
      exit
    }
    in_jobs && /^  [A-Za-z0-9_-]+:$/ {
      sub(":", "", $1)
      print $1
    }
  ' "$file"
}

yaml_value() {
  local file="$1"
  local key="$2"

  awk -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      sub("^[[:space:]]*" key ":[[:space:]]*", "", $0)
      print $0
      exit
    }
  ' "$file"
}

matches_target_shape() {
  local repo="$1"
  local dotnet="$repo/.github/workflows/dotnet.yml"
  local pr="$repo/.github/workflows/pull-request.yml"
  local auto_update="$repo/.github/workflows/auto-update.yml"

  [[ -f "$dotnet" ]] || return 1
  [[ -f "$pr" ]] || return 1
  [[ -f "$auto_update" ]] || return 1

  grep -q 'uses: HavenDV/workflows/.github/workflows/dotnet_build-test-publish.yml@main' "$dotnet" || return 1
  grep -q 'uses: HavenDV/workflows/.github/workflows/dotnet_build-test-publish.yml@main' "$pr" || return 1
  grep -q 'autosdk trim ' "$dotnet" || return 1

  local dotnet_jobs
  dotnet_jobs=$(job_ids "$dotnet" | tr '\n' ' ')
  [[ "$dotnet_jobs" == 'publish trim-check release ' ]] || return 1

  local pr_jobs
  pr_jobs=$(job_ids "$pr" | tr '\n' ' ')
  [[ "$pr_jobs" == 'test ' ]] || return 1
}

print_repo_list() {
  local repo

  for repo in "$workspace_root"/*; do
    [[ -d "$repo/.git" ]] || continue
    matches_target_shape "$repo" || continue
    printf '%s\n' "$repo"
  done
}

project_path() {
  local repo="$1"

  awk '
    /autosdk trim / {
      sub("^.*autosdk trim ", "", $0)
      print $0
      exit
    }
  ' "$repo/.github/workflows/dotnet.yml"
}

write_dotnet_workflow() {
  local repo="$1"
  local project="$2"
  local dotnet="$repo/.github/workflows/dotnet.yml"
  local dotnet_version
  local enable_caching
  local additional_test_arguments
  local nuget_key
  local api_key

  dotnet_version=$(yaml_value "$dotnet" 'dotnet-version')
  enable_caching=$(yaml_value "$dotnet" 'enable-caching')
  additional_test_arguments=$(yaml_value "$dotnet" 'additional-test-arguments')
  nuget_key=$(yaml_value "$dotnet" 'nuget-key')
  api_key=$(yaml_value "$dotnet" 'api-key')

  [[ -n "$project" ]] || {
    echo "Unable to determine project path for $repo" >&2
    return 1
  }

  dotnet_version=${dotnet_version:-10.0.x}
  enable_caching=${enable_caching:-false}
  additional_test_arguments=${additional_test_arguments:-'--logger GitHubActions'}
  nuget_key=${nuget_key:-'${{ secrets.NUGET_KEY }}'}

  {
    printf 'name: Publish\n'
    printf 'on:\n'
    printf '  push:\n'
    printf '    branches:\n'
    printf '      - main\n'
    printf '    tags:\n'
    printf '      - v**\n'
    printf '  workflow_dispatch:\n\n'
    printf 'permissions:\n'
    printf '  contents: write\n\n'
    printf 'jobs:\n'
    printf '  publish:\n'
    printf '    name: Publish\n'
    printf '    uses: tryAGI/workflows/.github/workflows/generated-sdk-publish.yml@main\n'
    printf '    with:\n'
    printf '      project-path: %s\n' "$project"
    printf '      dotnet-version: %s\n' "$dotnet_version"
    printf '      enable-caching: %s\n' "$enable_caching"
    printf '      additional-test-arguments: %s\n' "$additional_test_arguments"
    printf '    secrets:\n'
    printf '      nuget-key: %s\n' "$nuget_key"
    if [[ -n "$api_key" ]]; then
      printf '      api-key: %s\n' "$api_key"
    fi
  } > "$dotnet"
}

write_pull_request_workflow() {
  local repo="$1"
  local project="$2"
  local pr="$repo/.github/workflows/pull-request.yml"
  local dotnet_version
  local enable_caching
  local additional_test_arguments
  local api_key

  dotnet_version=$(yaml_value "$pr" 'dotnet-version')
  enable_caching=$(yaml_value "$pr" 'enable-caching')
  additional_test_arguments=$(yaml_value "$pr" 'additional-test-arguments')
  api_key=$(yaml_value "$pr" 'api-key')

  dotnet_version=${dotnet_version:-10.0.x}
  enable_caching=${enable_caching:-false}
  additional_test_arguments=${additional_test_arguments:-'--logger GitHubActions'}

  {
    printf 'name: Test\n'
    printf 'on:\n'
    printf '  pull_request:\n'
    printf '    branches:\n'
    printf '      - main\n\n'
    printf 'jobs:\n'
    printf '  test:\n'
    printf '    name: Test\n'
    printf '    if: github.event.pull_request.draft == false\n'
    printf '    uses: tryAGI/workflows/.github/workflows/generated-sdk-pull-request.yml@main\n'
    printf '    with:\n'
    printf '      project-path: %s\n' "$project"
    printf '      dotnet-version: %s\n' "$dotnet_version"
    printf '      enable-caching: %s\n' "$enable_caching"
    printf '      additional-test-arguments: %s\n' "$additional_test_arguments"
    if [[ -n "$api_key" ]]; then
      printf '    secrets:\n'
      printf '      api-key: %s\n' "$api_key"
    fi
  } > "$pr"
}

apply_to_repo() {
  local repo="$1"
  local project

  matches_target_shape "$repo" || {
    echo "Repository does not match the standard generated SDK workflow shape: $repo" >&2
    return 1
  }

  project=$(project_path "$repo")

  write_dotnet_workflow "$repo" "$project"
  write_pull_request_workflow "$repo" "$project"
}

main() {
  [[ $# -ge 1 ]] || {
    usage >&2
    exit 1
  }

  case "$1" in
    list)
      [[ $# -eq 1 ]] || {
        usage >&2
        exit 1
      }
      print_repo_list
      ;;
    apply)
      [[ $# -eq 2 ]] || {
        usage >&2
        exit 1
      }
      apply_to_repo "$2"
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
