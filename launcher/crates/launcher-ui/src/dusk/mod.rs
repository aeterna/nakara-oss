// SPDX-License-Identifier: MIT

pub mod board;
pub mod glass;
pub mod hero;
pub mod icons;
pub mod sidebar;
pub mod topbar;

use crate::model::Instance;
use crate::theme;
use crate::Message;
use iced::widget::{column, container, row, stack, svg, Space};
use iced::{ContentFit, Element, Length};

pub fn view<'a>(
    instances: &'a [Instance],
    selected: usize,
    notice: Option<&str>,
) -> Element<'a, Message> {
    let inst = &instances[selected.min(instances.len() - 1)];

    let scene = svg(svg::Handle::from_memory(
        include_bytes!("../../../../assets/scenes/dusk.svg").as_slice(),
    ))
    .width(Length::Fill)
    .height(Length::Fill)
    .content_fit(ContentFit::Cover);

    let main = column![
        topbar::view(),
        hero::view(inst, notice),
        Space::new().height(Length::Fill),
        board::view(inst),
    ]
    .spacing(0)
    .width(Length::Fill)
    .height(Length::Fill);

    let content = container(
        row![sidebar::view(instances, selected), main]
            .spacing(32)
            .width(Length::Fill)
            .height(Length::Fill),
    )
    .padding(16)
    .width(Length::Fill)
    .height(Length::Fill);

    container(stack![scene, content])
        .width(Length::Fill)
        .height(Length::Fill)
        .style(theme::panel(theme::rgb(0x07121a), 0.0))
        .into()
}
