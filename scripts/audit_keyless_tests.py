#!/usr/bin/env python3
"""Which SDKs have a test that runs without an API key, and which have none at all.

Every test in most of these suites fetches a key from the environment and raises
`AssertInconclusiveException` when it is missing, which MSTest reports as skipped. A suite where
*every* test does that passes vacuously in CI: a spec fix, a `$ref` change or a regenerated model can
only be backed by "it compiles". Coze was in exactly that state - 0 passed, 9 skipped - until a
round-trip test was added for the type its spec fix touched.

This finds the SDKs in that state so the gap is a list rather than an impression.

## What counts as key-free, and why this is a heuristic

A **test method** is counted as key-free when its own body mentions none of the auth gateways:
`GetEnvironmentVariable`, `AssertInconclusive`, or a call to a helper whose name starts with
`GetAuthenticatedClient`, `GetApiKey` or `GetClient`. Bodies are taken by brace matching after
comments and string literals are erased, so a gateway named in a fixture or a comment does not count.

This used to work per *file*, and that undercounted: Pinecone's `Examples/EmbeddingGenerator.cs`
declares three tests, one of which calls `GetAuthenticatedClient()` while the other two build a
generator locally and assert on `GetService`. The file was counted as fully gated, so two tests that
run - and pass - with no key were invisible. Per method, Pinecone reports 4, exactly the number the
runner passes there with no key.

That is a proxy, and it errs in both directions. A test can reach a key through a helper this does
not name, and a test that mentions `GetEnvironmentVariable` may still run when the variable is
optional. So the counts here are a shortlist to check by running, not a verdict - `--verify NAME`
prints the command that settles one.

Checked against four real runs, and it agrees with all four: Pinecone 4 of 10 (4 passed, 6 skipped),
Coze 2 of 11 (2 passed, 9 skipped), DId 3 of 18 (3 passed, 15 skipped), Martian 2 of 9 after its
streaming test (before it, 0 of 7 and nothing but skips).

## What it found, 2026-11-17

Of **235** SDKs with a test project, **137 have no key-free test at all** - 58%. In those, a spec
fix, a regenerated model or a changed `$ref` can only ever be backed by a successful build, and the
suite passes vacuously in CI. 93 have at least one, and 5 declare no test methods.

Usage:
    scripts/audit_keyless_tests.py [--limit N] [--verify SDK]
"""

from __future__ import annotations

import argparse
import collections
import json
import pathlib
import re
import sys

# Isolated mode (`python3 -I`) drops the script's own directory from sys.path.
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from csharp_references import strip_non_code  # noqa: E402

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
TEST_METHOD = re.compile(r"\[\s*TestMethod\s*\]")
AUTH_GATEWAY = re.compile(
    r"GetEnvironmentVariable|AssertInconclusive|GetAuthenticatedClient|GetApiKey\b|GetClient\s*\("
)


def test_method_bodies(text: str):
    """Each [TestMethod]'s source, by brace matching from the attribute.

    Per method, not per file. A file that gates one test does not gate the others: Pinecone's
    Examples/EmbeddingGenerator.cs declares three, of which one calls GetAuthenticatedClient() and
    two build a generator locally and assert on GetService. Counting the file as gated hid two
    tests that run - and do pass - with no key.
    """
    code = strip_non_code(text)
    for match in TEST_METHOD.finditer(code):
        start = code.find("{", match.end())
        if start < 0:
            continue
        depth = 0
        for index in range(start, len(code)):
            if code[index] == "{":
                depth += 1
            elif code[index] == "}":
                depth -= 1
                if depth == 0:
                    yield code[match.end():index + 1]
                    break


def scan(sdk_tests: pathlib.Path) -> tuple[int, int, list[str]]:
    """(test methods in all files, test methods that reach no auth gateway, those files' names)."""
    total = keyless = 0
    files: list[str] = []
    for path in sorted(sdk_tests.rglob("*.cs")):
        if any(part in ("bin", "obj") for part in path.parts):
            continue
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        bodies = list(test_method_bodies(text))
        if not bodies:
            continue
        total += len(bodies)
        free = sum(1 for body in bodies if not AUTH_GATEWAY.search(body))
        keyless += free
        if free:
            files.append(path.name)
    return total, keyless, files


def main() -> int:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--limit", type=int, default=25)
    parser.add_argument("--verify", help="print the command that settles one SDK by running it")
    parser.add_argument("--write-baseline", action="store_true",
                        help="record today's key-free counts as the floor")
    parser.add_argument("--check", action="store_true",
                        help="exit 1 if any SDK has fewer key-free tests than the baseline")
    args = parser.parse_args()

    if args.check or args.write_baseline:
        return ratchet(write=args.write_baseline)

    if args.verify:
        print(f"cd {WORKSPACE / args.verify} && dotnet test src/tests/*/ -c Release")
        print("A suite with no key-free test reports `Skipped!` and zero passed.")
        return 0

    no_keyless: dict[str, int] = {}
    some_keyless: dict[str, tuple[int, int]] = {}
    without_tests: list[str] = []

    for sdk in sorted(p for p in WORKSPACE.iterdir() if p.is_dir() and not p.name.startswith(".")):
        tests = sdk / "src" / "tests"
        if not tests.is_dir():
            continue
        total, keyless, files = scan(tests)
        if total == 0:
            without_tests.append(sdk.name)
        elif keyless == 0:
            no_keyless[sdk.name] = total
        else:
            some_keyless[sdk.name] = (keyless, total)

    print(f"SDKs with a test project: {len(no_keyless) + len(some_keyless) + len(without_tests)}")
    print(f"  every test needs a key - a spec fix there rests on the build alone: {len(no_keyless)}")
    print(f"  at least one test runs without a key:                               {len(some_keyless)}")
    print(f"  no test methods at all:                                             {len(without_tests)}")

    if no_keyless:
        print("\nno key-free test, most tests first:")
        for sdk, total in collections.Counter(no_keyless).most_common(args.limit):
            print(f"  {sdk}: {total} test method(s), all gated")

    if some_keyless:
        print("\nkey-free coverage, thinnest first:")
        ranked = sorted(some_keyless.items(), key=lambda kv: (kv[1][0], kv[0]))
        for sdk, (keyless, total) in ranked[: args.limit]:
            print(f"  {sdk}: {keyless} of {total}")

    if without_tests:
        print(f"\nno test methods at all: {', '.join(without_tests[:args.limit])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
