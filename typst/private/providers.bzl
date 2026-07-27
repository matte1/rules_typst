"""Typst providers"""

TypstInfo = provider(
    doc = "A unique provider for typst rules.",
    fields = {},
)

TypstPackageInfo = provider(
    doc = "A Typst package and its package-root-relative files.",
    fields = {
        "entries": "list[struct]: Package files and their relative paths.",
        "name": "string: The package name.",
        "namespace": "string: The package namespace.",
        "version": "string: The package version.",
    },
)
