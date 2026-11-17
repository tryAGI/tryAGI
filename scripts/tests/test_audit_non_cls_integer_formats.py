"""The audit reports zero today, so prove it can still see an `int8` when there is one.

A check that is correct only because the thing it looks for is currently absent is
indistinguishable from a check that is broken. These build the shape by hand.
"""

import importlib.util
import json
import pathlib
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).parents[1] / "audit_non_cls_integer_formats.py"
SPEC = importlib.util.spec_from_file_location("audit_non_cls_integer_formats", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class IntegerFormatScanTests(unittest.TestCase):
    def scan(self, document):
        import collections
        found: collections.Counter = collections.Counter()
        MODULE.integer_formats(document, found)
        return dict(found)

    def test_finds_int8_wherever_it_is_nested(self) -> None:
        document = {
            "components": {"schemas": {"A": {"properties": {
                "k": {"type": "integer", "format": "int8"},
            }}}},
            "paths": {"/x": {"get": {"parameters": [
                {"schema": {"type": "integer", "format": "int8"}},
            ]}}},
        }
        self.assertEqual(self.scan(document), {"int8": 2})

    def test_ignores_the_unsigned_formats_autosdk_widens(self) -> None:
        # The measurement that corrected this script: AutoSDK maps every unsigned format to a
        # signed type, so none of these can produce a CS3001.
        for fmt in ("uint8", "uint16", "uint32", "uint64", "int16", "int32", "int64"):
            document = {"a": {"type": "integer", "format": fmt}}
            self.assertEqual(self.scan(document), {}, fmt)

    def test_ignores_an_int8_format_on_a_non_integer_type(self) -> None:
        self.assertEqual(self.scan({"a": {"type": "string", "format": "int8"}}), {})


class ClsComplianceDetectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.sdk = pathlib.Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write_props(self, relative: str) -> None:
        path = self.sdk / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            '<Project><ItemGroup Label="CLSCompliant">'
            '<AssemblyAttribute Include="System.CLSCompliantAttribute" />'
            "</ItemGroup></Project>"
        )

    def test_finds_it_where_the_sdks_actually_keep_it(self) -> None:
        # Julep's is at src/libs; the other two are checked because layouts differ.
        self.write_props("src/libs/Directory.Build.props")
        self.assertTrue(MODULE.declares_cls_compliance(self.sdk))

    def test_absent_props_is_not_compliance(self) -> None:
        self.assertFalse(MODULE.declares_cls_compliance(self.sdk))

    def test_props_without_the_attribute_is_not_compliance(self) -> None:
        path = self.sdk / "src" / "libs" / "Directory.Build.props"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("<Project><PropertyGroup><Nullable>enable</Nullable></PropertyGroup></Project>")
        self.assertFalse(MODULE.declares_cls_compliance(self.sdk))


class ZeroInputTests(unittest.TestCase):
    def test_a_run_over_no_specs_is_an_error_not_a_pass(self) -> None:
        # The failure mode that makes a CI job look green while checking nothing. The workspace repo
        # tracks no SDK sources, so this is the state a job here would actually be in.
        import contextlib
        import io
        import sys

        argv = sys.argv
        sys.argv = ["audit", "--sdk", "ThisSdkDoesNotExist"]
        err = io.StringIO()
        try:
            with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
                code = MODULE.main()
        finally:
            sys.argv = argv

        self.assertEqual(code, 2)
        self.assertIn("scanned no specs", err.getvalue())


class NonClsTableTests(unittest.TestCase):
    def test_the_table_holds_int8_alone(self) -> None:
        # Guards the correction: re-adding uint16/uint32 would resurrect six false positives.
        self.assertEqual(MODULE.NON_CLS, {"int8": "sbyte"})


if __name__ == "__main__":
    unittest.main()
