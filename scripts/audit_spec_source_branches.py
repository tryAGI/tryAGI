#!/usr/bin/env python3
"""Find SDKs whose spec is fetched from a branch upstream has stopped moving.

Each SDK's auto-update workflow compares the fetched spec with the committed one. A spec fetched from
a branch upstream froze never differs, so no PR is opened and the SDK looks current while falling
behind. Runway hit this with `runwayml/openapi`'s `next` branch and sat 29 models and a whole
endpoint behind for weeks.

Runway now carries `scripts/check-spec-source.sh`, which fails its own CI when the fetch points
anywhere but the upstream default branch. This is that check done once for every SDK instead of
copied into fifty repositories and wired into fifty workflows — the same question, asked from the
place that can see all of them.

Three answers, and the second is the one that matters:

- **default** — the fetch points at the upstream default branch. Nothing to do.
- **non-default** — a named branch that is not the default. Reported with both branches' last commit
  dates, because "not default" is only a problem when the branch has also stopped moving.
- **pinned** — a commit SHA. Frozen deliberately and visible in `generate.sh`; Letta pins one
  because upstream deleted the spec from `main` entirely. Not a defect, but worth re-reading
  occasionally.
- **unresolved** — the ref comes from a shell variable. Reported rather than guessed at.

Needs `gh` authenticated for the branch dates.

Usage:
    scripts/audit_spec_source_branches.py [--sdk NAME] [--offline]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
# raw.githubusercontent.com/<owner>/<repo>/<ref...>/<path>, where <ref> is `refs/heads/x`, a tag, a
# branch name or a SHA. The spec filename varies per SDK, so match any document.
RAW = re.compile(
    r"raw\.githubusercontent\.com/([A-Za-z0-9_.\-]+)/([A-Za-z0-9_.\-]+)/"
    r"(refs/heads/[^/\s\"']+|refs/tags/[^/\s\"']+|[^/\s\"']+)/"
)
SHA = re.compile(r"^[0-9a-f]{7,40}$")
# Refs that are off the default branch on purpose, with the reason. Without this the check can never
# be a gate: it would exit 1 for ever on a ref that is correct, and a permanently red check is one
# nobody reads. A row here is a claim that someone looked, so it carries the reason, and the audit
# still prints these so they can be re-read rather than forgotten.
DELIBERATE = {
    ("Julep", "julep-ai/julep", "v1"): (
        "this SDK is for Julep v1, which upstream preserved on the `v1` branch; `main` is Julep 3, "
        "a ground-up rewrite with no migration path and no OpenAPI document - a different API"
    ),
}
# `spec_revision="56ba9c..."` two lines above the URL. Resolving these is what tells a deliberate
# commit pin (Letta) apart from a ref nobody can determine, and the difference matters: one is a
# decision, the other is a gap in this audit.
ASSIGNMENT = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)=[\"']?([^\"'\s$]+)[\"']?\s*$", re.M)


def github(path: str):
    result = subprocess.run(["gh", "api", path], capture_output=True, text=True)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def last_commit(repo: str, ref: str) -> str:
    data = github(f"repos/{repo}/branches/{ref}")
    if not data:
        return "unknown"
    return (data.get("commit", {}).get("commit", {}).get("committer", {}).get("date") or "unknown")[:10]


def resolve(ref: str, script_text: str) -> str:
    """Substitute a `$var` or `${var}` ref from a literal assignment in the same script."""
    bare = ref.strip("${}")
    if "$" not in ref and "{" not in ref:
        return ref
    for name, value in ASSIGNMENT.findall(script_text):
        if name == bare:
            return value
    return ref


def classify(ref: str) -> str:
    if ref.startswith("refs/tags/"):
        return "tag"
    name = ref.removeprefix("refs/heads/")
    if "$" in name or "{" in name:
        return "unresolved"
    if SHA.match(name):
        return "pinned"
    return "branch"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk")
    parser.add_argument("--offline", action="store_true",
                        help="skip the GitHub calls; report refs without comparing dates")
    args = parser.parse_args()

    non_default, pinned, unresolved, deliberate, fine = [], [], [], [], 0

    for script in sorted(WORKSPACE.glob("*/src/libs/*/generate.sh")):
        sdk = script.relative_to(WORKSPACE).parts[0]
        if args.sdk and sdk != args.sdk:
            continue
        try:
            text = script.read_text(errors="replace")
        except OSError:
            continue

        for owner, repo_name, ref in sorted(set(RAW.findall(text))):
            repo = f"{owner}/{repo_name}"
            resolved = resolve(ref, text)
            kind = classify(resolved)
            name = resolved.removeprefix("refs/heads/")

            if kind == "unresolved":
                unresolved.append((sdk, repo, name))
                continue
            if kind == "pinned":
                pinned.append((sdk, repo, name))
                continue
            if kind == "tag":
                fine += 1
                continue
            if args.offline:
                if name in ("main", "master"):
                    fine += 1
                elif (sdk, repo, name) in DELIBERATE:
                    deliberate.append((sdk, repo, name, DELIBERATE[(sdk, repo, name)]))
                else:
                    non_default.append((sdk, repo, name, "?", "?", "?"))
                continue

            info = github(f"repos/{repo}")
            default = (info or {}).get("default_branch")
            if default is None:
                unresolved.append((sdk, repo, f"{name} (repository unreachable)"))
                continue
            if name == default:
                fine += 1
                continue
            if (sdk, repo, name) in DELIBERATE:
                deliberate.append((sdk, repo, name, DELIBERATE[(sdk, repo, name)]))
                continue
            non_default.append((sdk, repo, name, last_commit(repo, name),
                                default, last_commit(repo, default)))

    print(f"spec fetches pointing at the upstream default branch or a tag: {fine}")
    print(f"pointing at another branch: {len(non_default)}")
    for sdk, repo, name, name_date, default, default_date in non_default:
        stale = name_date != "unknown" and default_date != "unknown" and name_date < default_date
        print(f"  {sdk}: {repo} @ {name} (last {name_date})"
              f" vs default {default} (last {default_date})"
              + ("   <- the fetched branch is behind" if stale else ""))
    if deliberate:
        print(f"\noff the default branch on purpose: {len(deliberate)}")
        for sdk, repo, name, reason in deliberate:
            print(f"  {sdk}: {repo} @ {name}\n      {reason}")
    if pinned:
        print(f"\npinned to a commit, frozen by design: {len(pinned)}")
        for sdk, repo, name in pinned:
            print(f"  {sdk}: {repo} @ {name[:12]}")
    if unresolved:
        print(f"\nref not determinable from the script: {len(unresolved)}")
        for sdk, repo, name in unresolved:
            print(f"  {sdk}: {repo} @ {name}")
    return 1 if non_default else 0


if __name__ == "__main__":
    sys.exit(main())
