//! The process wrapper for TypstC actions

use std::collections::BTreeMap;
use std::fs;
use std::path::PathBuf;
use std::process::Command;

/// Command line args for the process wrapper.
struct Args {
    /// The location of the typst compiler.
    pub compiler: PathBuf,

    /// The location of the document source file.
    /// .0 = bazel-generated path, .1 = rlocationpath (relative destination)
    pub src: (PathBuf, PathBuf),

    /// The location of the output PDF file.
    pub out: PathBuf,

    /// A mapping of source paths to their rlocationpath IDs.
    pub inputs: BTreeMap<PathBuf, PathBuf>,
}

impl Args {
    pub fn parse() -> Self {
        let mut compiler: Option<PathBuf> = None;
        let mut src: Option<(PathBuf, PathBuf)> = None;
        let mut out: Option<PathBuf> = None;
        let mut inputs: BTreeMap<PathBuf, PathBuf> = BTreeMap::new();

        for arg in std::env::args().skip(1) {
            if let Some(val) = arg.strip_prefix("--compiler=") {
                compiler = Some(PathBuf::from(val));
            } else if let Some(val) = arg.strip_prefix("--out=") {
                out = Some(PathBuf::from(val));
            } else if let Some(val) = arg.strip_prefix("--src=") {
                let (l, r) = val
                    .split_once('=')
                    .expect("--src must be in format path=rlocationpath");
                src = Some((PathBuf::from(l), PathBuf::from(r)));
            } else if let Some(val) = arg.strip_prefix("--input=") {
                let (l, r) = val
                    .split_once('=')
                    .expect("--input must be in format path=rlocationpath");
                inputs.insert(PathBuf::from(l), PathBuf::from(r));
            } else {
                eprintln!("Warning: unrecognized argument: {}", arg);
            }
        }

        Args {
            compiler: compiler.expect("--compiler is required"),
            src: src.expect("--src is required"),
            out: out.expect("--out is required"),
            inputs,
        }
    }
}

fn cleanup(temp_runfiles_dir: &PathBuf) {
    if temp_runfiles_dir.exists() {
        fs::remove_dir_all(temp_runfiles_dir)
            .unwrap_or_else(|e| eprintln!("Warning: failed to clean up temp dir: {}", e));
    }
}

fn main() {
    let args = Args::parse();

    let temp_runfiles_dir = PathBuf::from(format!("{}.runfiles", args.out.display()));

    // Create the temp runfiles directory
    fs::create_dir_all(&temp_runfiles_dir).expect("Failed to create temp runfiles directory");

    // Copy the source file into the build directory at its rlocation path
    let abs_src = temp_runfiles_dir.join(&args.src.1);
    if let Some(parent) = abs_src.parent() {
        fs::create_dir_all(parent).expect("Failed to create parent directories for src");
    }
    fs::copy(&args.src.0, &abs_src).expect("Failed to copy src into build directory");

    // Copy all inputs into the build directory at their rlocation paths
    for (src, dest) in args.inputs.iter() {
        let abs_dest = temp_runfiles_dir.join(dest);
        if let Some(parent) = abs_dest.parent() {
            fs::create_dir_all(parent).expect("Failed to create parent directories for input");
        }
        fs::copy(src, &abs_dest).expect("Failed to copy file into build directory");
    }

    // Set --root to the workspace root so paths resolve relative to the
    // workspace rather than the .typ file's parent directory.
    let workspace_root = temp_runfiles_dir.join(
        args.src
            .1
            .iter()
            .next()
            .expect("src rlocationpath must have a workspace name component"),
    );

    // Run the typst compiler. Host fonts are excluded so output does not
    // depend on which font packages the machine has installed.
    let result = Command::new(&args.compiler)
        .arg("compile")
        .arg("--root")
        .arg(&workspace_root)
        .arg("--ignore-system-fonts")
        .arg(&abs_src)
        .arg(&args.out)
        .output();

    match result {
        Ok(output) => {
            if !output.status.success() {
                eprintln!(
                    "Typst compiler failed with status: {}\nstdout: {}\nstderr: {}",
                    output.status,
                    String::from_utf8_lossy(&output.stdout),
                    String::from_utf8_lossy(&output.stderr),
                );
                cleanup(&temp_runfiles_dir);
                std::process::exit(1);
            }

            if !output.stdout.is_empty() {
                print!("{}", String::from_utf8_lossy(&output.stdout));
            }

            cleanup(&temp_runfiles_dir);
        }
        Err(e) => {
            eprintln!("Failed to run typst compiler: {}", e);
            cleanup(&temp_runfiles_dir);
            std::process::exit(1);
        }
    }
}
