"""Find operations that take a `stream` flag but declare no streaming response content type.

A streaming content type on a 2XX response is the only thing that makes AutoSDK emit a
`*AsStreamAsync` method. Two are recognised: `text/event-stream` (parsed with `SseParser`) and the
sequential-JSON family - `application/x-ndjson`, `application/jsonl`, `application/json-seq` -
(parsed with `StreamReader.ReadLineAsync`). Either one is enough. An operation that accepts `stream: true` and declares only `application/json` therefore has
no generated stream at all: the SDK either hand-writes the transport, or - worse - offers the caller
a `stream` parameter on a method that cannot stream and fails to parse the result.

That is not hypothetical. tryAGI/Anthropic hand-wrote ~360 lines of SSE transport for exactly this
reason, and tryAGI/Groq exposed the flag with nothing behind it. Both were fixed by declaring the
content type in `generate.sh`.

**A hit is a candidate, not a defect**, because of one big innocent case: there may be no event
schema to point at. A patch needs a schema for the stream frame. Most hits have none, so declaring
the content type would mean hand-writing an event schema - a much larger job than a one-line `yq`.
Run with --paired to see only the hits where a sibling stream schema already exists, which is the
mechanically patchable set.

**Pick the content type the service actually sends.** SSE and NDJSON are not interchangeable:
declaring `text/event-stream` for a service that sends newline-delimited JSON hands NDJSON to
`SseParser` and yields nothing. Ollama is the worked example of getting this right - it streams
NDJSON, declares `application/x-ndjson`, and AutoSDK generates a `ReadLineAsync` loop for it. That
is why this script treats either content type as satisfied rather than looking only for SSE.

Usage:
    scripts/audit_undeclared_streams.py [--paired]
"""

import json, pathlib, sys, re

WS = pathlib.Path("/Users/havendv/GitHub/tryAGI")

def load(p):
    t = p.read_text(errors="replace")
    if p.suffix == ".json":
        return json.loads(t)
    import yaml
    return yaml.safe_load(t)

def resolve(doc, node, depth=0):
    while isinstance(node, dict) and "$ref" in node and depth < 20:
        ref = node["$ref"]
        if not ref.startswith("#/"):
            return {}
        cur = doc
        for part in ref[2:].split("/"):
            if not isinstance(cur, dict) or part not in cur:
                return {}
            cur = cur[part]
        node, depth = cur, depth + 1
    return node if isinstance(node, dict) else {}

def has_stream_flag(doc, op):
    body = resolve(doc, (op.get("requestBody") or {}))
    for media in (body.get("content") or {}).values():
        schema = resolve(doc, media.get("schema") or {})
        props = schema.get("properties") or {}
        for variant_key in ("allOf", "oneOf", "anyOf"):
            for v in schema.get(variant_key) or []:
                props = {**(resolve(doc, v).get("properties") or {}), **props}
        s = props.get("stream")
        if isinstance(s, dict) and resolve(doc, s).get("type") == "boolean":
            return True
    for param in op.get("parameters") or []:
        param = resolve(doc, param)
        if param.get("name") == "stream":
            return True
    return False

# Every response content type AutoSDK can turn into a generated stream.
STREAMING_CONTENT_TYPES = ("event-stream", "x-ndjson", "jsonl", "json-seq")


def declares_stream(op):
    """True when a 2XX response declares a content type AutoSDK streams."""
    for resp in (op.get("responses") or {}).values():
        if isinstance(resp, dict):
            for ct in (resp.get("content") or {}):
                if any(marker in ct for marker in STREAMING_CONTENT_TYPES):
                    return True
    return False

specs = sorted(set(WS.glob("*/src/libs/*/openapi.*")) | set(WS.glob("*/src/libs/*/*/openapi.*")))
findings = {}
for p in specs:
    try:
        doc = load(p)
    except Exception:
        continue
    if not isinstance(doc, dict):
        continue
    hits = []
    for path, item in (doc.get("paths") or {}).items():
        if not isinstance(item, dict):
            continue
        for method, op in item.items():
            if method not in ("get", "post", "put", "patch", "delete") or not isinstance(op, dict):
                continue
            if has_stream_flag(doc, op) and not declares_stream(op):
                hits.append(f"{method.upper()} {path}")
    if hits:
        findings[p.relative_to(WS).parts[0]] = hits

def report_all():
    """Every candidate, patchable or not."""
    for sdk, hits in sorted(findings.items()):
        print(f"{sdk}: {len(hits)} operation(s)")
        for h in hits[:6]:
            print(f"    {h}")
        if len(hits) > 6:
            print(f"    ... and {len(hits)-6} more")
    print(f"-- {len(findings)} of {len(specs)} specs")


def response_schema_name(doc, op):
    for code, resp in (op.get("responses") or {}).items():
        if not str(code).startswith("2") or not isinstance(resp, dict):
            continue
        for media in (resp.get("content") or {}).values():
            ref = ((media or {}).get("schema") or {}).get("$ref")
            if isinstance(ref, str) and ref.startswith("#/components/schemas/"):
                return ref.rsplit("/", 1)[1]
    return None


def stream_siblings(name, schemas):
    """Sibling schemas that are `name` with a streaming marker inserted or appended.

    This pairing is what makes a patch mechanical: `CreateChatCompletionResponse` sits next to
    `CreateChatCompletionStreamResponse`, so there is an unambiguous schema to point the content
    type at. Without a pair, the patch needs a hand-written event schema.
    """
    out = []
    for marker in ("Stream", "Chunk", "StreamResponse", "ChunkResponse", "StreamEvent", "Delta"):
        for cand in (
            name + marker,
            name.replace("Response", marker + "Response") if "Response" in name else None,
            name.replace("Response", marker) if "Response" in name else None,
            re.sub(r"(Response|Result)$", marker + r"\1", name),
        ):
            if cand and cand in schemas and cand != name and cand not in out:
                out.append(cand)
    return out


def report_paired():
    """Only the hits a one-line content-type patch can fix today."""
    total = 0
    for p in specs:
        sdk = p.relative_to(WS).parts[0]
        if sdk not in findings:
            continue
        try:
            doc = load(p)
        except Exception:
            continue
        schemas = ((doc.get("components") or {}).get("schemas") or {})
        rows = []
        for path, item in (doc.get("paths") or {}).items():
            if not isinstance(item, dict):
                continue
            for method, op in item.items():
                if method not in ("get", "post") or not isinstance(op, dict):
                    continue
                if not (has_stream_flag(doc, op) and not declares_stream(op)):
                    continue
                rname = response_schema_name(doc, op)
                if not rname:
                    continue
                cands = stream_siblings(rname, schemas)
                if cands:
                    rows.append((f"{method.upper()} {path}", rname, cands))
        if rows:
            print(f"{sdk}:")
            for op, rname, cands in rows:
                print(f"    {op}\n        {rname} -> {', '.join(cands)}")
            total += len(rows)
    print(f"-- {total} operation(s) can be patched mechanically")


if "--paired" in sys.argv:
    report_paired()
else:
    report_all()
