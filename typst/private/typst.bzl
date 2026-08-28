"""Typst rules"""

load(":providers.bzl", "TypstInfo")
load(":toolchain.bzl", "TOOLCHAIN_TYPE")

def _rlocationpath(file, workspace_name):
    if file.short_path.startswith("../"):
        return file.short_path[len("../"):]

    return "{}/{}".format(workspace_name, file.short_path)

def _typst_impl(ctx):
    """Implementation of the typst rule."""

    toolchain_info = ctx.toolchains[TOOLCHAIN_TYPE].typstc_info

    # Declare pdf output file.
    pdf_outfile = ctx.actions.declare_file("{}.pdf".format(ctx.label.name))

    args = ctx.actions.args()
    args.add(toolchain_info.compiler, format = "--compiler=%s")
    args.add(pdf_outfile, format = "--out=%s")
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

    env = {"SOURCE_DATE_EPOCH": "0"}
    env.update(ctx.attr.env)

    ctx.actions.run(
        mnemonic = "TypstC",
        executable = toolchain_info.process_wrapper,
        arguments = [args],
        outputs = [pdf_outfile],
        tools = toolchain_info.all_files,
        inputs = depset([ctx.file.src] + ctx.files.data),
        env = env,
    )

    return [
        DefaultInfo(files = depset([pdf_outfile])),
        TypstInfo(),
    ]

typst = rule(
    doc = "Compile a Typst document to PDF.\n\n" +
          "Compilation sees only the declared sources and the fonts embedded in " +
          "the pinned compiler. Fonts installed on the host are ignored so the " +
          "same inputs produce the same bytes on every machine.",
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
        "src": attr.label(
            doc = "The .typ source file to compile.",
            allow_single_file = [".typ"],
            mandatory = True,
        ),
    },
    toolchains = [TOOLCHAIN_TYPE],
)
