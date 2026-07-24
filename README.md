# rules_typst

Bazel rules for [Typst](https://typst.app/).

## Typst packages

Declare packages in `MODULE.bazel` with an exact version and integrity hash:

```starlark
typst_packages = use_extension(
    "@rules_typst//typst:extensions.bzl",
    "typst_packages",
)
typst_packages.package(
    name = "cetz",
    version = "0.3.4",
    integrity = "sha256-T0tajTEdUZ50mUCnZv5QUh5AwEESnhyRrwxC5h8wdRQ=",
)
use_repo(typst_packages, "typst_packages")
```

Add each package to the documents that import it:

```starlark
load("@rules_typst//typst:typst.bzl", "typst")

typst(
    name = "document",
    src = "document.typ",
    packages = ["@typst_packages//:preview_cetz_0_3_4"],
)
```

The corresponding Typst import remains unchanged:

```typst
#import "@preview/cetz:0.3.4": canvas
```

Package archives are fetched during Bazel repository setup and verified using
the declared integrity. Compile actions receive only declared package files,
use isolated package data and cache directories, and are marked to block
network access. This keeps compilation independent of Typst's host package
cache and on-demand downloader.

Integrity verification pins package contents but does not make third-party
package code trusted. Review packages and their transitive dependencies before
adding them; they execute as part of Typst compilation inside the Bazel action
sandbox.

Typst's package format does not currently provide complete dependency metadata.
Declare packages imported by another package alongside direct dependencies and
add them to the target's `packages` list. Use exact versions in Typst imports;
versionless imports require the remote registry index and are not hermetic.

To calculate an integrity value for a preview package:

```sh
curl -fsSL https://packages.typst.org/preview/cetz-0.3.4.tar.gz \
  | openssl dgst -sha256 -binary \
  | base64
```

Prefix the output with `sha256-`.

See `examples/cetz_example.typ` for a CeTZ drawing and
`examples/circuit_example.typ` for an electronic schematic built with
[Zap](https://typst.app/universe/package/zap/). The Zap target explicitly
declares CeTZ and CeTZ's `oxifmt` dependency to keep compilation hermetic.

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
