"""Tests for Typst manifest parsing."""

load("@bazel_skylib//lib:unittest.bzl", "asserts", "unittest")
load("//typst/private:manifest.bzl", "parse_typst_manifest")

def _manifest_test_impl(ctx):
    env = unittest.begin(ctx)
    manifest = parse_typst_manifest("""
# Leading comment
[package]
name = "cetz" # trailing comment
version = '0.5.2'
entrypoint = "src/lib.typ"
compiler = "0.14.0"
description = "A # remains inside a string"

[tool.example]
name = "ignored"
""")

    asserts.equals(env, "cetz", manifest["name"])
    asserts.equals(env, "0.5.2", manifest["version"])
    asserts.equals(env, "src/lib.typ", manifest["entrypoint"])
    asserts.equals(env, "0.14.0", manifest["compiler"])
    return unittest.end(env)

manifest_test = unittest.make(_manifest_test_impl)
