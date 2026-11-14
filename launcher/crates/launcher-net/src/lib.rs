// SPDX-License-Identifier: MIT

//! Feed fetch and the network gate (ADR 0002 decision 5)

pub mod feed;
pub mod image;
pub mod policy;

pub use image::{check_image_header, MAX_IMAGE_BYTES, MAX_IMAGE_PIXELS};
pub use policy::{CheckedUrl, NetError, NetPolicy, Role};
