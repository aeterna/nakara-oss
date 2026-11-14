// SPDX-License-Identifier: MIT

//! Join a server: FiveM, Roblox and Rongroi adapters (ADR 0002 decision 6).
//!
//! The launcher never reads or changes a game's files. It only builds a join
//! URL from the profile's `connect` value and hands it to the system opener.

use launcher_core::{Game, Profile};
use std::fmt;
use std::io;

/// Why a join URL could not be built or opened.
#[derive(Debug)]
pub enum JoinError {
    /// The input is not exactly one `host:port` pair.
    HostPort,
    /// IPv6 addresses are not accepted, and more than one colon is refused.
    Ipv6,
    /// The host part is empty.
    EmptyHost,
    /// The host is not an IPv4 dotted quad or a DNS name.
    Host,
    /// The port part is empty.
    EmptyPort,
    /// The port is not 1 to 65535, has a leading zero or is not decimal.
    Port,
    /// The Roblox place id is not 1 to 20 digits without a leading zero that fit in `u64`.
    Place,
    /// The system opener could not open the URL.
    Open(io::Error),
}

impl fmt::Display for JoinError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::HostPort => f.write_str("connect must be exactly host:port"),
            Self::Ipv6 => f.write_str("IPv6 addresses are not accepted"),
            Self::EmptyHost => f.write_str("host is empty"),
            Self::Host => f.write_str("host must be an IPv4 address or a DNS name"),
            Self::EmptyPort => f.write_str("port is empty"),
            Self::Port => f.write_str("port must be 1 to 65535 without a leading zero"),
            Self::Place => {
                f.write_str("place must be 1 to 20 decimal digits without a leading zero")
            }
            Self::Open(_) => f.write_str("could not open the join URL"),
        }
    }
}

impl std::error::Error for JoinError {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Open(error) => Some(error),
            _ => None,
        }
    }
}

/// The URL to open and the way to open it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct JoinTarget {
    /// The complete join URL.
    pub url: String,
    /// How the URL reaches the game.
    pub kind: Kind,
}

/// How a join URL reaches the game.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    /// A registered protocol such as `fivem://` reaches the game client.
    ProtocolHandler,
    /// The URL opens in the default browser.
    Browser,
}

/// Build a FiveM join URL from a strict `host:port` value.
///
/// The host is an IPv4 dotted quad without leading zeros, or a DNS name of
/// 1 to 63 character LDH labels with at least one dot and a total length of
/// at most 253 characters. The port is 1 to 65535 without a leading zero.
pub fn fivem_join_url(connect: &str) -> Result<String, JoinError> {
    let Some((host, port)) = connect.split_once(':') else {
        return Err(JoinError::HostPort);
    };

    if host.contains(':') || port.contains(':') || connect.starts_with('[') {
        return Err(JoinError::Ipv6);
    }
    if host.is_empty() {
        return Err(JoinError::EmptyHost);
    }
    if port.is_empty() {
        return Err(JoinError::EmptyPort);
    }

    validate_host(host)?;
    validate_port(port)?;

    Ok(format!("fivem://connect/{connect}"))
}

/// Build a Roblox join URL from a decimal place id.
///
/// The place id is 1 to 20 digits without a leading zero and must fit in
/// `u64`. The result always uses the browser, never the `roblox-player:`
/// handler.
pub fn roblox_join_url(place: &str) -> Result<String, JoinError> {
    let bytes = place.as_bytes();
    if bytes.is_empty()
        || bytes.len() > 20
        || !bytes.iter().all(|byte| byte.is_ascii_digit())
        || bytes[0] == b'0'
    {
        return Err(JoinError::Place);
    }

    place.parse::<u64>().map_err(|_| JoinError::Place)?;

    Ok(format!(
        "https://www.roblox.com/games/start?placeId={place}"
    ))
}

/// Build the join target for a profile.
///
/// FiveM Legacy and FiveM Enhanced use the FiveM protocol from
/// `server.connect`; Roblox uses the browser from the same field.
pub fn join_target(profile: &Profile) -> Result<JoinTarget, JoinError> {
    match &profile.server.game {
        Game::FivemLegacy | Game::FivemEnhanced => Ok(JoinTarget {
            url: fivem_join_url(&profile.server.connect)?,
            kind: Kind::ProtocolHandler,
        }),
        Game::Roblox => Ok(JoinTarget {
            url: roblox_join_url(&profile.server.connect)?,
            kind: Kind::Browser,
        }),
    }
}

/// Opens a URL through the system.
pub trait Opener {
    /// Open `url` and return when the request has been handed over.
    fn open(&self, url: &str) -> std::io::Result<()>;
}

/// An opener that uses the operating system's default handler.
#[derive(Debug, Clone, Copy, Default)]
pub struct SystemOpener;

impl Opener for SystemOpener {
    fn open(&self, url: &str) -> std::io::Result<()> {
        open::that_detached(url)
    }
}

/// Build the profile's join target and open it.
pub fn join(profile: &Profile, opener: &dyn Opener) -> Result<JoinTarget, JoinError> {
    let target = join_target(profile)?;
    opener.open(&target.url).map_err(JoinError::Open)?;
    Ok(target)
}

fn validate_host(host: &str) -> Result<(), JoinError> {
    if !host.is_ascii() {
        return Err(JoinError::Host);
    }
    if host
        .bytes()
        .all(|byte| byte.is_ascii_digit() || byte == b'.')
    {
        validate_ipv4(host)
    } else {
        validate_dns(host)
    }
}

fn validate_ipv4(host: &str) -> Result<(), JoinError> {
    let mut octets = 0;
    for octet in host.split('.') {
        octets += 1;
        if !valid_ipv4_octet(octet) {
            return Err(JoinError::Host);
        }
    }

    if octets == 4 {
        Ok(())
    } else {
        Err(JoinError::Host)
    }
}

fn valid_ipv4_octet(octet: &str) -> bool {
    let bytes = octet.as_bytes();
    if bytes.is_empty()
        || bytes.len() > 3
        || !bytes.iter().all(|byte| byte.is_ascii_digit())
        || (bytes.len() > 1 && bytes[0] == b'0')
    {
        return false;
    }

    matches!(octet.parse::<u16>(), Ok(value) if value <= 255)
}

fn validate_dns(host: &str) -> Result<(), JoinError> {
    if host.len() > 253 || !host.contains('.') {
        return Err(JoinError::Host);
    }

    for label in host.split('.') {
        if !valid_dns_label(label) {
            return Err(JoinError::Host);
        }
    }

    Ok(())
}

fn valid_dns_label(label: &str) -> bool {
    let bytes = label.as_bytes();
    if bytes.is_empty() || bytes.len() > 63 {
        return false;
    }

    let ldh = bytes
        .iter()
        .all(|byte| byte.is_ascii_alphanumeric() || *byte == b'-');
    ldh && bytes[0] != b'-' && bytes[bytes.len() - 1] != b'-'
}

fn validate_port(port: &str) -> Result<(), JoinError> {
    let bytes = port.as_bytes();
    if bytes.is_empty()
        || bytes.len() > 5
        || !bytes.iter().all(|byte| byte.is_ascii_digit())
        || (bytes.len() > 1 && bytes[0] == b'0')
    {
        return Err(JoinError::Port);
    }

    let value = port.parse::<u32>().map_err(|_| JoinError::Port)?;
    if (1..=65535).contains(&value) {
        Ok(())
    } else {
        Err(JoinError::Port)
    }
}
