#!/usr/bin/env python3
"""Components a spec declares that no `$ref` reaches, and whose generated types are therefore dead.

AutoSDK emits a type for every entry in `components.schemas`, reachable or not. When a document
declares a component nothing references, the SDK ships a public type no operation can ever produce
or accept. D-ID is the case that prompted this: six of its components had zero `$ref`s and the SDK
carried six duplicate error types that no call site could reach.

Reachability is computed from the operations inward: every `$ref` outside `components.schemas` seeds
the walk, then component-to-component `$ref`s are followed transitively. Three things that are also
references get followed, because missing one would invent an orphan:

- `discriminator.mapping` values, which are `$ref` strings in a position where the key is not
  `$ref`.
- the rest of `components` - parameters, responses, requestBodies, headers - which reach into
  schemas.
- a sibling `asyncapi.*` beside the spec, since an SDK's WebSocket channels reference the same
  component set and are generated from a separate document.

## What it found, 2026-11-17

**2444 components across 81 SDKs** are reached by no `$ref`, out of 34037 declared. The extremes
say more than the total:

- **D-ID: 354 of 362, 98%.** Its document has **eleven** `$ref` occurrences in all - the ReadMe
  extraction inlined every schema into the paths and left `components.schemas` as a parallel,
  disconnected copy. The six duplicate error types removed earlier were a sliver of this.
- Vapi 418, Anthropic 242, OpenAI 224, Mubert 93 of 128.

Spot-checked whether an unreferenced component really becomes a public type: five of six did
(`DId.A2eModel`, `Vapi.AWSStsAssumeRoleUser`, `Anthropic.BetaBrowserClickTarget`,
`Coze.AudioConfig`, `Mubert.AccessTokenCustomerServiceShow`), while `OpenAI.BetaContent` did not -
something in that SDK's generation drops it. So 2444 is an **upper bound** on dead types, not a
count of them.

## What an orphan is not

It is not necessarily a defect in the SDK. A spec may declare a component for documentation, or as
an extension point, and a few SDKs reference their components only from a hand-written partial.
What it reliably means is that nothing in the document connects the type to an operation, so a
reader cannot tell what produces it.

Usage:
    scripts/audit_unreferenced_components.py [--sdk NAME] [--limit N] [--list SDK]
"""

from __future__ import annotations

import argparse
import collections
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from spec_tools import load_document  # noqa: E402

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
PREFIX = "#/components/schemas/"


def collect_refs(node, into: set[str]) -> None:
    if isinstance(node, dict):
        reference = node.get("$ref")
        if isinstance(reference, str) and reference.startswith(PREFIX):
            into.add(reference[len(PREFIX):])
        discriminator = node.get("discriminator")
        if isinstance(discriminator, dict):
            mapping = discriminator.get("mapping")
            if isinstance(mapping, dict):
                for target in mapping.values():
                    if isinstance(target, str) and target.startswith(PREFIX):
                        into.add(target[len(PREFIX):])
        for value in node.values():
            collect_refs(value, into)
    elif isinstance(node, list):
        for value in node:
            collect_refs(value, into)


def orphans(document, siblings: list) -> tuple[set[str], set[str]]:
    schemas = (document.get("components") or {}).get("schemas") or {}
    if not isinstance(schemas, dict) or not schemas:
        return set(), set()

    seeds: set[str] = set()
    for key, value in document.items():
        if key != "components":
            collect_refs(value, seeds)
    for key, value in (document.get("components") or {}).items():
        if key != "schemas":
            collect_refs(value, seeds)
    for sibling in siblings:
        collect_refs(sibling, seeds)

    edges: dict[str, set[str]] = {}
    for name, schema in schemas.items():
        found: set[str] = set()
        collect_refs(schema, found)
        edges[name] = found

    reachable: set[str] = set()
    queue = [name for name in seeds if name in schemas]
    while queue:
        name = queue.pop()
        if name in reachable:
            continue
        reachable.add(name)
        queue.extend(edges.get(name, ()))

    return set(schemas), set(schemas) - reachable


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk")
    parser.add_argument("--limit", type=int, default=15)
    parser.add_argument("--list", help="print every orphan of one SDK instead of a summary")
    args = parser.parse_args()

    dead = collections.Counter()
    totals: dict[str, int] = {}
    examples: dict[str, list[str]] = {}
    read = 0

    for path in sorted(WORKSPACE.glob("*/src/libs/*/openapi.*")):
        if path.suffix not in (".yaml", ".yml", ".json"):
            continue
        sdk = path.relative_to(WORKSPACE).parts[0]
        if args.sdk and sdk != args.sdk:
            continue
        if args.list and sdk != args.list:
            continue
        document = load_document(path)
        if not isinstance(document, dict):
            continue
        siblings = [
            doc for doc in (load_document(p) for p in sorted(path.parent.glob("asyncapi.*"))
                            if p.suffix in (".yaml", ".yml", ".json"))
            if isinstance(doc, dict)
        ]
        all_names, unreferenced = orphans(document, siblings)
        if not all_names:
            continue
        read += 1
        totals[sdk] = len(all_names)
        if unreferenced:
            dead[sdk] = len(unreferenced)
            examples[sdk] = sorted(unreferenced)

    if args.list:
        names = examples.get(args.list)
        if not names:
            print(f"{args.list}: every component is reachable")
            return 0
        print(f"{args.list}: {len(names)} of {totals[args.list]} components are unreferenced")
        for name in names:
            print(f"  {name}")
        return 0

    print(f"specs read: {read}")
    print(f"components no $ref reaches: {sum(dead.values())} in {len(dead)} SDK(s), "
          f"out of {sum(totals.values())} declared")
    print("\nworst first — unreferenced / declared:")
    for sdk, count in dead.most_common(args.limit):
        share = count / totals[sdk]
        note = "  <- the document barely uses $ref at all" if share > 0.9 else ""
        print(f"  {sdk}: {count}/{totals[sdk]} ({share:.0%}){note}")
        print(f"      {', '.join(examples[sdk][:3])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
