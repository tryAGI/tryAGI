#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${TRYAGI_WORKSPACE:-$(pwd)}"
OUT_DIR="${TRYAGI_CLI_AUDIT_OUT:-/tmp/tryagi-cli-audit}"
REPO_REGEX='.*'

usage() {
  cat <<'USAGE'
Usage: scripts/audit-generated-cli-rollout.sh [--repo REGEX]

Audits generated SDK repositories for CLI rollout readiness and writes:
  /tmp/tryagi-cli-audit/cli-rollout.tsv
  /tmp/tryagi-cli-audit/cli-rollout.md

Columns track detected generated SDK projects, OpenAPI specs, manual PackAsTool CLIs,
generated api-only sources, generated CLI projects, and trim-publish candidates.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_REGEX="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mkdir -p "$OUT_DIR"
TSV="$OUT_DIR/cli-rollout.tsv"
MD="$OUT_DIR/cli-rollout.md"

find_first() {
  local root="$1"
  shift
  find "$root" "$@" -print -quit 2>/dev/null || true
}

join_lines() {
  paste -sd ';' - 2>/dev/null || true
}

relpath() {
  python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$2"
}

detect_manual_cli_projects() {
  local repo="$1"
  find "$repo/src" \
    -path '*/bin' -prune -o \
    -path '*/obj' -prune -o \
    -name '*.csproj' -print 2>/dev/null |
    while IFS= read -r project; do
      if grep -q '<PackAsTool>true</PackAsTool>' "$project"; then
        relpath "$project" "$repo"
      fi
    done |
    join_lines
}

detect_generated_api_sources() {
  local repo="$1"
  find "$repo/src" \
    -path '*/bin' -prune -o \
    -path '*/obj' -prune -o \
    -path '*/GeneratedApi/Commands/ApiCommand.g.cs' -print 2>/dev/null |
    while IFS= read -r file; do
      relpath "$file" "$repo"
    done |
    join_lines
}

detect_generated_cli_projects() {
  local repo="$1"
  find "$repo/src" \
    -path '*/bin' -prune -o \
    -path '*/obj' -prune -o \
    -name '*.csproj' -print 2>/dev/null |
    while IFS= read -r project; do
      if grep -q '<PackAsTool>true</PackAsTool>' "$project" &&
         { grep -qi '<PackageId>.*\.CLI\.Generated' "$project" ||
           grep -qi '<ToolCommandName>tryagi-.*-generated</ToolCommandName>' "$project"; }; then
        relpath "$project" "$repo"
      fi
    done |
    join_lines
}

{
  printf 'repo\tsdk_project\tspec\tmanual_cli_projects\tgenerated_api_sources\tgenerated_cli_projects\ttrim_candidates\tnotes\n'

  find "$WORKSPACE" -mindepth 1 -maxdepth 1 -type d -name '.git' -prune -o -type d -print |
    sort |
    while IFS= read -r repo; do
      repo_name="$(basename "$repo")"
      [[ "$repo_name" =~ $REPO_REGEX ]] || continue
      [[ -d "$repo/.git" ]] || continue

      sdk_project="$(find_first "$repo/src/libs" -mindepth 2 -maxdepth 2 -name '*.csproj')"
      [[ -n "$sdk_project" ]] || continue

      spec="$(find_first "$repo/src/libs" -mindepth 2 -maxdepth 2 \( -name 'openapi.yaml' -o -name 'openapi.yml' -o -name 'openapi.json' \))"
      generated_dir="$(find_first "$repo/src/libs" -mindepth 2 -maxdepth 2 -type d -name 'Generated')"
      [[ -n "$spec" && -n "$generated_dir" ]] || continue

      manual_cli_projects="$(detect_manual_cli_projects "$repo")"
      generated_api_sources="$(detect_generated_api_sources "$repo")"
      generated_cli_projects="$(detect_generated_cli_projects "$repo")"
      trim_candidates="${generated_cli_projects:-$manual_cli_projects}"
      notes=ready
      if [[ -z "$manual_cli_projects" && -z "$generated_cli_projects" ]]; then
        notes=needs-cli-project
      elif [[ -n "$manual_cli_projects" && -z "$generated_api_sources" ]]; then
        notes=manual-cli-needs-generated-api
      fi

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo_name" \
        "$(relpath "$sdk_project" "$repo")" \
        "$(relpath "$spec" "$repo")" \
        "$manual_cli_projects" \
        "$generated_api_sources" \
        "$generated_cli_projects" \
        "$trim_candidates" \
        "$notes"
    done
} > "$TSV"

{
  echo '# Generated CLI Rollout Audit'
  echo
  echo "Source: \`$TSV\`"
  echo
  echo '| Repo | SDK project | Spec | Manual CLI | Generated API sources | Generated CLI project | Notes |'
  echo '| --- | --- | --- | --- | --- | --- | --- |'
  tail -n +2 "$TSV" |
    while IFS=$'\t' read -r repo sdk spec manual generated_api generated_cli trim notes; do
      printf '| %s | `%s` | `%s` | %s | %s | %s | %s |\n' \
        "$repo" \
        "$sdk" \
        "$spec" \
        "${manual:-none}" \
        "${generated_api:-none}" \
        "${generated_cli:-none}" \
        "$notes"
    done
} > "$MD"

echo "Wrote $TSV"
echo "Wrote $MD"
