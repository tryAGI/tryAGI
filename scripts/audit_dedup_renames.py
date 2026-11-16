#!/usr/bin/env python3
"""List the public type renames a generator change causes, per spec, from AutoSDK's snapshot tree.

Counting how many numbered names disappear says nothing about what a consumer has to edit. Removing
`FooResponse2` while `FooResponse` stays is invisible to anyone who was using `FooResponse`. Renaming
`FinetuneEvent` to `FineTuneEvent2` is a compile break in their code. Both show up as "one fewer
collision".

So this classifies every per-spec name change into four kinds:

- **collapsed** - a numbered name is gone and its un-suffixed base survives. The dedup did its job
  and only consumers of the numbered name are affected.
- **renamed** - a name is gone and a numbered or differently-cased sibling appeared in its place.
  This is the breaking kind: code that named the old type stops compiling.
- **added** - a name that did not exist before, with nothing plausible to pair it with.
- **removed** - gone with nothing to pair it with.

Renames are split by direction, because the two are opposite news for a consumer:

- **to a bare name** (`ToolChoice2` -> `ToolChoice`, `Model14` -> `Model`) is the improvement the
  dedup exists for. It still breaks code that named the numbered type.
- **to a numbered name** (`FinetuneEvent` -> `FinetuneEvent2`) is the regression: a type that had a
  clean name acquires a digit.

Pairing is by base name with numbering stripped, and within one base group it is **positional, not
semantic** - the script cannot know which new name is which old one. together is the honest example:
`{FinetuneEvent, FineTuneEvent2}` became `{FineTuneEvent, FinetuneEvent2}`, and reporting that as
`FineTuneEvent2 -> FineTuneEvent` plus `FinetuneEvent -> FinetuneEvent2` is one reading; the other
is `FinetuneEvent -> FineTuneEvent` as a casing fix plus `FineTuneEvent2 -> FinetuneEvent2`. The
counts and the membership are exact; which arrow goes where, inside a base group, is not.

Usage:
    scripts/audit_dedup_renames.py [--repo PATH] --before REV --after REV [--spec NAME]
"""

from __future__ import annotations

import argparse
import collections
import pathlib
import re
import subprocess
import sys

SNAPSHOTS = "src/tests/AutoSDK.SnapshotTests/Snapshots"
MODEL_FILE = re.compile(r"^_#.*\.Models\.([A-Za-z0-9_]+)\.g\.verified\.cs$")
SKIP_DIRS = re.compile(r"^(CLI|Empty|Parallel|DependencyInjection|HttpResilience|CloudSigning)")
STRIP = re.compile(r"\d+$")


def names_at(repo: pathlib.Path, rev: str) -> dict[str, set[str]]:
    """Generated model type names per spec directory, as of one revision."""
    listing = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "-r", "--name-only", rev, "--", SNAPSHOTS],
        capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    prefix = SNAPSHOTS + "/"
    found: dict[str, set[str]] = collections.defaultdict(set)
    for path in listing:
        if not path.startswith(prefix):
            continue
        relative = path[len(prefix):]
        parts = relative.split("/")
        if len(parts) < 2 or SKIP_DIRS.match(parts[0]):
            continue
        match = MODEL_FILE.match(parts[-1])
        if match:
            found[parts[0]].add(match.group(1))
    return found


def classify(before: set[str], after: set[str]):
    gone = sorted(before - after)
    new = sorted(after - before)

    # Group both sides by base name, so a name that left and a sibling that arrived under the same
    # base can be paired. Case is ignored because the generator's own collision grouping ignores it.
    new_by_base: dict[str, list[str]] = collections.defaultdict(list)
    for name in new:
        new_by_base[STRIP.sub("", name).lower()].append(name)

    collapsed, renamed, removed = [], [], []
    for name in gone:
        base = STRIP.sub("", name)
        candidates = new_by_base.get(base.lower())
        if candidates:
            # Something arrived under the same base: the type did not vanish, it changed name.
            renamed.append((name, candidates.pop(0)))
        elif name != base and base in after:
            # A numbered name went away and its bare base is still there - a pure collapse.
            collapsed.append(name)
        else:
            removed.append(name)

    added = sorted(n for group in new_by_base.values() for n in group)
    return collapsed, renamed, added, removed


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--repo", default=str(pathlib.Path.home() / "GitHub/tryAGI/AutoSDK"))
    parser.add_argument("--before", required=True)
    parser.add_argument("--after", required=True)
    parser.add_argument("--spec", help="report one spec in full instead of the summary")
    args = parser.parse_args()

    repo = pathlib.Path(args.repo)
    before_all = names_at(repo, args.before)
    after_all = names_at(repo, args.after)

    totals = collections.Counter()
    per_spec = {}
    for spec in sorted(set(before_all) | set(after_all)):
        result = classify(before_all.get(spec, set()), after_all.get(spec, set()))
        collapsed, renamed, added, removed = result
        if not (collapsed or renamed or added or removed):
            continue
        per_spec[spec] = result
        totals["collapsed"] += len(collapsed)
        totals["renamed"] += len(renamed)
        for old, new in renamed:
            # A rename onto a bare name is the dedup working; onto a numbered one it is a type
            # losing a clean name. Opposite news for a consumer, so never one number.
            totals["to_bare" if not STRIP.search(new) else "to_numbered"] += 1
        totals["added"] += len(added)
        totals["removed"] += len(removed)

    if args.spec:
        result = per_spec.get(args.spec)
        if result is None:
            print(f"{args.spec}: no change between {args.before} and {args.after}")
            return 0
        collapsed, renamed, added, removed = result
        print(f"{args.spec}: {args.before} -> {args.after}")
        print(f"\nRENAMED - breaking for consumers ({len(renamed)}):")
        for old, new in renamed:
            print(f"  {old}  ->  {new}")
        print(f"\ncollapsed - numbered name gone, base survives ({len(collapsed)}):")
        for name in collapsed:
            print(f"  {name}")
        print(f"\nadded ({len(added)}):")
        for name in added:
            print(f"  {name}")
        print(f"\nremoved ({len(removed)}):")
        for name in removed:
            print(f"  {name}")
        return 0

    print(f"{args.before} -> {args.after}, {len(per_spec)} specs changed")
    print(f"  RENAMED (breaking):  {totals['renamed']}")
    print(f"    onto a bare name:  {totals['to_bare']}  (the improvement)")
    print(f"    onto a number:     {totals['to_numbered']}  (a clean name lost)")
    print(f"  collapsed:           {totals['collapsed']}")
    print(f"  added:               {totals['added']}")
    print(f"  removed:             {totals['removed']}")
    print("\nspecs with the most breaking renames:")
    worst = collections.Counter({s: len(r[1]) for s, r in per_spec.items() if r[1]})
    for spec, count in worst.most_common(15):
        sample = ", ".join(f"{o}->{n}" for o, n in per_spec[spec][1][:2])
        print(f"  {spec}: {count} — {sample}")
    if not worst:
        print("  (none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
