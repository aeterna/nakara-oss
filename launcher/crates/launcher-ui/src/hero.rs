// SPDX-License-Identifier: MIT

use crate::{sample::Instance, Message};
use iced::Element;

pub fn view<'a>(inst: &'a Instance) -> Element<'a, Message> {
    crate::text::label(inst.name, 52.0, crate::theme::T1).into()
}
