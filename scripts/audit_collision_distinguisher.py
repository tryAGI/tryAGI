#!/usr/bin/env python3
"""Decide what actually distinguishes each surviving name collision, by reading the spec.

The earlier split - "49% response-shaped, 51% something else" - was a guess made from the type name:
anything ending in `Response`, `Error` or `Result` was counted as distinguished by a status code.
That is not evidence. `CreateCrawlResponse2` may be a second status code on one operation, or a
second operation of the same name, or a sub-object of a request that happens to be called `response`.
The name cannot tell them apart, and a naming scheme built on it would be built on nothing.

This reads the operations instead. For a collision `X` / `X2`, it resolves `X`'s base name to an
operation and counts that operation's **inline** response schemas - the ones that make a type,
rather than a `$ref` that reuses a component. Two or more inline responses on one operation means a
status code really is the distinguishing fact, and the codes are printed, so a derived name like
`DeleteChatResponse400` is a fact about the spec rather than an invention.

Three verdicts, and the third one is the point of the exercise:

- **status-code** - the operation declares two or more inline response schemas. Derivable.
- **not-a-status-code** - the name resolves to an operation that declares at most one inline
  response, so whatever separates the pair is something else.
- **unresolved** - the base name does not resolve to any operation. Reported separately and never
  folded into either answer, because an unmatched name is ignorance, not evidence.

Operation matching normalizes `operationId` the way the generator roughly does - strip everything
that is not a letter or digit, compare case-insensitively - which is approximate: a spec using
`x-fern-sdk-method-name`, tag grouping or `MethodAndPath` naming will land in `unresolved` rather
than be matched wrongly. That is the safe direction for this question.

## What it found, 2026-11-16, on the 1000 real collisions surviving 025bb33e2c

| verdict | count | |
|---|---|---|
| status-code | 408 (40.8%) | derivable: the operation's codes are known and printed |
| not-a-status-code | 80 (8.0%) | resolves to an operation with at most one inline response |
| not-a-response-type | 433 (43.3%) | a nested sub-object, named by the generator from its position |
| unresolved | 74 (7.4%) | honestly unknown |

So the old heuristic's "49% response-shaped" was not close. The real figure is **40.8%**, and of the
567 names the heuristic called responses, **159 - 28.0% - are not distinguished by a status code**.
The conclusion it was used to support survives: a status code names two fifths of them and nothing
names the rest, so no scheme keyed on status codes can cover the problem.

The 1000 is itself a correction. Counting every `Name<N>` whose base exists gave 1251, but 251 of
those are names the documents declare themselves - did.json ships `JsonError` through `JsonError4`,
dedoose ships `AccountVO` and `AccountVO2`, openrouter alone accounts for 214 - and AutoSDK has
nothing to merge there. Excluding them also moves the status-code share up, since nearly all of them
were landing in `not-a-response-type`.

Usage:
    scripts/audit_collision_distinguisher.py [--rev REV] [--spec NAME] [--limit N]
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import subprocess
import sys

REPO = pathlib.Path.home() / "GitHub/tryAGI/AutoSDK"
SNAPSHOTS = "src/tests/AutoSDK.SnapshotTests/Snapshots"
MODEL_FILE = re.compile(r"^_#.*\.Models\.([A-Za-z0-9_]+)\.g\.verified\.cs$")
NOT_A_COLLISION = re.compile(r"Variant\d+$|V\d+$|\d{6,}$")
SKIP_DIRS = re.compile(r"^(CLI|Empty|Parallel|DependencyInjection|HttpResilience|CloudSigning)")
NON_ALNUM = re.compile(r"[^A-Za-z0-9]")
# What the generator appends to an operation's method name for a response body type.
RESPONSE_SUFFIX = re.compile(r"(Response|Result)$")


def key(text: str) -> str:
    return NON_ALNUM.sub("", text).lower()


def collisions_at(rev: str) -> dict[str, list[str]]:
    listing = subprocess.run(
        ["git", "-C", str(REPO), "ls-tree", "-r", "--name-only", rev, "--", SNAPSHOTS],
        capture_output=True, text=True, check=True,
    ).stdout.splitlines()
    prefix = SNAPSHOTS + "/"
    names: dict[str, set[str]] = collections.defaultdict(set)
    for path in listing:
        if not path.startswith(prefix):
            continue
        parts = path[len(prefix):].split("/")
        if len(parts) < 2 or SKIP_DIRS.match(parts[0]):
            continue
        match = MODEL_FILE.match(parts[-1])
        if match:
            names[parts[0]].add(match.group(1))

    found: dict[str, list[str]] = {}
    for spec, all_names in names.items():
        # A name the document itself declares is not a collision: some upstream generators
        # deduplicate by appending an index, so did.json arrives holding JsonError through
        # JsonError4 and dedoose holds AccountVO and AccountVO2. AutoSDK reproduces those names
        # faithfully and has nothing to merge. Counting them inflated this by 251 names.
        document = load_spec(spec)
        declared = set(((document or {}).get("components") or {}).get("schemas") or {}) \
            if isinstance(document, dict) else set()
        hits = [
            name for name in sorted(all_names)
            if re.search(r"\d$", name)
            and not NOT_A_COLLISION.search(name)
            and name not in declared
            and re.sub(r"\d+$", "", name) in all_names
        ]
        if hits:
            found[spec] = hits
    return found


def load_spec(stem: str):
    for candidate in sorted((REPO / "specs").glob(f"{stem}.*")):
        if candidate.suffix not in (".yaml", ".yml", ".json"):
            continue
        text = candidate.read_text(errors="replace")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            try:
                import yaml
                return yaml.safe_load(text)
            except Exception:
                return None
    return None


def inline_responses_by_operation(document) -> dict[str, list[str]]:
    """Per operation (keyed by normalized operationId), the status codes with an inline schema."""
    result: dict[str, list[str]] = {}
    for path_item in (document.get("paths") or {}).values():
        if not isinstance(path_item, dict):
            continue
        for method, operation in path_item.items():
            if method.lower() not in ("get", "put", "post", "delete", "patch", "head", "options"):
                continue
            if not isinstance(operation, dict):
                continue
            operation_id = operation.get("operationId")
            if not operation_id:
                continue
            codes = []
            for code, response in (operation.get("responses") or {}).items():
                if not isinstance(response, dict):
                    continue
                for media in (response.get("content") or {}).values():
                    schema = (media or {}).get("schema")
                    # A `$ref` reuses a component and makes no new type, so it cannot be half of a
                    # collision. Only an inline schema can.
                    if isinstance(schema, dict) and "$ref" not in schema:
                        codes.append(str(code))
                        break
            result[key(operation_id)] = sorted(set(codes))
    return result


def propose_names(found, only_spec: str | None) -> int:
    """Print the name every status-code collision would get, taken from the spec's own codes.

    The convention is the only one that needs no invention: the lowest 2XX keeps the bare
    `<Method>Response` that callers already use, and every other declared code appends its own
    number. Nothing here is a guess - each name is a code the operation declares.

    What this does NOT settle is which of today's `…Response2`, `…Response3` maps to which code.
    That order lives in the generator, so the mapping has to come from there; this is the target
    set, not a rename table.
    """
    total = 0
    for spec_name, names in sorted(found.items()):
        if only_spec and spec_name != only_spec:
            continue
        document = load_spec(spec_name)
        if not isinstance(document, dict):
            continue
        responses = inline_responses_by_operation(document)
        printed_for_spec = False
        seen_operations = set()
        for name in names:
            base = re.sub(r"\d+$", "", name)
            if not RESPONSE_SUFFIX.search(base):
                continue
            operation = RESPONSE_SUFFIX.sub("", base)
            codes = responses.get(key(operation))
            if not codes or len(codes) < 2 or operation in seen_operations:
                continue
            seen_operations.add(operation)
            if not printed_for_spec:
                print(f"\n## {spec_name}")
                printed_for_spec = True
            success = sorted(c for c in codes if c.startswith("2"))
            bare = success[0] if success else None
            proposed = [
                f"{base}" if code == bare else f"{base}{code}"
                for code in sorted(codes)
            ]
            total += len(proposed)
            print(f"  {operation}: {', '.join(proposed)}")
    print(f"\nproposed names: {total}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--rev", default="025bb33e2c", help="revision whose baselines to read")
    parser.add_argument("--spec", help="report one spec in detail")
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--names", action="store_true",
                        help="print the name each status-code collision would get, per operation")
    args = parser.parse_args()

    found = collisions_at(args.rev)

    if args.names:
        return propose_names(found, args.spec)

    verdicts = collections.Counter()
    per_spec = collections.defaultdict(collections.Counter)
    examples: dict[str, list[str]] = collections.defaultdict(list)
    heuristic_said_response = 0
    heuristic_disagreed = 0

    for spec_name, names in sorted(found.items()):
        document = load_spec(spec_name)
        if not isinstance(document, dict):
            verdicts["spec-unreadable"] += len(names)
            continue
        responses = inline_responses_by_operation(document)

        for name in names:
            base = re.sub(r"\d+$", "", name)
            # The old heuristic, kept only to report how far off it was.
            looked_like_a_response = bool(re.search(r"(Response|Error|Result)$", base))

            # A response body type is named `<MethodName>Response`. A name without that suffix is a
            # nested sub-object the generator named from its position - `BaseInputsOneOf1Items0`,
            # `BadGatewayResponseErrorDataMetadata` - and cannot be a response body, so no status
            # code is available to name it. That is the generator's own path encoding, not a guess
            # about what the type means.
            operation = RESPONSE_SUFFIX.sub("", base)
            codes = responses.get(key(operation))
            if not RESPONSE_SUFFIX.search(base):
                verdict = "not-a-response-type"
            elif codes is None:
                verdict = "unresolved"
            elif len(codes) >= 2:
                verdict = "status-code"
            else:
                verdict = "not-a-status-code"

            verdicts[verdict] += 1
            per_spec[spec_name][verdict] += 1
            if looked_like_a_response:
                heuristic_said_response += 1
                if verdict != "status-code":
                    heuristic_disagreed += 1
            if verdict == "status-code" and len(examples[spec_name]) < 3:
                examples[spec_name].append(f"{name} [{', '.join(codes)}]")

    if args.spec:
        counts = per_spec.get(args.spec)
        if not counts:
            print(f"{args.spec}: no surviving collisions at {args.rev}")
            return 0
        print(f"{args.spec} at {args.rev}: " +
              ", ".join(f"{v}={n}" for v, n in sorted(counts.items())))
        for sample in examples.get(args.spec, []):
            print(f"  status-code: {sample}")
        return 0

    total = sum(verdicts.values())
    print(f"surviving collisions at {args.rev}: {total}")
    for verdict in ("status-code", "not-a-status-code", "not-a-response-type",
                    "unresolved", "spec-unreadable"):
        if verdicts[verdict]:
            print(f"  {verdict:<18} {verdicts[verdict]:>5}  ({verdicts[verdict] / total:.1%})")

    decided = (verdicts["status-code"] + verdicts["not-a-status-code"]
               + verdicts["not-a-response-type"])
    if decided:
        print(f"\nof the {decided} this can answer, "
              f"{verdicts['status-code'] / decided:.1%} are distinguished by a status code; "
              f"{verdicts['unresolved']} stay unknown")
    print(f"\nthe old name-suffix heuristic called {heuristic_said_response} of them responses, "
          f"and was wrong about {heuristic_disagreed} "
          f"({heuristic_disagreed / heuristic_said_response:.1%})"
          if heuristic_said_response else "")

    print("\nspecs with the most status-code collisions:")
    worst = collections.Counter({s: c["status-code"] for s, c in per_spec.items() if c["status-code"]})
    for spec_name, count in worst.most_common(args.limit):
        print(f"  {spec_name}: {count} — {'; '.join(examples[spec_name])}")
    if not worst:
        print("  (none)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
