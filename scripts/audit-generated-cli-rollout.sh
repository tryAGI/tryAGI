#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="${TRYAGI_WORKSPACE:-$(pwd)}"
OUT_DIR="${TRYAGI_CLI_AUDIT_OUT:-/tmp/tryagi-cli-audit}"
REPO_REGEX='.*'
PROBE_BUILDS=false
PROBE_LIMIT=0

if [[ -n "${TRYAGI_AUTOSDK_CLI:-}" ]]; then
  read -r -a AUTOSDK_CMD <<< "$TRYAGI_AUTOSDK_CLI"
else
  AUTOSDK_CMD=(autosdk)
fi

usage() {
  cat <<'USAGE'
Usage: scripts/audit-generated-cli-rollout.sh [--repo REGEX] [--probe-builds] [--probe-limit N]

Audits generated SDK repositories for CLI rollout readiness and writes:
  /tmp/tryagi-cli-audit/cli-rollout.tsv
  /tmp/tryagi-cli-audit/cli-rollout.md
  /tmp/tryagi-cli-audit/cli-rollout-commands.sh

Columns track detected generated SDK projects, OpenAPI specs, manual PackAsTool CLIs,
generated api-only sources, generated CLI projects, solution-file gaps, trim-publish
candidates, operation counts, auth/base-url generation hints, optional build-probe
status, and ready-to-run CLI generation commands for SDKs that do not have a CLI yet.

Set TRYAGI_AUTOSDK_CLI='dotnet run --project /path/to/AutoSDK/src/libs/AutoSDK.CLI --'
to run throwaway probes with a local AutoSDK checkout.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO_REGEX="${2:-}"
      shift 2
      ;;
    --probe-builds)
      PROBE_BUILDS=true
      shift
      ;;
    --probe-limit)
      PROBE_LIMIT="${2:-0}"
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
COMMANDS="$OUT_DIR/cli-rollout-commands.sh"

find_first() {
  local root="$1"
  shift
  find "$root" "$@" -print -quit 2>/dev/null || true
}

join_lines() {
  paste -sd ';' - 2>/dev/null || true
}

first_item() {
  local value="$1"
  printf '%s\n' "${value%%;*}"
}

relpath() {
  python3 -c 'import os, sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$1" "$2"
}

realpath_portable() {
  python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

to_kebab() {
  python3 -c 'import re, sys; value = re.sub(r"([A-Z]+)([A-Z][a-z])", r"\1-\2", sys.argv[1]); value = re.sub(r"([a-z0-9])([A-Z])", r"\1-\2", value).replace("_", "-").lower(); print(re.sub(r"[^a-z0-9]+", "-", value).strip("-"))' "$1"
}

to_env_prefix() {
  python3 -c 'import re, sys; print(re.sub(r"[^A-Za-z0-9]+", "_", sys.argv[1]).upper().strip("_"))' "$1"
}

shell_quote() {
  python3 -c 'import shlex, sys; print(" ".join(shlex.quote(arg) for arg in sys.argv[1:]))' "$@"
}

detect_generate_script() {
  local spec="$1"
  local script
  script="$(dirname "$spec")/generate.sh"
  [[ -f "$script" ]] && printf '%s\n' "$script"
}

detect_generate_arg_values() {
  local script="$1"
  local arg="$2"
  [[ -n "$script" && -f "$script" ]] || return 0
  python3 - "$script" "$arg" <<'PY'
import re
import sys

script, arg = sys.argv[1], sys.argv[2]
text = open(script, encoding="utf-8").read()
text = "\n".join(line for line in text.splitlines() if not line.lstrip().startswith("#"))
pattern = re.compile(rf"{re.escape(arg)}(?:=|\s+)([^\s\\]+)")
values = []
seen = set()
for match in pattern.finditer(text):
    value = match.group(1).strip("'\"")
    if value not in seen:
        values.append(value)
        seen.add(value)
print(";".join(values))
PY
}

detect_first_generate_arg_value() {
  local values
  values="$(detect_generate_arg_values "$1" "$2")"
  first_item "$values"
}

detect_generate_flag() {
  local script="$1"
  local arg="$2"
  [[ -n "$script" && -f "$script" ]] || return 1
  grep -q -- "$arg" "$script"
}

count_openapi_operations() {
  local spec="$1"
  python3 - "$spec" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
try:
    if path.suffix.lower() == ".json":
        document = json.loads(path.read_text(encoding="utf-8"))
    else:
        import yaml
        document = yaml.safe_load(path.read_text(encoding="utf-8"))
except Exception:
    print("unknown")
    raise SystemExit(0)

methods = {"get", "put", "post", "delete", "options", "head", "patch", "trace"}
paths = document.get("paths") if isinstance(document, dict) else None
if not isinstance(paths, dict):
    print("0")
    raise SystemExit(0)

count = 0
for path_item in paths.values():
    if isinstance(path_item, dict):
        count += sum(1 for method, operation in path_item.items() if method.lower() in methods and isinstance(operation, dict))
print(count)
PY
}

detect_manual_cli_projects() {
  local repo="$1"
  find "$repo/src" \
    -path '*/bin' -prune -o \
    -path '*/obj' -prune -o \
    -name '*.csproj' -print 2>/dev/null |
    while IFS= read -r project; do
      local project_dir
      project_dir="$(dirname "$project")"
      if grep -q '<PackAsTool>true</PackAsTool>' "$project" &&
         ! { [[ -f "$project_dir/Commands/ApiCommand.g.cs" ]] && [[ -f "$project_dir/CliRuntime.cs" ]]; }; then
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
      local project_dir
      project_dir="$(dirname "$project")"
      if grep -q '<PackAsTool>true</PackAsTool>' "$project" &&
         { grep -qi '<PackageId>.*\.CLI\.Generated' "$project" ||
           grep -qi '<ToolCommandName>tryagi-.*-generated</ToolCommandName>' "$project" ||
           { [[ -f "$project_dir/Commands/ApiCommand.g.cs" ]] && [[ -f "$project_dir/CliRuntime.cs" ]]; }; }; then
        relpath "$project" "$repo"
      fi
    done |
    join_lines
}

detect_solution_cli_gaps() {
  local repo="$1"
  local generated_cli_projects="$2"
  [[ -n "$generated_cli_projects" ]] || return 0

  python3 - "$repo" "$generated_cli_projects" <<'PY'
import pathlib
import sys

repo = pathlib.Path(sys.argv[1])
projects = [value for value in sys.argv[2].split(";") if value]
solutions = list(repo.glob("*.sln")) + list(repo.glob("*.slnx"))
missing = []

for project in projects:
    normalized = project.replace("\\", "/")
    is_in_solution = False
    for solution in solutions:
        text = solution.read_text(encoding="utf-8", errors="ignore").replace("\\", "/")
        if normalized in text:
            is_in_solution = True
            break
    if not is_in_solution:
        missing.append(project)

print(";".join(missing))
PY
}

append_rollout_command() {
  local repo="$1"
  local repo_name="$2"
  local sdk_project_rel="$3"
  local spec_rel="$4"
  local generate_script="$5"

  local namespace client target package_id tool_name env_prefix output_rel base_url security_schemes
  namespace="$(detect_first_generate_arg_value "$generate_script" "--namespace")"
  client="$(detect_first_generate_arg_value "$generate_script" "--clientClassName")"
  target="$(detect_first_generate_arg_value "$generate_script" "--targetFramework")"
  base_url="$(first_item "$(detect_generate_arg_values "$generate_script" "--base-url")")"
  security_schemes="$(detect_generate_arg_values "$generate_script" "--security-scheme")"
  namespace="${namespace:-$repo_name}"
  client="${client:-${repo_name}Client}"
  target="${target:-net10.0}"
  package_id="${repo_name}.CLI"
  tool_name="$(to_kebab "$repo_name")"
  env_prefix="$(to_env_prefix "$repo_name")"
  output_rel="src/cli/${repo_name}.CLI"

  local cmd=(
    "${AUTOSDK_CMD[@]}"
    cli-project "$spec_rel"
    --output "$output_rel"
    --sdk-project "$sdk_project_rel"
    --targetFramework "$target"
    --namespace "$namespace"
    --clientClassName "$client"
    --package-id "$package_id"
    --tool-command-name "$tool_name"
    --user-secrets-id "$package_id"
    --api-key-env-var "${env_prefix}_API_KEY"
    --base-url-env-var "${env_prefix}_BASE_URL"
    --cli-credential-file
    --exclude-deprecated-operations
  )

  if [[ -n "$base_url" ]]; then
    cmd+=(--base-url "$base_url")
  fi

  if [[ -n "$security_schemes" ]]; then
    local IFS=';'
    for scheme in $security_schemes; do
      [[ -n "$scheme" ]] && cmd+=(--security-scheme "$scheme")
    done
  fi

  if detect_generate_flag "$generate_script" "--ignore-openapi-errors"; then
    cmd+=(--ignore-openapi-errors)
  fi

  {
    printf '\n# %s\n' "$repo_name"
    printf '(\n'
    printf '  cd %s\n' "$(shell_quote "$repo")"
    printf '  rm -rf %s\n' "$(shell_quote "$output_rel")"
    printf '  %s\n' "$(shell_quote "${cmd[@]}")"
    printf ')\n'
  } >> "$COMMANDS"
}

run_build_probe() {
  local repo="$1"
  local repo_name="$2"
  local sdk_project_rel="$3"
  local spec_rel="$4"
  local manual_cli_projects="$5"
  local generated_cli_projects="$6"
  local generate_script="$7"

  local log_dir="$OUT_DIR/probe-logs"
  mkdir -p "$log_dir"

  local existing_project=""
  if [[ -n "$generated_cli_projects" ]]; then
    existing_project="$(first_item "$generated_cli_projects")"
  elif [[ -n "$manual_cli_projects" ]]; then
    existing_project="$(first_item "$manual_cli_projects")"
  fi

  if [[ -n "$existing_project" ]]; then
    local log="$log_dir/${repo_name}-existing.log"
    if dotnet build "$repo/$existing_project" >"$log" 2>&1; then
      printf 'pass:%s\n' "$existing_project"
    else
      printf 'fail:%s\n' "$log"
    fi
    return 0
  fi

  local probe_dir
  probe_dir="$(realpath_portable "$OUT_DIR/probes/$repo_name")"
  local log="$log_dir/${repo_name}-generated.log"
  rm -rf "$probe_dir"

  local namespace client target package_id tool_name env_prefix base_url security_schemes
  namespace="$(detect_first_generate_arg_value "$generate_script" "--namespace")"
  client="$(detect_first_generate_arg_value "$generate_script" "--clientClassName")"
  target="$(detect_first_generate_arg_value "$generate_script" "--targetFramework")"
  base_url="$(first_item "$(detect_generate_arg_values "$generate_script" "--base-url")")"
  security_schemes="$(detect_generate_arg_values "$generate_script" "--security-scheme")"
  namespace="${namespace:-$repo_name}"
  client="${client:-${repo_name}Client}"
  target="${target:-net10.0}"
  package_id="${repo_name}.CLI.Probe"
  tool_name="$(to_kebab "$repo_name")-probe"
  env_prefix="$(to_env_prefix "$repo_name")"
  local spec_abs sdk_project_abs
  spec_abs="$(realpath_portable "$repo/$spec_rel")"
  sdk_project_abs="$(realpath_portable "$repo/$sdk_project_rel")"

  local cmd=(
    "${AUTOSDK_CMD[@]}"
    cli-project "$spec_abs"
    --output "$probe_dir"
    --sdk-project "$sdk_project_abs"
    --targetFramework "$target"
    --namespace "$namespace"
    --clientClassName "$client"
    --package-id "$package_id"
    --tool-command-name "$tool_name"
    --api-key-env-var "${env_prefix}_API_KEY"
    --exclude-deprecated-operations
  )

  if [[ -n "$base_url" ]]; then
    cmd+=(--base-url "$base_url")
  fi

  if [[ -n "$security_schemes" ]]; then
    local IFS=';'
    for scheme in $security_schemes; do
      [[ -n "$scheme" ]] && cmd+=(--security-scheme "$scheme")
    done
  fi

  if detect_generate_flag "$generate_script" "--ignore-openapi-errors"; then
    cmd+=(--ignore-openapi-errors)
  fi

  if ! "${cmd[@]}" >"$log" 2>&1; then
    printf 'generate-fail:%s\n' "$log"
    return 0
  fi

  local probe_project
  probe_project="$(find_first "$probe_dir" -maxdepth 1 -name '*.csproj')"
  if [[ -z "$probe_project" ]]; then
    printf 'generate-fail:%s\n' "$log"
    return 0
  fi

  if dotnet build "$probe_project" >>"$log" 2>&1; then
    printf 'pass:probe\n'
  else
    printf 'fail:%s\n' "$log"
  fi
}

{
  printf '#!/usr/bin/env bash\n'
  printf 'set -euo pipefail\n\n'
  printf '# Generated by scripts/audit-generated-cli-rollout.sh\n'
  printf '# Set TRYAGI_AUTOSDK_CLI before running the audit if these commands should use a local AutoSDK checkout.\n'
} > "$COMMANDS"

{
  printf 'repo\tsdk_project\tspec\toperation_count\tsecurity_schemes\tbase_url_override\tmanual_cli_projects\tgenerated_api_sources\tgenerated_cli_projects\tsolution_cli_gaps\ttrim_candidates\tbuild_probe\tnotes\n'

  probe_count=0
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
      solution_cli_gaps="$(detect_solution_cli_gaps "$repo" "$generated_cli_projects")"
      generate_script="$(detect_generate_script "$spec")"
      operation_count="$(count_openapi_operations "$spec")"
      security_schemes="$(detect_generate_arg_values "$generate_script" "--security-scheme")"
      base_url_override="$(detect_generate_arg_values "$generate_script" "--base-url")"
      trim_candidates="${generated_cli_projects:-$manual_cli_projects}"
      notes=ready
      if [[ -n "$solution_cli_gaps" ]]; then
        notes=generated-cli-missing-solution
      elif [[ -n "$generated_cli_projects" ]]; then
        notes=ready
      elif [[ -z "$manual_cli_projects" ]]; then
        notes=needs-cli-project
      elif [[ -z "$generated_api_sources" ]]; then
        notes=manual-cli-needs-generated-api
      fi
      build_probe=not-run
      if [[ "$PROBE_BUILDS" == true ]]; then
        if [[ "$PROBE_LIMIT" -le 0 || "$probe_count" -lt "$PROBE_LIMIT" ]]; then
          build_probe="$(run_build_probe "$repo" "$repo_name" "$(relpath "$sdk_project" "$repo")" "$(relpath "$spec" "$repo")" "$manual_cli_projects" "$generated_cli_projects" "$generate_script")"
          probe_count=$((probe_count + 1))
        else
          build_probe=skipped-limit
        fi
      fi
      if [[ "$notes" == "needs-cli-project" ]]; then
        append_rollout_command "$repo" "$repo_name" "$(relpath "$sdk_project" "$repo")" "$(relpath "$spec" "$repo")" "$generate_script"
      fi

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$repo_name" \
        "$(relpath "$sdk_project" "$repo")" \
        "$(relpath "$spec" "$repo")" \
        "$operation_count" \
        "$security_schemes" \
        "$base_url_override" \
        "$manual_cli_projects" \
        "$generated_api_sources" \
        "$generated_cli_projects" \
        "$solution_cli_gaps" \
        "$trim_candidates" \
        "$build_probe" \
        "$notes"
    done
} > "$TSV"

chmod +x "$COMMANDS"

python3 - "$TSV" "$MD" "$COMMANDS" <<'PY'
import csv
import sys

tsv_path, md_path, commands_path = sys.argv[1], sys.argv[2], sys.argv[3]

def value(row, key, default="none"):
    return row.get(key) or default

with open(tsv_path, newline="", encoding="utf-8") as handle:
    rows = list(csv.DictReader(handle, delimiter="\t"))

with open(md_path, "w", encoding="utf-8") as handle:
    handle.write("# Generated CLI Rollout Audit\n\n")
    handle.write(f"Source: `{tsv_path}`\n\n")
    handle.write(f"Commands: `{commands_path}`\n\n")
    handle.write("| Repo | SDK project | Spec | Ops | Auth override | Base URL override | Manual CLI | Generated API sources | Generated CLI project | Solution CLI gaps | Build probe | Notes |\n")
    handle.write("| --- | --- | --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |\n")
    for row in rows:
        handle.write(
            f"| {row['repo']} | `{row['sdk_project']}` | `{row['spec']}` | "
            f"{row['operation_count']} | {value(row, 'security_schemes')} | "
            f"{value(row, 'base_url_override')} | {value(row, 'manual_cli_projects')} | "
            f"{value(row, 'generated_api_sources')} | {value(row, 'generated_cli_projects')} | "
            f"{value(row, 'solution_cli_gaps')} | "
            f"{row['build_probe']} | {row['notes']} |\n"
        )
PY

echo "Wrote $TSV"
echo "Wrote $MD"
echo "Wrote $COMMANDS"
