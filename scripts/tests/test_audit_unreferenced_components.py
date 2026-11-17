"""The ratchet passes today, so prove it can fail.

A check that is green because nothing has moved is indistinguishable from one that cannot see
movement. These drive `ratchet` against a stand-in count so every outcome is exercised.
"""

import importlib.util
import io
import json
import pathlib
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

SCRIPT = pathlib.Path(__file__).parents[1] / "audit_unreferenced_components.py"
SPEC = importlib.util.spec_from_file_location("audit_unreferenced_components", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RatchetTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.baseline = pathlib.Path(self.temp.name) / "baseline.json"
        self.original_baseline = MODULE.BASELINE
        self.original_counts = MODULE.orphan_counts
        MODULE.BASELINE = self.baseline

    def tearDown(self) -> None:
        MODULE.BASELINE = self.original_baseline
        MODULE.orphan_counts = self.original_counts
        self.temp.cleanup()

    def run_ratchet(self, counts, write=False, tolerance=25):
        MODULE.orphan_counts = lambda: counts
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = MODULE.ratchet(write, tolerance)
        return code, out.getvalue(), err.getvalue()

    def write_baseline(self, counts) -> None:
        self.baseline.write_text(json.dumps(counts) + "\n")

    def test_an_unchanged_tree_passes(self) -> None:
        self.write_baseline({"A": 10, "B": 0})
        code, out, _ = self.run_ratchet({"A": 10, "B": 0})
        self.assertEqual(code, 0)
        self.assertIn("total 10 -> 10", out)

    def test_drift_under_the_tolerance_does_not_fail(self) -> None:
        # Every SDK's spec refreshes every few hours; an equality check would be red for ever.
        self.write_baseline({"A": 100})
        code, out, _ = self.run_ratchet({"A": 112})
        self.assertEqual(code, 0)
        self.assertIn("drift  A: 100 -> 112", out)

    def test_a_jump_over_the_tolerance_fails(self) -> None:
        self.write_baseline({"A": 100})
        code, out, _ = self.run_ratchet({"A": 600})
        self.assertEqual(code, 1)
        self.assertIn("JUMP   A: 100 -> 600", out)

    def test_a_jump_downwards_fails_too(self) -> None:
        # A collapse is as much a question as a spike: it can mean a spec lost its components.
        self.write_baseline({"A": 600})
        code, out, _ = self.run_ratchet({"A": 100})
        self.assertEqual(code, 1)
        self.assertIn("JUMP   A: 600 -> 100", out)

    def test_a_baselined_sdk_disappearing_fails(self) -> None:
        self.write_baseline({"A": 5, "B": 5})
        code, out, _ = self.run_ratchet({"A": 5})
        self.assertEqual(code, 1)
        self.assertIn("JUMP   B: 5 -> gone", out)

    def test_a_small_new_sdk_is_drift_and_a_large_one_is_a_jump(self) -> None:
        self.write_baseline({"A": 5})
        code, out, _ = self.run_ratchet({"A": 5, "B": 3})
        self.assertEqual(code, 0)
        self.assertIn("drift  B: new -> 3", out)

        code, out, _ = self.run_ratchet({"A": 5, "B": 300})
        self.assertEqual(code, 1)
        self.assertIn("JUMP   B: new -> 300", out)

    def test_a_run_over_nothing_is_an_error_not_a_pass(self) -> None:
        self.write_baseline({"A": 5})
        code, _, err = self.run_ratchet({})
        self.assertEqual(code, 2)
        self.assertIn("found no SDK spec", err)

    def test_a_missing_baseline_says_so(self) -> None:
        code, _, err = self.run_ratchet({"A": 5})
        self.assertEqual(code, 1)
        self.assertIn("run --write-baseline first", err)

    def test_write_baseline_records_what_it_counted(self) -> None:
        code, out, _ = self.run_ratchet({"A": 7, "B": 0}, write=True)
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(self.baseline.read_text()), {"A": 7, "B": 0})
        self.assertIn("2 SDKs, 7 orphans", out)


if __name__ == "__main__":
    unittest.main()
