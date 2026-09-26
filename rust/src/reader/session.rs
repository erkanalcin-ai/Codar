//! Session registry: `session_id -> open book`.
//!
//! Lifecycle contract: `open` inserts exactly one entry, `close` removes it.
//! No session survives `close`; repeated open/close must not accumulate state.

use ebook_rs::Book;

use std::collections::{HashMap, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex, MutexGuard};

use super::content::{self, SectionContent};
use super::format::BookFormat;

const PDF_PAGE_CACHE_CAPACITY: usize = 3;

pub struct PdfSession {
    pub document: pdf_oxide::PdfDocument,
    pub page_count: usize,
    pages: Mutex<VecDeque<SectionContent>>,
}

impl PdfSession {
    pub fn content(&self, index: usize) -> Result<Option<SectionContent>, String> {
        if index >= self.page_count {
            return Ok(None);
        }
        let cached = {
            let mut pages = self.pages.lock().expect("PDF page cache poisoned");
            if let Some(position) = pages.iter().position(|page| page.index == index as u64) {
                let page = pages.remove(position).expect("cached page position");
                pages.push_back(page.clone());
                Some(page)
            } else {
                None
            }
        };
        if let Some(page) = cached {
            return Ok(Some(page));
        }
        let page_result = content::pdf_page_content(&self.document, index);
        let page = page_result?;
        let mut pages = self.pages.lock().expect("PDF page cache poisoned");
        if let Some(position) = pages.iter().position(|cached| cached.index == index as u64) {
            let cached = pages.remove(position).expect("cached page position");
            pages.push_back(cached.clone());
            return Ok(Some(cached));
        }
        pages.push_back(page.clone());
        while pages.len() > PDF_PAGE_CACHE_CAPACITY {
            pages.pop_front();
        }
        Ok(Some(page))
    }
}

pub struct Session {
    pub book: Book,
    pub format: BookFormat,
    pub path: String,
    pub pdf: Option<PdfSession>,
}

static NEXT_ID: AtomicU64 = AtomicU64::new(1);
static SESSIONS: LazyLock<Mutex<HashMap<u64, Session>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn lock() -> MutexGuard<'static, HashMap<u64, Session>> {
    SESSIONS.lock().expect("reader session registry poisoned")
}

/// Insert a newly opened book, returning its session id.
pub fn insert(book: Book, format: BookFormat, path: String) -> u64 {
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    lock().insert(
        id,
        Session {
            book,
            format,
            path,
            pdf: None,
        },
    );
    id
}

pub fn insert_pdf(
    book: Book,
    document: pdf_oxide::PdfDocument,
    page_count: usize,
    path: String,
) -> u64 {
    let id = NEXT_ID.fetch_add(1, Ordering::Relaxed);
    lock().insert(
        id,
        Session {
            book,
            format: BookFormat::Pdf,
            path,
            pdf: Some(PdfSession {
                document,
                page_count,
                pages: Mutex::new(VecDeque::new()),
            }),
        },
    );
    id
}

/// Remove and return the session. `None` means unknown/already closed.
pub fn remove(id: u64) -> Option<Session> {
    lock().remove(&id)
}

/// Number of currently live sessions (spike/soak observability).
pub fn live_count() -> u64 {
    lock().len() as u64
}

/// Run a read-only closure against a live session's book.
pub fn with_book<T>(id: u64, f: impl FnOnce(&Book) -> T) -> Option<T> {
    lock().get(&id).map(|s| f(&s.book))
}

/// Run a mutating closure against a live session's book.
pub fn with_book_mut<T>(id: u64, f: impl FnOnce(&mut Book) -> T) -> Option<T> {
    lock().get_mut(&id).map(|s| f(&mut s.book))
}

pub fn with_pdf<T>(id: u64, f: impl FnOnce(&PdfSession) -> T) -> Option<T> {
    lock().get(&id)?.pdf.as_ref().map(f)
}

/// Read session metadata (format + path) without touching the book.
pub fn session_meta(id: u64) -> Option<(BookFormat, String)> {
    lock().get(&id).map(|s| (s.format, s.path.clone()))
}
