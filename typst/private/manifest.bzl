"""Parsing helpers for Typst package manifests."""

def _strip_comment(line):
    in_basic_string = False
    in_literal_string = False
    escaped = False

    for index in range(len(line)):
        character = line[index]
        if in_basic_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == "\"":
                in_basic_string = False
        elif in_literal_string:
            if character == "'":
                in_literal_string = False
        elif character == "\"":
            in_basic_string = True
        elif character == "'":
            in_literal_string = True
        elif character == "#":
            return line[:index]

    return line

def _parse_string(value, field):
    value = value.strip()
    if len(value) < 2:
        fail("Typst manifest field {} must be a string".format(repr(field)))

    if value.startswith("\"") and value.endswith("\""):
        return json.decode(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1]

    fail("Typst manifest field {} must be a single-line string".format(repr(field)))

def parse_typst_manifest(content):
    """Parse the required scalar fields from a typst.toml manifest.

    Args:
      content: The manifest contents.

    Returns:
      A dictionary containing the parsed package metadata.
    """
    package = {}
    table = ""

    for raw_line in content.splitlines():
        line = _strip_comment(raw_line).strip()
        if not line:
            continue

        if line.startswith("[") and line.endswith("]"):
            table = line[1:-1].strip()
            continue

        if table != "package":
            continue

        key, separator, value = line.partition("=")
        if not separator:
            continue

        key = key.strip()
        if key in ["name", "version", "entrypoint", "compiler"]:
            if key in package:
                fail("Duplicate Typst manifest field {}".format(repr(key)))
            package[key] = _parse_string(value, key)

    for field in ["name", "version", "entrypoint"]:
        if not package.get(field):
            fail("Typst manifest is missing [package].{}".format(field))

    entrypoint = package["entrypoint"]
    if entrypoint.startswith("/") or "\\" in entrypoint or ".." in entrypoint.split("/"):
        fail("Typst package entrypoint must remain within the package: {}".format(repr(entrypoint)))

    return package
