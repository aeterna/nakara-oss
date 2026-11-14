// SPDX-License-Identifier: MIT

use crate::Message;
use iced::widget::svg;
use iced::{Color, Element, Length};

#[derive(Clone, Copy)]
pub enum Icon {
    Play,
    More,
    Chevron,
    Shield,
    Folder,
    User,
    Sliders,
    Chat,
    Globe,
    AddUser,
}

const PLAY: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path d="M8 5.3 19 12 8 18.7Z" fill="black"/></svg>"#;

const MORE: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><circle cx="5.5" cy="12" r="1.8" fill="black"/><circle cx="12" cy="12" r="1.8" fill="black"/><circle cx="18.5" cy="12" r="1.8" fill="black"/></svg>"#;

const CHEVRON: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M9 6l6 6-6 6"/></svg>"#;

const SHIELD: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3.2 18.7 5.9v5.8c0 4.1-2.8 7-6.7 8.4-3.9-1.4-6.7-4.3-6.7-8.4V5.9z"/></svg>"#;

const FOLDER: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 8a2 2 0 0 1 2-2h3.6l2 2h7.4a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/></svg>"#;

const USER: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8" r="3.6"/><path d="M5.2 20c0-3.2 3.1-5.4 6.8-5.4s6.8 2.2 6.8 5.4"/></svg>"#;

const SLIDERS: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4 7h16M4 12h16M4 17h16"/><circle cx="9" cy="7" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="8" cy="17" r="2"/></svg>"#;

const CHAT: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><path d="M4.5 6.5h15v10h-9l-4 3.2v-3.2h-2z"/></svg>"#;

const GLOBE: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="8.4"/><path d="M3.6 12h16.8M12 3.6c2.4 2.4 3.6 5.2 3.6 8.4S14.4 18 12 20.4C9.6 18 8.4 15.2 8.4 12S9.6 6 12 3.6z"/></svg>"#;

const ADD_USER: &str = r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="black" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="10" cy="8" r="3.6"/><path d="M3.8 20c0-3.2 2.8-5.4 6.2-5.4 1.2 0 2.3.3 3.2.8"/><path d="M18 9v6M15 12h6"/></svg>"#;

pub fn icon<'a>(which: Icon, size: f32, color: Color) -> Element<'a, Message> {
    let data: &'static str = match which {
        Icon::Play => PLAY,
        Icon::More => MORE,
        Icon::Chevron => CHEVRON,
        Icon::Shield => SHIELD,
        Icon::Folder => FOLDER,
        Icon::User => USER,
        Icon::Sliders => SLIDERS,
        Icon::Chat => CHAT,
        Icon::Globe => GLOBE,
        Icon::AddUser => ADD_USER,
    };

    svg(svg::Handle::from_memory(data.as_bytes()))
        .width(Length::Fixed(size))
        .height(Length::Fixed(size))
        .style(move |_theme, _status| svg::Style { color: Some(color) })
        .into()
}
