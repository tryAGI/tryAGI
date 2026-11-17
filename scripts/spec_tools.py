"""Shared helpers for the OpenAPI audit scripts in this directory.

Every audit here grew its own copy of "read a spec" and "serialize a parsed value", and the copies
drifted. That drift is not cosmetic: the collision counts in three separate audits were wrong because
each decided independently - and differently - what counts as a name the document declares itself.
Three corrections later, the loaders live here.

Importing this under `python3 -I` needs one line of ceremony, because isolated mode drops the
script's own directory from `sys.path`:

    import pathlib, sys
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    from spec_tools import load_document

The audits are run as `python3 -I scripts/<name>.py`, so that is the supported way in.
"""

from __future__ import annotations

import json
import os
import pathlib
import sys

SPEC_SUFFIXES = (".yaml", ".yml", ".json")

# Directories that hold no hand-written or generated *source* worth scanning. `Snapshots` is the one
# that matters: AutoSDK keeps 261515 .cs baselines under src/tests/AutoSDK.SnapshotTests/Snapshots,
# 98.6% of every .cs file under any src/tests in the workspace, and an audit that walked into them
# took 2m18s instead of 1.4s.
#
# So this is for walking source trees, and it is wrong for walking a snapshot tree - don't reach for
# `source_files` in an audit whose subject IS the baselines (audit_snapshot_collisions is one).
PRUNED_DIRECTORIES = frozenset({"bin", "obj", "Snapshots", "_snapshots", "TestResults", "node_modules"})


_WARNED_ABOUT_PURE_YAML = False


def _yaml_loader(yaml):
    """libyaml's loader, or the pure-Python one with a warning that says what it costs.

    The pure loader is ~11x slower on these documents - 8.80s against 0.79s on Anthropic's 7MB spec -
    and it was 76% of one audit's runtime. A PyYAML built without libyaml would make every audit
    slow with nothing to show why, so say it once rather than let it be mysterious.
    """
    loader = getattr(yaml, "CSafeLoader", None)
    if loader is not None:
        return loader

    global _WARNED_ABOUT_PURE_YAML
    if not _WARNED_ABOUT_PURE_YAML:
        _WARNED_ABOUT_PURE_YAML = True
        print("warning: PyYAML has no CSafeLoader (libyaml); spec parsing will be ~11x slower. "
              "Reinstall PyYAML with libyaml available.", file=sys.stderr)
    return yaml.SafeLoader


def source_files(root: pathlib.Path, suffix: str = ".cs"):
    """Files under `root` with that suffix, pruning PRUNED_DIRECTORIES during the walk.

    Pruning while walking rather than filtering afterwards is the point: `rglob` descends into a
    directory before anything can reject it.
    """
    for directory, subdirectories, names in os.walk(root):
        subdirectories[:] = [d for d in subdirectories if d not in PRUNED_DIRECTORIES]
        for name in sorted(names):
            if name.endswith(suffix):
                yield pathlib.Path(directory) / name


def load_document(path: pathlib.Path):
    """Parse an OpenAPI document, JSON or YAML, or return None.

    JSON first because most of these documents are JSON and `yaml.safe_load` on a large JSON file is
    an order of magnitude slower. Returns None rather than raising: an audit runs over a couple of
    hundred documents and one unparseable file should be reported, not fatal.
    """
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    try:
        import yaml
    except ImportError:
        return None
    loader = _yaml_loader(yaml)
    try:
        return yaml.load(text, Loader=loader)
    except Exception:
        return None


def find_spec(stem: str, *roots: pathlib.Path) -> pathlib.Path | None:
    """The first file named `<stem>.<json|yaml|yml>` in any of the given directories."""
    for root in roots:
        if not root.is_dir():
            continue
        for candidate in sorted(root.glob(f"{stem}.*")):
            if candidate.suffix in SPEC_SUFFIXES:
                return candidate
    return None


def declared_components(document) -> set[str]:
    """The names under `components.schemas`, which are never AutoSDK name collisions.

    Several of the tools that produce these documents deduplicate by appending an index, so a spec
    can arrive already holding `JsonError` through `JsonError4` (D-ID), `AccountVO` and `AccountVO2`
    (Dedoose), `CanvasPosition` and `CanvasPosition1` (Coze). AutoSDK reproduces those names
    faithfully and has nothing to merge - they are separate components, not one schema seen twice -
    so an audit that counts them as collisions overstates its own subject. That error was worth 251
    names on AutoSDK's fixtures, 214 of them OpenRouter's, and 175 across the SDK repositories.
    """
    if not isinstance(document, dict):
        return set()
    schemas = (document.get("components") or {}).get("schemas") or {}
    return set(schemas) if isinstance(schemas, dict) else set()


def stable(value) -> str:
    """A deterministic string for any parsed YAML/JSON value.

    `json.dumps(..., sort_keys=True)` is not usable on these documents. YAML turns unquoted dates
    into `datetime` objects, which json refuses, and bare `on` / `off` / `yes` keys into booleans, so
    a map can end up with keys of mixed types that will not sort against each other. This sorts keys
    by their text and never calls json.
    """
    if isinstance(value, dict):
        return "{" + ",".join(
            f"{key}:{stable(child)}"
            for key, child in sorted(((str(k), v) for k, v in value.items()), key=lambda kv: kv[0])
        ) + "}"
    if isinstance(value, list):
        return "[" + ",".join(stable(child) for child in value) + "]"
    return repr(value)
