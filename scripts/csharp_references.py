"""Find where C# source refers to a *type*, as opposed to a member that happens to share its name.

Written because a word-boundary regex got this wrong in the way that matters. Asked which of D-ID's
unreachable components its hand-written code uses, a regex answered eight; four of those were
`response.Status`, `response.AudioUrl`, `talk.Status` and a `Role` property - member accesses, not
type references - and the real answer was three. A conclusion about what is safe to delete was
nearly built on that.

Two steps, and the second is the one with the content:

1. **Erase what is not code.** Comments, and every flavour of string literal C# has: raw (`\"\"\"`),
   verbatim (`@\"\"`), interpolated (`$\"\"`, `$@\"\"`, `$\"\"\"\"\"\"`) and ordinary. An identifier inside a
   JSON fixture is not a reference to anything.
2. **Reject member accesses.** An identifier preceded by `.` is a member - *unless* the qualifier is
   a namespace, which is exactly how generated code spells a type: `global::DId.Status` is the type
   `Status`, while `response.Status` is a property. Passing the namespaces tells the two apart; with
   none passed, every dotted occurrence is treated as a member.

What it does not do is parse C#. It has no notion of scope, so a local variable named `Agent` would
read as a reference to the type `Agent`. For the question it answers - does this file mention this
generated type at all - that errs toward reporting a use, which is the safe direction when the
answer decides whether something can be deleted.
"""

from __future__ import annotations

import re

# Ordinary and verbatim strings, raw strings of any fence length, and their interpolated forms.
RAW_STRING = re.compile(r'\$*"{3,}')
VERBATIM_STRING = re.compile(r'@\$?"(?:[^"]|"")*"', re.S)
NORMAL_STRING = re.compile(r'\$?"(?:\\.|[^"\\\n])*"')
CHAR_LITERAL = re.compile(r"'(?:\\.|[^'\\])'")


# One alternation to find the next construct that is not code. Everything between two of these is
# plain source and can be copied in one slice - which is the whole point: the previous version
# stepped one character at a time, and the audits that call this walk every test file of 235 SDKs.
INTERESTING = re.compile(r'//|/\*|\$*"{3,}|@\$?"|\$?"|\'')


def strip_non_code(source: str) -> str:
    """Replace comments and string literals with spaces, preserving every other offset.

    One left-to-right pass, not a pass per construct. Separate passes get this wrong: a verbatim
    string that ends with a doubled quote before its closing quote finishes with three quote
    characters in a row - indistinguishable from the start of a raw string - so a raw-string pass
    running first blanks the rest of the file.
    """
    out: list[str] = []
    index = 0
    length = len(source)
    while index < length:
        match = INTERESTING.search(source, index)
        if match is None:
            out.append(source[index:])
            break

        out.append(source[index:match.start()])
        index = match.start()
        token = match.group(0)

        if token == "//":
            end = source.find("\n", index)
            end = length if end < 0 else end
        elif token == "/*":
            end = source.find("*/", index + 2)
            end = length if end < 0 else end + 2
        elif token.lstrip("$").startswith('"""'):
            fence = token.lstrip("$")
            closing = source.find(fence, index + len(token))
            end = length if closing < 0 else closing + len(fence)
        elif token.startswith("@"):
            verbatim = VERBATIM_STRING.match(source, index)
            end = verbatim.end() if verbatim else length
        elif token.endswith('"'):
            normal = NORMAL_STRING.match(source, index)
            end = normal.end() if normal else index + len(token)
        else:
            literal = CHAR_LITERAL.match(source, index)
            end = literal.end() if literal else index + 1

        out.append(" " * (end - index))
        index = end
    return "".join(out)


def type_references(source: str, names, namespaces=()) -> set[str]:
    """Which of `names` the source refers to as a type.

    `namespaces` are the qualifiers under which a dotted occurrence is still a type reference -
    pass the SDK's root namespace, e.g. ("DId",), so `global::DId.Status` counts while
    `response.Status` does not.
    """
    text = strip_non_code(source)
    allowed = {n for n in namespaces}
    found = set()
    for name in names:
        for match in re.finditer(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", text):
            after = text[match.end():].lstrip()
            # `Role = ChatRequestMessageRole.User` inside an object initializer: the identifier is
            # an assignment target, so a member or a local, never a type. `=>` and `==` are not
            # assignments, and a declaration like `TextScript? script =` has `?` here, not `=`.
            if after.startswith("=") and not after.startswith(("==", "=>")):
                continue

            before = text[: match.start()].rstrip()
            if not before.endswith("."):
                found.add(name)
                break
            qualifier = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*$", before)
            if qualifier and qualifier.group(1) in allowed:
                found.add(name)
                break
    return found
