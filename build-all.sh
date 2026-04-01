#!/usr/bin/env bash
#
# build-all.sh — Batch build verification for all tryAGI SDK repos.
#
# Loops through every direct subdirectory that contains a .slnx file,
# runs `dotnet build`, and prints a pass/fail summary.
#
# Usage:
#   ./build-all.sh              # build all repos
#   ./build-all.sh --parallel   # build up to N repos in parallel (N = CPU count)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------
PARALLEL=false
if [[ "${1:-}" == "--parallel" ]]; then
    PARALLEL=true
fi

# ---------------------------------------------------------------------------
# Discover repos
# ---------------------------------------------------------------------------
declare -a REPOS=()
for dir in "$SCRIPT_DIR"/*/; do
    dir="${dir%/}"
    # Find the first .slnx file in the directory root
    slnx_file="$(find "$dir" -maxdepth 1 -name '*.slnx' -print -quit 2>/dev/null)"
    if [[ -n "$slnx_file" ]]; then
        REPOS+=("$dir")
    fi
done

if [[ ${#REPOS[@]} -eq 0 ]]; then
    echo "No repos with .slnx files found in $SCRIPT_DIR"
    exit 1
fi

echo "========================================"
echo " tryAGI Batch Build"
echo " Found ${#REPOS[@]} repos with .slnx files"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Build function
# ---------------------------------------------------------------------------
build_repo() {
    local repo_dir="$1"
    local repo_name
    repo_name="$(basename "$repo_dir")"

    # Locate the .slnx file (handles cases like PrivateJoi/Joi.slnx)
    local slnx_file
    slnx_file="$(find "$repo_dir" -maxdepth 1 -name '*.slnx' -print -quit)"

    local log_file
    log_file="$(mktemp "/tmp/build-${repo_name}.XXXXXX.log")"

    if dotnet build "$slnx_file" --nologo -v quiet > "$log_file" 2>&1; then
        echo "  OK      $repo_name"
        rm -f "$log_file"
        return 0
    else
        echo "  FAILED  $repo_name  (log: $log_file)"
        return 1
    fi
}

export -f build_repo  # needed for parallel xargs

# ---------------------------------------------------------------------------
# Run builds
# ---------------------------------------------------------------------------
SUCCEEDED=0
FAILED=0
declare -a FAILED_REPOS=()

if $PARALLEL; then
    # Parallel mode — run builds via background jobs, capped at CPU count
    MAX_JOBS="$(sysctl -n hw.logicalcpu 2>/dev/null || nproc 2>/dev/null || echo 4)"
    echo "Building in parallel (max $MAX_JOBS jobs)..."
    echo ""

    declare -A PIDS=()
    RUNNING=0

    for repo_dir in "${REPOS[@]}"; do
        # Wait if we've hit the job limit
        while (( RUNNING >= MAX_JOBS )); do
            for pid in "${!PIDS[@]}"; do
                if ! kill -0 "$pid" 2>/dev/null; then
                    wait "$pid" && status=0 || status=$?
                    repo_name="${PIDS[$pid]}"
                    if [[ $status -eq 0 ]]; then
                        (( SUCCEEDED++ ))
                    else
                        (( FAILED++ ))
                        FAILED_REPOS+=("$repo_name")
                    fi
                    unset "PIDS[$pid]"
                    (( RUNNING-- ))
                fi
            done
            sleep 0.1
        done

        build_repo "$repo_dir" &
        PIDS[$!]="$(basename "$repo_dir")"
        (( RUNNING++ ))
    done

    # Wait for remaining jobs
    for pid in "${!PIDS[@]}"; do
        wait "$pid" && status=0 || status=$?
        repo_name="${PIDS[$pid]}"
        if [[ $status -eq 0 ]]; then
            (( SUCCEEDED++ ))
        else
            (( FAILED++ ))
            FAILED_REPOS+=("$repo_name")
        fi
    done
else
    # Sequential mode (default)
    echo "Building sequentially..."
    echo ""

    for repo_dir in "${REPOS[@]}"; do
        repo_name="$(basename "$repo_dir")"
        if build_repo "$repo_dir"; then
            (( SUCCEEDED++ ))
        else
            (( FAILED++ ))
            FAILED_REPOS+=("$repo_name")
        fi
    done
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "========================================"
echo " Summary"
echo "========================================"
echo "  Succeeded: $SUCCEEDED"
echo "  Failed:    $FAILED"
echo "  Total:     ${#REPOS[@]}"

if [[ $FAILED -gt 0 ]]; then
    echo ""
    echo "  Failed repos:"
    for name in "${FAILED_REPOS[@]}"; do
        echo "    - $name"
    done
    echo ""
    echo "  Check the log files above for details."
    exit 1
else
    echo ""
    echo "  All builds passed!"
    exit 0
fi
