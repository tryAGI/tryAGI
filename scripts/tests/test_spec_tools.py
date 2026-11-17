import importlib.util
import pathlib
import tempfile
import unittest

SCRIPT_PATH = pathlib.Path(__file__).parents[1] / "spec_tools.py"
SPEC = importlib.util.spec_from_file_location("spec_tools", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class LoadDocumentTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def write(self, name: str, text: str) -> pathlib.Path:
        path = self.root / name
        path.write_text(text)
        return path

    def test_reads_json(self) -> None:
        path = self.write("a.json", '{"openapi": "3.1.0"}')
        self.assertEqual(MODULE.load_document(path), {"openapi": "3.1.0"})

    def test_reads_yaml(self) -> None:
        path = self.write("a.yaml", "openapi: 3.1.0\ncomponents:\n  schemas: {}\n")
        document = MODULE.load_document(path)
        self.assertEqual(document["openapi"], "3.1.0")

    def test_missing_file_is_none_not_an_exception(self) -> None:
        self.assertIsNone(MODULE.load_document(self.root / "absent.json"))

    def test_unparseable_file_is_none(self) -> None:
        path = self.write("a.json", "{this is neither json nor yaml: [")
        self.assertIsNone(MODULE.load_document(path))


class FindSpecTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_finds_by_stem_across_roots(self) -> None:
        second = self.root / "second"
        second.mkdir()
        (second / "did.json").write_text("{}")
        found = MODULE.find_spec("did", self.root / "first", second)
        self.assertEqual(found.name, "did.json")

    def test_ignores_unrelated_suffixes(self) -> None:
        (self.root / "did.md").write_text("notes")
        self.assertIsNone(MODULE.find_spec("did", self.root))

    def test_missing_root_is_not_an_error(self) -> None:
        self.assertIsNone(MODULE.find_spec("did", self.root / "nope"))


class DeclaredComponentsTests(unittest.TestCase):
    def test_returns_component_names(self) -> None:
        document = {"components": {"schemas": {"JsonError": {}, "JsonError1": {}}}}
        self.assertEqual(MODULE.declared_components(document), {"JsonError", "JsonError1"})

    def test_tolerates_every_shape_of_missing(self) -> None:
        for document in (None, {}, {"components": None}, {"components": {"schemas": None}},
                         {"components": {"schemas": []}}, "not a document"):
            self.assertEqual(MODULE.declared_components(document), set(), repr(document))


class SourceFilesTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temp.name)
        (self.root / "src").mkdir()
        (self.root / "src" / "Kept.cs").write_text("//")
        for pruned in ("bin", "obj", "Snapshots", "TestResults"):
            (self.root / "src" / pruned).mkdir()
            (self.root / "src" / pruned / "Skipped.cs").write_text("//")
        # nested, to prove the prune happens during the walk and not per-level
        (self.root / "src" / "Deep").mkdir()
        (self.root / "src" / "Deep" / "Snapshots").mkdir()
        (self.root / "src" / "Deep" / "Snapshots" / "Buried.cs").write_text("//")
        (self.root / "src" / "Deep" / "AlsoKept.cs").write_text("//")

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_prunes_the_listed_directories(self) -> None:
        found = {p.name for p in MODULE.source_files(self.root)}
        self.assertEqual(found, {"Kept.cs", "AlsoKept.cs"})

    def test_prunes_at_any_depth(self) -> None:
        self.assertNotIn("Buried.cs", {p.name for p in MODULE.source_files(self.root)})

    def test_suffix_is_respected(self) -> None:
        (self.root / "src" / "notes.md").write_text("x")
        self.assertEqual(
            {p.name for p in MODULE.source_files(self.root, suffix=".md")}, {"notes.md"})

    def test_missing_root_yields_nothing(self) -> None:
        self.assertEqual(list(MODULE.source_files(self.root / "absent")), [])


class StableTests(unittest.TestCase):
    def test_key_order_does_not_matter(self) -> None:
        self.assertEqual(MODULE.stable({"a": 1, "b": 2}), MODULE.stable({"b": 2, "a": 1}))

    def test_list_order_does_matter(self) -> None:
        self.assertNotEqual(MODULE.stable([1, 2]), MODULE.stable([2, 1]))

    def test_mixed_type_keys_do_not_raise(self) -> None:
        # YAML turns a bare `on:` key into True, so a map can hold both a bool and a str key.
        self.assertIsInstance(MODULE.stable({True: 1, "on": 2}), str)

    def test_datetime_values_do_not_raise(self) -> None:
        import datetime
        self.assertIsInstance(MODULE.stable({"d": datetime.date(2026, 11, 16)}), str)

    def test_distinguishes_values(self) -> None:
        self.assertNotEqual(MODULE.stable({"a": 1}), MODULE.stable({"a": "1"}))


if __name__ == "__main__":
    unittest.main()
