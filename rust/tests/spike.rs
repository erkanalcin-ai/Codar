//! Phase 1 spike: drive the Reader Core API directly (host target).
//!
//! Each test maps to a Phase 1 gate. Fixtures live in
//! `<repo>/spike/fixtures` (hand-made + Project Gutenberg public domain).

use codar_reader::api::reader;
use codar_reader::reader::session;
use std::path::PathBuf;

fn fixture(name: &str) -> String {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("spike")
        .join("fixtures")
        .join(name)
        .to_string_lossy()
        .to_string()
}

fn open(path: &str) -> reader::OpenBookResult {
    reader::open_book(fixture(path)).unwrap_or_else(|e| panic!("open {path} failed: {e}"))
}

/// Large/vendor fixtures are git-ignored (see spike/fixtures/README.md).
/// Skip gracefully when absent so a fresh clone stays green.
fn vendor_path(name: &str) -> Option<String> {
    let p = fixture(name);
    if PathBuf::from(&p).is_file() {
        Some(p)
    } else {
        println!("SKIP {name}: vendor fixture absent (see spike/fixtures/README.md)");
        None
    }
}

fn close(sid: u64) {
    assert!(
        reader::close_book(sid).expect("close failed"),
        "close reported missing"
    );
    // Removal proof: second close must report absent (idempotent, no residue).
    assert!(!reader::close_book(sid).expect("second close failed"));
}

#[test]
fn epub_open_min_metadata_chapters() {
    let opened = open("min.epub");
    assert_eq!(opened.info.title, "Codar Spike Fixture");
    assert!(opened.info.authors.iter().any(|a| a.contains("Codar")));
    assert_eq!(opened.info.section_count, 2);
    assert_eq!(opened.info.format, "epub");
    let chapters = reader::get_chapters(opened.session_id).expect("chapters");
    assert_eq!(chapters.len(), 2);
    assert_eq!(chapters[0].title, "First Chapter");
    assert_eq!(chapters[1].title, "Second Chapter");
    assert_eq!(chapters[1].depth, 0);
    let c0 = reader::get_content(opened.session_id, 0).expect("content 0");
    assert!(c0.plain_text.contains("CodarSpikePhrase"));
    assert!(c0.plain_text.contains("İstanbul"));
    close(opened.session_id);
}

#[test]
fn epub_cfi_roundtrip_across_reopen() {
    let opened = open("min.epub");
    let sid = opened.session_id;
    // Known section 1 (second chapter), offset into its text.
    let locator = reader::get_locator(sid, 1, 10).expect("locator");
    assert!(
        locator.contains("cfi") || locator.contains("href"),
        "locator JSON: {locator}"
    );
    let progress = reader::get_progress(sid, 1, 10).expect("progress");
    assert_eq!(progress.section_index, 1);
    close(sid);

    // Reopen and restore from the persisted JSON.
    let reopened = open("min.epub");
    let restored = reader::restore_locator(reopened.session_id, progress.locator_json.clone())
        .expect("restore");
    assert_eq!(restored.section_index, 1, "restored to wrong section");
    // The restored CFI must resolve again (same logical location).
    let reloc =
        reader::get_locator(reopened.session_id, restored.section_index, 10).expect("relocator");
    assert!(
        reloc.contains(&restored.cfi) || restored.cfi.is_empty(),
        "CFI changed across restore"
    );
    close(reopened.session_id);
}

#[test]
fn epub_search_hit_restores_location() {
    let opened = open("min.epub");
    let sid = opened.session_id;
    let hits = reader::search(sid, "CodarSpikePhrase".to_string()).expect("search");
    assert!(!hits.is_empty(), "expected search hits");
    let hit = &hits[0];
    assert_eq!(hit.section_index, 0);
    assert!(!hit.cfi.is_empty(), "search hit must carry a CFI");
    assert!(hit.snippet.contains("CodarSpikePhrase"));
    // Restore via the hit's CFI through a locator round-trip.
    let locator = reader::get_locator(sid, hit.section_index, hit.char_offset).expect("loc");
    let restored = reader::restore_locator(sid, locator).expect("restore search locator");
    assert_eq!(restored.section_index, hit.section_index);
    close(sid);
}

#[test]
fn epub_pagination_deterministic() {
    let opened = open("min.epub");
    let sid = opened.session_id;
    let run = || reader::paginate_section(sid, 0, 18, 1.5, 800, 1280, 48).expect("paginate");
    let r1 = run();
    let r2 = run();
    assert!(r1.total_pages >= 1);
    assert_eq!(
        r1.total_pages, r2.total_pages,
        "page count nondeterministic"
    );
    assert_eq!(
        r1.page_map_debug, r2.page_map_debug,
        "page boundaries nondeterministic"
    );
    assert!(!r1.is_rtl);
    close(sid);
}

#[test]
fn pdf_two_pages_map_one_to_one() {
    let opened = open("spike.pdf");
    assert_eq!(opened.info.format, "pdf");
    assert_eq!(opened.info.section_count, 2, "expected 1 section per page");
    let p0 = reader::get_page(opened.session_id, 0).expect("page 0");
    let p1 = reader::get_page(opened.session_id, 1).expect("page 1");
    assert!(p0.plain_text.contains("CodarSpikePhrase"));
    assert!(p1.plain_text.contains("Second PDF page"));
    let chapters = reader::get_chapters(opened.session_id).expect("chapters");
    assert_eq!(chapters.len(), 2);
    let hits = reader::search(opened.session_id, "CodarSpikePhrase".to_string()).expect("search");
    assert!(!hits.is_empty());
    close(opened.session_id);
}

#[test]
fn cbz_pages_order_and_filtering() {
    let opened = open("spike.cbz");
    assert_eq!(opened.info.format, "cbz");
    assert_eq!(opened.info.section_count, 3, "decoys must be excluded");
    // Natural sort: page1, page2, page10.
    let c0 = reader::get_content(opened.session_id, 0).expect("c0");
    let c1 = reader::get_content(opened.session_id, 1).expect("c1");
    let c2 = reader::get_content(opened.session_id, 2).expect("c2");
    assert!(c0.plain_text.contains("page1.png"), "c0: {}", c0.plain_text);
    assert!(c1.plain_text.contains("page2.png"), "c1: {}", c1.plain_text);
    assert!(
        c2.plain_text.contains("page10.png"),
        "c2: {}",
        c2.plain_text
    );
    close(opened.session_id);
}

#[test]
fn txt_turkish_glyphs_and_offset_locator() {
    let opened = open("spike_tr.txt");
    assert_eq!(opened.info.format, "txt");
    let c0 = reader::get_content(opened.session_id, 0).expect("content");
    for g in [
        "ç",
        "Ç",
        "ğ",
        "Ğ",
        "ı",
        "İ",
        "ö",
        "Ö",
        "ş",
        "Ş",
        "ü",
        "Ü",
        "İstanbul",
    ] {
        assert!(c0.plain_text.contains(g), "missing glyph {g}");
    }
    let locator = reader::get_locator(opened.session_id, 0, 5).expect("locator");
    let restored = reader::restore_locator(opened.session_id, locator).expect("restore");
    assert_eq!(restored.section_index, 0);
    close(opened.session_id);
}

#[test]
fn md_opens_with_sections() {
    let opened = open("spike_md.md");
    assert_eq!(opened.info.format, "md");
    // Markdown headings become sections: title + 2 chapters.
    assert_eq!(opened.info.section_count, 3);
    let c1 = reader::get_content(opened.session_id, 1).expect("content");
    assert!(c1.plain_text.contains("CodarSpikePhrase"));
    assert!(c1.plain_text.contains("ğ"));
    close(opened.session_id);
}

#[test]
fn fb2_sections_and_search() {
    let opened = open("spike.fb2");
    assert_eq!(opened.info.format, "fb2");
    assert!(opened.info.section_count >= 1);
    let hits = reader::search(opened.session_id, "CodarSpikePhrase".to_string()).expect("search");
    assert!(!hits.is_empty());
    close(opened.session_id);
}

#[test]
fn mobi_real_world_alice() {
    let opened = open("alice.mobi");
    assert!(
        opened.info.section_count > 5,
        "sections: {}",
        opened.info.section_count
    );
    let hits = reader::search(opened.session_id, "Rabbit".to_string()).expect("search");
    assert!(!hits.is_empty(), "expected 'Rabbit' hits in Alice");
    let chapters = reader::get_chapters(opened.session_id).expect("chapters");
    assert!(!chapters.is_empty());
    close(opened.session_id);
}

#[test]
fn epub_real_world_alice() {
    let opened = open("alice.epub");
    assert!(opened.info.section_count > 5);
    assert!(!opened.info.title.is_empty());
    let hits = reader::search(opened.session_id, "Rabbit".to_string()).expect("search");
    assert!(!hits.is_empty());
    close(opened.session_id);
}

#[test]
fn vendor_azw3_real() {
    let Some(path) = vendor_path("vendor/alice.azw3") else {
        return;
    };
    let opened = reader::open_book(path).expect("open azw3");
    assert_eq!(opened.info.format, "azw3");
    assert_eq!(opened.info.section_count, 14);
    let hits = reader::search(opened.session_id, "Rabbit".to_string()).expect("search");
    assert_eq!(hits.len(), 56);
    assert!(!hits[0].cfi.is_empty());
    let restored = reader::restore_locator(
        opened.session_id,
        reader::get_locator(
            opened.session_id,
            hits[0].section_index,
            hits[0].char_offset,
        )
        .expect("locator"),
    )
    .expect("restore");
    assert_eq!(restored.section_index, hits[0].section_index);
    close(opened.session_id);
}

#[test]
fn vendor_pdf_real_world_pages_and_search() {
    let Some(path) = vendor_path("vendor/alice_vendor.pdf") else {
        return;
    };
    let opened = reader::open_book(path).expect("open vendor pdf");
    assert_eq!(opened.info.format, "pdf");
    assert_eq!(
        opened.info.section_count, 102,
        "expected 1 section per page"
    );
    let hits = reader::search(opened.session_id, "Rabbit".to_string()).expect("search");
    assert_eq!(hits.len(), 54);
    // Page mapping: hit section index must be a valid page.
    assert!(hits[0].section_index < 102);
    let page = reader::get_page(opened.session_id, hits[0].section_index).expect("page");
    assert!(!page.plain_text.is_empty() || hits[0].section_index == 0);
    close(opened.session_id);
}

#[test]
fn vendor_lit_opens() {
    let Some(path) = vendor_path("vendor/alice.lit") else {
        return;
    };
    let opened = reader::open_book(path).expect("open lit");
    assert_eq!(opened.info.format, "lit");
    assert_eq!(opened.info.section_count, 21);
    close(opened.session_id);
}

#[test]
fn vendor_cbz_big_book() {
    let Some(path) = vendor_path("vendor/jumbo099.cbz") else {
        return;
    };
    let opened = reader::open_book(path).expect("open big cbz");
    assert_eq!(opened.info.format, "cbz");
    assert_eq!(opened.info.section_count, 52);
    let c0 = reader::get_content(opened.session_id, 0).expect("c0");
    assert!(c0.plain_text.contains("Comic Page 1"));
    close(opened.session_id);
}

#[test]
fn vendor_cbr_cleanly_rejected() {
    // CBR/RAR is out of scope by product decision: clean error, never panic.
    let Some(path) = vendor_path("vendor/jumbo082.cbr") else {
        return;
    };
    let err = reader::open_book(path).expect_err("CBR must be rejected");
    assert!(matches!(err, reader::ReaderError::UnsupportedFormat(_)));
}

#[test]
fn large_epub_lazy_behavior() {
    let Some(path) = vendor_path("pride.epub") else {
        return;
    };
    let start = std::time::Instant::now();
    let opened = reader::open_book(path).expect("open pride");
    let elapsed = start.elapsed();
    println!(
        "pride.epub open: {elapsed:?}, sections: {}",
        opened.info.section_count
    );
    assert!(opened.info.section_count > 10);
    // Lazy per-section access without hydrating the whole book in Dart.
    let sid = opened.session_id;
    let got = session::with_book(sid, |b| b.load_section_lazy(0).is_ok());
    assert_eq!(got, Some(true), "load_section_lazy must work");
    let c5 = reader::get_content(sid, 5).expect("section 5");
    assert!(!c5.plain_text.is_empty());
    close(sid);
}

#[test]
fn open_close_soak_no_session_growth() {
    let before = reader::live_session_count();
    for _ in 0..50 {
        let opened = reader::open_book(fixture("min.epub")).expect("open");
        let _ = reader::get_document_info(opened.session_id).expect("info");
        let _ = reader::get_content(opened.session_id, 0).expect("content");
        assert!(reader::close_book(opened.session_id).expect("close"));
    }
    assert_eq!(reader::live_session_count(), before, "sessions accumulated");
}

#[test]
fn hostile_script_epub_opens_without_executing() {
    // The engine must parse it; execution is impossible (no JS runtime involved).
    // What matters: clean parse + script content identifiable for sanitization.
    let opened = reader::open_book(fixture("hostile_script.epub")).expect("open hostile script");
    let c0 = reader::get_content(opened.session_id, 0).expect("content");
    assert!(
        c0.html.contains("<script") || c0.plain_text.contains("Script test"),
        "unexpected content shape"
    );
    reader::close_book(opened.session_id).expect("close");
    assert_eq!(reader::live_session_count(), 0);
}

#[test]
fn hostile_badxml_fails_cleanly_or_repairs() {
    match reader::open_book(fixture("hostile_badxml.epub")) {
        Ok(opened) => {
            // Repair path: must still serve *something* without panicking.
            let _ = reader::get_content(opened.session_id, 0);
            reader::close_book(opened.session_id).expect("close");
        }
        Err(e) => println!("badxml cleanly rejected: {e}"),
    }
    assert_eq!(reader::live_session_count(), 0);
}

#[test]
fn hostile_traversal_writes_nothing_outside() {
    let opened = reader::open_book(fixture("hostile_traversal.epub")).expect("open traversal");
    let _ = reader::get_content(opened.session_id, 0);
    reader::close_book(opened.session_id).expect("close");
    // Payload must not have materialized beside the fixture or in CWD.
    for dir in [
        "C:\\Codar\\spike\\fixtures",
        "C:\\Codar\\rust",
        "C:\\Users\\Erkan\\AppData\\Local\\Temp",
    ] {
        let candidate = PathBuf::from(dir).join("evil_traversal.txt");
        assert!(
            !candidate.exists(),
            "traversal payload escaped to {}",
            candidate.display()
        );
    }
    assert_eq!(reader::live_session_count(), 0);
}

#[test]
fn unsupported_extension_rejected() {
    let err = reader::open_book(fixture("spike_tr.txt").replace(".txt", ".exe"))
        .expect_err("exe must be rejected");
    assert!(matches!(err, reader::ReaderError::InvalidPath(_)));
}

#[test]
fn unknown_session_errors() {
    assert!(matches!(
        reader::get_content(999_999_999, 0),
        Err(reader::ReaderError::UnknownSession(_))
    ));
    // Double close is idempotent success=false.
    let opened = open("min.epub");
    assert!(reader::close_book(opened.session_id).expect("close1"));
    assert!(!reader::close_book(opened.session_id).expect("close2"));
}
