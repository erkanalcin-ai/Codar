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

    let title = pdf_info_text(&document, "Title")
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| title_fallback(path));
    let author = pdf_info_text(&document, "Author").filter(|value| !value.trim().is_empty());
    let metadata = ebook_rs::Metadata {
        title,
        creators: author.into_iter().collect(),
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

fn pdf_info_text(document: &pdf_oxide::PdfDocument, key: &str) -> Option<String> {
    let info = document.trailer().as_dict()?.get("Info")?;
    let info_object = match info {
        pdf_oxide::object::Object::Reference(reference) => document.load_object(*reference).ok()?,
        direct => direct.clone(),
    };
    let bytes = info_object.as_dict()?.get(key)?.as_string()?;
    decode_pdf_text(bytes)
}

fn decode_pdf_text(bytes: &[u8]) -> Option<String> {
    let decoded = if bytes.starts_with(&[0xFE, 0xFF]) {
        let units = bytes[2..]
            .chunks_exact(2)
            .map(|pair| u16::from_be_bytes([pair[0], pair[1]]))
            .collect::<Vec<_>>();
        String::from_utf16(&units).ok()?
    } else if bytes.starts_with(&[0xFF, 0xFE]) {
        let units = bytes[2..]
            .chunks_exact(2)
            .map(|pair| u16::from_le_bytes([pair[0], pair[1]]))
            .collect::<Vec<_>>();
        String::from_utf16(&units).ok()?
    } else {
        bytes.iter().map(|byte| decode_pdfdoc_byte(*byte)).collect()
    };
    let decoded = decoded.trim_matches('\0').trim().to_string();
    (!decoded.is_empty()).then_some(decoded)
}

fn decode_pdfdoc_byte(byte: u8) -> char {
    match byte {
        0x18 => '\u{02D8}',               // BREVE
        0x19 => '\u{02C7}',               // CARON
        0x1A => '\u{02C6}',               // MODIFIER LETTER CIRCUMFLEX ACCENT
        0x1B => '\u{02D9}',               // DOT ABOVE
        0x1C => '\u{02DD}',               // DOUBLE ACUTE ACCENT
        0x1D => '\u{02DB}',               // OGONEK
        0x1E => '\u{02DA}',               // RING ABOVE
        0x1F => '\u{02DC}',               // SMALL TILDE
        0x7F | 0x9F | 0xAD => '\u{FFFD}', // Undefined in PDFDocEncoding.
        0x80 => '\u{2022}',               // BULLET
        0x81 => '\u{2020}',               // DAGGER
        0x82 => '\u{2021}',               // DOUBLE DAGGER
        0x83 => '\u{2026}',               // HORIZONTAL ELLIPSIS
        0x84 => '\u{2014}',               // EM DASH
        0x85 => '\u{2013}',               // EN DASH
        0x86 => '\u{0192}',               // LATIN SMALL LETTER F WITH HOOK
        0x87 => '\u{2044}',               // FRACTION SLASH
        0x88 => '\u{2039}',               // SINGLE LEFT-POINTING ANGLE QUOTATION MARK
        0x89 => '\u{203A}',               // SINGLE RIGHT-POINTING ANGLE QUOTATION MARK
        0x8A => '\u{2212}',               // MINUS SIGN
        0x8B => '\u{2030}',               // PER MILLE SIGN
        0x8C => '\u{201E}',               // DOUBLE LOW-9 QUOTATION MARK
        0x8D => '\u{201C}',               // LEFT DOUBLE QUOTATION MARK
        0x8E => '\u{201D}',               // RIGHT DOUBLE QUOTATION MARK
        0x8F => '\u{2018}',               // LEFT SINGLE QUOTATION MARK
        0x90 => '\u{2019}',               // RIGHT SINGLE QUOTATION MARK
        0x91 => '\u{201A}',               // SINGLE LOW-9 QUOTATION MARK
        0x92 => '\u{2122}',               // TRADE MARK SIGN
        0x93 => '\u{FB01}',               // LATIN SMALL LIGATURE FI
        0x94 => '\u{FB02}',               // LATIN SMALL LIGATURE FL
        0x95 => '\u{0141}',               // LATIN CAPITAL LETTER L WITH STROKE
        0x96 => '\u{0152}',               // LATIN CAPITAL LIGATURE OE
        0x97 => '\u{0160}',               // LATIN CAPITAL LETTER S WITH CARON
        0x98 => '\u{0178}',               // LATIN CAPITAL LETTER Y WITH DIAERESIS
        0x99 => '\u{017D}',               // LATIN CAPITAL LETTER Z WITH CARON
        0x9A => '\u{0131}',               // LATIN SMALL LETTER DOTLESS I
        0x9B => '\u{0142}',               // LATIN SMALL LETTER L WITH STROKE
        0x9C => '\u{0153}',               // LATIN SMALL LIGATURE OE
        0x9D => '\u{0161}',               // LATIN SMALL LETTER S WITH CARON
        0x9E => '\u{017E}',               // LATIN SMALL LETTER Z WITH CARON
        0xA0 => '\u{20AC}',               // EURO SIGN
        _ => char::from(byte),
    }
}

#[cfg(test)]
mod tests {
    use super::decode_pdf_text;

    #[test]
    fn decodes_pdf_info_utf16_and_latin_text() {
        assert_eq!(
            decode_pdf_text(&[0xFE, 0xFF, 0x00, b'C', 0x00, 0x6F]),
            Some("Co".into())
        );
        assert_eq!(decode_pdf_text(&[b'K', 0xFC, b'r']), Some("Kür".into()));
        assert_eq!(decode_pdf_text(&[b' ', b' ', 0]), None);
    }

    #[test]
    fn decodes_pdfdoc_encoding_special_and_undefined_bytes() {
        assert_eq!(decode_pdf_text(&[0x80]), Some("•".into()));
        assert_eq!(decode_pdf_text(&[0xA0]), Some("€".into()));
        assert_eq!(decode_pdf_text(&[0x85]), Some("–".into()));
        assert_eq!(decode_pdf_text(&[0x7F]), Some("�".into()));
    }
}
