// SPDX-License-Identifier: MIT

//! The network gate (ADR 0002 decision 5): which URLs the launcher may fetch
//! and which resolved addresses it may connect to.
//!
//! The policy is built once from the profile. A URL is checked before a
//! request starts and every resolved address is checked before connecting.

use std::net::IpAddr;

use launcher_core::Profile;
use thiserror::Error;
use url::{Host, Url};

/// GitHub hosts that release downloads may use.
const RELEASE_HOSTS: [&str; 4] = [
    "github.com",
    "api.github.com",
    "objects.githubusercontent.com",
    "release-assets.githubusercontent.com",
];

/// What a trusted host is used for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// The profile's feed host.
    Feed,
    /// GitHub release and release-download hosts.
    Release,
}

/// A URL that passed the gate.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CheckedUrl {
    /// Lower-case host.
    pub host: String,
    /// What the host is trusted for.
    pub role: Role,
    /// The URL as the `url` crate normalized it.
    pub url: String,
}

/// Why a URL, an address or an image was refused.
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum NetError {
    /// The URL is not valid.
    #[error("could not parse URL: {0}")]
    Parse(String),

    /// The URL scheme is not `https`.
    #[error("URL scheme {0:?} is not https")]
    NotHttps(String),

    /// The URL carries a user name or password.
    #[error("URL for host {0:?} carries user information")]
    Userinfo(String),

    /// The URL names a port other than 443.
    #[error("URL port {0} is not allowed")]
    Port(u16),

    /// The URL host is an IP literal instead of a name.
    #[error("URL host {0:?} is an IP address")]
    IpHost(String),

    /// The URL host is not in the profile's list.
    #[error("URL host {0:?} is not allowed")]
    Host(String),

    /// The URL carries a fragment.
    #[error("URL has a fragment {0:?}")]
    Fragment(String),

    /// A resolved address is not a public unicast address.
    #[error("address {ip} is not a public address")]
    ForbiddenAddress { ip: String },

    /// The image is not PNG, WebP or JPEG.
    #[error("image is not PNG, WebP or JPEG")]
    ImageFormat,

    /// The image is larger than the byte cap.
    #[error("image is {size} bytes, the limit is {limit}")]
    ImageBytes { size: usize, limit: usize },

    /// The image has more pixels than the pixel cap.
    #[error("image has {pixels} pixels, the limit is {limit}")]
    ImagePixels { pixels: u64, limit: u64 },
}

/// The hosts and addresses a build may touch.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NetPolicy {
    feed_host: Option<String>,
    release: bool,
    allow_local_feed: bool,
}

impl NetPolicy {
    /// Builds the policy from a profile.
    ///
    /// The feed host is allowed for [`Role::Feed`]. The GitHub release hosts
    /// are allowed for [`Role::Release`] when the profile sets `release_repo`
    /// or turns on `rongroi_connect`. Nothing else is allowed.
    pub fn from_profile(profile: &Profile) -> Self {
        let feed_host = profile
            .server
            .feed
            .as_deref()
            .and_then(|feed| Url::parse(feed).ok())
            .and_then(|url| url.host_str().map(|host| host.to_ascii_lowercase()));
        let release = profile.server.release_repo.is_some() || profile.features.rongroi_connect;
        Self {
            feed_host,
            release,
            allow_local_feed: profile.features.allow_local_feed,
        }
    }

    /// Checks a URL before fetching it.
    ///
    /// Refuses anything but `https`, user information, a port other than 443,
    /// an IP-literal host, a host outside the policy and a fragment.
    pub fn check_url(&self, input: &str) -> Result<CheckedUrl, NetError> {
        let url = Url::parse(input).map_err(|err| NetError::Parse(err.to_string()))?;

        if url.scheme() != "https" {
            return Err(NetError::NotHttps(url.scheme().to_owned()));
        }
        if !url.username().is_empty() || url.password().is_some() {
            return Err(NetError::Userinfo(url.host_str().unwrap_or_default().to_owned()));
        }
        if let Some(port) = url.port() {
            return Err(NetError::Port(port));
        }
        if let Some(fragment) = url.fragment() {
            return Err(NetError::Fragment(fragment.to_owned()));
        }

        let host = match url.host() {
            Some(Host::Domain(domain)) => domain.to_ascii_lowercase(),
            Some(Host::Ipv4(address)) => return Err(NetError::IpHost(address.to_string())),
            Some(Host::Ipv6(address)) => return Err(NetError::IpHost(address.to_string())),
            None => return Err(NetError::Host(String::new())),
        };

        let role = if self.feed_host.as_deref() == Some(host.as_str()) {
            Role::Feed
        } else if self.release && RELEASE_HOSTS.contains(&host.as_str()) {
            Role::Release
        } else {
            return Err(NetError::Host(host));
        };

        Ok(CheckedUrl {
            host,
            role,
            url: url.to_string(),
        })
    }

    /// Checks one resolved address before connecting.
    ///
    /// Refuses loopback, unspecified, private, link-local, CGNAT, reserved,
    /// multicast, broadcast, documentation, ULA, site-local, discard and
    /// IPv4-embedding addresses, including IPv4-mapped and IPv4-compatible
    /// IPv6 forms. `allow_local_feed` lifts the check for [`Role::Feed`] only,
    /// never for [`Role::Release`].
    pub fn check_ip(&self, role: Role, address: IpAddr) -> Result<(), NetError> {
        if role == Role::Feed && self.allow_local_feed {
            return Ok(());
        }
        if forbidden(address) {
            return Err(NetError::ForbiddenAddress {
                ip: address.to_string(),
            });
        }
        Ok(())
    }
}

/// Returns true when an address is not a public unicast address.
fn forbidden(address: IpAddr) -> bool {
    match address {
        IpAddr::V4(ip) => forbidden_v4(ip),
        IpAddr::V6(ip) => ip.to_ipv4().is_some_and(forbidden_v4) || forbidden_v6(ip),
    }
}

/// Loopback, unspecified, private, link-local, CGNAT, multicast, broadcast,
/// documentation, reserved and future-use IPv4 ranges.
fn forbidden_v4(ip: std::net::Ipv4Addr) -> bool {
    let octets = ip.octets();
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_private()
        || ip.is_link_local()
        || ip.is_multicast()
        || octets[0] == 0
        || (octets[0] & 0xf0) == 0xf0
        || (octets[0] == 198 && (octets[1] & 0xfe) == 18)
        || matches!(
            octets,
            [192, 0, 0, _]
                | [192, 88, 99, _]
                | [192, 0, 2, _]
                | [198, 51, 100, _]
                | [203, 0, 113, _]
        )
        || (octets[0] == 100 && (octets[1] & 0xc0) == 64)
}

/// Loopback, unspecified, link-local, site-local, ULA, multicast, discard,
/// documentation, IPv4-embedding and future-use IPv6 ranges.
fn forbidden_v6(ip: std::net::Ipv6Addr) -> bool {
    let segments = ip.segments();
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_multicast()
        || segments[0] <= 0x00ff
        || (segments[0] & 0xffc0) == 0xfe80
        || (segments[0] & 0xffc0) == 0xfec0
        || (segments[0] & 0xfe00) == 0xfc00
        || (segments[0] == 0x2001 && segments[1] == 0)
        || (segments[0] == 0x2001 && segments[1] == 0x0db8)
        || segments[0] == 0x2002
        || (segments[0] == 0x0064 && segments[1] == 0xff9b && segments[2..6] == [0u16, 0, 0, 0])
        || (segments[0] == 0x0100 && segments[1..4] == [0u16, 0, 0])
}
