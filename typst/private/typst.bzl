"""Typst rules"""

load("@bazel_skylib//rules:common_settings.bzl", "BuildSettingInfo")
load(":providers.bzl", "TypstInfo", "TypstPackageInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _supports_package_path(version):
    major, minor, _ = [int(part) for part in version.split(".")]
    return major > 0 or minor >= 12

def _typst_impl(ctx):
    """Implementation of the typst rule."""

    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE].typstc_info

    # Declare pdf output file.
    pdf_outfile = ctx.actions.declare_file("{}.pdf".format(ctx.label.name))

    args = ctx.actions.args()
    args.add(toolchain_info.compiler, format = "--compiler=%s")
    args.add(pdf_outfile, format = "--out=%s")
    args.add(
        "cli" if _supports_package_path(ctx.attr._typst_version[BuildSettingInfo].value) else "environment",
        format = "--package-path-mode=%s",
    )
    args.add("--src={}={}".format(
        ctx.file.src.path,
        _rlocationpath(ctx.file.src, ctx.workspace_name),
    ))

    # Track all inputs with their runfiles paths to ensure generated sources
    # are placed to their appropriate relative paths.
    for src in ctx.files.data:
        args.add("--input={}={}".format(
            src.path,
            _rlocationpath(src, ctx.workspace_name),
        ))

    package_files = []
    package_specs = {}
    for package_target in ctx.attr.packages:
        package = package_target[TypstPackageInfo]
        package_spec = "@{}/{}:{}".format(package.namespace, package.name, package.version)
        if package_spec in package_specs:
            fail("Duplicate Typst package {} from {} and {}".format(
                repr(package_spec),
                package_specs[package_spec],
                package_target.label,
            ))
        package_specs[package_spec] = package_target.label
        for entry in package.entries:
            package_path = "/".join([
                package.namespace,
                package.name,
                package.version,
                entry.path,
            ])
            args.add("--package-input={}={}".format(
                entry.file.path,
                package_path,
            ))
            package_files.append(entry.file)

    env = {"SOURCE_DATE_EPOCH": "0"}
    env.update(ctx.attr.env)

    ctx.actions.run(
        mnemonic = "TypstC",
        executable = toolchain_info.process_wrapper,
        arguments = [args],
        outputs = [pdf_outfile],
        tools = toolchain_info.all_files,
        inputs = depset([ctx.file.src] + ctx.files.data + package_files),
        env = env,
        execution_requirements = {"block-network": ""},
    )

    return [
        DefaultInfo(files = depset([pdf_outfile])),
        TypstInfo(),
    ]

typst = rule(
    doc = "Compile a Typst document to PDF.",
    implementation = _typst_impl,
    attrs = {
        "data": attr.label_list(
            doc = "Additional data dependencies (images, templates, etc.).",
            allow_files = True,
            mandatory = False,
        ),
        "env": attr.string_dict(
            doc = "Additional environment variables for the typst compiler action. " +
                  "SOURCE_DATE_EPOCH=0 is set by default for deterministic output. " +
                  "Override with a different value to opt out.",
        ),
        "packages": attr.label_list(
            doc = "Pinned Typst package dependencies.",
            providers = [TypstPackageInfo],
        ),
        "src": attr.label(
            doc = "The .typ source file to compile.",
            allow_single_file = [".typ"],
            mandatory = True,
        ),
        "_typst_version": attr.label(
            default = Label("//typst/settings:version"),
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
