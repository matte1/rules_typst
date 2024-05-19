load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")

def typst_aarch64_apple_darwin_deps():
    TOOLCHAIN_BUILD_FILE = """
sh_binary(
    name = "typst_aarch64_darwin_bin",
    srcs = [
        "typst"
    ],
    visibility = ["//visibility:public"],
)
"""
    url = "https://github.com/typst/typst/releases/download/v0.11.1/typst-aarch64-apple-darwin.tar.xz"
    http_archive(
        name = "typst",
        build_file_content = TOOLCHAIN_BUILD_FILE,
        url = url,
        integrity = "sha256-gK9wJQzUhkTfNshM7Y8+ZsEJA+5Az5j+QjaLQrzci7o=",
        strip_prefix = "typst-aarch64-apple-darwin",
    )

def typst_x86_64_unknown_linux_musl_deps():
    TOOLCHAIN_BUILD_FILE = """
sh_binary(
    name = "typst_x86_64_unknown_linux_musl_bin",
    srcs = [
        "typst"
    ],
    visibility = ["//visibility:public"],
)
"""
    url = "https://github.com/typst/typst/releases/download/v0.11.1/typst-x86_64-unknown-linux-musl.tar.xz"
    http_archive(
        name = "typst-x86_64-unknown-linux-musl",
        build_file_content = TOOLCHAIN_BUILD_FILE,
        url = url,
        integrity = "sha256-gK9wJQzUhkTfNshM7Y8+ZsEJA+5Az5j+QjaLQrzci7o=",
        strip_prefix = "typst-x86_64-unknown-linux-musl",
    )

TypstInfo = provider(
    doc = "Information about how to invoke the barc compiler.",
    fields = ["compiler"],
)

def _typst_toolchain_impl(ctx):
    toolchain_info = platform_common.ToolchainInfo(
        typstc_info = TypstInfo(
            compiler = ctx.attr.compiler,
        ),
    )
    return [toolchain_info]

typst_toolchain = rule(
    implementation = _typst_toolchain_impl,
    attrs = {
        "compiler": attr.label(
            executable = True,
            mandatory = True,
            cfg = "exec",
        ),
    },
)