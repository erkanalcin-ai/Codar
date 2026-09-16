//! Book format detection and dispatch into the unified `ebook_rs::Book`.
//!
//! Every supported format funnels into `Book`; Flutter never sees engine types.

use ebook_rs::{Book, CbzBook, PdfBook, TxtBook};

use std::path::Path;

/// Formats Codar Phase 1 targets. CBR/RAR is explicitly out of scope.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BookFormat {
    Epub,
    Mobi,
    Azw3,
    Fb2,
    Lit,
    Cbz,
    Pdf,
    Txt,
    Markdown,
}

impl BookFormat {
    pub fn as_str(self) -> &'static str {
        match self {
            BookFormat::Epub => "epub",
            BookFormat::Mobi => "mobi",
            BookFormat::Azw3 => "azw3",
            BookFormat::Fb2 => "fb2",
            BookFormat::Lit => "lit",
            BookFormat::Cbz => "cbz",
            BookFormat::Pdf => "pdf",
            BookFormat::Txt => "txt",
            BookFormat::Markdown => "md",
        }
    }

    /// Extension-based detection. Magic-byte detection lives inside ebook-rs
    /// (`Book::from_bytes`); the extension only selects the converter funnel.
    pub fn detect(path: &Path) -> Result<Self, String> {
        let ext = path
            .extension()
            .and_then(|e| e.to_str())
            .unwrap_or("")
            .to_lowercase();
        match ext.as_str() {
            "epub" | "kepub" => Ok(BookFormat::Epub),
            "mobi" => Ok(BookFormat::Mobi),
            "azw3" | "azw" | "kf8" => Ok(BookFormat::Azw3),
            "fb2" => Ok(BookFormat::Fb2),
            "lit" => Ok(BookFormat::Lit),
            "cbz" => Ok(BookFormat::Cbz),
            "pdf" => Ok(BookFormat::Pdf),
            "txt" => Ok(BookFormat::Txt),
            "md" | "markdown" => Ok(BookFormat::Markdown),
            other => Err(format!("unsupported book extension: '{other}'")),
        }
    }
}

/// Open any supported file into a unified [`Book`].
pub fn open_unified(path: &Path, format: BookFormat) -> Result<Book, ebook_rs::EbookError> {
    match format {
        BookFormat::Pdf => {
            let bytes = std::fs::read(path).map_err(|e| {
                ebook_rs::EbookError::InvalidFormat(format!("cannot read PDF file: {e}"))
            })?;
            let title = title_fallback(path);
            PdfBook::parse(&bytes, &title)
        }
        BookFormat::Txt => {
            let bytes = std::fs::read(path).map_err(|e| {
                ebook_rs::EbookError::InvalidFormat(format!("cannot read TXT file: {e}"))
            })?;
            TxtBook::parse(&bytes, &title_fallback(path), false)
        }
        BookFormat::Markdown => {
            let bytes = std::fs::read(path).map_err(|e| {
                ebook_rs::EbookError::InvalidFormat(format!("cannot read Markdown file: {e}"))
            })?;
            TxtBook::parse(&bytes, &title_fallback(path), true)
        }
        BookFormat::Cbz => {
            let bytes = std::fs::read(path).map_err(|e| {
                ebook_rs::EbookError::InvalidFormat(format!("cannot read CBZ file: {e}"))
            })?;
            CbzBook::parse(&bytes, &title_fallback(path))
        }
        // EPUB-family, MOBI, AZW3, FB2, LIT: native `Book` loaders.
        _ => Book::from_file(path),
    }
}

fn title_fallback(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Untitled")
        .to_string()
}
