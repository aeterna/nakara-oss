// SPDX-License-Identifier: MIT

//! Tests for the network gate (ADR 0002 decision 5): which URLs the launcher
//! may touch, which resolved addresses it may connect to, and which image
//! headers it accepts.

use std::net::{IpAddr, Ipv4Addr, Ipv6Addr};

use launcher_core::parse;
use launcher_net::{check_image_header, NetError, NetPolicy, Role};

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

const WITH_RONGROI: &str = r##"schema = 1

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
rongroi_connect = true
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

fn ip4(octets: [u8; 4]) -> IpAddr {
    IpAddr::V4(Ipv4Addr::from(octets))
}

fn ip6(segments: [u16; 8]) -> IpAddr {
    IpAddr::V6(Ipv6Addr::from(segments))
}

fn refused(policy: &NetPolicy, role: Role, address: IpAddr) {
    assert_eq!(
        policy.check_ip(role, address),
        Err(NetError::ForbiddenAddress {
            ip: address.to_string(),
        }),
    );
}

fn accepted(policy: &NetPolicy, role: Role, address: IpAddr) {
    assert_eq!(policy.check_ip(role, address), Ok(()));
}

// --- check_url: the profile's feed host ---

#[test]
fn feed_url_allowed_with_feed_role() {
    let p = policy(BASE);
    let checked = p
        .check_url("https://feed.example.com/api/launcher/v1")
        .expect("feed URL should pass");
    assert_eq!(checked.host, "feed.example.com");
    assert_eq!(checked.role, Role::Feed);
    assert_eq!(checked.url, "https://feed.example.com/api/launcher/v1");
}

#[test]
fn feed_host_role_is_case_insensitive() {
    let p = policy(BASE);
    let checked = p
        .check_url("https://FEED.Example.COM/api/launcher/v1")
        .expect("upper-case feed URL should pass");
    assert_eq!(checked.host, "feed.example.com");
    assert_eq!(checked.role, Role::Feed);
}

// --- check_url: refusals ---

#[test]
fn unknown_host_refused() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("https://mirror.example.net/api/launcher/v1"),
        Err(NetError::Host(_)),
    ));
}

#[test]
fn non_https_scheme_refused() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("http://feed.example.com/api/launcher/v1"),
        Err(NetError::NotHttps(_)),
    ));
    assert!(matches!(
        p.check_url("ftp://feed.example.com/api"),
        Err(NetError::NotHttps(_)),
    ));
}

#[test]
fn userinfo_refused() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("https://user:pass@feed.example.com/api/launcher/v1"),
        Err(NetError::Userinfo(_)),
    ));
}

#[test]
fn non_default_port_refused() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("https://feed.example.com:8443/api/launcher/v1"),
        Err(NetError::Port(_)),
    ));
}

#[test]
fn explicit_default_port_allowed() {
    let p = policy(BASE);
    let checked = p
        .check_url("https://feed.example.com:443/api/launcher/v1")
        .expect("explicit port 443 should pass");
    assert_eq!(checked.url, "https://feed.example.com/api/launcher/v1");
    assert_eq!(checked.role, Role::Feed);
}

#[test]
fn ip_literal_host_refused() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("https://127.0.0.1/api/launcher/v1"),
        Err(NetError::IpHost(_)),
    ));
    assert!(matches!(
        p.check_url("https://[2001:db8::1]/api/launcher/v1"),
        Err(NetError::IpHost(_)),
    ));
}

#[test]
fn fragment_refused() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("https://feed.example.com/api/launcher/v1#top"),
        Err(NetError::Fragment(_)),
    ));
}

#[test]
fn unparseable_url_refused() {
    let p = policy(BASE);
    assert!(matches!(p.check_url("not a url"), Err(NetError::Parse(_)),));
}

// --- check_url: the GitHub release hosts ---

#[test]
fn github_host_refused_without_release_policy() {
    let p = policy(BASE);
    assert!(matches!(
        p.check_url("https://github.com/example-rp/game-releases/releases/download/v1.0/app.exe"),
        Err(NetError::Host(_)),
    ));
}

#[test]
fn release_repo_enables_github_hosts() {
    let p = policy(WITH_RELEASE_REPO);
    for host in [
        "github.com",
        "api.github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ] {
        let checked = p
            .check_url(&format!("https://{host}/example-rp/game-releases/v1.0"))
            .unwrap_or_else(|e| panic!("{host} should pass: {e}"));
        assert_eq!(checked.host, host);
        assert_eq!(checked.role, Role::Release);
    }
}

#[test]
fn rongroi_connect_enables_github_hosts() {
    let p = policy(WITH_RONGROI);
    let checked = p
        .check_url("https://github.com/example-rp/game-releases/releases/download/v1.0/app.exe")
        .expect("github.com should pass with rongroi_connect");
    assert_eq!(checked.host, "github.com");
    assert_eq!(checked.role, Role::Release);
}

#[test]
fn github_host_lookup_is_case_insensitive() {
    let p = policy(WITH_RELEASE_REPO);
    let checked = p
        .check_url("https://GITHUB.COM/example-rp/game-releases")
        .expect("upper-case host should pass");
    assert_eq!(checked.host, "github.com");
    assert_eq!(checked.role, Role::Release);
}

#[test]
fn github_subdomain_refused() {
    let p = policy(WITH_RELEASE_REPO);
    assert!(matches!(
        p.check_url("https://github.com.evil.dev/example-rp/game-releases"),
        Err(NetError::Host(_)),
    ));
}

// --- check_ip: allowed addresses ---

#[test]
fn public_addresses_allowed() {
    let p = policy(BASE);
    for role in [Role::Feed, Role::Release] {
        accepted(&p, role, ip4([8, 8, 8, 8]));
        accepted(&p, role, ip4([1, 1, 1, 1]));
        accepted(&p, role, ip6([0x2620, 0x00fe, 0, 0, 0, 0, 0, 0x00fe]));
    }
}

// --- check_ip: refused addresses ---

#[test]
fn loopback_unspecified_and_private_refused() {
    let p = policy(BASE);
    refused(&p, Role::Feed, ip4([127, 0, 0, 1]));
    refused(&p, Role::Feed, ip4([127, 255, 255, 255]));
    refused(&p, Role::Feed, ip4([0, 0, 0, 0]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0, 0, 0]));
    refused(&p, Role::Feed, ip4([10, 0, 0, 1]));
    refused(&p, Role::Feed, ip4([10, 255, 255, 255]));
    refused(&p, Role::Feed, ip4([172, 16, 0, 1]));
    refused(&p, Role::Feed, ip4([172, 31, 255, 255]));
    refused(&p, Role::Feed, ip4([192, 168, 1, 1]));
    // Just outside the private ranges.
    accepted(&p, Role::Feed, ip4([9, 255, 255, 255]));
    accepted(&p, Role::Feed, ip4([11, 0, 0, 1]));
    accepted(&p, Role::Feed, ip4([172, 15, 0, 1]));
    accepted(&p, Role::Feed, ip4([172, 32, 0, 1]));
    accepted(&p, Role::Feed, ip4([192, 169, 0, 1]));
}

#[test]
fn link_local_cgnat_and_ula_refused() {
    let p = policy(BASE);
    refused(&p, Role::Feed, ip4([169, 254, 0, 1]));
    refused(&p, Role::Feed, ip4([169, 254, 255, 255]));
    refused(&p, Role::Feed, ip6([0xfe80, 0, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip6([0xfebf, 0xffff, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip4([100, 64, 0, 1]));
    refused(&p, Role::Feed, ip4([100, 127, 255, 255]));
    refused(&p, Role::Feed, ip6([0xfc00, 0, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip6([0xfd12, 0x3456, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip6([0xfdff, 0xffff, 0, 0, 0, 0, 0, 1]));
    // Just outside.
    accepted(&p, Role::Feed, ip4([169, 255, 0, 1]));
    accepted(&p, Role::Feed, ip4([100, 63, 0, 1]));
    accepted(&p, Role::Feed, ip4([100, 128, 0, 1]));
    accepted(&p, Role::Feed, ip6([0xfe00, 0, 0, 0, 0, 0, 0, 1]));
}

#[test]
fn multicast_broadcast_and_documentation_refused() {
    let p = policy(BASE);
    refused(&p, Role::Feed, ip4([224, 0, 0, 1]));
    refused(&p, Role::Feed, ip4([239, 255, 255, 250]));
    refused(&p, Role::Feed, ip4([255, 255, 255, 255]));
    refused(&p, Role::Feed, ip6([0xff02, 0, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip6([0xff0e, 0, 0, 0, 0, 0, 0, 1]));
    refused(&p, Role::Feed, ip4([192, 0, 2, 1]));
    refused(&p, Role::Feed, ip4([198, 51, 100, 7]));
    refused(&p, Role::Feed, ip4([203, 0, 113, 9]));
    refused(&p, Role::Feed, ip6([0x2001, 0x0db8, 0, 0, 0, 0, 0, 1]));
}

#[test]
fn additional_reserved_ipv4_ranges_refused() {
    let p = policy(BASE);
    // 0.0.0.0/8
    refused(&p, Role::Feed, ip4([0, 1, 2, 3]));
    // 240.0.0.0/4
    refused(&p, Role::Feed, ip4([240, 0, 0, 1]));
    // 198.18.0.0/15
    refused(&p, Role::Feed, ip4([198, 18, 0, 1]));
    // 192.0.0.0/24
    refused(&p, Role::Feed, ip4([192, 0, 0, 1]));
    // 192.88.99.0/24
    refused(&p, Role::Feed, ip4([192, 88, 99, 1]));
    // A public address still passes.
    accepted(&p, Role::Feed, ip4([8, 8, 8, 8]));
}

#[test]
fn additional_reserved_ipv6_ranges_refused() {
    let p = policy(BASE);
    // ::/8, with a zero first byte but no embedded IPv4 part.
    refused(&p, Role::Feed, ip6([0x00ff, 0, 0, 0, 0, 0, 0, 1]));
    // fec0::/10 site-local
    refused(&p, Role::Feed, ip6([0xfec0, 0, 0, 0, 0, 0, 0, 1]));
    // 100::/64 discard
    refused(&p, Role::Feed, ip6([0x0100, 0, 0, 0, 0, 0, 0, 1]));
    // 2002::/16 6to4
    refused(&p, Role::Feed, ip6([0x2002, 0, 0, 0, 0, 0, 0, 1]));
    // 64:ff9b::/96 NAT64
    refused(&p, Role::Feed, ip6([0x0064, 0xff9b, 0, 0, 0, 0, 0, 1]));
    // 2001::/32 Teredo
    refused(&p, Role::Feed, ip6([0x2001, 0, 0, 0, 0, 0, 0, 1]));
    // A public address still passes.
    accepted(&p, Role::Feed, ip6([0x2620, 0x00fe, 0, 0, 0, 0, 0, 0x00fe]));
}

#[test]
fn ipv4_mapped_and_compat_forms_checked() {
    let p = policy(BASE);
    // Every refused IPv4 range must also be refused in its IPv4-mapped form.
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0x7f00, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0x0a00, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0xac10, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0xc0a8, 0x0101]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0xa9fe, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0x6440, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0xe000, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0xffff, 0xffff]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0xc000, 0x0201]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0, 0]));
    // A public IPv4 address is still refused in mapped form inside ::/8.
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0xffff, 0x0808, 0x0808]));
    // The deprecated IPv4-compatible form ::a.b.c.d is checked the same way.
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0, 0x7f00, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0, 0x0a00, 0x0001]));
    refused(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0, 0x0808, 0x0808]));
}

// --- check_ip: allow_local_feed ---

#[test]
fn allow_local_feed_lifts_the_check_for_feed_only() {
    let p = policy(WITH_LOCAL_FEED);
    accepted(&p, Role::Feed, ip4([127, 0, 0, 1]));
    accepted(&p, Role::Feed, ip4([192, 168, 1, 1]));
    accepted(&p, Role::Feed, ip6([0, 0, 0, 0, 0, 0, 0, 1]));
    // Never for the release role.
    refused(&p, Role::Release, ip4([127, 0, 0, 1]));
    refused(&p, Role::Release, ip4([192, 168, 1, 1]));
}

#[test]
fn local_addresses_refused_without_allow_local_feed() {
    let p = policy(BASE);
    refused(&p, Role::Feed, ip4([127, 0, 0, 1]));
    refused(&p, Role::Feed, ip4([192, 168, 1, 1]));
}

// --- check_image_header ---

fn png_header(width: u32, height: u32) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"\x89PNG\r\n\x1a\n");
    bytes.extend_from_slice(&13u32.to_be_bytes());
    bytes.extend_from_slice(b"IHDR");
    bytes.extend_from_slice(&width.to_be_bytes());
    bytes.extend_from_slice(&height.to_be_bytes());
    bytes
}

fn webp_lossy(width: u16, height: u16) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&22u32.to_le_bytes());
    bytes.extend_from_slice(b"WEBP");
    bytes.extend_from_slice(b"VP8 ");
    bytes.extend_from_slice(&10u32.to_le_bytes());
    bytes.extend_from_slice(&[0x00, 0x00, 0x00]);
    bytes.extend_from_slice(&[0x9d, 0x01, 0x2a]);
    bytes.extend_from_slice(&(width & 0x3fff).to_le_bytes());
    bytes.extend_from_slice(&(height & 0x3fff).to_le_bytes());
    bytes
}

fn webp_lossless(width: u16, height: u16) -> Vec<u8> {
    let w1 = u32::from(width - 1);
    let h1 = u32::from(height - 1);
    let b0 = (w1 & 0xff) as u8;
    let b1 = (((w1 >> 8) & 0x3f) as u8) | (((h1 & 0x03) << 6) as u8);
    let b2 = ((h1 >> 2) & 0xff) as u8;
    let b3 = ((h1 >> 10) & 0x3f) as u8;
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&17u32.to_le_bytes());
    bytes.extend_from_slice(b"WEBP");
    bytes.extend_from_slice(b"VP8L");
    bytes.extend_from_slice(&5u32.to_le_bytes());
    bytes.extend_from_slice(&[0x2f, b0, b1, b2, b3]);
    bytes
}

fn webp_extended(width: u32, height: u32) -> Vec<u8> {
    let w1 = width - 1;
    let h1 = height - 1;
    let mut bytes = Vec::new();
    bytes.extend_from_slice(b"RIFF");
    bytes.extend_from_slice(&22u32.to_le_bytes());
    bytes.extend_from_slice(b"WEBP");
    bytes.extend_from_slice(b"VP8X");
    bytes.extend_from_slice(&10u32.to_le_bytes());
    bytes.extend_from_slice(&[0x00, 0x00, 0x00, 0x00]);
    bytes.extend_from_slice(&[w1 as u8, (w1 >> 8) as u8, (w1 >> 16) as u8]);
    bytes.extend_from_slice(&[h1 as u8, (h1 >> 8) as u8, (h1 >> 16) as u8]);
    bytes
}

fn jpeg_header(width: u16, height: u16) -> Vec<u8> {
    let mut bytes = Vec::new();
    bytes.extend_from_slice(&[0xff, 0xd8]);
    bytes.extend_from_slice(&[0xff, 0xc0]);
    bytes.extend_from_slice(&17u16.to_be_bytes());
    bytes.push(8);
    bytes.extend_from_slice(&height.to_be_bytes());
    bytes.extend_from_slice(&width.to_be_bytes());
    bytes.extend_from_slice(&[3, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01]);
    bytes
}

#[test]
fn png_header_accepted() {
    assert_eq!(
        check_image_header(&png_header(1920, 1080), 1024, 4_194_304),
        Ok((1920, 1080)),
    );
}

#[test]
fn webp_headers_accepted() {
    assert_eq!(
        check_image_header(&webp_lossy(1024, 768), 1024, 4_194_304),
        Ok((1024, 768)),
    );
    assert_eq!(
        check_image_header(&webp_lossless(640, 480), 1024, 4_194_304),
        Ok((640, 480)),
    );
    assert_eq!(
        check_image_header(&webp_extended(2048, 2048), 1024, 4_194_304),
        Ok((2048, 2048)),
    );
}

#[test]
fn jpeg_header_accepted() {
    assert_eq!(
        check_image_header(&jpeg_header(800, 600), 1024, 4_194_304),
        Ok((800, 600)),
    );
}

#[test]
fn other_formats_refused() {
    let mut gif = Vec::new();
    gif.extend_from_slice(b"GIF89a");
    gif.extend_from_slice(&[1, 0, 1, 0]);
    assert_eq!(
        check_image_header(&gif, 1024, 4_194_304),
        Err(NetError::ImageFormat)
    );
    assert_eq!(
        check_image_header(&[], 1024, 4_194_304),
        Err(NetError::ImageFormat)
    );
    assert_eq!(
        check_image_header(b"\x89PNG\r\n\x1a\n", 1024, 4_194_304),
        Err(NetError::ImageFormat),
    );
    assert_eq!(
        check_image_header(b"\xff\xd8\xff", 1024, 4_194_304),
        Err(NetError::ImageFormat),
    );
}

#[test]
fn zero_dimensions_refused() {
    assert_eq!(
        check_image_header(&png_header(0, 1080), 1024, 4_194_304),
        Err(NetError::ImageFormat),
    );
    assert_eq!(
        check_image_header(&png_header(1920, 0), 1024, 4_194_304),
        Err(NetError::ImageFormat),
    );
}

#[test]
fn over_byte_cap_refused() {
    let png = png_header(1920, 1080);
    assert_eq!(
        check_image_header(&png, 23, 4_194_304),
        Err(NetError::ImageBytes {
            size: 24,
            limit: 23,
        }),
    );
}

#[test]
fn over_pixel_cap_refused() {
    let png = png_header(1920, 1080);
    assert_eq!(
        check_image_header(&png, 1024, 2_073_599),
        Err(NetError::ImagePixels {
            pixels: 2_073_600,
            limit: 2_073_599,
        }),
    );
}

#[test]
fn at_pixel_cap_allowed() {
    assert_eq!(
        check_image_header(&png_header(1920, 1080), 1024, 2_073_601),
        Ok((1920, 1080)),
    );
}
