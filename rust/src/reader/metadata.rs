//! FRB-facing DTOs for document info and chapters (spine/TOC mapping).

use serde::{Deserialize, Serialize};

/// Document-level info. Plain data only — no engine types cross FRB.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentInfo {
    pub title: String,
    pub authors: Vec<String>,
    pub language: Option<String>,
    pub description: Option<String>,
    pub format: String,
    pub section_count: u64,
    pub has_cover: bool,
    pub fingerprint: String,
}

/// One navigable chapter: TOC entry preferred, spine fallback.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChapterInfo {
    pub index: u64,
    pub title: String,
    pub href: String,
    pub depth: u64,
}

pub fn document_info(
    book: &ebook_rs::Book,
    format: crate::reader::format::BookFormat,
) -> DocumentInfo {
    let md = book.metadata();
    DocumentInfo {
        title: md.title.clone(),
        authors: md.creators.clone(),
        language: md.languages.first().cloned(),
        description: md.description.clone(),
        format: format.as_str().to_string(),
        section_count: book.sections().len() as u64,
        has_cover: book.cover_image().is_some(),
        fingerprint: format!("{:?}", book.fingerprint()),
    }
}

/// Chapters from the TOC tree (depth-first); falls back to spine order when
/// the TOC is empty (e.g. PDF/CBZ converters emit per-page TOC — still fine).
pub fn chapters(book: &ebook_rs::Book) -> Vec<ChapterInfo> {
    let mut out = Vec::new();
    if book.toc().is_empty() {
        for item in book.spine() {
            out.push(ChapterInfo {
                index: item.index as u64,
                title: item.idref.clone(),
                href: item.href.clone(),
                depth: 0,
            });
        }
        return out;
    }
    let mut stack: Vec<(&ebook_rs::NavPoint, u64)> = book.toc().iter().map(|n| (n, 0)).collect();
    // Preserve document order while walking depth-first.
    stack.reverse();
    let mut counter = 0u64;
    while let Some((node, depth)) = stack.pop() {
        out.push(ChapterInfo {
            index: counter,
            title: node.label.clone(),
            href: node.href.clone(),
            depth,
        });
        counter += 1;
        for child in node.subitems.iter().rev() {
            stack.push((child, depth + 1));
        }
    }
    out
}
