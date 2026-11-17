#!/usr/bin/env python3
"""Measure the generated type names that end in a number, and say which ones deserve a real name.

`ToolChoice2` reads like a bug, and about half the time it is one. This separates the populations,
because they need opposite fixes and a single percentage hides that.

Four populations, and only the first two are collisions at all:

- **Structural duplicates** — `Name<N>` whose generated code is identical to `Name` once numbering
  is ignored. The spec repeated the same inline schema and the generator made a fresh type per
  occurrence. Deduplicating them makes the number disappear with no naming scheme and no rename:
  the surviving type keeps the un-suffixed name. 55% of collisions, measured 2026-11-16.
- **Genuinely different types sharing a name** — these need a name derived from context. The
  distinguishing fact is usually the **status code**: in tryAGI/RetellAI, `DeleteChatResponse` is the
  400 error body and `DeleteChatResponse2` is the 401. So `DeleteChatResponse400` or
  `DeleteChatUnauthorizedResponse` is derivable, not invented. 45% of collisions.
- **`Variant<N>`** — union variant naming, a different mechanism entirely. Not counted.
- **The spec's own name** — `TextScoreV3`, `CodeExecutionTool20260521`, and also a numbered name the
  document declares outright beside its own base (D-ID ships `JsonError` through `JsonError4`,
  Dedoose `AccountVO` and `AccountVO2`). Not a collision; leaving these alone is correct. Excluding
  the declared ones was worth 175 names here, so the duplicate share moved from 55.0% to 55.4% -
  a correction that confirms the figure rather than overturning it. The same error cost 251 names on
  AutoSDK's own snapshot specs, where OpenRouter alone accounts for 214, so the size of it depends
  entirely on which documents are in the sample.

Why the duplicate share is easy to under-measure: a duplicate that references another duplicate
(`SearchRequestsResponseError` holds a `SearchRequestsResponseErrorType`) looks different unless the
numbering is stripped from *every* identifier in the file, not just the type's own name. Doing only
the latter reported 32%; the correct normalization reports 55%.

Usage:
    scripts/audit_numeric_type_suffixes.py [--limit N] [--sdk NAME]
"""

from __future__ import annotations

import argparse
import collections
import datetime
import functools
import subprocess
import hashlib
import json
import pathlib
import re
import sys

# Isolated mode (`python3 -I`, how these audits are run) drops the script's own directory from
# sys.path, so the shared module needs its path put back explicitly.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from spec_tools import declared_components as _declared_components  # noqa: E402
from spec_tools import find_spec as _find_spec  # noqa: E402
from spec_tools import load_document as _load_document  # noqa: E402

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent

MODEL_FILE = re.compile(r"^[^.]+\.Models\.([A-Za-z0-9_]+)\.g\.cs$")
# Not a collision: union variants, and names the spec itself ends with a number.
NOT_A_COLLISION = re.compile(r"Variant\d+$|V\d+$|\d{6,}$")
# Inside identifiers, drop runs of 1-3 digits following a letter. Runs of 4+ (dates) stay.
# Both files being compared get the same treatment, so this can only make two files look MORE
# alike, never less - it cannot manufacture a duplicate that is not one.
STRIP_NUMBERING = re.compile(r"(?<=[A-Za-z])\d{1,3}(?![0-9])")


def declared_components(generated: pathlib.Path) -> set[str]:
    """The component names the SDK's own committed spec declares, beside its Generated/ directory."""
    path = _find_spec("openapi", generated.parent)
    return _declared_components(_load_document(path)) if path else set()


@functools.lru_cache(maxsize=None)
def shape(path: pathlib.Path) -> str | None:
    """A hash of the file with all type numbering erased, so copies hash alike.

    Cached by path: the un-suffixed base is re-read once per colliding name that shares it, and
    `Fal` alone has 492 collisions. File reads were the single largest cost in the profile.

    Reading these concurrently was measured and rejected: a 16-thread pool moved ~14.5s to 12-14s,
    inside the noise of a busy host, for a chunk of set-building logic. The wall time is spread
    across 2.8s of iterdir over 306607 entries in 220 Generated directories and the rest in
    per-file latency, so there is no single hot spot left to parallelize.
    """
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    normalized = re.sub(r"\s+", " ", STRIP_NUMBERING.sub("", text))
    return hashlib.sha256(normalized.encode()).hexdigest()


def head_revision(sdk: str) -> str:
    """The SDK repository's current commit, so a reading can be reproduced."""
    result = subprocess.run(
        ["git", "-C", str(WORKSPACE / sdk), "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True)
    return result.stdout.strip() or "unknown"


def audit(only_sdk: str | None):
    duplicates = collections.Counter()
    different = collections.Counter()
    variants = 0
    spec_named = 0
    spec_declared = 0
    total_types = 0
    examples: dict[str, list[str]] = collections.defaultdict(list)
    revisions: dict[str, str] = {}

    for generated in sorted(WORKSPACE.glob("*/src/libs/*/Generated")):
        sdk = generated.parts[-4] if len(generated.parts) >= 4 else generated.parts[0]
        sdk = generated.relative_to(WORKSPACE).parts[0]
        if only_sdk and sdk != only_sdk:
            continue

        files: dict[str, pathlib.Path] = {}
        for entry in generated.iterdir():
            match = MODEL_FILE.match(entry.name)
            if match:
                files[match.group(1)] = entry

        revisions[sdk] = head_revision(sdk)
        total_types += len(files)
        declared = declared_components(generated)
        names = set(files)
        for name in sorted(names):
            if not re.search(r"\d$", name):
                continue
            if NOT_A_COLLISION.search(name):
                if "Variant" in name:
                    variants += 1
                else:
                    spec_named += 1
                continue
            if name in declared:
                # The document itself declares this exact numbered name.
                spec_declared += 1
                continue
            base = re.sub(r"\d+$", "", name)
            if base not in names:
                # Numbered, but nothing it collides with - the spec's own name.
                spec_named += 1
                continue
            if shape(files[name]) == shape(files[base]) is not None:
                duplicates[sdk] += 1
            else:
                different[sdk] += 1
                if len(examples[sdk]) < 3:
                    examples[sdk].append(name)

    return total_types, duplicates, different, variants, spec_named, spec_declared, examples, revisions


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk", help="audit a single SDK instead of the whole workspace")
    parser.add_argument("--limit", type=int, default=10, help="how many SDKs to list (default 10)")
    args = parser.parse_args()

    total, duplicates, different, variants, spec_named, spec_declared, examples, sdk_revisions = audit(args.sdk)
    collisions = sum(duplicates.values()) + sum(different.values())

    # Stamp the reading. These trees are refreshed by each SDK's auto-update workflow every few
    # hours, so a figure without a date cannot be compared with anything: on 2026-11-17 the
    # collision count moved 8796 -> 8010 inside one session, 774 of 786 of it upstream refreshes.
    print(f"measured {datetime.datetime.now().astimezone():%Y-%m-%d %H:%M %z}")
    for sdk, revision in sorted(sdk_revisions.items())[:3]:
        print(f"  e.g. {sdk} at {revision}")
    if len(sdk_revisions) > 3:
        print(f"  ... {len(sdk_revisions)} repositories, revisions above are a sample")
    print()
    print(f"generated model types: {total}")
    print(f"collisions (Name<N> where Name also exists): {collisions}")
    if collisions:
        dup = sum(duplicates.values())
        dif = sum(different.values())
        print(f"  structural duplicates - dedup removes them: {dup} ({dup / collisions:.1%}) in {len(duplicates)} SDK(s)")
        print(f"  genuinely different - need a derived name:  {dif} ({dif / collisions:.1%}) in {len(different)} SDK(s)")
    print(f"not collisions: {variants} Variant<N>, {spec_named} numbered with no base to collide "
          f"with, {spec_declared} declared under that exact name by the spec")

    if different:
        print()
        print("need a derived name, worst first:")
        for sdk, count in different.most_common(args.limit):
            print(f"  {sdk}: {count} — {', '.join(examples[sdk])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
