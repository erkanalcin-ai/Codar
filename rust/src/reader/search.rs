//! Full-text search mapped to FRB DTOs carrying CFI anchors.

use serde::{Deserialize, Serialize};

/// One hit. `cfi` + `section_index` + `char_offset` restore the location
/// through the same locator model as bookmarks/progress.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchHit {
    pub section_index: u64,
    pub cfi: String,
    pub char_offset: u64,
    pub snippet: String,
}

pub fn search(book: &ebook_rs::Book, query: &str) -> Vec<SearchHit> {
    book.search(query)
        .into_iter()
        .map(|h| SearchHit {
            section_index: h.spine_index as u64,
            cfi: h.cfi,
            char_offset: h.char_offset as u64,
            snippet: h.snippet,
        })
        .collect()
}
