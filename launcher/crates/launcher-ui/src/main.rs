// SPDX-License-Identifier: MIT

#![cfg_attr(target_os = "windows", windows_subsystem = "windows")]

mod board;
mod hero;
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
        .window_size((1280.0, 780.0))
        .font(include_bytes!("../../../assets/Anuphan.ttf").as_slice())
        .default_font(iced::Font::with_name("Anuphan"))
        .run()
}

pub struct App {
    selected: usize,
}

impl Default for App {
    fn default() -> Self {
        Self { selected: 0 }
    }
}

#[derive(Debug, Clone)]
pub enum Message {
    Select(usize),
    Noop,
}

impl App {
    fn update(&mut self, message: Message) {
        match message {
            Message::Select(index) => self.selected = index,
            Message::Noop => {}
        }
    }

    fn view(&self) -> Element<'_, Message> {
        let instances: &'static [sample::Instance; 4] = &sample::INSTANCES;
        let inst = &instances[self.selected];

        let main = column![
            topbar::view(),
            hero::view(inst),
            board::view(inst),
        ]
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
