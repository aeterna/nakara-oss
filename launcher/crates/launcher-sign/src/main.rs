// SPDX-License-Identifier: MIT

//! CLI entrypoint for `launcher-sign` (ADR 0002 decision 7).
//!
//! Commands:
//! - `launcher-sign keygen --out <path>`
//! - `launcher-sign pubkey`
//! - `launcher-sign manifest --product P --version V --channel C --expires-days N FILE...`
//! - `launcher-sign sign --manifest PATH --out PATH`

use std::env;
use std::fs::{self, OpenOptions};
use std::io::{self, Write};
use std::path::{Path, PathBuf};
use std::process::ExitCode;

use launcher_sign::{
    build_manifest, new_seed, parse_key_hex, public_key_hex, sign, to_hex, ManifestInput, SignError,
};
use semver::Version;
use time::{Duration, OffsetDateTime};

const SIGNING_KEY_ENV: &str = "LAUNCHER_SIGNING_KEY";

enum CliError {
    Usage(String),
    Fail(String),
}

impl From<SignError> for CliError {
    fn from(err: SignError) -> Self {
        CliError::Fail(err.to_string())
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(CliError::Usage(msg)) => {
            let _ = writeln!(io::stderr(), "usage error: {msg}");
            ExitCode::from(2)
        }
        Err(CliError::Fail(msg)) => {
            let _ = writeln!(io::stderr(), "error: {msg}");
            ExitCode::from(1)
        }
    }
}

fn run(args: &[String]) -> Result<(), CliError> {
    let Some((cmd, rest)) = args.split_first() else {
        return Err(CliError::Usage(
            "expected command: keygen, pubkey, manifest, or sign".to_owned(),
        ));
    };
    match cmd.as_str() {
        "keygen" => cmd_keygen(rest),
        "pubkey" => cmd_pubkey(rest),
        "manifest" => cmd_manifest(rest),
        "sign" => cmd_sign(rest),
        other => Err(CliError::Usage(format!("unknown command {other:?}"))),
    }
}

fn cmd_keygen(args: &[String]) -> Result<(), CliError> {
    let out_path = match args {
        [flag, path] if flag == "--out" && !path.is_empty() => PathBuf::from(path),
        _ => {
            return Err(CliError::Usage(
                "usage: launcher-sign keygen --out <path>".to_owned(),
            ));
        }
    };

    if out_path.exists() {
        return Err(CliError::Fail(format!(
            "refusing to overwrite existing file {}",
            out_path.display()
        )));
    }

    let seed = new_seed()?;
    let mut line = to_hex(&seed);
    line.push('\n');

    write_new_secret_file(&out_path, line.as_bytes())?;

    let pub_hex = public_key_hex(&seed);
    println!("{pub_hex}");
    Ok(())
}

fn write_new_secret_file(path: &Path, contents: &[u8]) -> Result<(), CliError> {
    let mut opts = OpenOptions::new();
    opts.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    let mut file = opts
        .open(path)
        .map_err(|e| CliError::Fail(format!("could not create {}: {e}", path.display())))?;
    file.write_all(contents)
        .map_err(|e| CliError::Fail(format!("could not write {}: {e}", path.display())))?;
    file.sync_all()
        .map_err(|e| CliError::Fail(format!("could not sync {}: {e}", path.display())))?;
    Ok(())
}

fn read_signing_key_from_env() -> Result<[u8; 32], CliError> {
    let raw = env::var(SIGNING_KEY_ENV).map_err(|_| {
        CliError::Fail(format!(
            "environment variable {SIGNING_KEY_ENV} is not set or not valid UTF-8"
        ))
    })?;
    parse_key_hex(&raw).map_err(CliError::from)
}

fn cmd_pubkey(args: &[String]) -> Result<(), CliError> {
    if !args.is_empty() {
        return Err(CliError::Usage("usage: launcher-sign pubkey".to_owned()));
    }
    let seed = read_signing_key_from_env()?;
    let pub_hex = public_key_hex(&seed);
    println!("{pub_hex}");
    Ok(())
}

fn cmd_manifest(args: &[String]) -> Result<(), CliError> {
    let mut product: Option<String> = None;
    let mut version_str: Option<String> = None;
    let mut channel: Option<String> = None;
    let mut expires_days_str: Option<String> = None;
    let mut files: Vec<PathBuf> = Vec::new();

    let mut i = 0;
    while i < args.len() {
        let arg = &args[i];
        match arg.as_str() {
            "--product" => {
                i += 1;
                let val = args.get(i).ok_or_else(|| {
                    CliError::Usage("missing value for --product".to_owned())
                })?;
                if product.replace(val.clone()).is_some() {
                    return Err(CliError::Usage("duplicate --product flag".to_owned()));
                }
            }
            "--version" => {
                i += 1;
                let val = args.get(i).ok_or_else(|| {
                    CliError::Usage("missing value for --version".to_owned())
                })?;
                if version_str.replace(val.clone()).is_some() {
                    return Err(CliError::Usage("duplicate --version flag".to_owned()));
                }
            }
            "--channel" => {
                i += 1;
                let val = args.get(i).ok_or_else(|| {
                    CliError::Usage("missing value for --channel".to_owned())
                })?;
                if channel.replace(val.clone()).is_some() {
                    return Err(CliError::Usage("duplicate --channel flag".to_owned()));
                }
            }
            "--expires-days" => {
                i += 1;
                let val = args.get(i).ok_or_else(|| {
                    CliError::Usage("missing value for --expires-days".to_owned())
                })?;
                if expires_days_str.replace(val.clone()).is_some() {
                    return Err(CliError::Usage("duplicate --expires-days flag".to_owned()));
                }
            }
            "--" => {
                for f in &args[i + 1..] {
                    files.push(PathBuf::from(f));
                }
                break;
            }
            s if s.starts_with('-') => {
                return Err(CliError::Usage(format!("unknown option {s:?}")));
            }
            s => {
                files.push(PathBuf::from(s));
            }
        }
        i += 1;
    }

    let product = product.ok_or_else(|| CliError::Usage("missing --product".to_owned()))?;
    let version_str = version_str.ok_or_else(|| CliError::Usage("missing --version".to_owned()))?;
    let channel = channel.ok_or_else(|| CliError::Usage("missing --channel".to_owned()))?;
    let expires_days_str =
        expires_days_str.ok_or_else(|| CliError::Usage("missing --expires-days".to_owned()))?;

    if files.is_empty() {
        return Err(CliError::Usage(
            "at least one FILE is required for manifest".to_owned(),
        ));
    }

    let days: i64 = expires_days_str.parse().map_err(|_| {
        CliError::Usage(format!(
            "--expires-days must be an integer in 1..=365, got {expires_days_str:?}"
        ))
    })?;
    if !(1..=365).contains(&days) {
        return Err(CliError::Usage(format!(
            "--expires-days must be in 1..=365, got {days}"
        )));
    }

    let version = Version::parse(&version_str)
        .map_err(|e| CliError::Fail(format!("invalid semver version {version_str:?}: {e}")))?;

    let expires = OffsetDateTime::now_utc()
        .checked_add(Duration::days(days))
        .ok_or_else(|| CliError::Fail("expires timestamp overflowed".to_owned()))?;

    let input = ManifestInput {
        product,
        version,
        channel,
        expires,
        files,
    };

    let bytes = build_manifest(&input)?;
    let mut stdout = io::stdout().lock();
    stdout
        .write_all(&bytes)
        .map_err(|e| CliError::Fail(format!("could not write manifest to stdout: {e}")))?;
    stdout
        .write_all(b"\n")
        .map_err(|e| CliError::Fail(format!("could not write newline to stdout: {e}")))?;
    stdout
        .flush()
        .map_err(|e| CliError::Fail(format!("could not flush stdout: {e}")))?;
    Ok(())
}

fn cmd_sign(args: &[String]) -> Result<(), CliError> {
    let mut manifest_path: Option<PathBuf> = None;
    let mut out_path: Option<PathBuf> = None;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--manifest" => {
                i += 1;
                let val = args.get(i).ok_or_else(|| {
                    CliError::Usage("missing value for --manifest".to_owned())
                })?;
                if val.is_empty() {
                    return Err(CliError::Usage("--manifest path must not be empty".to_owned()));
                }
                if manifest_path.replace(PathBuf::from(val)).is_some() {
                    return Err(CliError::Usage("duplicate --manifest flag".to_owned()));
                }
            }
            "--out" => {
                i += 1;
                let val = args
                    .get(i)
                    .ok_or_else(|| CliError::Usage("missing value for --out".to_owned()))?;
                if val.is_empty() {
                    return Err(CliError::Usage("--out path must not be empty".to_owned()));
                }
                if out_path.replace(PathBuf::from(val)).is_some() {
                    return Err(CliError::Usage("duplicate --out flag".to_owned()));
                }
            }
            other => {
                return Err(CliError::Usage(format!(
                    "unexpected argument {other:?} (usage: launcher-sign sign --manifest PATH --out PATH)"
                )));
            }
        }
        i += 1;
    }

    let manifest_path = manifest_path.ok_or_else(|| {
        CliError::Usage("usage: launcher-sign sign --manifest PATH --out PATH".to_owned())
    })?;
    let out_path = out_path.ok_or_else(|| {
        CliError::Usage("usage: launcher-sign sign --manifest PATH --out PATH".to_owned())
    })?;

    let seed = read_signing_key_from_env()?;
    let manifest_bytes = fs::read(&manifest_path).map_err(|e| {
        CliError::Fail(format!(
            "could not read manifest {}: {e}",
            manifest_path.display()
        ))
    })?;

    let sig = sign(&seed, &manifest_bytes);
    fs::write(&out_path, sig).map_err(|e| {
        CliError::Fail(format!(
            "could not write signature {}: {e}",
            out_path.display()
        ))
    })?;

    let pub_hex = public_key_hex(&seed);
    println!("{pub_hex}");
    Ok(())
}
