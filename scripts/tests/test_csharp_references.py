import importlib.util
import pathlib
import unittest

SCRIPT_PATH = pathlib.Path(__file__).parents[1] / "csharp_references.py"
SPEC = importlib.util.spec_from_file_location("csharp_references", SCRIPT_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)

NAMES = ["Status", "AudioUrl", "TextScript", "JsonError", "Agent"]


def refs(source: str):
    return MODULE.type_references(source, NAMES, namespaces=("DId",))


class MemberAccessTests(unittest.TestCase):
    """The failure this module exists for: a property that shares a type's name."""

    def test_property_access_is_not_a_type_reference(self) -> None:
        self.assertEqual(refs("var s = response.Status.ToValueString();"), set())

    def test_property_access_in_interpolation_is_not_a_reference(self) -> None:
        self.assertEqual(refs('parts.Add($"Audio URL: {response.AudioUrl}");'), set())

    def test_namespace_qualified_name_IS_a_type_reference(self) -> None:
        # Generated code spells types this way, and it is dotted like a member access.
        self.assertEqual(refs("global::DId.Status x = default;"), {"Status"})

    def test_an_unknown_qualifier_stays_a_member(self) -> None:
        self.assertEqual(refs("other.Status = 1;"), set())

    def test_an_object_initializer_property_is_not_a_type(self) -> None:
        # The false positive this rule exists for: D-ID's DIdRealtimeSession.cs assigns a property
        # called Role, and there is also a component called Role.
        self.assertEqual(refs("var m = new Message { Status = 1, Agent = other.Agent };"), set())

    def test_a_declaration_is_still_a_type(self) -> None:
        # `?` sits where `=` would, so the assignment rule must not swallow this.
        self.assertEqual(refs("TextScript? script = null;"), {"TextScript"})

    def test_a_lambda_arrow_is_not_an_assignment(self) -> None:
        self.assertEqual(refs("var f = (Agent a) => a;"), {"Agent"})


class TypePositionTests(unittest.TestCase):
    def test_static_call_on_the_type(self) -> None:
        self.assertEqual(refs('var x = TextScript.FromJson(body);'), {"TextScript"})

    def test_construction(self) -> None:
        self.assertEqual(refs("var e = new JsonError();"), {"JsonError"})

    def test_generic_argument(self) -> None:
        self.assertEqual(refs("List<Agent> agents = [];"), {"Agent"})

    def test_declaration_and_nullable(self) -> None:
        self.assertEqual(refs("TextScript? script = null;"), {"TextScript"})


class NonCodeTests(unittest.TestCase):
    def test_identifier_inside_a_raw_string_is_not_a_reference(self) -> None:
        source = 'var body = """{"Status":"ok","TextScript":1}""";'
        self.assertEqual(refs(source), set())

    def test_identifier_inside_an_ordinary_string_is_not_a_reference(self) -> None:
        self.assertEqual(refs('var s = "Agent";'), set())

    def test_identifier_inside_a_verbatim_string_is_not_a_reference(self) -> None:
        self.assertEqual(refs('var s = @"JsonError and ""Agent""";'), set())

    def test_identifier_in_a_line_comment_is_not_a_reference(self) -> None:
        self.assertEqual(refs("// TextScript used to live here\nvar x = 1;"), set())

    def test_identifier_in_a_block_comment_is_not_a_reference(self) -> None:
        self.assertEqual(refs("/* Agent\n   JsonError */\nvar x = 1;"), set())

    def test_code_after_a_raw_string_is_still_scanned(self) -> None:
        # The offset-preserving strip is what keeps this from swallowing the rest of the file.
        source = 'var body = """{"Status":1}""";\nvar e = new JsonError();'
        self.assertEqual(refs(source), {"JsonError"})


class SubstringTests(unittest.TestCase):
    def test_a_longer_identifier_is_not_a_match(self) -> None:
        self.assertEqual(refs("var x = new AgentTemplate();"), set())

    def test_a_prefixed_identifier_is_not_a_match(self) -> None:
        self.assertEqual(refs("var x = MyAgent.Create();"), set())


if __name__ == "__main__":
    unittest.main()
