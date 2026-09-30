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
    Some(section_content_from_section(book, &section, true))
}

/// Section payload for exact Flutter pagination without decompressing or
/// crossing the bridge with image bytes. Image descriptors remain present so
/// the page count sees the same image blocks as the render path.
pub fn section_content_for_page_count(
    book: &ebook_rs::Book,
    index: usize,
) -> Option<SectionContent> {
    let source = book.get_section_raw(index)?;
    let mut section = if source.raw_html.is_empty() {
        ebook_rs::section::Section::new(
            source.index,
            source.idref.clone(),
            source.href.clone(),
            source.full_path.clone(),
            &book.archive,
        )
        .ok()?
    } else {
        source.clone()
    };
    section.processed_html = section.raw_html.clone();
    if book.opf.metadata.direction == ebook_rs::metadata::PageProgressionDirection::Rtl
        && !section.processed_html.contains("dir=\"rtl\"")
        && !section.processed_html.contains("dir='rtl'")
    {
        section.processed_html = section.processed_html.replace("<html", "<html dir=\"rtl\"");
        if !section.processed_html.contains("dir=\"rtl\"") {
            section.processed_html =
                section.processed_html.replace("<body", "<body dir=\"rtl\"");
        }
    }
    if !book.layout.allow_scripted_content {
        section.strip_script_content();
    }
    for hook in &book.before_display_hooks {
        hook(&mut section.processed_html, &section.full_path);
    }
    Some(section_content_from_section(book, &section, false))
}

fn section_content_from_section(
    book: &ebook_rs::Book,
    section: &ebook_rs::section::Section,
    include_image_data: bool,
) -> SectionContent {
    let (html, inline_images) = if include_image_data {
        (section.processed_html.clone(), Vec::new())
    } else {
        compact_embedded_image_data(&section.processed_html)
    };
    let images = section_html_images(book, &section.full_path, &html, include_image_data);
    let images = images.into_iter().chain(inline_images).collect();
    SectionContent {
        index: section.index as u64,
        idref: section.idref.clone(),
        href: section.href.clone(),
        html,
        plain_text: section.plain_text.clone(),
        char_count: section.char_count as u64,
        images,
    }
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
    include_image_data: bool,
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
            let image_dir = if opf_dir.is_empty() { "OEBPS" } else { opf_dir };
            for extension in ["jpg", "jpeg", "png", "gif", "webp", "bmp"] {
                candidates.push(format!(
                    "{image_dir}/images/img_{image_index:04}.{extension}"
                ));
            }
        }
        candidates.dedup();

        let resource = candidates.iter().find_map(|path| {
            if include_image_data {
                book.get_resource_bytes(path).ok()
            } else if book.archive.contains(path) {
                Some((
                    Vec::new(),
                    ebook_rs::archive::EpubArchive::get_mime_type(path),
                ))
            } else {
                None
            }
        });
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
    let mut sources = Vec::new();
    let mut cursor = 0;
    while let Some(start) = find_ascii_case_insensitive(html, "<img", cursor) {
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

fn find_ascii_case_insensitive(text: &str, needle: &str, from: usize) -> Option<usize> {
    let haystack = text.as_bytes().get(from..)?;
    let needle = needle.as_bytes();
    haystack
        .windows(needle.len())
        .position(|window| {
            window
                .iter()
                .zip(needle)
                .all(|(left, right)| left.eq_ignore_ascii_case(right))
        })
        .map(|index| from + index)
}

fn html_attribute(tag: &str, wanted: &str) -> Option<String> {
    let (start, end) = html_attribute_range(tag, wanted)?;
    Some(tag[start..end].to_string())
}

fn html_attribute_range(tag: &str, wanted: &str) -> Option<(usize, usize)> {
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
            while cursor < bytes.len()
                && !bytes[cursor].is_ascii_whitespace()
                && bytes[cursor] != b'>'
            {
                cursor += 1;
            }
        }
        if name.eq_ignore_ascii_case(wanted) {
            return Some((value_start, cursor));
        }
        if quote.is_some() && cursor < bytes.len() {
            cursor += 1;
        }
    }
    None
}

fn compact_embedded_image_data(html: &str) -> (String, Vec<SectionImage>) {
    let mut output = String::with_capacity(html.len().min(64 * 1024));
    let mut images = Vec::new();
    let mut copy_cursor = 0;
    let mut scan_cursor = 0;
    let mut changed = false;

    while let Some(tag_start) = find_ascii_case_insensitive(html, "<img", scan_cursor) {
        let Some(relative_end) = html[tag_start..].find('>') else {
            break;
        };
        let tag_end = tag_start + relative_end + 1;
        let tag = &html[tag_start..tag_end];
        let replacement = html_attribute_range(tag, "src").and_then(|(start, end)| {
            let source = decode_basic_html_entities(&tag[start..end]);
            let mime = compactable_embedded_image(&source)?;
            Some((tag_start + start, tag_start + end, mime))
        });

        if let Some((value_start, value_end, mime)) = replacement {
            if value_start >= copy_cursor {
                output.push_str(&html[copy_cursor..value_start]);
                let source = if let Some(mime_type) = mime {
                    let index = images.len();
                    let source = format!("codar-count-image:{index}");
                    images.push(SectionImage {
                        source: source.clone(),
                        mime_type,
                        data: Vec::new(),
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
                    source
                } else {
                    "about:blank".to_string()
                };
                output.push_str(&source);
                copy_cursor = value_end;
                changed = true;
            }
        }
        scan_cursor = tag_end;
    }

    if !changed {
        return (html.to_string(), images);
    }
    output.push_str(&html[copy_cursor..]);
    (output, images)
}

fn compactable_embedded_image(source: &str) -> Option<Option<String>> {
    let trimmed = source.trim();
    let data = trimmed
        .get(..5)
        .filter(|prefix| prefix.eq_ignore_ascii_case("data:"))
        .and_then(|_| trimmed.get(5..))?;
    if !data
        .get(..6)
        .is_some_and(|mime| mime.eq_ignore_ascii_case("image/"))
    {
        return None;
    }
    let Some((metadata, payload)) = data.split_once(',') else {
        return Some(None);
    };
    let mut fields = metadata.split(';');
    let raw_mime = fields.next()?.to_ascii_lowercase();
    let mime = if raw_mime == "image/jpg" {
        "image/jpeg"
    } else {
        raw_mime.as_str()
    };
    let supported_raster = matches!(
        mime,
        "image/jpeg" | "image/png" | "image/gif" | "image/webp" | "image/bmp"
    );
    if !supported_raster {
        return Some(None);
    }
    let is_base64 = fields.any(|field| field.eq_ignore_ascii_case("base64"));
    if !is_base64 {
        return None;
    }
    if !supported_raster || !valid_base64_payload(payload) {
        return Some(None);
    }
    Some(Some(mime.to_string()))
}

fn valid_base64_payload(payload: &str) -> bool {
    let bytes = payload.as_bytes();
    if bytes.is_empty() {
        return false;
    }
    let padding = bytes.iter().rev().take_while(|byte| **byte == b'=').count();
    if padding > 2 {
        return false;
    }
    let content_len = bytes.len() - padding;
    if bytes[..content_len]
        .iter()
        .any(|byte| !byte.is_ascii_alphanumeric() && !matches!(*byte, b'+' | b'/'))
    {
        return false;
    }
    if bytes[content_len..].iter().any(|byte| *byte != b'=') {
        return false;
    }
    match padding {
        1 if content_len % 4 != 3 => return false,
        2 if content_len % 4 != 2 => return false,
        0 if content_len % 4 == 1 => return false,
        _ => {}
    }
    padding == 0 || bytes.len() % 4 == 0
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
    use super::{
        compact_embedded_image_data, image_sources, kindle_embed_index, pdf_markdown_to_html,
        raw_image_to_rgba, section_content, section_content_for_page_count,
    };
    use pdf_oxide::extractors::PixelFormat;

    #[test]
    fn count_only_epub_content_keeps_image_descriptors_without_payloads() {
        let fixture = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("tests/fixtures/count-images.epub");
        let book = ebook_rs::Book::from_file(fixture).expect("fixture EPUB opens");
        let rendered = section_content(&book, 0).expect("render section exists");
        let counted = section_content_for_page_count(&book, 0).expect("count section exists");
        assert_ne!(counted.html, rendered.html);
        assert!(rendered.html.contains("data:image/png;base64"));
        assert!(!counted.html.contains("iVBORw0KGgo"));
        assert!(counted.html.contains("images/pixel.png"));
        assert_eq!(counted.plain_text, rendered.plain_text);
        assert_eq!(counted.char_count, rendered.char_count);
        assert!(rendered.images.is_empty());
        assert_eq!(counted.images.len(), 1);
        assert_eq!(counted.images[0].source, "images/pixel.png");
        assert_eq!(counted.images[0].mime_type, "image/png");
        assert!(counted.images[0].data.is_empty());
        assert!(counted.html.len() < rendered.html.len());
    }

    #[test]
    fn count_only_strips_nonrenderable_base64_image_payloads() {
        let html = "<img src=\"data:image/svg+xml;base64,PHN2Zz4=\"><img src=\"data:image/png;base64,invalid!\">";
        let (count_html, images) = compact_embedded_image_data(html);

        assert!(images.is_empty());
        assert!(!count_html.contains("PHN2Zz4="));
        assert!(!count_html.contains("invalid!"));
        assert_eq!(count_html.matches("about:blank").count(), 2);
    }

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

    #[test]
    fn plain_text_alignment_fixtures_match_the_pinned_ebook_extractor() {
        let fixtures = [
            (
                "<p>Copyright &copy; 2012</p>",
                "Copyright &copy; 2012",
            ),
            (
                "<p>&nbsp;&#169;&#xA9;</p>",
                "&nbsp;&#169;&#xA9;",
            ),
            (
                "<p>Kabala</p><div><b>&#160;</b></div><div><b>&#160;</b></div><div><b>&#160;</b></div><div><b>&#160;</b></div><p><b> A. Ekrem Ülkü</b></p>",
                "Kabala &#160; &#160; &#160; &#160; A. Ekrem Ülkü",
            ),
            (
                "<p>Visible</p><div><b>&#160;</b></div><h1>Next</h1>",
                "Visible &#160; Next",
            ),
            (
                "<p>Visible</p><div><b>&#xA0;</b></div><h1>Next</h1>",
                "Visible &#xA0; Next",
            ),
            (
                "<p>Visible</p><div><b>&nbsp;</b></div><h1>Next</h1>",
                "Visible &nbsp; Next",
            ),
            (
                "<p>Visible</p><span>&nbsp;</span><h1>Next</h1>",
                "Visible &nbsp; Next",
            ),
            (
                "<p>foo<em>bar</em>baz</p>",
                "foo bar baz",
            ),
            (
                "<p>one\u{2003}\u{00a0}\t two</p>",
                "one two",
            ),
            (
                "<p>A<script>hidden</script><style>rules</style>B</p>",
                "A B",
            ),
            (
                "<p>  leading and trailing  </p><p>next</p>",
                "leading and trailing next",
            ),
            (
                "<p>A😀 café</p>",
                "A😀 café",
            ),
        ];

        for (html, expected) in fixtures {
            assert_eq!(
                ebook_rs::section::extract_plain_text(html),
                expected,
                "extractor fixture: {html}"
            );
        }
    }
}
