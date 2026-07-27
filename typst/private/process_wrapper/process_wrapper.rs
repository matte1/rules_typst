//! The process wrapper for TypstC actions

use std::collections::BTreeMap;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
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

    /// A mapping of source paths to package-root-relative paths.
    pub package_inputs: BTreeMap<PathBuf, PathBuf>,

    /// How the selected Typst version discovers package directories.
    pub package_path_mode: PackagePathMode,
}

#[derive(Clone, Copy)]
enum PackagePathMode {
    Cli,
    Environment,
}

impl Args {
    pub fn parse() -> Self {
        let mut compiler: Option<PathBuf> = None;
        let mut src: Option<(PathBuf, PathBuf)> = None;
        let mut out: Option<PathBuf> = None;
        let mut inputs: BTreeMap<PathBuf, PathBuf> = BTreeMap::new();
        let mut package_inputs: BTreeMap<PathBuf, PathBuf> = BTreeMap::new();
        let mut package_path_mode: Option<PackagePathMode> = None;

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
            } else if let Some(val) = arg.strip_prefix("--package-input=") {
                let (l, r) = val
                    .split_once('=')
                    .expect("--package-input must be in format path=package-path");
                package_inputs.insert(PathBuf::from(l), PathBuf::from(r));
            } else if let Some(val) = arg.strip_prefix("--package-path-mode=") {
                package_path_mode = Some(match val {
                    "cli" => PackagePathMode::Cli,
                    "environment" => PackagePathMode::Environment,
                    _ => panic!("--package-path-mode must be cli or environment"),
                });
            } else {
                eprintln!("Warning: unrecognized argument: {}", arg);
            }
        }

        Args {
            compiler: compiler.expect("--compiler is required"),
            src: src.expect("--src is required"),
            out: out.expect("--out is required"),
            inputs,
            package_inputs,
            package_path_mode: package_path_mode.expect("--package-path-mode is required"),
        }
    }
}

fn remove_path(path: &Path) -> io::Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() || !metadata.is_dir() => {
            fs::remove_file(path)
        }
        Ok(_) => fs::remove_dir_all(path),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error),
    }
}

fn cleanup(temp_runfiles_dir: &Path) {
    remove_path(temp_runfiles_dir)
        .unwrap_or_else(|error| eprintln!("Warning: failed to clean up temp dir: {error}"));
}

fn reset_temp_dir(temp_runfiles_dir: &Path) {
    remove_path(temp_runfiles_dir).expect("Failed to remove stale temp runfiles directory");
    fs::create_dir_all(temp_runfiles_dir).expect("Failed to create temp runfiles directory");
}

fn is_safe_relative_path(path: &Path) -> bool {
    !path.as_os_str().is_empty()
        && path
            .components()
            .all(|component| matches!(component, Component::Normal(_) | Component::CurDir))
}

fn copy_file(src: &Path, dest: &Path, kind: &str) {
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent).unwrap_or_else(|error| {
            panic!("Failed to create parent directories for {kind}: {error}")
        });
    }
    fs::copy(src, dest).unwrap_or_else(|error| panic!("Failed to copy {kind}: {error}"));
}

fn environment_package_root(temp_runfiles_dir: &Path) -> PathBuf {
    #[cfg(target_os = "macos")]
    return temp_runfiles_dir
        .join(".home")
        .join("Library/Application Support/typst/packages");

    #[cfg(target_os = "windows")]
    return temp_runfiles_dir.join(".typst-data").join("typst/packages");

    #[cfg(not(any(target_os = "macos", target_os = "windows")))]
    return temp_runfiles_dir.join(".typst-data").join("typst/packages");
}

fn main() {
    let args = Args::parse();

    let temp_runfiles_dir = std::env::current_dir()
        .expect("Failed to determine current directory")
        .join(format!("{}.runfiles", args.out.display()));

    reset_temp_dir(&temp_runfiles_dir);

    assert!(
        is_safe_relative_path(&args.src.1),
        "src path must remain within the temporary runfiles directory: {:?}",
        args.src.1,
    );

    // Copy the source file into the build directory at its rlocation path
    let abs_src = temp_runfiles_dir.join(&args.src.1);
    copy_file(&args.src.0, &abs_src, "src into build directory");

    // Copy all inputs into the build directory at their rlocation paths
    for (src, dest) in args.inputs.iter() {
        assert!(
            is_safe_relative_path(dest),
            "input path must remain within the temporary runfiles directory: {:?}",
            dest,
        );
        let abs_dest = temp_runfiles_dir.join(dest);
        copy_file(src, &abs_dest, "input into build directory");
    }

    let package_root = match args.package_path_mode {
        PackagePathMode::Cli => temp_runfiles_dir.join(".typst-packages"),
        PackagePathMode::Environment => environment_package_root(&temp_runfiles_dir),
    };
    for (src, dest) in args.package_inputs.iter() {
        assert!(
            is_safe_relative_path(dest),
            "package path must remain within the package root: {:?}",
            dest,
        );
        copy_file(
            src,
            &package_root.join(dest),
            "package input into package directory",
        );
    }

    let package_cache_root = temp_runfiles_dir.join(".typst-package-cache");

    // Set --root to the workspace root so paths resolve relative to the
    // workspace rather than the .typ file's parent directory.
    let workspace_root = temp_runfiles_dir.join(
        args.src
            .1
            .iter()
            .next()
            .expect("src rlocationpath must have a workspace name component"),
    );

    // Run the typst compiler
    let mut command = Command::new(&args.compiler);
    command.arg("compile").arg("--root").arg(&workspace_root);

    match args.package_path_mode {
        PackagePathMode::Cli => {
            command
                .arg("--package-path")
                .arg(&package_root)
                .arg("--package-cache-path")
                .arg(&package_cache_root);
        }
        PackagePathMode::Environment => {
            command
                .env("HOME", temp_runfiles_dir.join(".home"))
                .env("XDG_DATA_HOME", temp_runfiles_dir.join(".typst-data"))
                .env("XDG_CACHE_HOME", &package_cache_root)
                .env("APPDATA", temp_runfiles_dir.join(".typst-data"))
                .env("LOCALAPPDATA", &package_cache_root);
        }
    }

    let result = command.arg(&abs_src).arg(&args.out).output();

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

#[cfg(test)]
mod tests {
    use super::{is_safe_relative_path, remove_path, reset_temp_dir};
    use std::fs;
    use std::path::{Path, PathBuf};

    fn test_dir(name: &str) -> PathBuf {
        std::env::temp_dir().join(format!(
            "rules_typst_process_wrapper_{}_{}",
            std::process::id(),
            name,
        ))
    }

    #[test]
    fn accepts_safe_relative_paths() {
        assert!(is_safe_relative_path(Path::new(
            "preview/cetz/0.5.2/src/lib.typ"
        )));
        assert!(is_safe_relative_path(Path::new("./src/lib.typ")));
    }

    #[test]
    fn rejects_paths_outside_staging_root() {
        assert!(!is_safe_relative_path(Path::new("")));
        assert!(!is_safe_relative_path(Path::new("/tmp/package.typ")));
        assert!(!is_safe_relative_path(Path::new("../package.typ")));
        assert!(!is_safe_relative_path(Path::new("src/../../package.typ")));
    }

    #[test]
    fn reset_removes_stale_contents() {
        let directory = test_dir("reset");
        remove_path(&directory).unwrap();
        fs::create_dir_all(directory.join("stale")).unwrap();
        fs::write(directory.join("stale/package.typ"), "stale").unwrap();

        reset_temp_dir(&directory);

        assert!(directory.is_dir());
        assert!(!directory.join("stale").exists());
        remove_path(&directory).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn reset_replaces_symlink_without_touching_target() {
        use std::os::unix::fs::symlink;

        let directory = test_dir("symlink");
        let target = test_dir("symlink_target");
        remove_path(&directory).unwrap();
        remove_path(&target).unwrap();
        fs::create_dir_all(&target).unwrap();
        fs::write(target.join("sentinel"), "keep").unwrap();
        symlink(&target, &directory).unwrap();

        reset_temp_dir(&directory);

        assert!(directory.is_dir());
        assert!(!directory.join("sentinel").exists());
        assert_eq!(fs::read_to_string(target.join("sentinel")).unwrap(), "keep");
        remove_path(&directory).unwrap();
        remove_path(&target).unwrap();
    }
}
