//! Session registry: `session_id -> open book`.
//!
//! Lifecycle contract: `open` inserts exactly one entry, `close` removes it.
//! No session survives `close`; repeated open/close must not accumulate state.

use ebook_rs::Book;

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex, MutexGuard};

use super::format::BookFormat;

pub struct Session {
    pub book: Book,
    pub format: BookFormat,
    pub path: String,
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
    lock().insert(id, Session { book, format, path });
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

/// Read session metadata (format + path) without touching the book.
pub fn session_meta(id: u64) -> Option<(BookFormat, String)> {
    lock().get(&id).map(|s| (s.format, s.path.clone()))
}
