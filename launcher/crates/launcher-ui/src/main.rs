// SPDX-License-Identifier: MIT

#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

mod action;
mod board;
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
            &format!("{}-launcher/{}", profile.server.id, env!("CARGO_PKG_VERSION")),
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
}

impl App {
    fn update(&mut self, message: Message) {
        match message {
            Message::Select(index) => self.selected = index,
            Message::Noop => {}
            Message::PrivacyOk => {
                self.show_privacy = false;

                if let Some(dir) = &self.state_dir {
                    let _ = launcher_core::first_run::mark_seen(dir);
                }
            }
            Message::FeedLoaded(Ok(feed)) => {
                self.instances = model::instances(profile::get(), Some(&feed));
                self.selected = self.selected.min(self.instances.len().saturating_sub(1));
            }
            Message::FeedLoaded(Err(err)) => {
                eprintln!("{err}");
            }
            Message::Play => {
                let index = self.selected.min(self.instances.len().saturating_sub(1));
                if let Some(inst) = self.instances.get(index) {
                    if action::can_play(inst) {
                        match launcher_games::join(profile::get(), &launcher_games::SystemOpener) {
                            Ok(_) => {
                                self.notice = None;
                            }
                            Err(err) => {
                                eprintln!("{err}");
                                self.notice = Some(
                                    "เปิดเกมไม่ได้ ลองอีกครั้ง หรือเปิด FiveM เอง".to_string(),
                                );
                            }
                        }
                    }
                }
            }
            Message::OpenInvite => {
                if let Some(url) = profile::invite_url() {
                    if action::safe_link(url) {
                        if let Err(err) = launcher_games::SystemOpener.open(url) {
                            eprintln!("{err}");
                        }
                    }
                }
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
