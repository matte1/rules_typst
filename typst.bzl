def _copy_runfiles(src, runfiles):
    """Hacky way to copy runfiles to the tmp directory that typst can find."""

    # We need to copy the .typ src file into the tmp directory which will become our root directory.
    commands = [
        "mkdir -p tmp/",
        "cp {} tmp/{}".format(src.path, src.basename)
    ]

    # For each runfile, we need to copy it to the tmp directory using the same directory structure
    # as the original runfile.
    for runfile in runfiles:
        dirname = runfile.short_path.rstrip(runfile.basename)
        commands.append(
            "mkdir -p tmp/{} && cp -f -L {path} tmp/{short_path}".format(dirname, path = runfile.path, short_path = runfile.short_path),
        )

    return "\n".join(commands)

def _typst_impl(ctx):
    """Implementation of the typst rule."""

    # Declare pdf output file.
    pdf_outfile = ctx.actions.declare_file("{}.pdf".format(ctx.label.name))

    info = ctx.toolchains["//:typst_toolchain_type"].typstc_info
    compiler = info.compiler

    ctx.actions.run_shell(
        inputs = depset(
            direct = ctx.files.src + ctx.files.data,
            transitive = [compiler.files],
        ),
        outputs = [pdf_outfile],
        mnemonic = "typstc",
        command = """
{cp_runfiles}
{compiler} compile tmp/{src} {pdf_outfile_path}
    """.format(
            cp_runfiles = _copy_runfiles(ctx.files.src[0], ctx.files.data),
            compiler = compiler.files.to_list()[0].path,
            src = ctx.files.src[0].basename,
            pdf_outfile_path = pdf_outfile.path,
        ),
    )

    return [
        DefaultInfo(files = depset([pdf_outfile])),
    ]

# Definition of the rule to generate a load.
_typst_rule = rule(
    implementation = _typst_impl,
    attrs = {
        "src": attr.label(
            allow_files = True,
            mandatory = True,
        ),
        "data": attr.label_list(
            allow_files = True,
            mandatory = False,
        ),
    },
    toolchains = ["@rules_typst//:typst_toolchain_type"],
)

def typst(name, src, data=[], **kwargs):
    _typst_rule(
        name = name,
        src = src,
        data = data,
        **kwargs
    )
