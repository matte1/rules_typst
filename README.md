# rules_typst

Bazel rules for [Typst](https://typst.app/).

## Reproducibility

Compilation sees only the declared inputs, so the same sources produce the same
PDF bytes on every machine:

- `SOURCE_DATE_EPOCH=0` fixes the document's creation timestamp. Override it
  through the `env` attribute to opt out.
- Fonts installed on the host are ignored. Only the fonts embedded in the pinned
  compiler are available.
- The package path and package cache point inside the action, so a `@preview`
  import cannot resolve against a developer's `~/.cache/typst`.

Fonts are the usual source of "works on my machine": a document that renders
with a system font produces a different glyph subset — and therefore different
bytes — wherever that font's build differs. Typst reports an unknown font family
as a warning and silently falls back to a default, so check the build log if the
output is not what you expect.

Hermetic font handling requires Typst 0.12 or newer, when
`--ignore-system-fonts` was added.

## Checking in generated PDFs

`write_source_file` runs `diff` when its test fails, which prints thousands of
lines of xref offsets and compressed font streams for a PDF. Pass `--brief` so
the log reports only that the file changed:

```python
write_source_file(
    name = "write_report_pdf",
    diff_args = ["--brief"],
    diff_test = True,
    in_file = ":report",
    out_file = "generated/report.pdf",
)
```

## Development

### Pre-commit hooks

This repo uses [pre-commit](https://pre-commit.com/) to run [buildifier](https://github.com/bazelbuild/buildtools/tree/master/buildifier) for formatting and linting Bazel files.

```sh
pip install pre-commit
pre-commit install
```

To manually run against all files:

```sh
pre-commit run --all-files
```
