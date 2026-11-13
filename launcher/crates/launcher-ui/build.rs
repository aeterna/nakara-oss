// SPDX-License-Identifier: MIT

use std::env;
use std::fs;
use std::path::{Path, PathBuf};

fn main() {
    println!("cargo:rerun-if-env-changed=AETERNA_LAUNCHER_PROFILE");

    let path = match env::var("AETERNA_LAUNCHER_PROFILE") {
        Ok(value) if !value.is_empty() => PathBuf::from(value),
        _ => PathBuf::from("profiles/aeterna/server.toml"),
    };
    let path = if path.is_absolute() {
        path
    } else {
        Path::new(&env::var("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is set"))
            .join("../..")
            .join(path)
    };

    println!("cargo:rerun-if-changed={}", path.display());

    let text = fs::read_to_string(&path)
        .unwrap_or_else(|err| panic!("could not read launcher profile {}: {err}", path.display()));

    launcher_core::parse(&text)
        .unwrap_or_else(|err| panic!("launcher profile {} is invalid: {err}", path.display()));

    let out = Path::new(&env::var("OUT_DIR").expect("OUT_DIR is set")).join("server.toml");
    fs::write(&out, text)
        .unwrap_or_else(|err| panic!("could not write {}: {err}", out.display()));
}
