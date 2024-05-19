workspace(name = "rules_typst")

load("//:toolchain.bzl", "typst_aarch64_apple_darwin_deps", "typst_x86_64_unknown_linux_musl_deps")

typst_aarch64_apple_darwin_deps()
typst_x86_64_unknown_linux_musl_deps()

register_toolchains(
    "@rules_typst//:typst_macos_toolchain",
    "@rules_typst//:typst_x86_64_unknown_linux_musl_toolchain"
)