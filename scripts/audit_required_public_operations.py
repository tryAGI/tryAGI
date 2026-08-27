#!/usr/bin/env python3

import argparse
import csv
import json
import re
from pathlib import Path


FIELDS = [
    "repo",
    "method",
    "path",
    "spec_path",
    "expected_operation_id",
    "actual_operation_id",
    "hidden_markers",
    "status",
    "reason",
    "details",
]

IGNORE_MARKERS = (
    "x-hidden",
    "x-fern-ignore",
    "x-speakeasy-ignore",
    "x-stainless-skip",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Audit configured OpenAPI operations that must remain public."
    )
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--repo-regex", default="")
    return parser.parse_args()


def is_truthy_marker(value: object) -> bool:
    if value is None or value is False:
        return False
    if isinstance(value, str):
        return value.strip().lower() not in {"", "false", "none", "null"}
    if isinstance(value, (list, dict)):
        return bool(value)
    return bool(value)


def load_policy(config_path: Path) -> list[dict[str, object]]:
    with config_path.open(encoding="utf-8") as config_file:
        config = json.load(config_file)

    entries = config.get("operation_visibility", {}).get(
        "required_public_operations", []
    )
    if not isinstance(entries, list):
        raise SystemExit(
            "operation_visibility.required_public_operations must be an array"
        )

    required_fields = {"repo", "spec_path", "method", "path", "operation_id", "reason"}
    for index, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise SystemExit(f"required public operation at index {index} must be an object")
        missing = sorted(required_fields - entry.keys())
        if missing:
            raise SystemExit(
                f"required public operation at index {index} is missing: {', '.join(missing)}"
            )

    return entries


def audit_entry(root: Path, entry: dict[str, object]) -> dict[str, str]:
    repo = str(entry["repo"])
    method = str(entry["method"]).lower()
    path = str(entry["path"])
    spec_path = str(entry["spec_path"])
    expected_operation_id = str(entry["operation_id"])
    reason = str(entry["reason"])
    row = {
        "repo": repo,
        "method": method.upper(),
        "path": path,
        "spec_path": spec_path,
        "expected_operation_id": expected_operation_id,
        "actual_operation_id": "",
        "hidden_markers": "",
        "status": "ok",
        "reason": reason,
        "details": "",
    }

    repo_path = root / repo
    if not repo_path.is_dir():
        row["status"] = "missing-repo"
        row["details"] = f"repository directory does not exist: {repo_path}"
        return row

    absolute_spec_path = repo_path / spec_path
    if not absolute_spec_path.is_file():
        row["status"] = "missing-spec"
        row["details"] = f"specification file does not exist: {absolute_spec_path}"
        return row

    try:
        with absolute_spec_path.open(encoding="utf-8") as spec_file:
            spec = json.load(spec_file)
    except (OSError, json.JSONDecodeError) as error:
        row["status"] = "invalid-spec"
        row["details"] = str(error).replace("\t", " ").replace("\n", " ")
        return row

    path_item = spec.get("paths", {}).get(path)
    if not isinstance(path_item, dict):
        row["status"] = "missing-path"
        row["details"] = "configured path is absent from the normalized specification"
        return row

    operation = path_item.get(method)
    if not isinstance(operation, dict):
        row["status"] = "missing-operation"
        row["details"] = "configured HTTP method is absent from the normalized specification"
        return row

    actual_operation_id = str(operation.get("operationId") or "")
    row["actual_operation_id"] = actual_operation_id
    hidden_markers = [
        marker
        for marker in IGNORE_MARKERS
        if marker in operation and is_truthy_marker(operation.get(marker))
    ]
    row["hidden_markers"] = ",".join(hidden_markers)

    details = []
    if hidden_markers:
        row["status"] = "hidden-operation"
        details.append("operation is excluded by " + ", ".join(hidden_markers))
    if actual_operation_id != expected_operation_id:
        if row["status"] == "ok":
            row["status"] = "operation-id-mismatch"
        details.append(
            f"expected operationId {expected_operation_id!r}, found {actual_operation_id!r}"
        )
    row["details"] = "; ".join(details)
    return row


def main() -> None:
    args = parse_args()
    repo_pattern = re.compile(args.repo_regex) if args.repo_regex else None
    entries = load_policy(args.config)
    rows = [
        audit_entry(args.root, entry)
        for entry in entries
        if repo_pattern is None or repo_pattern.search(str(entry["repo"]))
    ]

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8", newline="") as output_file:
        writer = csv.DictWriter(output_file, fieldnames=FIELDS, delimiter="\t")
        writer.writeheader()
        writer.writerows(rows)


if __name__ == "__main__":
    main()
