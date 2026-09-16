//! Annotation anchor helpers (Phase 1: reserved).
//!
//! Highlights/notes/bookmarks persist in Codar's SQLite store, anchored by
//! ebook-rs CFI strings. The library `AnnotationManager` is session-local
//! only and is deliberately NOT the store of record.
