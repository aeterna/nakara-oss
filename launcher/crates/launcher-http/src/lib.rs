// SPDX-License-Identifier: MIT

//! Blocking HTTPS client for the AETERNA launcher (ADR 0002 decisions 5 and 10).
//!
//! Every request checks the URL against [`launcher_net::NetPolicy::check_url`]
//! before touching the network, disables redirects, enforces HTTPS, resolves
//! addresses through [`launcher_net::NetPolicy::check_ip`], caps the response
//! body size while streaming, and sends no cookies or telemetry.
//! The DNS lookup itself is not bounded by the connect or request timeouts
//! (`std` `getaddrinfo`), and [`FetchError`] text may name hosts and refused
//! addresses, so it is for logs, not for players.

#![deny(missing_docs)]

use std::io::{self, Read};
use std::net::{SocketAddr, ToSocketAddrs};
use std::time::Duration;

use launcher_net::feed::{parse_feed, Feed, FeedError, MAX_FEED_BYTES};
use launcher_net::{CheckedUrl, NetError, NetPolicy, Role};
use thiserror::Error;

const CONNECT_TIMEOUT: Duration = Duration::from_secs(10);
const REQUEST_TIMEOUT: Duration = Duration::from_secs(30);

/// Why an HTTP request or feed fetch failed.
#[derive(Debug, Clone, PartialEq, Error)]
pub enum FetchError {
    /// The URL or resolved address failed the [`NetPolicy`] gate.
    #[error(transparent)]
    Policy(#[from] NetError),

    /// The URL passed the policy gate, but for a role other than expected.
    #[error("expected URL role {expected:?}, got {got:?}")]
    Role {
        /// The role required by the caller.
        expected: Role,
        /// The role matched by the policy.
        got: Role,
    },

    /// The server returned an HTTP status other than 200 OK.
    #[error("unexpected HTTP status {0}")]
    Status(u16),

    /// The response body or `Content-Length` header exceeded the byte cap.
    #[error("response body exceeds the {0}-byte limit")]
    TooLarge(u64),

    /// The feed body failed parsing or schema validation.
    #[error(transparent)]
    Feed(#[from] FeedError),

    /// Reading the response body failed.
    #[error("I/O error reading response body: {0}")]
    Io(String),

    /// The HTTP transport or address resolver failed.
    #[error("HTTP transport error: {0}")]
    Transport(String),
}

/// Blocking HTTPS client enforcing [`NetPolicy`] on every request.
#[derive(Debug, Clone)]
pub struct Client {
    policy: NetPolicy,
    user_agent: String,
}

impl Client {
    /// Creates a client that enforces `policy` and sends `user_agent`.
    pub fn new(policy: NetPolicy, user_agent: &str) -> Self {
        Self {
            policy,
            user_agent: user_agent.to_owned(),
        }
    }

    /// GET a URL that passes `policy.check_url`, with no redirects, body capped at `cap` bytes.
    ///
    /// Accepts any role the policy allows (feed or release hosts); callers that
    /// need one role check [`CheckedUrl::role`] themselves, as [`Self::fetch_feed`] does.
    pub fn get(&self, url: &str, cap: u64) -> Result<Vec<u8>, FetchError> {
        let checked = self.policy.check_url(url)?;
        self.get_checked(&checked, cap, None)
    }

    /// `get()` with role must be `Role::Feed` and cap [`MAX_FEED_BYTES`], then [`parse_feed`].
    pub fn fetch_feed(&self, url: &str) -> Result<Feed, FetchError> {
        let checked = self.policy.check_url(url)?;
        if checked.role != Role::Feed {
            return Err(FetchError::Role {
                expected: Role::Feed,
                got: checked.role,
            });
        }
        let bytes = self.get_checked(&checked, MAX_FEED_BYTES as u64, Some("application/json"))?;
        parse_feed(&bytes).map_err(FetchError::Feed)
    }

    fn get_checked(
        &self,
        checked: &CheckedUrl,
        cap: u64,
        accept: Option<&str>,
    ) -> Result<Vec<u8>, FetchError> {
        // Proxies from the environment are refused so ADR 0002 decision 5 does not depend on Cargo features.
        let agent = ureq::AgentBuilder::new()
            .try_proxy_from_env(false)
            .redirects(0)
            .https_only(true)
            .timeout_connect(CONNECT_TIMEOUT)
            .timeout(REQUEST_TIMEOUT)
            .user_agent(&self.user_agent)
            .resolver(PolicyResolver {
                policy: self.policy.clone(),
                role: checked.role,
            })
            .build();

        let mut request = agent.get(&checked.url);
        if let Some(accept_value) = accept {
            request = request.set("Accept", accept_value);
        }

        let response = match request.call() {
            Ok(resp) => resp,
            Err(ureq::Error::Status(code, _)) => return Err(FetchError::Status(code)),
            Err(ureq::Error::Transport(transport)) => {
                return Err(FetchError::Transport(format_transport(&transport)));
            }
        };

        let status = response.status();
        if status != 200 {
            return Err(FetchError::Status(status));
        }

        if let Some(raw_len) = response.header("Content-Length") {
            if let Ok(content_len) = raw_len.trim().parse::<u64>() {
                if content_len > cap {
                    return Err(FetchError::TooLarge(cap));
                }
            }
        }

        read_capped(response.into_reader(), cap)
    }
}

struct PolicyResolver {
    policy: NetPolicy,
    role: Role,
}

impl ureq::Resolver for PolicyResolver {
    fn resolve(&self, netloc: &str) -> io::Result<Vec<SocketAddr>> {
        let resolved: Vec<SocketAddr> = netloc.to_socket_addrs()?.collect();
        checked_addrs(&self.policy, self.role, resolved)
    }
}

/// Checks every resolved socket address against `policy.check_ip(role, ip)`.
///
/// If any resolved address is refused, the entire lookup is refused with
/// [`io::ErrorKind::PermissionDenied`] carrying the policy error message.
pub fn checked_addrs(
    policy: &NetPolicy,
    role: Role,
    addrs: Vec<SocketAddr>,
) -> io::Result<Vec<SocketAddr>> {
    for addr in &addrs {
        policy
            .check_ip(role, addr.ip())
            .map_err(|err| io::Error::new(io::ErrorKind::PermissionDenied, err.to_string()))?;
    }
    Ok(addrs)
}

/// Reads at most `cap + 1` bytes from `reader` and returns [`FetchError::TooLarge`]
/// if more than `cap` bytes arrive.
pub fn read_capped(reader: impl Read, cap: u64) -> Result<Vec<u8>, FetchError> {
    let limit = cap.saturating_add(1);
    let mut buf = Vec::new();
    reader
        .take(limit)
        .read_to_end(&mut buf)
        .map_err(|err| FetchError::Io(err.to_string()))?;
    if (buf.len() as u64) > cap {
        return Err(FetchError::TooLarge(cap));
    }
    Ok(buf)
}

fn format_transport(transport: &ureq::Transport) -> String {
    let mut message = transport.to_string();
    let mut source = std::error::Error::source(transport);
    while let Some(err) = source {
        let detail = err.to_string();
        if !message.contains(&detail) {
            message.push_str(": ");
            message.push_str(&detail);
        }
        source = err.source();
    }
    message
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;
    use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr};

    use launcher_core::parse;
    use launcher_net::{NetError, NetPolicy, Role};

    use super::{checked_addrs, read_capped, Client, FetchError};

    const BASE: &str = r##"schema = 1

[server]
id = "example-rp"
name = "Example RP"
game = "fivem-legacy"
connect = "play.example.com:30120"
operator = "Example RP Team"
contact_email = "team@example.com"
feed = "https://feed.example.com/api/launcher/v1"

[theme]
accent = "#3f6fd1"

[features]
"##;

    const WITH_RELEASE_REPO: &str = r##"schema = 1

[server]
id = "example-rp"
name = "Example RP"
game = "fivem-legacy"
connect = "play.example.com:30120"
operator = "Example RP Team"
contact_email = "team@example.com"
feed = "https://feed.example.com/api/launcher/v1"
release_repo = "example-rp/game-releases"

[theme]
accent = "#3f6fd1"

[features]
"##;

    const WITH_LOCAL_FEED: &str = r##"schema = 1

[server]
id = "example-rp"
name = "Example RP"
game = "fivem-legacy"
connect = "play.example.com:30120"
operator = "Example RP Team"
contact_email = "team@example.com"
feed = "https://feed.example.com/api/launcher/v1"

[theme]
accent = "#3f6fd1"

[features]
allow_local_feed = true
"##;

    fn policy(toml_text: &str) -> NetPolicy {
        NetPolicy::from_profile(&parse(toml_text).expect("test profile should parse"))
    }

    fn sock4(octets: [u8; 4]) -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::from(octets)), 443)
    }

    fn sock6(segments: [u16; 8]) -> SocketAddr {
        SocketAddr::new(IpAddr::V6(Ipv6Addr::from(segments)), 443)
    }

    #[test]
    fn read_capped_empty() {
        let bytes =
            read_capped(Cursor::new(Vec::<u8>::new()), 64).expect("empty reader should pass");
        assert!(bytes.is_empty());
    }

    #[test]
    fn read_capped_at_cap() {
        let input = vec![b'x'; 64];
        let bytes = read_capped(Cursor::new(input.clone()), 64).expect("at-cap reader should pass");
        assert_eq!(bytes, input);
    }

    #[test]
    fn read_capped_over_cap_by_one() {
        let input = vec![b'x'; 65];
        assert_eq!(
            read_capped(Cursor::new(input), 64),
            Err(FetchError::TooLarge(64)),
        );
    }

    #[test]
    fn checked_addrs_refuses_loopback_and_private_for_feed() {
        let p = policy(BASE);
        for forbidden in [
            sock4([127, 0, 0, 1]),
            sock4([10, 0, 0, 1]),
            sock4([172, 16, 0, 1]),
            sock4([192, 168, 1, 1]),
            sock6([0, 0, 0, 0, 0, 0, 0, 1]),
        ] {
            let err = checked_addrs(&p, Role::Feed, vec![forbidden])
                .expect_err("forbidden address should be refused");
            assert_eq!(err.kind(), std::io::ErrorKind::PermissionDenied);
            assert!(
                err.to_string().contains(&forbidden.ip().to_string()),
                "error {err:?} should name refused IP {}",
                forbidden.ip()
            );
        }
    }

    #[test]
    fn checked_addrs_keeps_public_address() {
        let p = policy(BASE);
        let addrs = vec![
            sock4([8, 8, 8, 8]),
            sock6([0x2620, 0x00fe, 0, 0, 0, 0, 0, 0x00fe]),
        ];
        let checked =
            checked_addrs(&p, Role::Feed, addrs.clone()).expect("public addresses should pass");
        assert_eq!(checked, addrs);
    }

    #[test]
    fn checked_addrs_refuses_mix_of_public_and_private() {
        let p = policy(BASE);
        let mixed = vec![sock4([8, 8, 8, 8]), sock4([192, 168, 1, 1])];
        let err = checked_addrs(&p, Role::Feed, mixed)
            .expect_err("mix of public and private addresses must refuse whole lookup");
        assert_eq!(err.kind(), std::io::ErrorKind::PermissionDenied);
        assert!(err.to_string().contains("192.168.1.1"));
    }

    #[test]
    fn checked_addrs_respects_allow_local_feed_for_feed_only() {
        let p = policy(WITH_LOCAL_FEED);
        let local = vec![sock4([127, 0, 0, 1])];
        assert!(checked_addrs(&p, Role::Feed, local.clone()).is_ok());
        let err = checked_addrs(&p, Role::Release, local)
            .expect_err("allow_local_feed must not allow loopback for Release role");
        assert_eq!(err.kind(), std::io::ErrorKind::PermissionDenied);
    }

    #[test]
    fn get_refuses_http_scheme_without_network() {
        let client = Client::new(policy(BASE), "aeterna-launcher/0.1.0");
        assert_eq!(
            client.get("http://feed.example.com/api/launcher/v1", 1024),
            Err(FetchError::Policy(NetError::NotHttps("http".to_owned()))),
        );
    }

    #[test]
    fn get_refuses_untrusted_host_without_network() {
        let client = Client::new(policy(BASE), "aeterna-launcher/0.1.0");
        assert_eq!(
            client.get("https://untrusted.example.org/api/launcher/v1", 1024),
            Err(FetchError::Policy(NetError::Host(
                "untrusted.example.org".to_owned()
            ))),
        );
    }

    #[test]
    fn fetch_feed_refuses_non_feed_role_without_network() {
        let client = Client::new(policy(WITH_RELEASE_REPO), "aeterna-launcher/0.1.0");
        assert_eq!(
            client.fetch_feed("https://github.com/example-rp/game-releases"),
            Err(FetchError::Role {
                expected: Role::Feed,
                got: Role::Release,
            }),
        );
    }
}
