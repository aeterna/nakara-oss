// SPDX-License-Identifier: MIT

use launcher_core::{parse, Profile};
use launcher_games::{fivem_join_url, join, join_target, roblox_join_url, JoinError, Kind, Opener};
use std::cell::RefCell;
use std::io;

const AETERNA: &str = include_str!("../../../profiles/aeterna/server.toml");

fn profile_for(game: &str, connect: &str) -> Profile {
    let text = format!(
        r#"schema = 1

[server]
id = "nakara"
name = "Nakara"
game = "{game}"
connect = "{connect}"
operator = "Nakara Team"
contact_email = "ops@nakara.example"

[theme]
accent = "#1a2b3c"

[features]
"#
    );
    parse(&text).expect("test profile should parse")
}

fn accepted(connect: &str) -> String {
    fivem_join_url(connect).expect("connect should be accepted")
}

fn refused(connect: &str) -> JoinError {
    fivem_join_url(connect).expect_err("connect should be refused")
}

struct RecordingOpener {
    urls: RefCell<Vec<String>>,
}

impl RecordingOpener {
    fn new() -> Self {
        Self { urls: RefCell::new(Vec::new()) }
    }

    fn urls(&self) -> Vec<String> {
        self.urls.borrow().clone()
    }
}

impl Opener for RecordingOpener {
    fn open(&self, url: &str) -> io::Result<()> {
        self.urls.borrow_mut().push(url.to_owned());
        Ok(())
    }
}

struct FailingOpener;

impl Opener for FailingOpener {
    fn open(&self, _url: &str) -> io::Result<()> {
        Err(io::Error::other("no browser"))
    }
}

#[test]
fn aeterna_profile_shape_joins_with_the_fivem_protocol() {
    let profile = parse(AETERNA).expect("AETERNA profile should parse");
    let target = join_target(&profile).expect("AETERNA profile should join");

    assert_eq!(
        target,
        launcher_games::JoinTarget {
            url: "fivem://connect/play.nakara-city.com:30120".to_owned(),
            kind: Kind::ProtocolHandler,
        }
    );
}

#[test]
fn fivem_accepts_ipv4_and_dns_hosts() {
    let cases = [
        "203.0.113.7:30120",
        "127.0.0.1:1",
        "1.2.3.4:65535",
        "play.nakara-city.com:30120",
        "play.example.com:30120",
        "a.b:30120",
    ];

    for case in cases {
        assert_eq!(accepted(case), format!("fivem://connect/{case}"));
    }
}

#[test]
fn fivem_accepts_uppercase_dns_hosts() {
    assert_eq!(
        accepted("Play.Nakara-City.COM:30120"),
        "fivem://connect/Play.Nakara-City.COM:30120"
    );
}

#[test]
fn fivem_accepts_label_length_63() {
    let label = "a".repeat(63);
    let connect = format!("{label}.example.com:30120");

    assert_eq!(accepted(&connect), format!("fivem://connect/{connect}"));
}

#[test]
fn fivem_accepts_total_host_length_253() {
    let host = format!(
        "{}.{}.{}.{}",
        "a".repeat(63),
        "b".repeat(63),
        "c".repeat(63),
        "d".repeat(61)
    );
    assert_eq!(host.len(), 253);
    let connect = format!("{host}:30120");

    assert_eq!(accepted(&connect), format!("fivem://connect/{connect}"));
}

#[test]
fn fivem_accepts_port_boundaries() {
    for port in ["1", "65535", "30120"] {
        let connect = format!("play.example.com:{port}");
        assert_eq!(accepted(&connect), format!("fivem://connect/{connect}"));
    }
}

#[test]
fn fivem_refuses_ipv6_addresses() {
    for case in ["2001:db8::1:30120", "[::1]:30120", "::1:30120", "[2001:db8::1]:30120"] {
        assert!(matches!(refused(case), JoinError::Ipv6), "{case:?}");
    }
}

#[test]
fn fivem_refuses_missing_port_and_extra_colon() {
    for case in [
        "play.example.com",
        "play.example.com:30120:extra",
        "play.example.com::30120",
        "play.example.com:30120:",
    ] {
        assert!(fivem_join_url(case).is_err(), "{case:?}");
    }
}

#[test]
fn fivem_refuses_empty_parts() {
    assert!(matches!(refused(""), JoinError::HostPort));
    assert!(matches!(refused(":30120"), JoinError::EmptyHost));
    assert!(matches!(refused("play.example.com:"), JoinError::EmptyPort));
    assert!(matches!(refused(":"), JoinError::EmptyHost));
}

#[test]
fn fivem_refuses_whitespace() {
    for case in [
        " play.example.com:30120",
        "play.example.com :30120",
        "play example.com:30120",
        "play.example.com: 30120",
        "play.example.com:30120 ",
        "play.example.com:\t30120",
        "play.example.com:30120\n",
    ] {
        assert!(fivem_join_url(case).is_err(), "{case:?}");
    }
}

#[test]
fn fivem_refuses_non_ascii_hosts() {
    for case in [
        "plaÿ.example.com:30120",
        "play.exämple.com:30120",
        "play。example.com:30120",
        "例え.テスト:30120",
    ] {
        assert!(matches!(refused(case), JoinError::Host), "{case:?}");
    }
}

#[test]
fn fivem_refuses_other_characters() {
    for case in [
        "play_example.com:30120",
        "user@play.example.com:30120",
        "play.example.com:3012a",
        "play.example.com:+30120",
        "play.example.com:-1",
        "play.example.com:3012.0",
        "play.example.com:30120/",
        "play.example.com:30120?x",
        "play.example.com:30120#x",
    ] {
        assert!(fivem_join_url(case).is_err(), "{case:?}");
    }
}

#[test]
fn fivem_refuses_ipv4_with_leading_zeros() {
    for case in [
        "01.2.3.4:30120",
        "1.02.3.4:30120",
        "1.2.003.4:30120",
        "1.2.3.004:30120",
        "00.0.0.0:30120",
    ] {
        assert!(matches!(refused(case), JoinError::Host), "{case:?}");
    }
}

#[test]
fn fivem_refuses_invalid_ipv4_addresses() {
    for case in [
        "256.1.1.1:30120",
        "1.2.3.256:30120",
        "1.2.3:30120",
        "1.2.3.4.5:30120",
        "1.2.3.:30120",
        "1..2.3:30120",
        ".1.2.3:30120",
    ] {
        assert!(matches!(refused(case), JoinError::Host), "{case:?}");
    }
}

#[test]
fn fivem_refuses_invalid_dns_labels() {
    for case in [
        "-play.example.com:30120",
        "play-.example.com:30120",
        "play..example.com:30120",
        ".play.example.com:30120",
        "play.example.com.:30120",
        "localhost:30120",
        "play:30120",
    ] {
        assert!(matches!(refused(case), JoinError::Host), "{case:?}");
    }

    let label = "a".repeat(64);
    let connect = format!("{label}.example.com:30120");
    assert!(matches!(refused(&connect), JoinError::Host));
}

#[test]
fn fivem_refuses_host_longer_than_253() {
    let host = format!(
        "{}.{}.{}.{}",
        "a".repeat(63),
        "b".repeat(63),
        "c".repeat(63),
        "d".repeat(62)
    );
    assert_eq!(host.len(), 254);
    let connect = format!("{host}:30120");

    assert!(matches!(refused(&connect), JoinError::Host));
}

#[test]
fn fivem_refuses_invalid_ports() {
    for case in [
        "play.example.com:0",
        "play.example.com:00",
        "play.example.com:01",
        "play.example.com:00080",
        "play.example.com:65536",
        "play.example.com:99999",
        "play.example.com:999999",
        "play.example.com:-1",
        "play.example.com:1.5",
        "play.example.com: 80",
        "play.example.com:80 ",
        "play.example.com:",
    ] {
        assert!(fivem_join_url(case).is_err(), "{case:?}");
    }
}

#[test]
fn roblox_accepts_decimal_place_ids() {
    assert_eq!(
        roblox_join_url("1").expect("place id should be accepted"),
        "https://www.roblox.com/games/start?placeId=1"
    );
    assert_eq!(
        roblox_join_url("1234567890").expect("place id should be accepted"),
        "https://www.roblox.com/games/start?placeId=1234567890"
    );
    assert_eq!(
        roblox_join_url("18446744073709551615").expect("place id should be accepted"),
        "https://www.roblox.com/games/start?placeId=18446744073709551615"
    );
}

#[test]
fn roblox_refuses_non_decimal_place_ids() {
    for case in ["", "-1", "+1", "1 ", " 1", "1.0", "12a", "0x10", "๑๒"] {
        assert!(matches!(roblox_join_url(case), Err(JoinError::Place)), "{case:?}");
    }
}

#[test]
fn roblox_refuses_leading_zeros_and_zero() {
    for case in ["0", "00", "007", "0123", "000000000000000000001"] {
        assert!(matches!(roblox_join_url(case), Err(JoinError::Place)), "{case:?}");
    }
}

#[test]
fn roblox_refuses_overlong_or_overflowing_place_ids() {
    for case in ["123456789012345678901", "18446744073709551616", "99999999999999999999"] {
        assert!(matches!(roblox_join_url(case), Err(JoinError::Place)), "{case:?}");
    }
}

#[test]
fn join_target_selects_fivem_for_both_fivem_games() {
    for game in ["fivem-legacy", "fivem-enhanced"] {
        let profile = profile_for(game, "play.example.com:30120");
        let target = join_target(&profile).expect("FiveM profile should join");

        assert_eq!(
            target,
            launcher_games::JoinTarget {
                url: "fivem://connect/play.example.com:30120".to_owned(),
                kind: Kind::ProtocolHandler,
            }
        );
    }
}

#[test]
fn join_target_selects_browser_for_roblox() {
    let profile = profile_for("roblox", "1234567890");
    let target = join_target(&profile).expect("Roblox profile should join");

    assert_eq!(
        target,
        launcher_games::JoinTarget {
            url: "https://www.roblox.com/games/start?placeId=1234567890".to_owned(),
            kind: Kind::Browser,
        }
    );
}

#[test]
fn join_target_refuses_an_invalid_connect() {
    let mut profile = profile_for("fivem-legacy", "play.example.com:30120");
    profile.server.connect = "localhost:30120".to_owned();

    assert!(matches!(join_target(&profile), Err(JoinError::Host)));
}

#[test]
fn join_opens_the_selected_url() {
    let opener = RecordingOpener::new();

    let fivem = profile_for("fivem-enhanced", "play.nakara-city.com:30120");
    let fivem_target = join(&fivem, &opener).expect("FiveM profile should open");
    assert_eq!(fivem_target.url, "fivem://connect/play.nakara-city.com:30120");

    let roblox = profile_for("roblox", "1234567890");
    let roblox_target = join(&roblox, &opener).expect("Roblox profile should open");
    assert_eq!(roblox_target.url, "https://www.roblox.com/games/start?placeId=1234567890");

    let urls = opener.urls();
    assert_eq!(urls.len(), 2);
    assert_eq!(urls[0], fivem_target.url);
    assert_eq!(urls[1], roblox_target.url);
}

#[test]
fn join_does_not_open_when_the_target_is_invalid() {
    let mut profile = profile_for("fivem-legacy", "play.example.com:30120");
    profile.server.connect = "play.example.com:0".to_owned();
    let opener = RecordingOpener::new();

    assert!(join(&profile, &opener).is_err());
    assert!(opener.urls().is_empty());
}

#[test]
fn join_reports_opener_failure() {
    let profile = profile_for("fivem-legacy", "play.example.com:30120");

    assert!(matches!(join(&profile, &FailingOpener), Err(JoinError::Open(_))));
}
