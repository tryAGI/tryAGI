#!/usr/bin/env python3
"""Say WHICH rule of AutoSDK's structural comparer rejects a pair of schemas, and where.

`OpenApiSchemaStructuralComparer.AreStructurallyEqual` answers true or false, which is all the
generator needs and nothing a person can act on. 110 collisions survive the dedup while their
generated code is byte-identical apart from the name, and "the comparer said different" does not say
why. This ports the comparer rule-for-rule and returns the first rule that fires, with the JSON
pointer of the sub-schema it fired on.

Give it two JSON pointers into one spec. The default pair is llamaparse's `ExtractResultsetData` /
`ExtractResultsetData2`, whose generated classes differ only in the digit.

## Divergence from the C# original, and why each one is a risk

This reads raw YAML/JSON; the C# reads the Microsoft.OpenApi object model, which materializes some
things the text leaves implicit. Where they can disagree:

- **`AdditionalPropertiesAllowed`** is a real property in the object model, defaulting to true, and
  set false only by a literal `additionalProperties: false`. Emulated here by that same rule, but a
  reader that normalizes differently would diverge.
- **`Type`** is a flags enum there and may be a string or a list here (OpenAPI 3.1). Compared as a
  set, so `[object, "null"]` and `["null", object]` match - as they do in the flags enum.
- **`$ref`** is an `OpenApiSchemaReference` with a resolved `Reference.Id`; here it is a literal
  `{"$ref": ...}` and the id is the last path segment. A ref into another document would diverge.
- **`Const`** is a string there; a non-string const here is compared by its JSON text.
- The C# compares the schema a `SchemaContext` holds, which is the schema at a position in the
  document - the same thing a pointer selects here, as long as the pointer is the right position.

So a verdict from this script is a lead, not proof. Confirm anything load-bearing against the C#.

## What it found, 2026-11-16

The premise behind "the comparer is too conservative" was wrong, on both counts that were offered:

- **The depth limit never fires.** Across every spec in `specs/`, 14 865 component schemas, the
  deepest nesting the comparer would walk is **10**, reached by exactly one schema. Nothing is
  deeper than 12, so `MaxDepth` has never rejected anything and lowering it buys nothing.
- **77% of the "missed copies" are not copies.** Of the 112 collisions whose generated code is
  identical once numbering is stripped, **86** are classes with no declared property at all - just
  the extension-data bag. `{type: object, additionalProperties: {anyOf: [...]}}` and
  `{type: object, additionalProperties: true}` are different schemas and the comparer is right to
  say so, but the generator does not express an `additionalProperties` value type anywhere in the
  class, so both emit the same empty type. What is identical is the generated code, not the schema.
  The remaining **26** have real properties and are the only honest candidates.

A second limit, visible in llamaparse and not a comparer matter at all: dedup is **name-scoped**. It
runs inside a collision group, so two structurally identical schemas that want *different* names are
never merged. `ExtractResultsetData` and `ExtractResultsetDataItem` are the same shape under two
names and both are emitted.

Usage:
    scripts/diagnose_comparer_rejections.py [--spec NAME] [--left PTR] [--right PTR]
"""

from __future__ import annotations

import argparse
import json
import pathlib
import sys

MAX_DEPTH = 12
SPECS = pathlib.Path.home() / "GitHub/tryAGI/AutoSDK/specs"

# llamaparse's ExtractResultset.data is `anyOf[ object, array-of-that-object, null ]`, so the same
# object schema appears twice and the generator built a context for each.
DEFAULT_LEFT = "/components/schemas/ExtractResultset/properties/data/anyOf/0"
DEFAULT_RIGHT = "/components/schemas/ExtractResultset/properties/data/anyOf/1/items"


class Different(Exception):
    """The first rule that fired, with where it fired."""

    def __init__(self, rule: str, pointer: str, left, right):
        super().__init__(rule)
        self.rule = rule
        self.pointer = pointer
        self.left = left
        self.right = right


def resolve(document, pointer: str):
    node = document
    for raw in pointer.strip("/").split("/"):
        if raw == "":
            continue
        token = raw.replace("~1", "/").replace("~0", "~")
        node = node[int(token)] if isinstance(node, list) else node[token]
    return node


def type_set(schema):
    value = schema.get("type")
    if value is None:
        return None
    return frozenset(value) if isinstance(value, list) else frozenset([value])


def additional_properties_allowed(schema) -> bool:
    # The object model's default is true; only a literal `false` turns it off. A sub-schema sets
    # AdditionalProperties and leaves Allowed alone.
    return schema.get("additionalProperties") is not False


def compare(left, right, depth: int, pointer: str) -> None:
    if left is right:
        return
    if left is None or right is None:
        raise Different("one side is null", pointer, left, right)
    if depth > MAX_DEPTH:
        raise Different(f"depth limit ({MAX_DEPTH}) reached - reported as different", pointer, "…", "…")

    left_ref, right_ref = left.get("$ref"), right.get("$ref")
    if left_ref is not None or right_ref is not None:
        # A reference is the same schema only when it names the same component; the C# never
        # resolves and compares targets.
        left_id = left_ref.rsplit("/", 1)[-1] if left_ref else None
        right_id = right_ref.rsplit("/", 1)[-1] if right_ref else None
        if left_id != right_id:
            raise Different("$ref component id", pointer, left_id, right_id)
        return

    for rule, get in (
        ("type", type_set),
        ("format", lambda s: s.get("format")),
        ("const", lambda s: None if "const" not in s else json.dumps(s["const"], sort_keys=True)),
        ("additionalPropertiesAllowed", additional_properties_allowed),
    ):
        if get(left) != get(right):
            raise Different(rule, pointer, get(left), get(right))

    if set(left.get("required", [])) != set(right.get("required", [])):
        raise Different("required", pointer,
                        sorted(set(left.get("required", []))), sorted(set(right.get("required", []))))

    left_enum, right_enum = left.get("enum") or [], right.get("enum") or []
    if [json.dumps(x, sort_keys=True) for x in left_enum] != \
       [json.dumps(x, sort_keys=True) for x in right_enum]:
        raise Different("enum (order matters)", pointer, left_enum, right_enum)

    left_disc, right_disc = left.get("discriminator"), right.get("discriminator")
    if bool(left_disc) != bool(right_disc):
        raise Different("discriminator presence", pointer, left_disc, right_disc)
    if left_disc and right_disc:
        if left_disc.get("propertyName") != right_disc.get("propertyName"):
            raise Different("discriminator.propertyName", pointer,
                            left_disc.get("propertyName"), right_disc.get("propertyName"))
        lm, rm = left_disc.get("mapping") or {}, right_disc.get("mapping") or {}
        if {k: v.rsplit("/", 1)[-1] for k, v in lm.items()} != \
           {k: v.rsplit("/", 1)[-1] for k, v in rm.items()}:
            raise Different("discriminator.mapping", pointer, lm, rm)

    for key in ("items", "additionalProperties"):
        left_child, right_child = left.get(key), right.get(key)
        # A boolean `additionalProperties` carries no sub-schema: `true`/`false` set
        # AdditionalPropertiesAllowed, compared above, and leave AdditionalProperties null. So a
        # bool on one side and a schema on the other is a presence difference, not something to
        # skip. Skipping it was this port's own bug - a divergence from the C# that made it report
        # EQUAL for a pair the original rejects, and the reason the list above is worth keeping
        # honest.
        left_child = None if isinstance(left_child, bool) else left_child
        right_child = None if isinstance(right_child, bool) else right_child
        if (left_child is None) != (right_child is None):
            raise Different(f"{key} presence", pointer, left_child, right_child)
        if left_child is not None:
            compare(left_child, right_child, depth + 1, f"{pointer}/{key}")

    left_props, right_props = left.get("properties") or {}, right.get("properties") or {}
    if len(left_props) != len(right_props):
        raise Different("property count", pointer, sorted(left_props), sorted(right_props))
    for name, child in left_props.items():
        if name not in right_props:
            raise Different("property name", pointer, name, sorted(right_props))
        compare(child, right_props[name], depth + 1, f"{pointer}/properties/{name}")

    for key in ("oneOf", "anyOf", "allOf"):
        left_list, right_list = left.get(key) or [], right.get(key) or []
        if len(left_list) != len(right_list):
            raise Different(f"{key} count", pointer, len(left_list), len(right_list))
        for index, (a, b) in enumerate(zip(left_list, right_list)):
            compare(a, b, depth + 1, f"{pointer}/{key}/{index}")


def load(name: str):
    for candidate in (SPECS / f"{name}.yaml", SPECS / f"{name}.json", SPECS / name):
        if candidate.is_file():
            text = candidate.read_text()
            try:
                return json.loads(text)
            except json.JSONDecodeError:
                import yaml
                return yaml.safe_load(text)
    raise SystemExit(f"spec not found: {name}")


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--spec", default="llamaparse")
    parser.add_argument("--left", default=DEFAULT_LEFT)
    parser.add_argument("--right", default=DEFAULT_RIGHT)
    args = parser.parse_args()

    document = load(args.spec)
    try:
        left = resolve(document, args.left)
        right = resolve(document, args.right)
    except (KeyError, IndexError, TypeError) as error:
        print(f"pointer does not resolve: {error}", file=sys.stderr)
        return 1

    print(f"spec:  {args.spec}")
    print(f"left:  {args.left}")
    print(f"right: {args.right}")
    try:
        compare(left, right, 0, "")
    except Different as difference:
        print(f"\nDIFFERENT — rule: {difference.rule}")
        print(f"  at: {difference.pointer or '(root)'}")
        print(f"  left:  {json.dumps(difference.left, sort_keys=True)[:300]}")
        print(f"  right: {json.dumps(difference.right, sort_keys=True)[:300]}")
        return 0

    print("\nEQUAL — no rule of the comparer rejects this pair.")
    print("If the generator still emitted two types, the cause is not the comparer: look at whether")
    print("the two contexts were grouped together at all, and at what the group's canonical was.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
