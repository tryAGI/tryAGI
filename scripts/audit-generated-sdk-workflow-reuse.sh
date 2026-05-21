#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-summary}"

HAVENDV_REF='uses: HavenDV/workflows/.github/workflows/dotnet_build-test-publish.yml@main'
TRYAGI_DOTNET_REF='uses: tryAGI/workflows/.github/workflows/dotnet-sdk-build-test-publish.yml@main'
TRYAGI_SDK_PUBLISH_REF='uses: tryAGI/workflows/.github/workflows/generated-sdk-publish.yml@main'

collect_matches() {
  local pattern="$1"
  shift
  rg -uu -l -F "$pattern" "$@" 2>/dev/null || true
}

collect_repos() {
  ROOT_DIR="$ROOT" python3 -c '
from pathlib import Path
import os
import sys

root = Path(os.environ["ROOT_DIR"])
paths = [line.strip() for line in sys.stdin if line.strip()]
repos = sorted({Path(path).resolve().relative_to(root).parts[0] for path in paths})
for repo in repos:
    print(repo)
'
}

count_lines() {
  local content="$1"
  if [ -z "$content" ]; then
    echo 0
  else
    printf '%s\n' "$content" | wc -l | awk '{print $1}'
  fi
}

TARGETS=(
  "$ROOT"/*/.github/workflows
  "$ROOT/AutoSDK/src/libs/AutoSDK.CLI/Resources"
)

havendv_files="$(collect_matches "$HAVENDV_REF" "${TARGETS[@]}")"
tryagi_dotnet_files="$(collect_matches "$TRYAGI_DOTNET_REF" "${TARGETS[@]}")"
tryagi_sdk_publish_files="$(collect_matches "$TRYAGI_SDK_PUBLISH_REF" "${TARGETS[@]}")"

case "$MODE" in
  summary)
    printf 'HavenDV dotnet reusable refs: %s files\n' "$(count_lines "$havendv_files")"
    if [ -n "$havendv_files" ]; then
      printf '%s\n' "$havendv_files" | collect_repos | sed 's/^/  - /'
    fi
    printf '\ntryAGI dotnet reusable refs: %s files\n' "$(count_lines "$tryagi_dotnet_files")"
    if [ -n "$tryagi_dotnet_files" ]; then
      printf '%s\n' "$tryagi_dotnet_files" | collect_repos | sed 's/^/  - /'
    fi
    printf '\ntryAGI generated SDK publish refs: %s files\n' "$(count_lines "$tryagi_sdk_publish_files")"
    if [ -n "$tryagi_sdk_publish_files" ]; then
      printf '%s\n' "$tryagi_sdk_publish_files" | collect_repos | sed 's/^/  - /'
    fi
    ;;
  havendv-files)
    if [ -n "$havendv_files" ]; then
      printf '%s\n' "$havendv_files"
    fi
    ;;
  tryagi-files)
    printf '%s\n%s\n' "$tryagi_dotnet_files" "$tryagi_sdk_publish_files" | sed '/^$/d'
    ;;
  *)
    echo "Usage: $(basename "$0") [summary|havendv-files|tryagi-files]" >&2
    exit 1
    ;;
esac
