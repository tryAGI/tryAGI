#!/usr/bin/env python3
"""Which SDKs declare the one integer format that cannot compile in a CLS-compliant assembly.

`format: int8` is the only integer format AutoSDK maps to a type that is **not** CLS-compliant:
`sbyte`. Most SDKs here declare their assembly `[CLSCompliant(true)]` in
`src/libs/Directory.Build.props`, and a non-CLS type in a public signature is `CS3001` - an error
under this workspace's warnings-as-errors. The library stops building.

Julep hit it on 2026-11-17 while being regenerated for an unrelated reason: three `format: int8`
fields, three `CS3001`s, no build. Nothing in its spec had changed - the mapping did, in a released
`autosdk.cli` - so the failure arrives as a red CI run on an auto-update PR nobody wrote. Its fix is
the one to copy: a `generate.sh` step that drops the format and leaves `type: integer`, which keeps
the declared `minimum`/`maximum` and loses nothing a caller could use.

**Only `int8`.** The first version of this script also flagged `uint16` and `uint32`, reasoning that
`ushort` and `uint` are not CLS-compliant either - and reported seven exposed SDKs. Reading
`CSharpTypeMapper` rather than reasoning about it says AutoSDK never emits those: it widens every
unsigned format into a signed type on purpose (`uint8` -> `byte`, `uint16` -> `int`,
`uint32` -> `long`, `uint64` -> `long`), which is also why Julep's `format: uint16` field generates
a plain `int`. Six of those seven were not exposed at all.

This reports what the **committed** spec declares, which is after each `generate.sh` has run, so an
SDK already carrying the fix correctly shows nothing. It cannot predict an `int8` that upstream adds
tomorrow; it answers whether anything is exposed today.

Usage:
    scripts/audit_non_cls_integer_formats.py [--sdk NAME]
"""

from __future__ import annotations

import argparse
import collections
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from spec_tools import load_document  # noqa: E402

WORKSPACE = HERE.parent
# The one format whose generated C# type is not CLS-compliant, per `CSharpTypeMapper`. Every
# unsigned format is widened into a signed type there, so none of them belongs here - see the
# module docstring for the measurement that removed them.
NON_CLS = {"int8": "sbyte"}


def declares_cls_compliance(sdk: pathlib.Path) -> bool:
    for props in (sdk / "src" / "libs" / "Directory.Build.props",
                  sdk / "src" / "Directory.Build.props",
                  sdk / "Directory.Build.props"):
        try:
            if "CLSCompliant" in props.read_text(errors="replace"):
                return True
        except OSError:
            continue
    return False


def integer_formats(node, found: collections.Counter) -> None:
    if isinstance(node, dict):
        if node.get("type") == "integer":
            fmt = node.get("format")
            if fmt in NON_CLS:
                found[fmt] += 1
        for value in node.values():
            integer_formats(value, found)
    elif isinstance(node, list):
        for value in node:
            integer_formats(value, found)


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk")
    args = parser.parse_args()

    exposed, compliant_but_clean, not_compliant = [], 0, []
    for spec in sorted(WORKSPACE.glob("*/src/libs/*/openapi.*")):
        if spec.suffix not in (".yaml", ".yml", ".json"):
            continue
        sdk_name = spec.relative_to(WORKSPACE).parts[0]
        if args.sdk and sdk_name != args.sdk:
            continue
        document = load_document(spec)
        if not isinstance(document, dict):
            continue

        found: collections.Counter = collections.Counter()
        integer_formats(document, found)
        if not found:
            continue

        if declares_cls_compliance(WORKSPACE / sdk_name):
            exposed.append((sdk_name, dict(found)))
        else:
            not_compliant.append((sdk_name, dict(found)))

    print(f"SDKs declaring `format: int8` in a CLS-compliant assembly: {len(exposed)}")
    for sdk_name, found in sorted(exposed, key=lambda r: -sum(r[1].values())):
        where = ", ".join(f"{fmt} -> {NON_CLS[fmt]} x{count}" for fmt, count in sorted(found.items()))
        print(f"  {sdk_name}: {where}")

    if not_compliant:
        print(f"\ndeclare such a format but not CLS compliance, so nothing breaks: {len(not_compliant)}")
        for sdk_name, found in sorted(not_compliant):
            print(f"  {sdk_name}: {', '.join(sorted(found))}")

    return 1 if exposed else 0


if __name__ == "__main__":
    sys.exit(main())
