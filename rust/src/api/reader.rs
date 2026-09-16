//! Codar Reader API (FRB boundary).
//!
//! Thin by design: session handling + DTO mapping. All parsing, CFI,
//! search and pagination logic is delegated to `ebook-rs` via `reader::*`.

use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::reader::{content, format, locator, metadata, search, session};

// Re-export DTOs so generated bindings carry them.
pub use crate::reader::content::{PaginationResult, SectionContent};
pub use crate::reader::locator::{ProgressInfo, RestoredLocation};
pub use crate::reader::metadata::{ChapterInfo, DocumentInfo};
pub use crate::reader::search::SearchHit;

/// Typed reader errors. No engine internals leak across the bridge.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ReaderError {
    InvalidPath(String),
    UnsupportedFormat(String),
    OpenFailed(String),
    UnknownSession(u64),
    InvalidSection(u64),
    ContentFailed(String),
    SearchFailed(String),
    LocatorFailed(String),
    PaginationFailed(String),
}

impl std::fmt::Display for ReaderError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            ReaderError::InvalidPath(m)
            | ReaderError::UnsupportedFormat(m)
            | ReaderError::OpenFailed(m)
            | ReaderError::ContentFailed(m)
            | ReaderError::SearchFailed(m)
            | ReaderError::LocatorFailed(m)
            | ReaderError::PaginationFailed(m) => write!(f, "{m}"),
            ReaderError::UnknownSession(id) => write!(f, "unknown session: {id}"),
            ReaderError::InvalidSection(i) => write!(f, "invalid section: {i}"),
        }
    }
}

/// Result of opening a book: session handle + first-glance info.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpenBookResult {
    pub session_id: u64,
    pub info: DocumentInfo,
}

/// Open a book file. Creates exactly one session; caller must `close_book`.
pub fn open_book(path: String) -> Result<OpenBookResult, ReaderError> {
    let fs_path = Path::new(&path);
    if !fs_path.is_file() {
        return Err(ReaderError::InvalidPath(format!("not a file: {path}")));
    }
    let fmt = format::BookFormat::detect(fs_path).map_err(ReaderError::UnsupportedFormat)?;
    let book =
        format::open_unified(fs_path, fmt).map_err(|e| ReaderError::OpenFailed(e.to_string()))?;
    let info = metadata::document_info(&book, fmt);
    let session_id = session::insert(book, fmt, path);
    Ok(OpenBookResult { session_id, info })
}

/// Close a session. Idempotent: closing twice reports success with `false`.
pub fn close_book(session_id: u64) -> Result<bool, ReaderError> {
    Ok(session::remove(session_id).is_some())
}

/// Live session count (lifecycle/soak observability).
pub fn live_session_count() -> u64 {
    session::live_count()
}

/// Document info for an open session.
pub fn get_document_info(session_id: u64) -> Result<DocumentInfo, ReaderError> {
    let meta = session::session_meta(session_id).ok_or(ReaderError::UnknownSession(session_id))?;
    session::with_book(session_id, |b| metadata::document_info(b, meta.0))
        .ok_or(ReaderError::UnknownSession(session_id))
}

/// Chapters (TOC depth-first, spine fallback).
pub fn get_chapters(session_id: u64) -> Result<Vec<ChapterInfo>, ReaderError> {
    session::with_book(session_id, metadata::chapters)
        .ok_or(ReaderError::UnknownSession(session_id))
}

/// Section content by spine/section index.
pub fn get_content(session_id: u64, section_index: u64) -> Result<SectionContent, ReaderError> {
    let idx = section_index as usize;
    session::with_book(session_id, |b| content::section_content(b, idx))
        .ok_or(ReaderError::UnknownSession(session_id))?
        .ok_or(ReaderError::InvalidSection(section_index))
}

/// Page access. For PDF/CBZ one section IS one page; for reflowable formats
/// the caller pages via `paginate_section` instead.
pub fn get_page(session_id: u64, page_index: u64) -> Result<SectionContent, ReaderError> {
    get_content(session_id, page_index)
}

/// Full-text search. Every hit carries section index + CFI + char offset.
pub fn search(session_id: u64, query: String) -> Result<Vec<SearchHit>, ReaderError> {
    session::with_book(session_id, |b| search::search(b, &query))
        .ok_or(ReaderError::UnknownSession(session_id))
}

/// Canonical Readium locator JSON for (section, char offset).
pub fn get_locator(
    session_id: u64,
    section_index: u64,
    char_offset: u64,
) -> Result<String, ReaderError> {
    session::with_book(session_id, |b| {
        locator::make_locator_json(b, section_index as usize, char_offset as usize)
    })
    .ok_or(ReaderError::UnknownSession(session_id))?
    .map_err(ReaderError::LocatorFailed)
}

/// Restore a persisted Readium locator JSON to a live location.
pub fn restore_locator(
    session_id: u64,
    locator_json: String,
) -> Result<RestoredLocation, ReaderError> {
    session::with_book(session_id, |b| {
        locator::restore_locator_json(b, &locator_json)
    })
    .ok_or(ReaderError::UnknownSession(session_id))?
    .map_err(ReaderError::LocatorFailed)
}

/// Progress snapshot: authoritative locator JSON + supplementary progression.
pub fn get_progress(
    session_id: u64,
    section_index: u64,
    char_offset: u64,
) -> Result<ProgressInfo, ReaderError> {
    let locator_json = get_locator(session_id, section_index, char_offset)?;
    // Session must still be live; progression values come from the locator itself.
    session::session_meta(session_id).ok_or(ReaderError::UnknownSession(session_id))?;
    let parsed: ebook_rs::ReadiumLocator = serde_json::from_str(&locator_json)
        .map_err(|e: serde_json::Error| ReaderError::LocatorFailed(e.to_string()))?;
    Ok(ProgressInfo {
        section_index,
        char_offset,
        progression: parsed.locations.progression,
        total_progression: parsed.locations.total_progression,
        locator_json,
    })
}

/// Deterministic reflow pagination for one section.
#[allow(clippy::too_many_arguments)]
pub fn paginate_section(
    session_id: u64,
    section_index: u64,
    font_size_px: u32,
    line_height: f32,
    viewport_width_px: u32,
    viewport_height_px: u32,
    margin_px: u32,
) -> Result<PaginationResult, ReaderError> {
    session::with_book(session_id, |b| {
        content::paginate_section(
            b,
            section_index as usize,
            font_size_px,
            line_height,
            viewport_width_px,
            viewport_height_px,
            margin_px,
        )
    })
    .ok_or(ReaderError::UnknownSession(session_id))?
    .ok_or(ReaderError::PaginationFailed(format!(
        "cannot paginate section {section_index}"
    )))
}
