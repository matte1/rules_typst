"""rules_typst bzlmod extensions"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//typst/private:versions.bzl", "TYPST_VERSIONS")

_HUB_BUILD_CONTENT = """\
{toolchains}
"""

_PACKAGES_HUB_BUILD_CONTENT = """\
package(default_visibility = ["//visibility:public"])

{packages}
"""

_PACKAGE_ALIAS = """\
alias(
    name = "{name}",
    actual = "{actual}",
)
"""

_PACKAGE_BUILD_CONTENT = """\
load("@rules_typst//typst:typst_package.bzl", "typst_package")

package(default_visibility = ["//visibility:public"])

typst_package(
    name = "package",
    namespace = {namespace},
    package_name = {package_name},
    srcs = glob(
        ["**"],
        exclude = [
            "BUILD",
            "BUILD.bazel",
            "MODULE.bazel",
            "REPO",
            "REPO.bazel",
            "WORKSPACE",
            "WORKSPACE.bazel",
        ],
    ),
    version = {version},
)
"""

_CONSTRAINTS = {
    "aarch64-apple-darwin": [
        "@platforms//os:macos",
        "@platforms//cpu:aarch64",
    ],
    "aarch64-pc-windows-msvc": [
        "@platforms//os:windows",
        "@platforms//cpu:aarch64",
    ],
    "aarch64-unknown-linux-musl": [
        "@platforms//os:linux",
        "@platforms//cpu:aarch64",
    ],
    "armv7-unknown-linux-musleabi": [
        "@platforms//os:linux",
        "@platforms//cpu:armv7",
    ],
    "riscv64gc-unknown-linux-gnu": [
        "@platforms//os:linux",
        "@platforms//cpu:riscv64",
    ],
    "x86_64-apple-darwin": [
        "@platforms//os:macos",
        "@platforms//cpu:x86_64",
    ],
    "x86_64-pc-windows-msvc": [
        "@platforms//os:windows",
        "@platforms//cpu:x86_64",
    ],
    "x86_64-unknown-linux-musl": [
        "@platforms//os:linux",
        "@platforms//cpu:x86_64",
    ],
}

_TOOLCHAIN_ENTRY = """\
toolchain(
    name = "typst_toolchain_{version}_{arch}",
    toolchain_type = "@rules_typst//typst:toolchain_type",
    toolchain = "{toolchain}",
    exec_compatible_with = {constraints},
    target_settings = ["@rules_typst//typst/settings:version_{version}"],
    visibility = ["//visibility:public"],
)
"""

def _typst_toolchains_hub_impl(repository_ctx):
    toolchains = []
    for toolchain, version_arch in repository_ctx.attr.toolchains.items():
        version, _, arch = version_arch.partition(":")
        toolchains.append(_TOOLCHAIN_ENTRY.format(
            arch = arch,
            constraints = repr(_CONSTRAINTS[arch]),
            toolchain = str(toolchain),
            version = version,
        ))

    repository_ctx.file("BUILD.bazel", _HUB_BUILD_CONTENT.format(
        toolchains = "\n".join(toolchains),
    ))

    repository_ctx.file("WORKSPACE.bazel", """workspace(name = "{}")""".format(
        repository_ctx.name,
    ))

typst_toolchains_hub = repository_rule(
    doc = "A repository rule for defining typst toolchains",
    implementation = _typst_toolchains_hub_impl,
    attrs = {
        "toolchains": attr.label_keyed_string_dict(
            doc = "A mapping of toolchain labels to platforms.",
            mandatory = True,
        ),
    },
)

def _typst_packages_hub_impl(repository_ctx):
    aliases = []
    for package, name in repository_ctx.attr.packages.items():
        aliases.append(_PACKAGE_ALIAS.format(
            actual = str(package),
            name = name,
        ))

    repository_ctx.file("BUILD.bazel", _PACKAGES_HUB_BUILD_CONTENT.format(
        packages = "\n".join(aliases),
    ))
    repository_ctx.file("WORKSPACE.bazel", "workspace(name = \"{}\")".format(
        repository_ctx.name,
    ))

typst_packages_hub = repository_rule(
    doc = "A repository containing aliases for fetched Typst packages.",
    implementation = _typst_packages_hub_impl,
    attrs = {
        "packages": attr.label_keyed_string_dict(mandatory = True),
    },
)

_TYPST_UNIX_BUILD_CONTENT = """\
load("@rules_typst//typst:typst_toolchain.bzl", "typst_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["typst"])

alias(
    name = "{name}",
    actual = "typst",
)

typst_toolchain(
    name = "toolchain",
    compiler = "typst",
)
"""

_TYPST_WINDOWS_BUILD_CONTENT = """\
load("@rules_typst//typst:typst_toolchain.bzl", "typst_toolchain")

package(default_visibility = ["//visibility:public"])

exports_files(["typst.exe"])

alias(
    name = "{name}",
    actual = "typst.exe",
)

typst_toolchain(
    name = "toolchain",
    compiler = "typst.exe",
)
"""

def _typst_impl(module_ctx):
    toolchains = {}

    for version, platforms in TYPST_VERSIONS.items():
        for platform, data in platforms.items():
            name = "typst_{}_{}".format(version, platform)

            build_file_content = _TYPST_UNIX_BUILD_CONTENT.format(
                name = name,
            )

            # Special case, as it is a zip archive with no prefix to strip.
            if "windows" in platform:
                build_file_content = _TYPST_WINDOWS_BUILD_CONTENT.format(
                    name = name,
                )

            maybe(
                http_archive,
                name = name,
                strip_prefix = "typst-{}".format(platform),
                build_file_content = build_file_content,
                integrity = data["integrity"],
                urls = data["urls"],
            )

            toolchains["@{}//:toolchain".format(name)] = "{}:{}".format(version, platform)

    maybe(
        typst_toolchains_hub,
        name = "typst_toolchains",
        toolchains = toolchains,
    )

    return module_ctx.extension_metadata(
        reproducible = True,
    )

typst = module_extension(
    implementation = _typst_impl,
)

def _normalize_name(value):
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join([
        value[index] if value[index] in allowed else "_"
        for index in range(len(value))
    ])

def _validate_package_identifier(field, value, spec):
    allowed = "abcdefghijklmnopqrstuvwxyz0123456789-"
    if not value:
        fail("{} must not be empty for Typst package {}".format(field, repr(spec)))
    for index in range(len(value)):
        if value[index] not in allowed:
            fail("{} contains an invalid character for Typst package {}".format(field, repr(spec)))

def _validate_package_version(version, spec):
    parts = version.split(".")
    if len(parts) != 3:
        fail("version must use major.minor.patch for Typst package {}".format(repr(spec)))
    for part in parts:
        if not part:
            fail("version must use major.minor.patch for Typst package {}".format(repr(spec)))
        for index in range(len(part)):
            if part[index] not in "0123456789":
                fail("version must use major.minor.patch for Typst package {}".format(repr(spec)))

def _typst_packages_impl(module_ctx):
    package_specs = {}
    repository_specs = {}
    packages = {}

    for module in module_ctx.modules:
        for package in module.tags.package:
            spec = "@{}/{}:{}".format(package.namespace, package.name, package.version)
            _validate_package_identifier("namespace", package.namespace, spec)
            _validate_package_identifier("name", package.name, spec)
            _validate_package_version(package.version, spec)
            if not package.integrity:
                fail("integrity must not be empty for Typst package {}".format(repr(spec)))
            definition = (package.integrity, package.urls)
            if spec in package_specs:
                if package_specs[spec] != definition:
                    fail("Conflicting definitions for Typst package {}".format(repr(spec)))
                continue
            package_specs[spec] = definition

            normalized_name = _normalize_name("{}_{}_{}".format(
                package.namespace,
                package.name,
                package.version,
            ))
            repository_name = "typst_package_{}".format(normalized_name)
            if repository_name in repository_specs and repository_specs[repository_name] != spec:
                fail("Typst packages {} and {} produce the same Bazel name".format(
                    repr(repository_specs[repository_name]),
                    repr(spec),
                ))
            repository_specs[repository_name] = spec
            urls = package.urls
            if not urls:
                if package.namespace != "preview":
                    fail("urls must be set for non-preview Typst package {}".format(repr(spec)))
                urls = ["https://packages.typst.org/preview/{}-{}.tar.gz".format(
                    package.name,
                    package.version,
                )]

            http_archive(
                name = repository_name,
                build_file_content = _PACKAGE_BUILD_CONTENT.format(
                    namespace = repr(package.namespace),
                    package_name = repr(package.name),
                    version = repr(package.version),
                ),
                integrity = package.integrity,
                urls = urls,
            )
            packages["@{}//:package".format(repository_name)] = normalized_name

    typst_packages_hub(
        name = "typst_packages",
        packages = packages,
    )

    return module_ctx.extension_metadata(reproducible = True)

_typst_package = tag_class(
    attrs = {
        "integrity": attr.string(mandatory = True),
        "name": attr.string(mandatory = True),
        "namespace": attr.string(default = "preview"),
        "urls": attr.string_list(),
        "version": attr.string(mandatory = True),
    },
)

typst_packages = module_extension(
    implementation = _typst_packages_impl,
    tag_classes = {"package": _typst_package},
)
