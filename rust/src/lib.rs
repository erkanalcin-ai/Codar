//! Codar Rust Reader Core.
//!
//! Sole owner of `ebook-rs` usage. Flutter must only talk to this crate
//! through the `api` module (flutter_rust_bridge boundary).

/* AUTO INJECTED BY flutter_rust_bridge (moved below crate docs). */
mod frb_generated;

pub mod annotations;
pub mod api;
pub mod bridge;
pub mod formats;
pub mod locator;
pub mod reader;
