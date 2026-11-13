// SPDX-License-Identifier: MIT

#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

mod board;
mod dusk;
mod hero;
mod privacy;
mod sample;
mod sidebar;
mod text;
mod theme;
mod topbar;

use iced::widget::{column, container, row};
use iced::{Element, Length};

fn main() -> iced::Result {
    iced::application(App::default, App::update, App::view)
        .title("AETERNA Game Launcher")
        .window_size((1280.0, 800.0))
        .font(include_bytes!("../../../assets/Anuphan.ttf").as_slice())
        .default_font(iced::Font::with_name("Anuphan"))
        .run()
}

pub struct App {
    selected: usize,
    state_dir: Option<std::path::PathBuf>,
    show_privacy: bool,
}

impl Default for App {
    fn default() -> Self {
        let state_dir = dirs::config_dir().map(|d| d.join("AETERNA Game Launcher"));
        let show_privacy = match &state_dir {
            Some(d) => !launcher_core::first_run::seen(d),
            None => true,
        };

        Self {
            selected: 0,
            state_dir,
            show_privacy,
        }
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    Select(usize),
    Noop,
    PrivacyOk,
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
        }
    }

    fn view(&self) -> Element<'_, Message> {
        let home: Element<'_, Message> = match sample::TEMPLATE {
            launcher_core::Template::Dusk => dusk::view(self.selected),
            launcher_core::Template::Classic => self.classic(),
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

    fn classic(&self) -> Element<'_, Message> {
        let instances: &'static [sample::Instance; 4] = &sample::INSTANCES;
        let inst = &instances[self.selected];

        let main = column![topbar::view(), hero::view(inst), board::view(inst),]
            .spacing(16)
            .width(Length::Fill)
            .height(Length::Fill);

        container(
            row![sidebar::view(self.selected), main]
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
