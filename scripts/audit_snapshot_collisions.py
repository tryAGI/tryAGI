#!/usr/bin/env python3
"""Measure numbered type names in AutoSDK's snapshot baselines, before and after dedup.

Why not `audit_numeric_type_suffixes.py`: that one reads the sibling SDKs' committed `Generated/`
trees, and every one of those was produced by the *published* `autosdk` from NuGet. Generator-level
dedup is not released, so the workspace holds no post-dedup population at all and any split measured
there is contaminated by copies.

AutoSDK's own snapshot baselines are post-dedup, for ~110 real specs, and `HEAD` still holds the
pre-dedup version of the same files. That makes a controlled comparison: same specs, same generator,
the dedup the only difference.

Two numbers per side:

- **collisions** - `Name<N>` where `Name` also exists among the generated models. Counted from names
  alone, so the pre-dedup side needs nothing but `git ls-tree`.
- **the split**, for the post-dedup side only: of the collisions that survive, how many are
  distinguished by a response status code versus by something else. This is the number that decides
  whether a derived-name scheme can lean on status codes, and it is only meaningful once the copies
  are gone.

Usage:
    scripts/audit_snapshot_collisions.py [--repo PATH] [--rev HEAD] [--limit N]
"""

from __future__ import annotations

import argparse
import collections
import hashlib
import pathlib
import re
import subprocess
import sys

SNAPSHOTS = "src/tests/AutoSDK.SnapshotTests/Snapshots"
# Baselines are named `_#G.Models.<Type>.g.verified.cs`; the `.Json.g` partial is the same type.
MODEL_FILE = re.compile(r"^_#.*\.Models\.([A-Za-z0-9_]+)\.g\.verified\.cs$")
# Not collisions: union-variant naming is a separate mechanism, and a name the spec itself ends with
# a number (`TextScoreV3`, `CodeExecutionTool20260521`) is correct as it stands.
NOT_A_COLLISION = re.compile(r"Variant\d+$|V\d+$|\d{6,}$")
STRIP_NUMBERING = re.compile(r"(?<=[A-Za-z])\d{1,3}(?![0-9])")
# Directories that are generator-option fixtures rather than a provider spec.
SKIP_DIRS = re.compile(r"^(CLI|Empty|Parallel|DependencyInjection|HttpResilience|CloudSigning)")


def collisions_from_names(by_spec: dict[str, set[str]]) -> dict[str, list[str]]:
    """For each spec, the numbered names that collide with an existing un-suffixed name."""
    found: dict[str, list[str]] = {}
    for spec, names in by_spec.items():
        hits = []
        for name in sorted(names):
            if not re.search(r"\d$", name) or NOT_A_COLLISION.search(name):
                continue
            if re.sub(r"\d+$", "", name) in names:
                hits.append(name)
        if hits:
            found[spec] = hits
    return found


def spec_of(path: str) -> str | None:
    parts = path.split("/")
    if len(parts) < 2 or SKIP_DIRS.match(parts[0]):
        return None
    return parts[0]


def collect_from_disk(root: pathlib.Path) -> dict[str, set[str]]:
    by_spec: dict[str, set[str]] = collections.defaultdict(set)
    for entry in root.rglob("_#*.g.verified.cs"):
        match = MODEL_FILE.match(entry.name)
        if not match:
            continue
        spec = spec_of(str(entry.relative_to(root)))
        if spec:
            by_spec[spec].add(match.group(1))
    return by_spec


def collect_from_rev(repo: pathlib.Path, rev: str) -> dict[str, set[str]]:
    listing = subprocess.run(
        ["git", "-C", str(repo), "ls-tree", "-r", "--name-only", rev, "--", SNAPSHOTS],
        capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    by_spec: dict[str, set[str]] = collections.defaultdict(set)
    prefix = SNAPSHOTS + "/"
    for path in listing:
        if not path.startswith(prefix):
            continue
        relative = path[len(prefix):]
        match = MODEL_FILE.match(relative.split("/")[-1])
        if not match:
            continue
        spec = spec_of(relative)
        if spec:
            by_spec[spec].add(match.group(1))
    return by_spec


def shape(path: pathlib.Path) -> str | None:
    """A hash of the file with all type numbering erased, so a copy hashes like its original."""
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    return hashlib.sha256(
        re.sub(r"\s+", " ", STRIP_NUMBERING.sub("", text)).encode()
    ).hexdigest()


def classify_survivors(root: pathlib.Path, found: dict[str, list[str]]):
    """Split the surviving collisions into copies the dedup missed and genuinely different types."""
    missed_copies = collections.Counter()
    by_status = collections.Counter()
    by_other = collections.Counter()
    examples: dict[str, list[str]] = collections.defaultdict(list)

    for spec, names in found.items():
        for serializer in ("SystemTextJson", "NewtonsoftJson"):
            directory = root / spec / serializer
            if not directory.is_dir():
                continue
            for name in names:
                base = re.sub(r"\d+$", "", name)
                numbered = directory / f"_#G.Models.{name}.g.verified.cs"
                plain = directory / f"_#G.Models.{base}.g.verified.cs"
                if not numbered.is_file() or not plain.is_file():
                    continue
                if shape(numbered) == shape(plain) is not None:
                    missed_copies[spec] += 1
                    continue
                # A response-body type carries the operation's name; a status code is what tells two
                # of them apart. Nothing here invents that - it only asks whether the surviving
                # collision looks like one, which is what a derived-name scheme would key on.
                if re.search(r"(Response|Error|Result)$", base):
                    by_status[spec] += 1
                else:
                    by_other[spec] += 1
                if len(examples[spec]) < 3 and name not in examples[spec]:
                    examples[spec].append(name)
            break  # one serializer is enough; both emit the same model names

    return missed_copies, by_status, by_other, examples


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--repo", default=str(pathlib.Path.home() / "GitHub/tryAGI/AutoSDK"))
    parser.add_argument("--rev", default="HEAD", help="the pre-dedup revision (default HEAD)")
    parser.add_argument("--limit", type=int, default=12)
    args = parser.parse_args()

    repo = pathlib.Path(args.repo)
    root = repo / SNAPSHOTS
    if not root.is_dir():
        print(f"not a snapshot tree: {root}", file=sys.stderr)
        return 1

    before = collect_from_rev(repo, args.rev)
    after = collect_from_disk(root)

    before_hits = collisions_from_names(before)
    after_hits = collisions_from_names(after)
    before_total = sum(len(v) for v in before_hits.values())
    after_total = sum(len(v) for v in after_hits.values())

    before_types = sum(len(v) for v in before.values())
    after_types = sum(len(v) for v in after.values())

    print(f"specs measured: {len(after)}")
    print(f"generated model types: {before_types} at {args.rev} -> {after_types} on disk")
    print(f"numbered collisions:   {before_total} at {args.rev} -> {after_total} on disk", end="")
    if before_total:
        print(f"  ({(before_total - after_total) / before_total:.1%} gone)")
    else:
        print()

    if not after_total:
        print("\nno surviving collisions to name.")
        return 0

    missed, by_status, by_other, examples = classify_survivors(root, after_hits)
    classified = sum(by_status.values()) + sum(by_other.values())
    print()
    print("of the survivors:")
    print(f"  still identical copies the comparer declined to collapse: {sum(missed.values())}")
    if classified:
        print(f"  response-shaped, so a status code could name them:        {sum(by_status.values())}"
              f" ({sum(by_status.values()) / classified:.1%})")
        print(f"  something else, needing a different derivation:           {sum(by_other.values())}"
              f" ({sum(by_other.values()) / classified:.1%})")

    print()
    print("worst specs, surviving collisions:")
    worst = collections.Counter({spec: len(names) for spec, names in after_hits.items()})
    for spec, count in worst.most_common(args.limit):
        shown = ", ".join(examples.get(spec, [])) or "-"
        print(f"  {spec}: {count} — {shown}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
