import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT_PATH = Path(__file__).parents[1] / "audit_required_public_operations.py"
SPEC = importlib.util.spec_from_file_location("operation_visibility_audit", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RequiredPublicOperationsAuditTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.spec_path = self.root / "Chroma" / "src" / "libs" / "Chroma" / "openapi.json"
        self.spec_path.parent.mkdir(parents=True)
        self.entry = {
            "repo": "Chroma",
            "spec_path": "src/libs/Chroma/openapi.json",
            "method": "POST",
            "path": "/api/v2/reset",
            "operation_id": "reset",
            "reason": "Public reset contract",
        }

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def write_spec(self, operation: dict[str, object]) -> None:
        self.spec_path.write_text(
            json.dumps({"paths": {"/api/v2/reset": {"post": operation}}}),
            encoding="utf-8",
        )

    def test_public_operation_passes(self) -> None:
        self.write_spec({"operationId": "reset"})

        row = MODULE.audit_entry(self.root, self.entry)

        self.assertEqual("ok", row["status"])
        self.assertEqual("reset", row["actual_operation_id"])
        self.assertEqual("", row["hidden_markers"])

    def test_hidden_operation_fails(self) -> None:
        self.write_spec({"operationId": "reset", "x-hidden": True})

        row = MODULE.audit_entry(self.root, self.entry)

        self.assertEqual("hidden-operation", row["status"])
        self.assertEqual("x-hidden", row["hidden_markers"])

    def test_operation_id_drift_fails(self) -> None:
        self.write_spec({"operationId": "reset_database"})

        row = MODULE.audit_entry(self.root, self.entry)

        self.assertEqual("operation-id-mismatch", row["status"])
        self.assertIn("reset_database", row["details"])


if __name__ == "__main__":
    unittest.main()
