// SPDX-License-Identifier: MIT

//! Feed fetch and the network gate (ADR 0002 decision 5)
//!
//! This crate has no HTTP client. A caller that fetches must re-check every
//! redirect with [`policy::NetPolicy::check_url`], connect only to an address
//! that passed [`policy::NetPolicy::check_ip`], and cap the body size while
//! streaming.

pub mod feed;
pub mod image;
pub mod policy;

pub use image::{check_image_header, MAX_IMAGE_BYTES, MAX_IMAGE_PIXELS};
pub use policy::{CheckedUrl, NetError, NetPolicy, Role};
