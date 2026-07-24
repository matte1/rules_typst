"""Typst package rules"""

load(":providers.bzl", "TypstPackageInfo")

def _validate_path_component(field, value):
    if not value or "/" in value or "\\" in value or value in [".", ".."]:
        fail("{} must be a single non-empty path component".format(field))

def _package_relative_path(file, package, strip_prefix):
    short_path = file.short_path
    if short_path.startswith("../"):
        _, _, short_path = short_path[len("../"):].partition("/")
    elif package and short_path.startswith(package + "/"):
        short_path = short_path[len(package) + 1:]
    if strip_prefix:
        prefix = strip_prefix.rstrip("/") + "/"
        if not short_path.startswith(prefix):
            fail("Package file {} is outside strip_prefix {}".format(file.path, strip_prefix))
        short_path = short_path[len(prefix):]
    return short_path

def _typst_package_impl(ctx):
    _validate_path_component("namespace", ctx.attr.namespace)
    _validate_path_component("package_name", ctx.attr.package_name)
    _validate_path_component("version", ctx.attr.version)

    paths = {}
    entries = [
        struct(
            file = file,
            path = _package_relative_path(file, ctx.label.package, ctx.attr.strip_prefix),
        )
        for file in ctx.files.srcs
    ]
    for entry in entries:
        if entry.path in paths:
            fail("Package files {} and {} map to the same path {}".format(
                paths[entry.path].path,
                entry.file.path,
                entry.path,
            ))
        paths[entry.path] = entry.file

    return [
        DefaultInfo(files = depset(ctx.files.srcs)),
        TypstPackageInfo(
            entries = entries,
            name = ctx.attr.package_name,
            namespace = ctx.attr.namespace,
            version = ctx.attr.version,
        ),
    ]

typst_package = rule(
    doc = "Describe files belonging to a fetched Typst package.",
    implementation = _typst_package_impl,
    attrs = {
        "namespace": attr.string(mandatory = True),
        "package_name": attr.string(mandatory = True),
        "srcs": attr.label_list(allow_files = True, mandatory = True),
        "strip_prefix": attr.string(),
        "version": attr.string(mandatory = True),
    },
)
