// SPDX-License-Identifier: MIT

//! Core types and validation for the launcher's server profile.
//!
//! The profile is data only (ADR 0002 decision 3): `server.toml` is embedded at
//! build time and describes the server, theme and feature flags. It never holds
//! HTML, scripts, plugins or executables.

pub mod profile;

pub use profile::{
    parse, validate, Features, Game, Profile, ProfileError, Server, Template, Theme,
};
