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


class YamlLoaderTests(unittest.TestCase):
    def test_prefers_libyaml_when_present(self) -> None:
        import yaml
        self.assertIs(MODULE._yaml_loader(yaml), yaml.CSafeLoader)

    def test_falls_back_and_warns_once(self) -> None:
        import contextlib
        import io
        import types

        MODULE._WARNED_ABOUT_PURE_YAML = False
        without = types.SimpleNamespace(SafeLoader=object())
        captured = io.StringIO()
        with contextlib.redirect_stderr(captured):
            first = MODULE._yaml_loader(without)
            second = MODULE._yaml_loader(without)

        self.assertIs(first, without.SafeLoader)
        self.assertIs(second, without.SafeLoader)
        # Once, not per document: an audit parses hundreds.
        self.assertEqual(captured.getvalue().count("warning:"), 1)
        self.assertIn("11x slower", captured.getvalue())


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


class SchemaPositionTests(unittest.TestCase):
    """The filter that turned "52 typeless schemas in 16 SDKs" into the real answer, 0."""

    def formats_found(self, document):
        return {
            "/".join(str(s) for s in segments): node["format"]
            for node, segments in MODULE.walk_schema_positions(document)
            if isinstance(node, dict) and "format" in node
        }

    def test_a_real_schema_is_a_schema_position(self) -> None:
        document = {"components": {"schemas": {"A": {"format": "date-time"}}}}
        self.assertEqual(self.formats_found(document), {"components/schemas/A": "date-time"})

    def test_an_example_payload_is_not(self) -> None:
        # OpenRouter's `components/schemas/ChatContentAudio/example/input_audio` holds
        # `{"data": ..., "format": "wav"}`. That is data, not a schema.
        document = {"components": {"schemas": {"A": {"example": {"input_audio": {"format": "wav"}}}}}}
        self.assertEqual(self.formats_found(document), {})

    def test_a_vendor_extension_is_not(self) -> None:
        # Vectara's `x-fern-streaming` declares `format: sse`.
        document = {"paths": {"/q": {"post": {"x-fern-streaming": {"format": "sse"}}}}}
        self.assertEqual(self.formats_found(document), {})

    def test_a_default_and_an_enum_value_are_not(self) -> None:
        for key in ("default", "enum", "examples"):
            document = {"components": {"schemas": {"A": {key: {"nested": {"format": "mp4"}}}}}}
            self.assertEqual(self.formats_found(document), {}, key)

    def test_the_exclusion_reaches_everything_nested_inside(self) -> None:
        # Ollama's is three levels below `example`; excluding only the immediate child would miss it.
        document = {"paths": {"/t": {"get": {"responses": {"200": {"content": {
            "application/json": {"example": {"models": [{"details": {"format": "gguf"}}]}}}}}}}}}
        self.assertEqual(self.formats_found(document), {})

    def test_a_schema_beside_an_example_still_counts(self) -> None:
        document = {"components": {"schemas": {"A": {
            "format": "uuid",
            "example": {"format": "mp4"},
        }}}}
        self.assertEqual(self.formats_found(document), {"components/schemas/A": "uuid"})

    def test_a_default_response_is_a_schema_position(self) -> None:
        # `default` under `responses` is the catch-all status code, not a default value. Excluding
        # it blindly hid 416 genuine schema positions across the corpus.
        document = {"paths": {"/x": {"post": {"responses": {"default": {"content": {
            "application/json": {"schema": {"format": "date-time"}}}}}}}}}
        self.assertEqual(
            self.formats_found(document),
            {"paths//x/post/responses/default/content/application/json/schema": "date-time"})

    def test_a_schemas_own_default_value_is_still_excluded(self) -> None:
        document = {"components": {"schemas": {"A": {"default": {"format": "mp4"}}}}}
        self.assertEqual(self.formats_found(document), {})

    def test_a_property_literally_named_default_outside_responses_is_excluded(self) -> None:
        # Conservative on purpose: `default` anywhere but directly under `responses` is a value.
        document = {"components": {"schemas": {"A": {"properties": {
            "default": {"format": "mp4"}}}}}}
        self.assertEqual(self.formats_found(document), {})

    def test_is_schema_position_takes_the_path_itself(self) -> None:
        self.assertTrue(MODULE.is_schema_position(["components", "schemas", "A"]))
        self.assertFalse(MODULE.is_schema_position(["components", "schemas", "A", "example"]))
        self.assertFalse(MODULE.is_schema_position(["paths", "/q", "post", "x-fern-streaming"]))
        self.assertTrue(MODULE.is_schema_position(["paths", "/q", "post", "responses", "default"]))
        self.assertFalse(MODULE.is_schema_position(["components", "schemas", "A", "default"]))


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
