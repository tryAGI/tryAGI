#!/usr/bin/env python3
"""Find components a spec declares more than once under different names.

This is an upstream defect, not a generator one. Several of the tools that produce these documents
deduplicate by appending an index, so the spec arrives already holding the same shape several times:
D-ID's `did.json` declares `JsonError`, `JsonError1`, `JsonError2`, `JsonError3` and `JsonError4`,
all identical; Dedoose declares `AccountVO` and `AccountVO2`; Coze declares `CanvasPosition` and
`CanvasPosition1`. AutoSDK reproduces those names faithfully and has nothing to merge — there is no
collision, they are separate components — so the fix belongs in the SDK's `generate.sh`, repointing
the `$ref`s at one survivor and deleting the rest, exactly as other spec workarounds do.

Chasing this through the generator is what two earlier attempts did, and both were wrong: the
collision groups never contained these schemas, because their names genuinely differ.

Structural equality is the same conservative comparison AutoSDK's own comparer makes, borrowed from
`diagnose_comparer_rejections.py`, so a group reported here is one AutoSDK would also consider
identical. `$ref`s compare by component id, which is what makes `A -> Foo` and `B -> Foo` equal while
`A -> Foo` and `B -> Bar` are not, even when Foo and Bar have the same shape.

## Only the indexed subset is actionable, and a trailing number is not enough to spot it

A number at the end of a name can mean something: Descript declares `Error400`, `Error401`,
`Error402`, `Error403`, `Error404` and `Error429`, all one shape, and collapsing them would throw
away which status each describes - a group where more than one name ends in a 3-digit HTTP code is
left out. ipinfo's `Prefix` and `Prefix6` differ by IP version, which no shape comparison can see.
So the output is a shortlist for a person, not a patch.

Measured across 338 documents (every SDK's committed spec plus AutoSDK's fixtures, since some
documents live only there): **3506** components share a shape with another, and **15** have a
trailing number. Those 15 are candidates, not conclusions - review each:

- **D-ID (6) and Coze (1) are real** indexing artifacts: `JsonError` through `JsonError4`,
  `TextScript3`, `AudioScript3`, `CanvasPosition1`. These are the ones a `generate.sh` can collapse.
- **Dedoose (7) are real too** (`AccountVO` = `AccountVO2`, and six more) but there is no Dedoose
  SDK - the document exists only as an AutoSDK fixture, so there is no `generate.sh` to fix.
- **ipinfo's `Prefix` / `Prefix6` is a false positive**: the 6 is IPv6, not an index.

Two families of false positive turned up while writing this, which is why the bucket proposes rather
than concludes. HTTP status codes are filtered out (Descript ships `Error400` through `Error429`,
one shape each, and collapsing them would discard which status each describes). Protocol versions
are not filtered, because `Prefix6` and `JsonError4` are indistinguishable by shape - a person has
to look.

The other 2837 are same shape, deliberately different names, and merging them would be a mistake -
the same mistake as trying to merge across names inside AutoSDK:

- `APIError` = `BetaAPIError` (Anthropic, 537 such pairs) - the stable and beta surfaces, which are
  meant to diverge.
- `BuildIconsResponse` = `BuildIconsWithoutIncludesResponse` (AppStoreConnect) - two endpoints.
- `ASRInputFormat` = `TTSOutputFormat` (ElevenLabs) - two enums that happen to list the same values
  today.
- `EventID` = `RunID` = `aroundLatLng` (Algolia) - identical because all three are plain strings.

So read the second number, not the first. The first is a measure of how often API designers name one
shape twice on purpose, which is often.

Usage:
    scripts/audit_duplicate_components.py [--sdk NAME] [--limit N] [--min-size N]
"""

from __future__ import annotations

import argparse
import collections
import importlib.util
import json
import pathlib
import re
import sys

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
TRAILING_NUMBER = re.compile(r"\d+$")
# A trailing number is not always an index. Descript declares Error400, Error401, Error402,
# Error403, Error404 and Error429 - one schema per status code, identical in shape and emphatically
# not one upstream generator counting. Treat a 3-digit number in the HTTP range as a status code.
STATUS_CODE = re.compile(r"(?<!\d)[1-5]\d\d$")


def comparer():
    """The structural comparer, loaded from the diagnostic script so there is one implementation."""
    path = WORKSPACE / "scripts" / "diagnose_comparer_rejections.py"
    spec = importlib.util.spec_from_file_location("comparer", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stable(value) -> str:
    """A deterministic string for any parsed YAML/JSON value.

    `json.dumps(..., sort_keys=True)` is not usable here: YAML turns unquoted dates into datetimes
    and bare `on`/`off`/`yes` keys into booleans, so a document can carry a map whose keys are of
    mixed types and refuse to sort. This walks the value and sorts keys by their text instead.
    """
    if isinstance(value, dict):
        return "{" + ",".join(
            f"{str(k)}:{stable(v)}" for k, v in sorted(value.items(), key=lambda kv: str(kv[0]))
        ) + "}"
    if isinstance(value, list):
        return "[" + ",".join(stable(v) for v in value) + "]"
    return repr(value)


def load(path: pathlib.Path):
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        try:
            import yaml
            return yaml.safe_load(text)
        except Exception:
            return None


def duplicate_groups(schemas: dict, compare, min_size: int) -> list[list[str]]:
    """Names grouped by identical shape, cheapest comparisons first.

    Bucketed by a crude signature before any deep comparison, because comparing every pair of a
    thousand components is quadratic and almost all pairs differ in their property names.
    """
    buckets: dict[tuple, list[str]] = collections.defaultdict(list)
    for name, schema in schemas.items():
        if not isinstance(schema, dict):
            continue
        if len(stable(schema)) < min_size:
            continue
        properties = schema.get("properties")
        signature = (
            stable(schema.get("type")),
            tuple(sorted(map(str, properties))) if isinstance(properties, dict) else (),
            len(schema.get("oneOf") or []),
            len(schema.get("anyOf") or []),
            len(schema.get("allOf") or []),
            stable(sorted(map(str, schema.get("required") or []))),
        )
        buckets[signature].append(name)

    groups = []
    for candidates in buckets.values():
        if len(candidates) < 2:
            continue
        remaining = list(candidates)
        while remaining:
            head = remaining.pop(0)
            same = [head]
            rest = []
            for other in remaining:
                try:
                    compare(schemas[head], schemas[other], 0, "")
                    same.append(other)
                except Exception:
                    rest.append(other)
            remaining = rest
            if len(same) > 1:
                groups.append(sorted(same))
    return groups


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk", help="audit one SDK instead of the whole workspace")
    parser.add_argument("--limit", type=int, default=15)
    parser.add_argument("--min-size", type=int, default=120,
                        help="ignore components whose JSON is shorter than this; a two-line "
                             "free-form object matching another says nothing (default 120)")
    args = parser.parse_args()

    module = comparer()
    redundant = collections.Counter()
    indexed = collections.Counter()
    examples: dict[str, list[str]] = collections.defaultdict(list)
    indexed_examples: dict[str, list[str]] = collections.defaultdict(list)
    specs_read = 0

    # An SDK repo's own committed spec, plus AutoSDK's test fixtures - some documents live only
    # there, with no SDK of their own (Dedoose is one, and it carries real duplicates), so scanning
    # the repos alone missed them. A group seen in both copies is counted once, below.
    sources = [(path.relative_to(WORKSPACE).parts[0], path)
               for path in sorted(WORKSPACE.glob("*/src/libs/*/openapi.*"))]
    sources += [(f"specs/{path.stem}", path)
                for path in sorted((WORKSPACE / "AutoSDK" / "specs").glob("*"))
                if path.is_file()]

    seen_groups: set[frozenset] = set()
    for sdk, spec_path in sources:
        if spec_path.suffix not in (".yaml", ".yml", ".json"):
            continue
        if args.sdk and sdk != args.sdk:
            continue
        document = load(spec_path)
        if not isinstance(document, dict):
            continue
        schemas = (document.get("components") or {}).get("schemas") or {}
        if not isinstance(schemas, dict) or not schemas:
            continue
        specs_read += 1

        for group in duplicate_groups(schemas, module.compare, args.min_size):
            # The same document can appear twice - once as an SDK's spec, once as a fixture.
            fingerprint = frozenset(group)
            if fingerprint in seen_groups:
                continue
            seen_groups.add(fingerprint)
            redundant[sdk] += len(group) - 1
            bases = {TRAILING_NUMBER.sub("", name) for name in group}
            looks_like_status_codes = sum(1 for name in group if STATUS_CODE.search(name)) > 1
            if len(bases) == 1 and not looks_like_status_codes:
                indexed[sdk] += len(group) - 1
                # The survivor is the one without a number; the rest are the artifact.
                survivor = sorted(group, key=lambda n: (bool(TRAILING_NUMBER.search(n)), n))[0]
                others = [n for n in group if n != survivor]
                if len(indexed_examples[sdk]) < 4:
                    indexed_examples[sdk].append(f"{survivor}  <-  {', '.join(others)}")
            elif len(examples[sdk]) < 2:
                examples[sdk].append(" = ".join(group[:3]))

    total = sum(redundant.values())
    actionable = sum(indexed.values())
    print(f"specs read: {specs_read}")
    print(f"CANDIDATES — a trailing number and one shape, review each: {actionable}"
          f" in {len(indexed)} source(s)")
    print(f"same shape under deliberately different names — DO NOT merge: {total - actionable}"
          f" in {len(redundant)} SDK(s)")
    if actionable:
        print("\nthe candidates, with the proposed survivor first:")
        for sdk, count in indexed.most_common():
            print(f"  {sdk}: {count}")
            for sample in indexed_examples[sdk]:
                print(f"      {sample}")
    if total - actionable:
        print("\nfor context only, where one shape carries several intended names:")
        for sdk, count in redundant.most_common(args.limit):
            if indexed[sdk] == count:
                continue
            print(f"  {sdk}: {count - indexed[sdk]}")
            for sample in examples[sdk]:
                print(f"      {sample}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
