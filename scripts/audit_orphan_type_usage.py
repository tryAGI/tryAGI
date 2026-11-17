#!/usr/bin/env python3
"""Which unreachable component types an SDK's own hand-written code and tests actually use.

This is the check that has to run before anyone deletes an "unreachable" component. A component no
`$ref` reaches still becomes a public type, and the SDK's own extensions and tests can be using it -
D-ID's `Tests.SharedJsonMetadata.cs` deserializes `TextScript`, which `scripts/audit_unreferenced_
components.py` reports as unreferenced, because the document inlines every schema into the paths and
never points at the component.

Hand-written means everything under `src/` that is not in `Generated/`, `bin/` or `obj/`.

Type references are found by `csharp_references`, not by a regex over the text. The difference is
not academic: asked this question with a word-boundary regex, D-ID answered eight, and four were
member accesses - `response.Status`, `response.AudioUrl`, `talk.Status` and a `Role` property. The
real answer is three.

Usage:
    scripts/audit_orphan_type_usage.py [--sdk NAME] [--limit N]
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from csharp_references import type_references  # noqa: E402
from spec_tools import load_document  # noqa: E402
from spec_tools import source_files  # noqa: E402

WORKSPACE = HERE.parent


def load_module(name: str):
    spec = importlib.util.spec_from_file_location(name, HERE / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def hand_written(root: pathlib.Path):
    """Every .cs file under `root` that a person wrote, i.e. not generated output.

    `source_files` prunes bin, obj and the snapshot trees during the walk; `Generated` is excluded
    here because this audit's question is specifically what hand-written code uses.
    """
    for path in source_files(root):
        if "Generated" not in path.parts:
            yield path


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk")
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    unreferenced_audit = load_module("audit_unreferenced_components")

    rows = []
    for path in sorted(WORKSPACE.glob("*/src/libs/*/openapi.*")):
        if path.suffix not in (".yaml", ".yml", ".json"):
            continue
        sdk = path.relative_to(WORKSPACE).parts[0]
        if args.sdk and sdk != args.sdk:
            continue
        document = load_document(path)
        if not isinstance(document, dict):
            continue
        siblings = [
            d for d in (load_document(p) for p in sorted(path.parent.glob("asyncapi.*"))
                        if p.suffix in (".yaml", ".yml", ".json")) if isinstance(d, dict)
        ]
        _, orphan_names = unreferenced_audit.orphans(document, siblings)
        if not orphan_names:
            continue

        namespace = path.parent.name
        used: dict[str, list[str]] = {}
        for source in hand_written(WORKSPACE / sdk / "src"):
            try:
                text = source.read_text(errors="replace")
            except OSError:
                continue
            for name in type_references(text, orphan_names, namespaces=(namespace,)):
                used.setdefault(name, []).append(source.name)
        if used:
            rows.append((sdk, len(orphan_names), used))

    if args.sdk:
        if not rows:
            print(f"{args.sdk}: no unreachable component is used by hand-written code")
            return 0
        sdk, orphan_count, used = rows[0]
        print(f"{sdk}: {len(used)} of {orphan_count} unreachable components are used by hand")
        for name, files in sorted(used.items()):
            print(f"  {name}  <-  {', '.join(sorted(set(files)))}")
        return 0

    total = sum(len(used) for _, _, used in rows)
    print(f"SDKs whose own code uses an unreachable component: {len(rows)}")
    print(f"such components in total: {total}")
    print("\nmost first:")
    for sdk, orphan_count, used in sorted(rows, key=lambda r: -len(r[2]))[: args.limit]:
        print(f"  {sdk}: {len(used)} of {orphan_count} — {', '.join(sorted(used)[:4])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
