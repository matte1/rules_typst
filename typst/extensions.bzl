"""rules_typst bzlmod extensions"""

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")
load("//typst/private:manifest.bzl", "parse_typst_manifest")
load("//typst/private:versions.bzl", "TYPST_VERSIONS")

_FACTS_KEY = "rules_typst"
_FACTS_SCHEMA = 1

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

def _stored_package_facts(module_ctx):
    if not hasattr(module_ctx, "facts"):
        return {}

    stored = module_ctx.facts.get(_FACTS_KEY, {})
    if type(stored) != "dict" or stored.get("schema") != _FACTS_SCHEMA:
        return {}

    packages = stored.get("packages", {})
    if type(packages) != "dict":
        return {}

    return dict(packages)

def _valid_package_fact(fact):
    if type(fact) != "dict" or type(fact.get("integrity")) != "string":
        return False

    manifest = fact.get("manifest")
    if type(manifest) != "dict":
        return False

    for field in ["name", "version", "entrypoint"]:
        if type(manifest.get(field)) != "string" or not manifest[field]:
            return False

    return True

def _validate_manifest(manifest, package):
    if manifest["name"] != package.name:
        fail("Typst package {} contains manifest name {}".format(
            repr(package.spec),
            repr(manifest["name"]),
        ))
    if manifest["version"] != package.version:
        fail("Typst package {} contains manifest version {}".format(
            repr(package.spec),
            repr(manifest["version"]),
        ))

def _resolve_package(module_ctx, package, stored_package_facts):
    fact_key = package.urls[0] if package.is_registry else ""
    fact = stored_package_facts.get(fact_key) if fact_key else None

    if _valid_package_fact(fact):
        if package.integrity and package.integrity != fact["integrity"]:
            fail("Integrity for Typst package {} conflicts with the stored registry fact".format(
                repr(package.spec),
            ))
        _validate_manifest(fact["manifest"], package)
        return struct(
            discovered_integrity = False,
            integrity = fact["integrity"],
            manifest = fact["manifest"],
        )

    if not package.integrity and not package.is_registry:
        fail("integrity must be set for Typst package {} with custom urls".format(
            repr(package.spec),
        ))

    output = "package_manifests/{}".format(package.normalized_name)
    download = module_ctx.download_and_extract(
        url = package.urls,
        output = output,
        canonical_id = "rules_typst:{}".format(package.spec),
        integrity = package.integrity,
    )
    manifest = parse_typst_manifest(module_ctx.read("{}/typst.toml".format(output)))
    _validate_manifest(manifest, package)

    return struct(
        discovered_integrity = not package.integrity,
        integrity = download.integrity,
        manifest = manifest,
    )

def _typst_packages_impl(module_ctx):
    package_specs = {}
    repository_specs = {}
    packages = {}
    stored_package_facts = _stored_package_facts(module_ctx)
    package_facts = {}
    discovered_integrity = False

    for module in module_ctx.modules:
        for tag in module.tags.package:
            spec = "@{}/{}:{}".format(tag.namespace, tag.name, tag.version)
            _validate_package_identifier("namespace", tag.namespace, spec)
            _validate_package_identifier("name", tag.name, spec)
            _validate_package_version(tag.version, spec)

            is_registry = not tag.urls
            urls = tag.urls
            if is_registry:
                if tag.namespace != "preview":
                    fail("urls must be set for non-preview Typst package {}".format(repr(spec)))
                urls = ["https://packages.typst.org/preview/{}-{}.tar.gz".format(
                    tag.name,
                    tag.version,
                )]

            normalized_name = _normalize_name("{}_{}_{}".format(
                tag.namespace,
                tag.name,
                tag.version,
            ))
            package = struct(
                integrity = tag.integrity,
                is_registry = is_registry,
                name = tag.name,
                namespace = tag.namespace,
                normalized_name = normalized_name,
                spec = spec,
                urls = urls,
                version = tag.version,
            )

            if spec in package_specs:
                existing = package_specs[spec]
                if existing.urls != package.urls or (
                    existing.integrity and package.integrity and existing.integrity != package.integrity
                ):
                    fail("Conflicting definitions for Typst package {}".format(repr(spec)))
                if not existing.integrity and package.integrity:
                    package_specs[spec] = package
                continue
            package_specs[spec] = package

            repository_name = "typst_package_{}".format(normalized_name)
            if repository_name in repository_specs and repository_specs[repository_name] != spec:
                fail("Typst packages {} and {} produce the same Bazel name".format(
                    repr(repository_specs[repository_name]),
                    repr(spec),
                ))
            repository_specs[repository_name] = spec

    for spec in sorted(package_specs.keys()):
        package = package_specs[spec]
        resolved = _resolve_package(module_ctx, package, stored_package_facts)
        discovered_integrity = discovered_integrity or resolved.discovered_integrity
        repository_name = "typst_package_{}".format(package.normalized_name)

        if package.is_registry:
            package_facts[package.urls[0]] = {
                "integrity": resolved.integrity,
                "manifest": resolved.manifest,
            }

        http_archive(
            name = repository_name,
            build_file_content = _PACKAGE_BUILD_CONTENT.format(
                namespace = repr(package.namespace),
                package_name = repr(package.name),
                version = repr(package.version),
            ),
            canonical_id = "rules_typst:{}".format(spec),
            integrity = resolved.integrity,
            urls = package.urls,
        )
        packages["@{}//:package".format(repository_name)] = package.normalized_name

    typst_packages_hub(
        name = "typst_packages",
        packages = packages,
    )

    if hasattr(module_ctx, "facts"):
        return module_ctx.extension_metadata(facts = {
            _FACTS_KEY: {
                "packages": package_facts,
                "schema": _FACTS_SCHEMA,
            },
        })

    return module_ctx.extension_metadata(reproducible = not discovered_integrity)

_typst_package = tag_class(
    attrs = {
        "integrity": attr.string(),
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
