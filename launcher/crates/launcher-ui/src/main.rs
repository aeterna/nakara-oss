// SPDX-License-Identifier: MIT

#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

mod action;
mod board;
mod connect;
mod dusk;
mod hero;
mod model;
mod privacy;
mod profile;
mod sample;
mod sidebar;
mod text;
mod theme;
mod topbar;

use iced::widget::{column, container, row};
use iced::{Element, Length, Task};
use launcher_games::Opener;
use launcher_net::policy::NetPolicy;

fn main() -> iced::Result {
    iced::application(boot, App::update, App::view)
        .title(|_: &App| format!("{} Launcher", profile::brand()))
        .window_size((1280.0, 800.0))
        .font(include_bytes!("../../../assets/Anuphan.ttf").as_slice())
        .default_font(iced::Font::with_name("Anuphan"))
        .run()
}

fn boot() -> (App, Task<Message>) {
    let app = App::default();
    let profile = profile::get();
    let task = match profile.server.feed.as_deref() {
        Some(url) => fetch_feed(profile, url),
        None => Task::none(),
    };
    (app, task)
}

fn fetch_feed(profile: &'static launcher_core::Profile, url: &'static str) -> Task<Message> {
    let (tx, rx) = iced::futures::channel::oneshot::channel();
    std::thread::spawn(move || {
        let client = launcher_http::Client::new(
            NetPolicy::from_profile(profile),
            &format!(
                "{}-launcher/{}",
                profile.server.id,
                env!("CARGO_PKG_VERSION")
            ),
        );
        let result = client.fetch_feed(url).map_err(|err| err.to_string());
        let _ = tx.send(result);
    });
    Task::perform(
        async move {
            match rx.await {
                Ok(result) => result,
                Err(err) => Err(err.to_string()),
            }
        },
        Message::FeedLoaded,
    )
}

pub struct App {
    instances: Vec<model::Instance>,
    selected: usize,
    state_dir: Option<std::path::PathBuf>,
    show_privacy: bool,
    notice: Option<String>,
    show_connect: bool,
    connect_code: String,
    connect_busy: bool,
    connect_status: Option<String>,
}

impl Default for App {
    fn default() -> Self {
        let state_dir =
            dirs::config_dir().map(|d| d.join(format!("{}-launcher", profile::get().server.id)));
        let show_privacy = match &state_dir {
            Some(d) => !launcher_core::first_run::seen(d),
            None => true,
        };

        Self {
            instances: model::instances(profile::get(), None),
            selected: 0,
            state_dir,
            show_privacy,
            notice: None,
            show_connect: false,
            connect_code: String::new(),
            connect_busy: false,
            connect_status: None,
        }
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    Select(usize),
    Noop,
    PrivacyOk,
    FeedLoaded(Result<launcher_net::feed::Feed, String>),
    Play,
    OpenInvite,
    OpenNews(usize),
    ConnectOpen,
    ConnectClose,
    ConnectCode(String),
    ConnectStart,
    ConnectDone(String),
}

impl App {
    fn update(&mut self, message: Message) -> Task<Message> {
        match message {
            Message::Select(index) => {
                self.selected = index;
                Task::none()
            }
            Message::Noop => Task::none(),
            Message::PrivacyOk => {
                self.show_privacy = false;

                if let Some(dir) = &self.state_dir {
                    let _ = launcher_core::first_run::mark_seen(dir);
                }
                Task::none()
            }
            Message::FeedLoaded(Ok(feed)) => {
                self.instances = model::instances(profile::get(), Some(&feed));
                self.selected = self.selected.min(self.instances.len().saturating_sub(1));
                Task::none()
            }
            Message::FeedLoaded(Err(err)) => {
                eprintln!("{err}");
                Task::none()
            }
            Message::Play => {
                let index = self.selected.min(self.instances.len().saturating_sub(1));
                if let Some(inst) = self.instances.get(index) {
                    if action::opens_connect(inst, profile::connect_on()) {
                        self.show_connect = true;
                        self.connect_status = None;
                    } else if action::can_play(inst) {
                        match launcher_games::join(profile::get(), &launcher_games::SystemOpener) {
                            Ok(_) => {
                                self.notice = None;
                            }
                            Err(err) => {
                                eprintln!("{err}");
                                self.notice =
                                    Some("เปิดเกมไม่ได้ ลองอีกครั้ง หรือเปิด FiveM เอง".to_string());
                            }
                        }
                    }
                }
                Task::none()
            }
            Message::OpenInvite => {
                if let Some(url) = profile::invite_url() {
                    if action::safe_link(url) {
                        if let Err(err) = launcher_games::SystemOpener.open(url) {
                            eprintln!("{err}");
                        }
                    }
                }
                Task::none()
            }
            Message::OpenNews(index) => {
                let selected = self.selected.min(self.instances.len().saturating_sub(1));
                if let Some(url) = self
                    .instances
                    .get(selected)
                    .and_then(|inst| inst.news.get(index))
                    .and_then(|item| item.url.as_deref())
                {
                    if action::safe_link(url) {
                        if let Err(err) = launcher_games::SystemOpener.open(url) {
                            eprintln!("{err}");
                        }
                    }
                }
                Task::none()
            }
            Message::ConnectOpen => {
                self.show_connect = true;
                self.connect_status = None;
                if !self.connect_busy {
                    self.connect_code.clear();
                }
                Task::none()
            }
            Message::ConnectClose => {
                if !self.connect_busy {
                    self.show_connect = false;
                    self.connect_code.clear();
                }
                Task::none()
            }
            Message::ConnectCode(code) => {
                if !self.connect_busy {
                    let trimmed = code.trim();
                    if trimmed.len() <= launcher_connect::MAX_CODE_BYTES {
                        self.connect_code = trimmed.to_string();
                    }
                }
                Task::none()
            }
            Message::ConnectStart => {
                if self.connect_busy {
                    return Task::none();
                }
                let Some(exe) = connect::connect_exe() else {
                    self.connect_status = Some(connect::MISSING.to_string());
                    return Task::none();
                };
                self.connect_busy = true;
                self.connect_status = None;
                let code = self.connect_code.clone();
                let (tx, rx) = iced::futures::channel::oneshot::channel();
                std::thread::spawn(move || {
                    let text =
                        match launcher_connect::start_connect(&exe, &code, connect::RUN_TIMEOUT) {
                            Ok(o) => connect::outcome_text(&o),
                            Err(e) => connect::error_text(&e),
                        };
                    let _ = tx.send(text);
                });
                Task::perform(
                    async move {
                        match rx.await {
                            Ok(text) => text,
                            Err(_) => "เปิด Rongroi Connect ไม่ได้".to_string(),
                        }
                    },
                    Message::ConnectDone,
                )
            }
            Message::ConnectDone(text) => {
                self.connect_busy = false;
                self.connect_status = Some(text);
                self.connect_code.clear();
                Task::none()
            }
        }
    }

    fn view(&self) -> Element<'_, Message> {
        let index = self.selected.min(self.instances.len().saturating_sub(1));
        let notice = if index == 0 {
            self.notice.as_deref()
        } else {
            None
        };

        let home: Element<'_, Message> = match profile::template() {
            launcher_core::Template::Dusk => dusk::view(&self.instances, self.selected, notice),
            launcher_core::Template::Classic => self.classic(notice),
        };

        if self.show_privacy {
            container(iced::widget::stack![home, privacy::view()])
                .width(Length::Fill)
                .height(Length::Fill)
                .into()
        } else if self.show_connect {
            container(iced::widget::stack![
                home,
                connect::view(
                    &self.connect_code,
                    self.connect_busy,
                    self.connect_status.as_deref(),
                )
            ])
            .width(Length::Fill)
            .height(Length::Fill)
            .into()
        } else {
            home
        }
    }

    fn classic<'a>(&'a self, notice: Option<&str>) -> Element<'a, Message> {
        let inst = &self.instances[self.selected.min(self.instances.len() - 1)];

        let main = column![topbar::view(), hero::view(inst, notice), board::view(inst),]
            .spacing(16)
            .width(Length::Fill)
            .height(Length::Fill);

        container(
            row![sidebar::view(&self.instances, self.selected), main]
                .spacing(16)
                .width(Length::Fill)
                .height(Length::Fill),
        )
        .padding(16)
        .width(Length::Fill)
        .height(Length::Fill)
        .style(theme::panel(theme::BG, 0.0))
        .into()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn connect_open_and_close_respect_busy_state() {
        let mut app = App {
            connect_status: Some("old".to_string()),
            ..App::default()
        };

        let _ = app.update(Message::ConnectOpen);
        assert!(app.show_connect);
        assert_eq!(app.connect_status, None);

        app.connect_busy = true;
        let _ = app.update(Message::ConnectClose);
        assert!(app.show_connect);

        app.connect_busy = false;
        let _ = app.update(Message::ConnectClose);
        assert!(!app.show_connect);
    }

    #[test]
    fn connect_close_and_reopen_clear_code() {
        let mut app = App::default();
        let _ = app.update(Message::ConnectOpen);
        let _ = app.update(Message::ConnectCode("rr1.abc".to_string()));
        assert_eq!(app.connect_code, "rr1.abc");

        let _ = app.update(Message::ConnectClose);
        assert!(!app.show_connect);
        assert_eq!(app.connect_code, "");

        let _ = app.update(Message::ConnectOpen);
        assert!(app.show_connect);
        assert_eq!(app.connect_code, "");

        let _ = app.update(Message::ConnectCode("rr1.stale".to_string()));
        let _ = app.update(Message::ConnectOpen);
        assert_eq!(app.connect_code, "");
    }

    #[test]
    fn connect_code_trims_start_caps_length_and_ignores_when_busy() {
        let mut app = App::default();
        let _ = app.update(Message::ConnectCode("  rr1.abc  \n".to_string()));
        assert_eq!(app.connect_code, "rr1.abc");

        let max = format!("rr1.{}", "a".repeat(4092));
        assert_eq!(max.len(), 4096);
        let _ = app.update(Message::ConnectCode(max.clone()));
        assert_eq!(app.connect_code, max);

        let too_long = format!("rr1.{}", "b".repeat(4093));
        assert_eq!(too_long.len(), 4097);
        let _ = app.update(Message::ConnectCode(too_long));
        assert_eq!(app.connect_code, max);

        app.connect_busy = true;
        let _ = app.update(Message::ConnectCode("rr1.other".to_string()));
        assert_eq!(app.connect_code, max);
    }

    #[test]
    fn connect_start_while_busy_leaves_state_unchanged() {
        let mut app = App {
            connect_busy: true,
            connect_code: "rr1.abc".to_string(),
            connect_status: Some("กำลังทำงาน".to_string()),
            ..App::default()
        };

        let _ = app.update(Message::ConnectStart);
        assert!(app.connect_busy);
        assert_eq!(app.connect_code, "rr1.abc");
        assert_eq!(app.connect_status.as_deref(), Some("กำลังทำงาน"));
    }

    #[test]
    fn connect_start_without_connect_binary_sets_missing_status() {
        let mut app = App {
            connect_code: "rr1.abc".to_string(),
            ..App::default()
        };

        let _ = app.update(Message::ConnectStart);
        assert!(!app.connect_busy);
        assert_eq!(app.connect_status.as_deref(), Some(connect::MISSING));
    }

    #[test]
    fn connect_done_clears_busy_and_code_and_sets_status() {
        let mut app = App {
            connect_busy: true,
            connect_code: "rr1.secret".to_string(),
            ..App::default()
        };

        let _ = app.update(Message::ConnectDone("ส่งผลตรวจให้ทีมงานแล้ว".to_string()));
        assert!(!app.connect_busy);
        assert_eq!(app.connect_code, "");
        assert_eq!(app.connect_status.as_deref(), Some("ส่งผลตรวจให้ทีมงานแล้ว"));
    }
}
