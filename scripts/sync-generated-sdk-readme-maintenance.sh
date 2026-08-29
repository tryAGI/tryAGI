#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
AUDIT_SCRIPT="$ROOT_DIR/scripts/audit-generated-sdks.sh"
TEMPLATE_PATH="$ROOT_DIR/AutoSDK/src/libs/AutoSDK.CLI/Resources/README.md"
START_MARKER='<!-- AUTOSDK:ECOSYSTEM-MAINTENANCE:START -->'
END_MARKER='<!-- AUTOSDK:ECOSYSTEM-MAINTENANCE:END -->'
MODE="check"
REPO_FILTER=""

usage() {
  cat <<'EOF'
Usage: ./scripts/sync-generated-sdk-readme-maintenance.sh [check|apply] [--repo REGEX]

Modes:
  check        Verify every selected generated SDK README contains the exact maintained block.
  apply        Insert or update the maintained block without changing any other README content.

Options:
  --repo REGEX Only include repository names matching the regular expression.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    check|apply)
      MODE="$1"
      shift
      ;;
    --repo)
      REPO_FILTER="${2:-}"
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

[[ -f "$TEMPLATE_PATH" ]] || {
  echo "Missing AutoSDK README template: $TEMPLATE_PATH" >&2
  exit 1
}

repos_command=("$AUDIT_SCRIPT" repos)
if [[ -n "$REPO_FILTER" ]]; then
  repos_command+=(--repo "$REPO_FILTER")
fi

repos_path="$(mktemp -t autosdk-readme-repos)"
trap 'rm -f "$repos_path"' EXIT
"${repos_command[@]}" > "$repos_path"

python3 - "$MODE" "$ROOT_DIR" "$TEMPLATE_PATH" "$START_MARKER" "$END_MARKER" "$repos_path" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

mode, root_value, template_value, start_marker, end_marker, repos_value = sys.argv[1:]
root = Path(root_value)
template_path = Path(template_value)
repos = [line.strip() for line in Path(repos_value).read_text(encoding="utf-8").splitlines() if line.strip()]


def extract_block(text: str, source: Path) -> str:
    start = text.find(start_marker)
    end = text.find(end_marker, start + len(start_marker))
    if start < 0 or end < 0:
        raise SystemExit(f"Missing maintenance markers in {source}")
    duplicate = text.find(start_marker, start + len(start_marker))
    if duplicate >= 0:
        raise SystemExit(f"Duplicate maintenance start marker in {source}")
    return text[start : end + len(end_marker)]


canonical = extract_block(template_path.read_text(encoding="utf-8"), template_path)
changed = []
failed = []

for repo in repos:
    repo_path = root / repo
    readme_path = repo_path / "README.md"
    if not readme_path.is_file():
        failed.append((repo, "missing README.md"))
        continue

    text = readme_path.read_text(encoding="utf-8")
    try:
        current = extract_block(text, readme_path)
    except SystemExit as error:
        if start_marker in text or end_marker in text:
            failed.append((repo, str(error)))
            continue
        current = None

    if current == canonical:
        continue

    changed.append(repo)
    if mode == "check":
        continue

    status = subprocess.run(
        ["git", "-C", str(repo_path), "status", "--porcelain"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    if status:
        failed.append((repo, "working tree is not clean"))
        continue

    if current is not None:
        updated = text.replace(current, canonical, 1)
    else:
        heading = re.search(r"(?m)^##+ (?:Support|Acknowledgments|License)\s*$", text)
        if heading:
            insertion = heading.start()
            updated = text[:insertion].rstrip() + "\n\n" + canonical + "\n\n" + text[insertion:]
        else:
            updated = text.rstrip() + "\n\n" + canonical + "\n"

    readme_path.write_text(updated, encoding="utf-8")

for repo, reason in failed:
    print(f"{repo}\tfailed\t{reason}", file=sys.stderr)

if mode == "check":
    for repo in changed:
        print(f"{repo}\tout-of-date")
    print(f"Checked repositories: {len(repos)}")
    print(f"Out-of-date READMEs: {len(changed)}")
else:
    for repo in changed:
        if not any(failed_repo == repo for failed_repo, _ in failed):
            print(f"{repo}\tupdated")
    print(f"Selected repositories: {len(repos)}")
    print(f"Updated READMEs: {len(changed) - sum(1 for repo, _ in failed if repo in changed)}")

if failed or (mode == "check" and changed):
    raise SystemExit(2)
PY
