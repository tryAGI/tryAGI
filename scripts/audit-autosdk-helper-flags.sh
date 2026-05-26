#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="${TRYAGI_AUTOSDK_HELPER_AUDIT_OUT_DIR:-/tmp/tryagi-sdk-audit}"
MODE="summary"
REPO_FILTER=""

HELPER_FLAGS=(
  "--generate-http-exception-hierarchy"
  "--generate-retry-handler"
  "--generate-pageable-helpers"
  "--generate-multipart-upload-helpers"
)

SUPPRESSION_CODES=(
  "CS1570"
  "CS1584"
  "CS1658"
  "CS0419"
)

usage() {
  cat <<'EOF'
Usage: ./scripts/audit-autosdk-helper-flags.sh [summary|tsv|check] [--repo REGEX] [--out-dir PATH]

Modes:
  summary    Write a TSV report and print a short summary.
  tsv        Write the TSV report and print its path.
  check      Write the TSV report and exit non-zero when any repo is missing helper flags.

Options:
  --repo REGEX   Only include repo names matching the regular expression.
  --out-dir PATH Override the output directory. Default: /tmp/tryagi-sdk-audit
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      summary|tsv|check)
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

find_generate_script() {
  local repo_dir="$1"
  local script=""

  script="$(find "$repo_dir/src/libs" -mindepth 2 -maxdepth 2 -name generate.sh -print -quit 2>/dev/null || true)"
  printf '%s' "$script"
}

collect_rows() {
  local repo_dir repo_name script script_rel text flag
  local http_exceptions retry pageable multipart missing_flags
  local csproj temp_xml_nowarn suppressions

  for repo_dir in "$ROOT_DIR"/*; do
    [[ -d "$repo_dir/.git" ]] || continue
    repo_name="${repo_dir##*/}"

    if [[ -n "$REPO_FILTER" ]] && ! [[ "$repo_name" =~ $REPO_FILTER ]]; then
      continue
    fi

    script="$(find_generate_script "$repo_dir")"
    [[ -n "$script" ]] || continue

    text="$(<"$script")"
    script_rel="${script#$ROOT_DIR/}"

    http_exceptions="no"
    retry="no"
    pageable="no"
    multipart="no"
    missing_flags=()

    for flag in "${HELPER_FLAGS[@]}"; do
      if grep -Fq -- "$flag" <<< "$text"; then
        case "$flag" in
          --generate-http-exception-hierarchy) http_exceptions="yes" ;;
          --generate-retry-handler) retry="yes" ;;
          --generate-pageable-helpers) pageable="yes" ;;
          --generate-multipart-upload-helpers) multipart="yes" ;;
        esac
      else
        missing_flags+=("$flag")
      fi
    done

    suppressions=""
    while IFS= read -r csproj; do
      [[ -n "$csproj" ]] || continue
      for code in "${SUPPRESSION_CODES[@]}"; do
        if grep -Fq -- "$code" "$csproj"; then
          suppressions+="${code},"
        fi
      done
    done < <(find "$repo_dir/src/libs" -name '*.csproj' -print 2>/dev/null)

    if [[ -n "$suppressions" ]]; then
      temp_xml_nowarn="$(printf '%s' "$suppressions" | tr ',' '\n' | awk 'NF && !seen[$0]++' | paste -sd ',' -)"
    else
      temp_xml_nowarn=""
    fi

    local missing_flags_text=""
    if ((${#missing_flags[@]} > 0)); then
      missing_flags_text="$(IFS=,; printf '%s' "${missing_flags[*]}")"
    fi

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$repo_name" \
      "$script_rel" \
      "$http_exceptions" \
      "$retry" \
      "$pageable" \
      "$multipart" \
      "$missing_flags_text" \
      "$temp_xml_nowarn"
  done | sort
}

write_report() {
  local report_path="$OUT_DIR/autosdk-helper-flags.tsv"
  mkdir -p "$OUT_DIR"
  {
    printf 'repo\tgenerate_script\thttp_exceptions\tretry\tpageable\tmultipart\tmissing_flags\ttemp_xml_nowarn\n'
    collect_rows
  } > "$report_path"
  printf '%s' "$report_path"
}

print_summary() {
  local report_path="$1"
  local total missing helper_ready temp_xml

  total="$(tail -n +2 "$report_path" | grep -c . || true)"
  missing="$(tail -n +2 "$report_path" | awk -F '\t' 'NF >= 7 && $7 != "" { count++ } END { print count + 0 }')"
  helper_ready="$(tail -n +2 "$report_path" | awk -F '\t' 'NF >= 7 && $7 == "" { count++ } END { print count + 0 }')"
  temp_xml="$(tail -n +2 "$report_path" | awk -F '\t' 'NF >= 8 && $8 != "" { count++ } END { print count + 0 }')"

  echo "Report: $report_path"
  echo "SDK repos scanned: $total"
  echo "Repos with all helper flags: $helper_ready"
  echo "Repos still missing one or more helper flags: $missing"
  echo "Repos still carrying temporary XML-doc suppressions: $temp_xml"

  echo
  echo "Missing helper flags:"
  tail -n +2 "$report_path" | awk -F '\t' 'NF >= 7 && $7 != "" { printf "%s\t%s\n", $1, $7 }'

  echo
  echo "Temporary XML-doc suppressions:"
  tail -n +2 "$report_path" | awk -F '\t' 'NF >= 8 && $8 != "" { printf "%s\t%s\n", $1, $8 }'
}

main() {
  local report_path

  parse_args "$@"
  report_path="$(write_report)"

  case "$MODE" in
    summary)
      print_summary "$report_path"
      ;;
    tsv)
      echo "$report_path"
      ;;
    check)
      print_summary "$report_path"
      if tail -n +2 "$report_path" | awk -F '\t' 'NF >= 7 && $7 != "" { exit 1 }'; then
        exit 0
      else
        echo
        echo "Helper flag drift detected." >&2
        exit 1
      fi
      ;;
  esac
}

main "$@"
