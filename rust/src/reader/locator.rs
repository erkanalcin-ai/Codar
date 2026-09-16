//! CFI-first locators: Readium JSON is the persisted form.

use serde::{Deserialize, Serialize};

/// A restored position: section + CFI + href. The CFI string is the stable
/// anchor; section index is the fast path for content fetching.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RestoredLocation {
    pub section_index: u64,
    pub cfi: String,
    pub href: String,
}

/// Progress snapshot: library-native progression values (supplementary)
/// plus the authoritative locator JSON (primary restore key).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProgressInfo {
    pub section_index: u64,
    pub char_offset: u64,
    pub progression: f64,
    pub total_progression: f64,
    pub locator_json: String,
}

/// Build the canonical Readium locator JSON for (section, offset).
pub fn make_locator_json(
    book: &ebook_rs::Book,
    section_index: usize,
    char_offset: usize,
) -> Result<String, String> {
    let locator = book
        .to_readium_locator(section_index, char_offset)
        .map_err(|e| e.to_string())?;
    serde_json::to_string(&locator).map_err(|e| e.to_string())
}

/// Restore a persisted Readium locator JSON to a live location.
/// Resolution order: embedded CFI → href→spine lookup.
pub fn restore_locator_json(
    book: &ebook_rs::Book,
    locator_json: &str,
) -> Result<RestoredLocation, String> {
    let locator: ebook_rs::ReadiumLocator =
        serde_json::from_str(locator_json).map_err(|e| format!("invalid locator JSON: {e}"))?;

    // Prefer the CFI: resolve it to prove the anchor is live.
    if let Some(cfi) = locator.locations.cfi.clone() {
        if !cfi.is_empty() {
            let section = book
                .get_section_by_cfi(&cfi)
                .map_err(|e| format!("CFI restore failed: {e}"))?;
            let index = section_index_by_href(book, &section.href)
                .ok_or_else(|| format!("CFI resolved but href '{}' not in spine", section.href))?;
            return Ok(RestoredLocation {
                section_index: index as u64,
                cfi,
                href: section.href,
            });
        }
    }

    // Fallback: href → spine index.
    let index = section_index_by_href(book, &locator.href)
        .ok_or_else(|| format!("locator href '{}' not found", locator.href))?;
    Ok(RestoredLocation {
        section_index: index as u64,
        cfi: locator.locations.cfi.unwrap_or_default(),
        href: locator.href,
    })
}

fn section_index_by_href(book: &ebook_rs::Book, href: &str) -> Option<usize> {
    book.spine()
        .iter()
        .position(|s| s.href == href || s.idref == href)
        .or_else(|| {
            book.sections()
                .iter()
                .position(|s| s.href == href || s.idref == href)
        })
}
