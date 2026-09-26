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

/// Opens PDF structure and page count without converting every page to text.
/// Page text is extracted by the reader session only when requested.
pub fn open_pdf_lazy(
    path: &Path,
) -> Result<(Book, pdf_oxide::PdfDocument, usize), ebook_rs::EbookError> {
    let document = pdf_oxide::PdfDocument::open(path)
        .map_err(|e| ebook_rs::EbookError::InvalidFormat(format!("cannot open PDF: {e}")))?;
    let page_count = document
        .page_count()
        .map_err(|e| ebook_rs::EbookError::InvalidFormat(format!("cannot count PDF pages: {e}")))?;
    if page_count == 0 {
        return Err(ebook_rs::EbookError::InvalidFormat(
            "PDF document contains 0 pages".to_string(),
        ));
    }

    let title = title_fallback(path);
    let metadata = ebook_rs::Metadata {
        title,
        creators: vec!["PDF Document".to_string()],
        languages: vec!["en".to_string()],
        description: Some(format!("PDF Document ({page_count} pages)")),
        subjects: vec!["PDF".to_string()],
        ..Default::default()
    };
    let mut spine = Vec::with_capacity(page_count);
    let mut toc = Vec::with_capacity(page_count);
    let mut sections = Vec::with_capacity(page_count);
    for index in 0..page_count {
        let idref = format!("page_{}", index + 1);
        let href = format!("page_{}.html", index + 1);
        spine.push(ebook_rs::SpineItem {
            index,
            idref: idref.clone(),
            href: href.clone(),
            linear: true,
            media_type: "application/xhtml+xml".to_string(),
            properties: Vec::new(),
        });
        toc.push(ebook_rs::NavPoint {
            id: format!("toc_{}", index + 1),
            label: format!("Page {}", index + 1),
            href: href.clone(),
            full_path: href.clone(),
            subitems: Vec::new(),
        });
        sections.push(ebook_rs::Section {
            index,
            idref,
            href: href.clone(),
            full_path: href,
            raw_html: String::new(),
            processed_html: String::new(),
            plain_text: String::new(),
            plain_text_lower: String::new(),
            char_count: 0,
            viewport_width: None,
            viewport_height: None,
        });
    }
    let mut book = Book {
        archive: ebook_rs::EpubArchive::empty(),
        opf: ebook_rs::opf::OpfPackage {
            version: "3.0".to_string(),
            opf_path: "content.opf".to_string(),
            opf_dir: String::new(),
            metadata,
            manifest: Default::default(),
            spine,
            guide: Vec::new(),
            toc_item_id: None,
            nav_item_id: None,
        },
        toc,
        landmarks: Vec::new(),
        page_list: Vec::new(),
        sections,
        locations: Default::default(),
        annotations: Default::default(),
        layout: Default::default(),
        font_deobfuscator: ebook_rs::FontDeobfuscator::parse_encryption_xml(""),
        before_display_hooks: Vec::new(),
        media_overlays: Default::default(),
        render_cache: Default::default(),
    };
    book.generate_locations(1000);
    Ok((book, document, page_count))
}

pub fn stable_pdf_fingerprint(bytes: &[u8]) -> String {
    let mut first = 0x811c9dc5u32;
    let mut second = 0x9e3779b9u32;
    for byte in bytes {
        first = (first ^ u32::from(*byte)).wrapping_mul(0x01000193);
        second = (second ^ u32::from(*byte ^ 0xa5)).wrapping_mul(0x01000193);
    }
    format!("pdf_{first:08x}{second:08x}_{}", bytes.len())
}

fn title_fallback(path: &Path) -> String {
    path.file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Untitled")
        .to_string()
}
