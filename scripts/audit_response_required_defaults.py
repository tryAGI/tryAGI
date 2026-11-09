#!/usr/bin/env python3
"""Find response fields a spec declares required while also giving them a default.

Why this shape matters: the generated deserializers enforce `required`, so a response field the
service omits turns a successful HTTP 200 into a `JsonException`. A property that declares a
`default` is one the producer is allowed to leave out, so `required` + `default` on a
response-reachable schema is a contradiction the service usually resolves in its own favour.

This is how `caller` would have been caught before it shipped: Anthropic's spec marked it required
on 52 response block schemas and gave it a default, and the API never sends it, so every response
that used a server tool failed to deserialize (see SPEC_WORKAROUNDS.md).

The report lists candidates, not confirmed defects - plenty of services do send a field that has a
documented default (`UsageInfo.prompt_tokens` and friends). Confirming one needs a real response,
which is what an SDK's live tests are for. Treat a hit as "write a live test for this surface".

Usage:
    scripts/audit_response_required_defaults.py [--spec PATH] [--min N] [--list]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import sys

try:
    import yaml
except ImportError:  # pragma: no cover - yaml is only needed for .yaml specs
    yaml = None

REF = re.compile(r"^#/components/schemas/(.+)$")
WORKSPACE = pathlib.Path(__file__).resolve().parent.parent


def load_spec(path: pathlib.Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None

    if text.lstrip().startswith("{"):
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return None

    if yaml is None:
        return None
    try:
        return yaml.safe_load(text)
    except yaml.YAMLError:
        return None


def collect_refs(node: object, out: set[str]) -> None:
    if isinstance(node, dict):
        ref = node.get("$ref")
        if isinstance(ref, str):
            match = REF.match(ref)
            if match:
                out.add(match.group(1))
        for value in node.values():
            collect_refs(value, out)
    elif isinstance(node, list):
        for item in node:
            collect_refs(item, out)


def response_reachable_schemas(doc: dict, schemas: dict) -> set[str]:
    """Every component schema reachable from a response body, transitively."""
    seeds: set[str] = set()
    for item in (doc.get("paths") or {}).values():
        if not isinstance(item, dict):
            continue
        for operation in item.values():
            if not isinstance(operation, dict):
                continue
            for response in (operation.get("responses") or {}).values():
                if isinstance(response, dict):
                    collect_refs(response, seeds)

    reachable: set[str] = set()
    queue = list(seeds)
    while queue:
        name = queue.pop()
        if name in reachable or name not in schemas:
            continue
        reachable.add(name)
        found: set[str] = set()
        collect_refs(schemas[name], found)
        queue.extend(found - reachable)

    return reachable


def is_discriminator(field: str, prop: dict) -> bool:
    """A const or single-value enum is a discriminator: always sent, default notwithstanding."""
    if prop.get("const") is not None:
        return True
    enum = prop.get("enum")
    if isinstance(enum, list) and len(enum) == 1:
        return True
    return field == "type"


def audit(path: pathlib.Path) -> list[tuple[str, str]]:
    doc = load_spec(path)
    if not isinstance(doc, dict):
        return []

    schemas = (doc.get("components") or {}).get("schemas")
    if not isinstance(schemas, dict):
        return []

    hits: list[tuple[str, str]] = []
    for name in sorted(response_reachable_schemas(doc, schemas)):
        schema = schemas.get(name)
        if not isinstance(schema, dict):
            continue
        required = schema.get("required")
        properties = schema.get("properties")
        if not isinstance(required, list) or not isinstance(properties, dict):
            continue
        for field in required:
            prop = properties.get(field)
            if not isinstance(prop, dict) or "default" not in prop:
                continue
            if is_discriminator(field, prop):
                continue
            hits.append((name, field))

    return hits


def discover_specs() -> list[pathlib.Path]:
    return sorted(
        set(WORKSPACE.glob("*/src/libs/*/openapi.*"))
        | set(WORKSPACE.glob("*/src/libs/*/*/openapi.*"))
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--spec", type=pathlib.Path, help="audit a single spec instead of the whole workspace")
    parser.add_argument("--min", type=int, default=1, help="only report specs with at least this many hits")
    parser.add_argument("--list", action="store_true", help="list every schema and field, not just a summary")
    args = parser.parse_args()

    specs = [args.spec] if args.spec else discover_specs()

    affected = 0
    for path in specs:
        hits = audit(path)
        if len(hits) < args.min or not hits:
            continue
        affected += 1
        relative = path.relative_to(WORKSPACE) if path.is_relative_to(WORKSPACE) else path
        print(f"{relative}: {len(hits)} response fields are required and have a default")
        if args.list:
            for schema, field in hits:
                print(f"    {schema}.{field}")
        else:
            fields = sorted({field for _, field in hits})
            shown = ", ".join(fields[:12])
            print(f"    fields: {shown}{'...' if len(fields) > 12 else ''}")

    print(f"-- {affected} of {len(specs)} specs have candidates")
    return 0


if __name__ == "__main__":
    sys.exit(main())
