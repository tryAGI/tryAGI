#!/usr/bin/env python3
"""Which documents each SDK actually generates from, read from generate.sh rather than guessed.

Written after a filename glob produced two wrong entries in a CLAUDE.md. Asked whether Cartesia had
an AsyncAPI document, I ran `ls asyncapi.*`, found nothing, and recorded that its realtime surface
was unspecified and its 711 hand-written lines were what a document would replace. Both were false:
`generate.sh` fetches four contracts - `managed-agents-asyncapi.json`, `tts-asyncapi.json`,
`stt-asyncapi.json`, `stt-turns-asyncapi.json` - and generates a client from each. The files simply
are not named `asyncapi.*`.

So this reads the `autosdk generate <document>` invocations out of each `generate.sh`, which is what
decides what is generated, and classifies each document by **content** - the `asyncapi:` or
`openapi:`/`swagger:` key inside it - not by its name. A document the script generates from but
cannot find on disk is reported too: it is produced at generation time by a fetch step, which is
itself worth knowing.

Usage:
    scripts/audit_generation_inputs.py [--sdk NAME] [--kind asyncapi|openapi] [--limit N]
"""

from __future__ import annotations

import argparse
import collections
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from spec_tools import load_document  # noqa: E402

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
# `autosdk generate <document>` - the document is the first positional argument. The command is not
# always the literal `autosdk`: OpenAI's script calls `"$autosdk_cli" generate`, D-ID's uses an
# `$AUTOSDK_EXECUTABLE` shell function, so the token is accepted when it mentions autosdk in any
# case, quoted or as a variable. Matching only the literal missed OpenAI - the same class of
# false negative this script exists to prevent, in the script itself.
INVOCATION = re.compile(
    r"^\s*\"?(?:\$\{?)?([A-Za-z_][A-Za-z0-9_]*)\}?\"?\s+generate\s+(\S+)", re.M)


def invocations(text: str):
    for command, document in INVOCATION.findall(text):
        if "autosdk" in command.lower():
            yield document


def classify(path: pathlib.Path) -> str:
    """What the document is, by what is inside it."""
    if not path.is_file():
        return "fetched at generation time"
    document = load_document(path)
    if not isinstance(document, dict):
        return "unparseable"
    if "asyncapi" in document:
        return "asyncapi"
    if "openapi" in document or "swagger" in document:
        return "openapi"
    return "neither"


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--sdk")
    parser.add_argument("--kind", choices=("asyncapi", "openapi"))
    parser.add_argument("--limit", type=int, default=20)
    args = parser.parse_args()

    kinds = collections.Counter()
    per_sdk: dict[str, list[tuple[str, str]]] = collections.defaultdict(list)

    for script in sorted(WORKSPACE.glob("*/src/libs/*/generate.sh")):
        sdk = script.relative_to(WORKSPACE).parts[0]
        if args.sdk and sdk != args.sdk:
            continue
        try:
            text = script.read_text(errors="replace")
        except OSError:
            continue
        for document in invocations(text):
            if document.startswith("-") or "$" in document:
                continue
            kind = classify(script.parent / document)
            kinds[kind] += 1
            per_sdk[sdk].append((document, kind))

    if args.sdk:
        rows = per_sdk.get(args.sdk)
        if not rows:
            print(f"{args.sdk}: generate.sh invokes no autosdk generate")
            return 0
        print(f"{args.sdk} generates from {len(rows)} document(s):")
        for document, kind in rows:
            print(f"  {document}  [{kind}]")
        return 0

    if args.kind:
        matching = {sdk: [d for d, k in rows if k == args.kind]
                    for sdk, rows in per_sdk.items()}
        matching = {sdk: docs for sdk, docs in matching.items() if docs}
        print(f"SDKs generating from an {args.kind} document: {len(matching)}")
        for sdk, docs in sorted(matching.items(), key=lambda kv: (-len(kv[1]), kv[0])):
            print(f"  {sdk}: {', '.join(docs)}")
        return 0

    print(f"SDKs with a generate.sh that invokes autosdk: {len(per_sdk)}")
    print(f"documents generated from: {sum(kinds.values())}")
    for kind, count in kinds.most_common():
        print(f"  {kind}: {count}")
    print("\nmost documents first:")
    for sdk, rows in sorted(per_sdk.items(), key=lambda kv: (-len(kv[1]), kv[0]))[: args.limit]:
        print(f"  {sdk}: {len(rows)} — " +
              ", ".join(f"{d} [{k}]" for d, k in rows))
    return 0


if __name__ == "__main__":
    sys.exit(main())
