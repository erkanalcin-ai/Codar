//! Section/page content access plus deterministic reflow pagination.

use serde::{Deserialize, Serialize};

/// Render-ready section payload. `html` is library-processed section HTML;
/// the Flutter renderer sanitizes it and never executes scripts.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectionContent {
    pub index: u64,
    pub idref: String,
    pub href: String,
    pub html: String,
    pub plain_text: String,
    pub char_count: u64,
}

/// Deterministic pagination outcome for one section.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaginationResult {
    pub section_index: u64,
    pub total_pages: u64,
    pub page_map_debug: String,
    pub is_rtl: bool,
}

pub fn section_content(book: &ebook_rs::Book, index: usize) -> Option<SectionContent> {
    book.get_section(index).ok().map(|s| SectionContent {
        index: index as u64,
        idref: s.idref.clone(),
        href: s.href.clone(),
        html: s.processed_html.clone(),
        plain_text: s.plain_text.clone(),
        char_count: s.char_count as u64,
    })
}

/// Paginate with explicit typography/viewport parameters. Identical inputs
/// must yield identical outputs (Phase 1 determinism gate).
#[allow(clippy::too_many_arguments)]
pub fn paginate_section(
    book: &ebook_rs::Book,
    index: usize,
    font_size_px: u32,
    line_height: f32,
    viewport_width_px: u32,
    viewport_height_px: u32,
    margin_px: u32,
) -> Option<PaginationResult> {
    let section = book.get_section(index).ok()?;
    let paginator = ebook_rs::ReflowPaginator::new(
        font_size_px,
        line_height,
        viewport_width_px,
        viewport_height_px,
        margin_px,
    );
    let map = paginator.paginate_section(&section);
    Some(PaginationResult {
        section_index: index as u64,
        total_pages: map.total_pages as u64,
        page_map_debug: format!("{map:?}"),
        is_rtl: map.is_rtl,
    })
}
