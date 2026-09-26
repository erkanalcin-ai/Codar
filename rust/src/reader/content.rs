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
    pub images: Vec<SectionImage>,
}

/// One lazily retrieved bitmap used by the current section/page.
///
/// HTML-backed formats use `source` to match an image tag to its archive
/// bytes. PDF images use a synthetic source and include page placement data.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SectionImage {
    pub source: String,
    pub mime_type: String,
    pub data: Vec<u8>,
    pub pixel_width: u32,
    pub pixel_height: u32,
    pub data_format: String,
    pub left: f32,
    pub top: f32,
    pub display_width: f32,
    pub display_height: f32,
    pub page_width: f32,
    pub page_height: f32,
    pub rotation_degrees: i32,
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
    let section = book.get_section(index).ok()?;
    let html = section.processed_html.clone();
    let images = section_html_images(book, &section.full_path, &html);
    Some(SectionContent {
        index: index as u64,
        idref: section.idref,
        href: section.href,
        html,
        plain_text: section.plain_text,
        char_count: section.char_count as u64,
        images,
    })
}

/// Extract exactly one PDF page and return the same text payload used by the
/// non-PDF readers. The PDF document remains file-session scoped and its
/// parser keeps only bounded internal object caches.
pub fn pdf_page_content(
    document: &pdf_oxide::PdfDocument,
    index: usize,
) -> Result<SectionContent, String> {
    let page = index + 1;
    let markdown_result = document.to_markdown(index, &Default::default());
    let raw_markdown = match markdown_result {
        Ok(markdown) => markdown,
        Err(_) => {
            document.extract_text(index).map_err(|e| e.to_string())?
        }
    };
    let markdown = ebook_rs::pdf::reflow_two_column_markdown(&raw_markdown);
    let html = pdf_markdown_to_html(&markdown, page);
    let plain_text = ebook_rs::section::extract_plain_text(&html);
    let images = if plain_text.trim().is_empty() {
        pdf_page_images(document, index)
    } else {
        Vec::new()
    };
    Ok(SectionContent {
        index: index as u64,
        idref: format!("page_{}", index + 1),
        href: format!("page_{}.html", index + 1),
        char_count: plain_text.chars().count() as u64,
        html,
        plain_text,
        images,
    })
}

fn section_html_images(
    book: &ebook_rs::Book,
    section_path: &str,
    html: &str,
) -> Vec<SectionImage> {
    let base_dir = section_path.rsplit_once('/').map_or("", |(dir, _)| dir);
    let mut seen = std::collections::HashSet::new();
    let mut images = Vec::new();

    for source in image_sources(html) {
        let source = decode_basic_html_entities(&source);
        let lower = source.to_ascii_lowercase();
        if lower.starts_with("data:")
            || lower.starts_with("http:")
            || lower.starts_with("https:")
            || lower.starts_with("//")
            || source.starts_with('#')
        {
            continue;
        }

        let clean_source = source.split(['?', '#']).next().unwrap_or_default();
        if clean_source.is_empty() || !seen.insert(source.clone()) {
            continue;
        }

        let mut candidates = vec![
            ebook_rs::archive::resolve_relative_path("", clean_source),
            ebook_rs::archive::resolve_relative_path(base_dir, clean_source),
        ];
        let opf_dir = book.opf().opf_dir.trim_matches('/');
        if !opf_dir.is_empty() {
            candidates.push(ebook_rs::archive::resolve_relative_path(
                opf_dir,
                clean_source,
            ));
        }
        candidates.push(ebook_rs::archive::resolve_relative_path(
            "OEBPS",
            clean_source,
        ));
        if let Some(image_index) = kindle_embed_index(&source) {
            let image_dir = if opf_dir.is_empty() {
                "OEBPS"
            } else {
                opf_dir
            };
            for extension in ["jpg", "jpeg", "png", "gif", "webp", "bmp"] {
                candidates.push(format!(
                    "{image_dir}/images/img_{image_index:04}.{extension}"
                ));
            }
        }
        candidates.dedup();

        let resource = candidates
            .iter()
            .find_map(|path| book.get_resource_bytes(path).ok());
        let Some((data, mime)) = resource else {
            continue;
        };
        if !mime.starts_with("image/") {
            continue;
        }
        images.push(SectionImage {
            source,
            mime_type: mime.to_string(),
            data,
            pixel_width: 0,
            pixel_height: 0,
            data_format: "encoded".to_string(),
            left: 0.0,
            top: 0.0,
            display_width: 0.0,
            display_height: 0.0,
            page_width: 0.0,
            page_height: 0.0,
            rotation_degrees: 0,
        });
    }

    images
}

fn kindle_embed_index(source: &str) -> Option<usize> {
    let clean_source = source.split(['?', '#']).next().unwrap_or_default();
    let suffix = clean_source
        .get(.."kindle:embed:".len())
        .filter(|prefix| prefix.eq_ignore_ascii_case("kindle:embed:"))
        .and_then(|_| clean_source.get("kindle:embed:".len()..))?;
    let index = usize::from_str_radix(suffix, 36).ok()?;
    (index > 0).then_some(index)
}

fn image_sources(html: &str) -> Vec<String> {
    let lower = html.to_ascii_lowercase();
    let mut sources = Vec::new();
    let mut cursor = 0;
    while let Some(relative_start) = lower[cursor..].find("<img") {
        let start = cursor + relative_start;
        let Some(relative_end) = html[start..].find('>') else {
            break;
        };
        let end = start + relative_end + 1;
        if let Some(source) = html_attribute(&html[start..end], "src") {
            sources.push(source);
        }
        cursor = end;
    }
    sources
}

fn html_attribute(tag: &str, wanted: &str) -> Option<String> {
    let bytes = tag.as_bytes();
    let mut cursor = tag.find(char::is_whitespace).unwrap_or(tag.len());
    while cursor < bytes.len() {
        while cursor < bytes.len() && (bytes[cursor].is_ascii_whitespace() || bytes[cursor] == b'/')
        {
            cursor += 1;
        }
        let name_start = cursor;
        while cursor < bytes.len()
            && !bytes[cursor].is_ascii_whitespace()
            && !matches!(bytes[cursor], b'=' | b'/' | b'>')
        {
            cursor += 1;
        }
        if name_start == cursor {
            cursor += 1;
            continue;
        }
        let name = &tag[name_start..cursor];
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if cursor >= bytes.len() || bytes[cursor] != b'=' {
            continue;
        }
        cursor += 1;
        while cursor < bytes.len() && bytes[cursor].is_ascii_whitespace() {
            cursor += 1;
        }
        if cursor >= bytes.len() {
            break;
        }
        let quote = if matches!(bytes[cursor], b'\'' | b'"') {
            let quote = bytes[cursor];
            cursor += 1;
            Some(quote)
        } else {
            None
        };
        let value_start = cursor;
        if let Some(quote) = quote {
            while cursor < bytes.len() && bytes[cursor] != quote {
                cursor += 1;
            }
        } else {
            while cursor < bytes.len() && !bytes[cursor].is_ascii_whitespace() && bytes[cursor] != b'>' {
                cursor += 1;
            }
        }
        if name.eq_ignore_ascii_case(wanted) {
            return Some(tag[value_start..cursor].to_string());
        }
        if quote.is_some() && cursor < bytes.len() {
            cursor += 1;
        }
    }
    None
}

fn decode_basic_html_entities(value: &str) -> String {
    value
        .replace("&amp;", "&")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'")
}

fn pdf_page_images(document: &pdf_oxide::PdfDocument, index: usize) -> Vec<SectionImage> {
    let media_box = document.get_page_media_box(index).unwrap_or_default();
    let page_width = (media_box.2 - media_box.0).max(0.0);
    let page_height = (media_box.3 - media_box.1).max(0.0);

    document
        .extract_images(index)
        .unwrap_or_default()
        .into_iter()
        .enumerate()
        .filter_map(|(image_index, image)| {
            let (mime_type, data, data_format) = match image.data() {
                pdf_oxide::extractors::ImageData::Jpeg(bytes) if !bytes.is_empty() => {
                    ("image/jpeg", bytes.clone(), "encoded")
                }
                pdf_oxide::extractors::ImageData::Raw { pixels, format } => (
                    "application/x-codar-rgba8888",
                    raw_image_to_rgba(pixels, image.width(), image.height(), format)?,
                    "rgba8888",
                ),
                _ => return None,
            };
            if data.is_empty() {
                return None;
            }

            let (left, top, display_width, display_height) = image.bbox().map_or(
                (0.0, 0.0, page_width, page_height),
                |bbox| {
                    (
                        bbox.x - media_box.0,
                        media_box.3 - (bbox.y + bbox.height),
                        bbox.width,
                        bbox.height,
                    )
                },
            );

            Some(SectionImage {
                source: format!("pdf-image-{index}-{image_index}"),
                mime_type: mime_type.to_string(),
                data,
                pixel_width: image.width(),
                pixel_height: image.height(),
                data_format: data_format.to_string(),
                left,
                top,
                display_width,
                display_height,
                page_width,
                page_height,
                rotation_degrees: image.rotation_degrees(),
            })
        })
        .collect()
}

fn raw_image_to_rgba(
    pixels: &[u8],
    width: u32,
    height: u32,
    format: &pdf_oxide::extractors::PixelFormat,
) -> Option<Vec<u8>> {
    let pixel_count = (width as usize).checked_mul(height as usize)?;
    let channels = match format {
        pdf_oxide::extractors::PixelFormat::Grayscale => 1,
        pdf_oxide::extractors::PixelFormat::RGB => 3,
        pdf_oxide::extractors::PixelFormat::CMYK => 4,
    };
    if pixels.len() < pixel_count.checked_mul(channels)? {
        return None;
    }

    let mut rgba = Vec::with_capacity(pixel_count.checked_mul(4)?);
    for sample in pixels.chunks_exact(channels).take(pixel_count) {
        let (red, green, blue) = match format {
            pdf_oxide::extractors::PixelFormat::Grayscale => (sample[0], sample[0], sample[0]),
            pdf_oxide::extractors::PixelFormat::RGB => (sample[0], sample[1], sample[2]),
            pdf_oxide::extractors::PixelFormat::CMYK => {
                let black = u16::from(sample[3]);
                let convert = |channel: u8| {
                    (((255 - u16::from(channel)) * (255 - black) + 127) / 255) as u8
                };
                (convert(sample[0]), convert(sample[1]), convert(sample[2]))
            }
        };
        rgba.extend_from_slice(&[red, green, blue, 255]);
    }
    Some(rgba)
}

fn pdf_markdown_to_html(markdown: &str, page_num: usize) -> String {
    fn escape_html(value: &str) -> String {
        value
            .replace('&', "&amp;")
            .replace('<', "&lt;")
            .replace('>', "&gt;")
            .replace('"', "&quot;")
    }

    fn flush_paragraph(html: &mut String, paragraph: &mut String) {
        if paragraph.is_empty() {
            return;
        }
        html.push_str("<p>");
        html.push_str(&escape_html(paragraph));
        html.push_str("</p>\n");
        paragraph.clear();
    }

    let mut html = format!("<div class=\"pdf-page\" data-page=\"{page_num}\">\n");
    let mut paragraph = String::new();
    for line in markdown.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            flush_paragraph(&mut html, &mut paragraph);
            continue;
        }
        if let Some(text) = trimmed.strip_prefix("# ") {
            flush_paragraph(&mut html, &mut paragraph);
            html.push_str(&format!("<h1>{}</h1>\n", escape_html(text.trim())));
        } else if let Some(text) = trimmed.strip_prefix("## ") {
            flush_paragraph(&mut html, &mut paragraph);
            html.push_str(&format!("<h2>{}</h2>\n", escape_html(text.trim())));
        } else if let Some(text) = trimmed.strip_prefix("### ") {
            flush_paragraph(&mut html, &mut paragraph);
            html.push_str(&format!("<h3>{}</h3>\n", escape_html(text.trim())));
        } else if let Some(text) = trimmed.strip_prefix("- ") {
            flush_paragraph(&mut html, &mut paragraph);
            html.push_str(&format!("<li>{}</li>\n", escape_html(text.trim())));
        } else {
            if !paragraph.is_empty() {
                paragraph.push(' ');
            }
            paragraph.push_str(trimmed);
        }
    }
    flush_paragraph(&mut html, &mut paragraph);
    html.push_str("</div>");
    html
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

#[cfg(test)]
mod tests {
    use super::{image_sources, kindle_embed_index, pdf_markdown_to_html, raw_image_to_rgba};
    use pdf_oxide::extractors::PixelFormat;

    #[test]
    fn image_source_parser_handles_common_attribute_forms() {
        let sources = image_sources(
            "<IMG src=cover.jpg><img alt='diagram' src=\"chapter/pic&amp;1.png\">",
        );

        assert_eq!(sources, ["cover.jpg", "chapter/pic&amp;1.png"]);
    }

    #[test]
    fn kindle_embed_ids_decode_as_base36_image_indices() {
        assert_eq!(kindle_embed_index("kindle:embed:000O?mime=image/png"), Some(24));
        assert_eq!(kindle_embed_index("KINDLE:EMBED:000H"), Some(17));
        assert_eq!(kindle_embed_index("kindle:embed:0000"), None);
        assert_eq!(kindle_embed_index("images/img_0024.png"), None);
    }

    #[test]
    fn raw_pdf_image_channels_are_converted_to_rgba() {
        assert_eq!(
            raw_image_to_rgba(&[120], 1, 1, &PixelFormat::Grayscale),
            Some(vec![120, 120, 120, 255])
        );
        assert_eq!(
            raw_image_to_rgba(&[10, 20, 30], 1, 1, &PixelFormat::RGB),
            Some(vec![10, 20, 30, 255])
        );
        assert_eq!(
            raw_image_to_rgba(&[0, 255, 255, 0], 1, 1, &PixelFormat::CMYK),
            Some(vec![255, 0, 0, 255])
        );
        assert_eq!(raw_image_to_rgba(&[1, 2], 1, 1, &PixelFormat::RGB), None);
    }

    #[test]
    fn pdf_soft_wrapped_lines_share_a_paragraph() {
        let html = pdf_markdown_to_html(
            "first soft\nwrapped line\n\nnext paragraph\n# Heading\n- item",
            3,
        );

        assert!(html.contains("<p>first soft wrapped line</p>"));
        assert!(html.contains("<p>next paragraph</p>"));
        assert!(html.contains("<h1>Heading</h1>"));
        assert!(html.contains("<li>item</li>"));
    }
}
