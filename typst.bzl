def _typst_impl(ctx):
    """Implementation of the typst rule."""

    # Declare pdf output file.
    pdf_outfile = ctx.actions.declare_file("{}.pdf".format(ctx.label.name))

    info = ctx.toolchains["//:typst_toolchain_type"].typstc_info
    compiler = info.compiler

    ctx.actions.run(
        inputs = depset(
                direct = ctx.files.src + ctx.files.data,
                transitive = [compiler.files],
        ),
        outputs = [pdf_outfile],
        mnemonic = "typstc",
        executable = compiler.files.to_list()[0].path,
        arguments = [
            "compile",
            ctx.files.src[0].path,
            pdf_outfile.path
        ],
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
