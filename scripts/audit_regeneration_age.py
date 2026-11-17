#!/usr/bin/env python3
"""How long since each SDK's generated code last changed, and whether that is a problem.

A regeneration can break a build with no spec change at all - tryAGI/Julep stopped compiling on
2026-11-17 because a released `autosdk.cli` had started mapping `format: int8` to `sbyte`, with its
spec byte-identical. That makes "which SDKs have not been regenerated in a long time" a real
question: the longer one sits, the more generator drift it will absorb at once, and it will absorb it
on an auto-update PR nobody wrote.

Asked on 2026-11-17, the answer was that there is nothing to do, which is why this script exists
rather than a batch of regenerations:

    1   2026-09-08   <- LMNT, archived on GitHub and retired on purpose
    99  2026-10-26   <- one mass regeneration
    rest             within the following three weeks

So the single outlier is deliberate, and a "controlled batch" had nothing to run on. Re-ask before
assuming that still holds - and read the `archived` column before regenerating anything, because an
archived repository cannot be pushed to and should not be touched.

The date is the last commit that touched the SDK's `Generated/` tree, not the repository's last
commit: CI spec refreshes, workflow changes and test commits all move the latter.

Usage:
    scripts/audit_regeneration_age.py [--limit N] [--check-archived]
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import subprocess
import sys

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent


def git(repo: pathlib.Path, *args: str) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True
    )
    return result.stdout.strip() if result.returncode == 0 else ""


def archived(repo_name: str) -> bool | None:
    result = subprocess.run(
        ["gh", "api", f"repos/tryAGI/{repo_name}", "--jq", ".archived"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--limit", type=int, default=15,
                        help="how many of the oldest to list individually")
    parser.add_argument("--check-archived", action="store_true",
                        help="ask GitHub whether each listed repository is archived (needs gh)")
    args = parser.parse_args()

    rows = []
    for generated in sorted(WORKSPACE.glob("*/src/libs/*/Generated")):
        if not generated.is_dir():
            continue
        repo = WORKSPACE / generated.relative_to(WORKSPACE).parts[0]
        if not (repo / ".git").exists():
            continue
        relative = generated.relative_to(repo).as_posix()
        date = git(repo, "log", "-1", "--format=%cs", "--", relative)
        if not date:
            continue
        dirty = len([line for line in git(repo, "status", "--porcelain").splitlines() if line])
        rows.append((date, repo.name, dirty))

    if not rows:
        print(
            "error: found no SDK with a Generated/ tree. Run this where the SDK repositories are "
            "checked out beside this one; a run over nothing is not a pass.",
            file=sys.stderr,
        )
        return 2

    rows.sort()
    buckets = collections.Counter(date for date, _, _ in rows)
    print(f"SDKs with generated code: {len(rows)}")
    print(f"distinct regeneration dates: {len(buckets)}")
    print(f"\noldest {min(args.limit, len(rows))}:")
    for date, name, dirty in rows[: args.limit]:
        flags = []
        if dirty:
            flags.append(f"{dirty} uncommitted")
        if args.check_archived:
            state = archived(name)
            if state is True:
                flags.append("ARCHIVED - do not regenerate")
            elif state is None:
                flags.append("archived state unknown")
        suffix = f"   ({', '.join(flags)})" if flags else ""
        print(f"  {date}  {name}{suffix}")

    print("\nby date, most SDKs first:")
    for date, count in buckets.most_common(5):
        print(f"  {date}: {count}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
