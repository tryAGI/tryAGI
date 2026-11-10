#!/usr/bin/env python3
"""Find schemas whose property names break the casing convention the rest of the spec uses.

Why this shape matters: a property name is the wire name. If a spec spells a field `object_type`
while the service sends `objectType`, the generated model looks for a key that never arrives — and
when the field is also `required`, deserializing a successful HTTP 200 throws. That is exactly how
Milvus's `POST /v2/vectordb/roles/describe` was unusable: the spec's `Privilege-Entity` used
snake_case in a document that is camelCase nearly everywhere else.

Nothing static can know what a service actually sends. What it can know is that one schema
disagrees with its own document. A spec that is consistently snake_case throughout reports nothing,
as it should.

**A deviation is not a defect.** The common innocent cause is a schema that mirrors a foreign
protocol: MCP is camelCase, so `MCPTool: inputSchema, outputSchema` is correct inside an otherwise
snake_case spec, and the same goes for the A2A agent-card schemas in Vectara and the OTLP envelopes
in PromptLayer. Those deviate because the wire really is camelCase there.

What is worth a live probe is a deviation with no such explanation - a one-off field in an error
envelope or a status wrapper, which is the shape nobody exercises and where Milvus's bug lived.
Judge each hit by whether the schema belongs to a protocol of its own; if it does not, probe it.

Single-word names carry no casing signal and are ignored, as are names that are already unambiguous
(`id`, `url`). Only schemas reachable from a response body are considered by default: there a
mismatch throws, where in a request body it silently sends a key the service ignores. Pass --all to
include request-only schemas too.

Usage:
    scripts/audit_property_casing.py [--spec PATH] [--all] [--min-dominance 0.8]
"""

from __future__ import annotations

import argparse
import importlib.util
import pathlib
import re
import sys

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent

_spec = importlib.util.spec_from_file_location(
    "response_required_audit", WORKSPACE / "scripts" / "audit_response_required_defaults.py"
)
_audit = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_audit)

SNAKE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)+$")
CAMEL = re.compile(r"^[a-z][a-z0-9]*([A-Z][a-z0-9]*)+$")

# Schemas that mirror a protocol with its own casing. Their deviation is correct, and they are the
# bulk of the noise: MCP, A2A, OTLP and Tempo traces are camelCase wherever they are embedded.
# Matched as name prefixes, because that is how these schemas are named in practice
# (`MCPTool`, `A2aV1AgentCard`, `TempoTraceSpan`, `OtlpExportTraceServiceResponse`).
FOREIGN_PROTOCOL_PREFIXES = (
    "mcp",
    "a2a",
    "otlp",
    "opentelemetry",
    "jsonrpc",
    "tempotrace",
)

# Protocol material whose name carries no prefix, for the same reason.
FOREIGN_PROTOCOL_EXACT = {
    "toolannotations",
    "toolexecution",
    "resourcelink",
    "blobresourcecontents",
    "textresourcecontents",
    "audiocontent",
    "imagecontent",
    "icon",
    "tool",
}


def is_foreign_protocol_schema(name: str) -> bool:
    """True when a schema mirrors a protocol that legitimately uses another casing."""
    bare = name.replace(".", "").replace("-", "").replace("_", "").lower()
    # Strip a trailing Fern-style direction suffix so `MCPTool-Output` matches too.
    bare = re.sub(r"(output|input)$", "", bare)
    return bare in FOREIGN_PROTOCOL_EXACT or bare.startswith(FOREIGN_PROTOCOL_PREFIXES)


def casing(name: str) -> str | None:
    """snake, camel, or None when the name carries no signal."""
    if SNAKE.match(name):
        return "snake"
    if CAMEL.match(name):
        return "camel"
    return None


def audit(
    path: pathlib.Path,
    response_only: bool,
    min_dominance: float,
    include_protocol_schemas: bool = False,
) -> tuple[str, float, list[tuple[str, list[str]]]]:
    doc = _audit.load_spec(path)
    if not isinstance(doc, dict):
        return ("", 0.0, [])

    schemas = (doc.get("components") or {}).get("schemas")
    if not isinstance(schemas, dict):
        return ("", 0.0, [])

    # The convention is whatever the whole document mostly does, counted once per distinct name so
    # a single huge schema cannot set it.
    seen: dict[str, str] = {}
    for schema in schemas.values():
        if not isinstance(schema, dict):
            continue
        for name in (schema.get("properties") or {}):
            style = casing(name)
            if style:
                seen[name] = style

    if not seen:
        return ("", 0.0, [])

    snake = sum(1 for s in seen.values() if s == "snake")
    camel = len(seen) - snake
    dominant, count = ("snake", snake) if snake >= camel else ("camel", camel)
    dominance = count / len(seen)
    if dominance < min_dominance:
        # A spec that genuinely mixes both has no convention to break.
        return (dominant, dominance, [])

    considered = set(schemas) if not response_only else _audit.response_reachable_schemas(doc, schemas)

    offenders = []
    for name in sorted(considered):
        schema = schemas.get(name)
        if not isinstance(schema, dict):
            continue
        if not include_protocol_schemas and is_foreign_protocol_schema(name):
            continue
        deviating = [
            prop for prop in (schema.get("properties") or {})
            if casing(prop) not in (None, dominant)
        ]
        if deviating:
            offenders.append((name, sorted(deviating)))

    return (dominant, dominance, offenders)


def discover_specs() -> list[pathlib.Path]:
    return sorted(
        set(WORKSPACE.glob("*/src/libs/*/openapi.*"))
        | set(WORKSPACE.glob("*/src/libs/*/*/openapi.*"))
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--spec", type=pathlib.Path, help="audit a single spec instead of the whole workspace")
    parser.add_argument("--all", action="store_true", help="include schemas only a request body reaches")
    parser.add_argument(
        "--include-protocol-schemas",
        action="store_true",
        help="keep MCP/A2A/OTLP schemas, whose deviation is correct and is most of the noise",
    )
    parser.add_argument(
        "--min-dominance",
        type=float,
        default=0.8,
        help="how one-sided a spec's casing must be before a deviation counts (default 0.8)",
    )
    args = parser.parse_args()

    specs = [args.spec] if args.spec else discover_specs()

    affected = 0
    for path in specs:
        dominant, dominance, offenders = audit(
            path,
            response_only=not args.all,
            min_dominance=args.min_dominance,
            include_protocol_schemas=args.include_protocol_schemas,
        )
        if not offenders:
            continue
        affected += 1
        relative = path.relative_to(WORKSPACE) if path.is_relative_to(WORKSPACE) else path
        print(f"{relative}: {dominant} ({dominance:.0%} of names), {len(offenders)} schema(s) deviate")
        for name, props in offenders:
            shown = ", ".join(props[:6])
            print(f"    {name}: {shown}{'...' if len(props) > 6 else ''}")

    print(f"-- {affected} of {len(specs)} specs have a schema that breaks their own convention")
    return 0


if __name__ == "__main__":
    sys.exit(main())
