//! TEMPORARY stand-ins for platforms/core. Replace this whole module with an
//! adapter over the real core crate; keep the trait impls in `core_api`.
pub mod relay_http;
pub mod recognizer;
pub mod secret;
pub mod config;
pub mod history;
