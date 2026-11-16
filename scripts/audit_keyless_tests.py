#!/usr/bin/env python3
"""Which SDKs have a test that runs without an API key, and which have none at all.

Every test in most of these suites fetches a key from the environment and raises
`AssertInconclusiveException` when it is missing, which MSTest reports as skipped. A suite where
*every* test does that passes vacuously in CI: a spec fix, a `$ref` change or a regenerated model can
only be backed by "it compiles". Coze was in exactly that state - 0 passed, 9 skipped - until a
round-trip test was added for the type its spec fix touched.

This finds the SDKs in that state so the gap is a list rather than an impression.

## What counts as key-free, and why this is a heuristic

A test file is counted as key-free when it declares at least one `[TestMethod]` and mentions none of
the auth gateways: `GetEnvironmentVariable`, `AssertInconclusive`, or a call to a helper whose name
starts with `GetAuthenticatedClient`, `GetApiKey` or `GetClient`.

That is a proxy, and it errs in both directions. A test can reach a key through a helper this does
not name, and a test that mentions `GetEnvironmentVariable` may still run when the variable is
optional. So the counts here are a shortlist to check by running, not a verdict - `--verify NAME`
prints the command that settles one.

Checked against three real runs on 2026-11-17, and it agreed with all three: Coze 2 key-free of 11
(ran as 2 passed, 9 skipped), DId 3 of 18 (3 passed, 15 skipped), Martian 0 of 7 (reported
`Skipped!`, 0 passed).

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

WORKSPACE = pathlib.Path(__file__).resolve().parent.parent
TEST_METHOD = re.compile(r"\[\s*TestMethod\s*\]")
AUTH_GATEWAY = re.compile(
    r"GetEnvironmentVariable|AssertInconclusive|GetAuthenticatedClient|GetApiKey\b|GetClient\s*\("
)


def scan(sdk_tests: pathlib.Path) -> tuple[int, int, list[str]]:
    """(test methods in all files, test methods in key-free files, those files' names)."""
    total = keyless = 0
    files: list[str] = []
    for path in sorted(sdk_tests.rglob("*.cs")):
        if any(part in ("bin", "obj") for part in path.parts):
            continue
        try:
            text = path.read_text(errors="replace")
        except OSError:
            continue
        methods = len(TEST_METHOD.findall(text))
        if not methods:
            continue
        total += methods
        if not AUTH_GATEWAY.search(text):
            keyless += methods
            files.append(path.name)
    return total, keyless, files


BASELINE = WORKSPACE / "scripts" / "keyless-tests-baseline.json"


def counts() -> dict[str, int]:
    found: dict[str, int] = {}
    for sdk in sorted(p for p in WORKSPACE.iterdir() if p.is_dir() and not p.name.startswith(".")):
        tests = sdk / "src" / "tests"
        if tests.is_dir():
            total, keyless, _ = scan(tests)
            if total:
                found[sdk.name] = keyless
    return found


def ratchet(write: bool) -> int:
    """A floor, not a target: 137 SDKs have no key-free test and demanding one today would only
    make the check red. What this catches is losing coverage that exists - a regenerated suite, a
    deleted file, a test that grew an environment variable - which is invisible otherwise, because
    a suite of nothing but skips reports success.

    Note this can only run where the SDK repositories are checked out beside this one. The
    workspace repository tracks no SDK, so its own CI cannot see them.
    """
    current = counts()
    if write:
        BASELINE.write_text(json.dumps(dict(sorted(current.items())), indent=2) + "\n")
        covered = sum(1 for v in current.values() if v)
        print(f"baseline written: {len(current)} SDKs, {covered} with key-free coverage")
        return 0

    if not BASELINE.is_file():
        print(f"no baseline at {BASELINE}; run --write-baseline first", file=sys.stderr)
        return 1

    previous = json.loads(BASELINE.read_text())
    regressions = [
        (sdk, previous[sdk], current.get(sdk, 0))
        for sdk in sorted(previous)
        if sdk in current and current[sdk] < previous[sdk]
    ]
    missing = sorted(sdk for sdk in previous if sdk not in current)
    gains = [(sdk, previous.get(sdk, 0), count) for sdk, count in sorted(current.items())
             if count > previous.get(sdk, 0)]

    for sdk, was, now in regressions:
        print(f"REGRESSION {sdk}: {was} key-free test(s) -> {now}")
    for sdk in missing:
        print(f"MISSING {sdk}: had {previous[sdk]} key-free test(s), no test project now")
    for sdk, was, now in gains:
        print(f"gained    {sdk}: {was} -> {now}; re-run --write-baseline to lock it in")

    if regressions or missing:
        return 1
    print(f"no regressions against {len(previous)} baselined SDKs")
    return 0


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
