// Plain data models mirroring the SQLite schema. No logic, no widgets.

class BookRecord {
  BookRecord({
    required this.bookId,
    required this.title,
    required this.author,
    required this.language,
    required this.format,
    required this.sectionCount,
    required this.fileSize,
    required this.fingerprint,
    required this.addedAt,
    required this.lastOpenedAt,
  });

  final String bookId;
  final String title;
  final String author;
  final String language;
  final String format;
  final int sectionCount;
  final int fileSize;
  final String fingerprint;
  final int addedAt;
  final int lastOpenedAt;

  factory BookRecord.fromMap(Map<String, Object?> m) => BookRecord(
        bookId: m['book_id'] as String,
        title: (m['title'] as String?) ?? '',
        author: (m['author'] as String?) ?? '',
        language: (m['language'] as String?) ?? '',
        format: (m['format'] as String?) ?? '',
        sectionCount: (m['section_count'] as int?) ?? 0,
        fileSize: (m['file_size'] as int?) ?? 0,
        fingerprint: (m['fingerprint'] as String?) ?? '',
        addedAt: (m['added_at'] as int?) ?? 0,
        lastOpenedAt: (m['last_opened_at'] as int?) ?? 0,
      );
}

/// A library list item with its optional, already-joined reading progress.
/// This keeps progress out of the books table model while avoiding per-book
/// progress queries in the Library UI.
class LibraryBookRecord {
  const LibraryBookRecord({required this.book, required this.progress});

  final BookRecord book;
  final ProgressRecord? progress;

  factory LibraryBookRecord.fromMap(Map<String, Object?> m) {
    final hasProgress = m['progress_locator_json'] != null;
    return LibraryBookRecord(
      book: BookRecord.fromMap(m),
      progress: hasProgress
          ? ProgressRecord.fromMap({
              'book_id': m['book_id'],
              'locator_json': m['progress_locator_json'],
              'section_index': m['progress_section_index'],
              'char_offset': m['progress_char_offset'],
              'progression': m['progress_progression'],
              'updated_at': m['progress_updated_at'],
            })
          : null,
    );
  }
}

class FileRecord {
  FileRecord({
    required this.displayName,
    required this.mime,
    required this.mediastoreUri,
    required this.cachePath,
    required this.size,
  });

  final String displayName;
  final String mime;
  final String mediastoreUri;
  final String cachePath;
  final int size;

  factory FileRecord.fromMap(Map<String, Object?> m) => FileRecord(
        displayName: (m['display_name'] as String?) ?? '',
        mime: (m['mime'] as String?) ?? '',
        mediastoreUri: (m['mediastore_uri'] as String?) ?? '',
        cachePath: (m['cache_path'] as String?) ?? '',
        size: (m['size'] as int?) ?? 0,
      );
}

class ProgressRecord {
  ProgressRecord({
    required this.bookId,
    required this.locatorJson,
    required this.sectionIndex,
    required this.charOffset,
    required this.progression,
    required this.updatedAt,
  });

  final String bookId;
  final String locatorJson;
  final int sectionIndex;
  final int charOffset;
  final double progression;
  final int updatedAt;

  factory ProgressRecord.fromMap(Map<String, Object?> m) => ProgressRecord(
        bookId: m['book_id'] as String,
        locatorJson: (m['locator_json'] as String?) ?? '',
        sectionIndex: (m['section_index'] as int?) ?? 0,
        charOffset: (m['char_offset'] as int?) ?? 0,
        progression: ((m['progression'] as num?) ?? 0).toDouble(),
        updatedAt: (m['updated_at'] as int?) ?? 0,
      );
}

class HighlightRecord {
  HighlightRecord({
    this.id,
    required this.bookId,
    required this.sectionIndex,
    required this.startOffset,
    required this.endOffset,
    required this.cfi,
    required this.color,
    required this.quotedText,
    required this.note,
  });

  final int? id;
  final String bookId;
  final int sectionIndex;
  final int startOffset;
  final int endOffset;
  final String cfi;
  final int color;
  final String quotedText;
  final String note;

  factory HighlightRecord.fromMap(Map<String, Object?> m) => HighlightRecord(
        id: m['id'] as int?,
        bookId: (m['book_id'] as String?) ?? '',
        sectionIndex: (m['section_index'] as int?) ?? 0,
        startOffset: (m['start_offset'] as int?) ?? 0,
        endOffset: (m['end_offset'] as int?) ?? 0,
        cfi: (m['cfi'] as String?) ?? '',
        color: (m['color'] as int?) ?? 0,
        quotedText: (m['quoted_text'] as String?) ?? '',
        note: (m['note'] as String?) ?? '',
      );
}

class NoteRecord {
  NoteRecord({
    this.id,
    required this.bookId,
    required this.sectionIndex,
    required this.cfi,
    required this.charOffset,
    required this.content,
    required this.quotedText,
  });

  final int? id;
  final String bookId;
  final int sectionIndex;
  final String cfi;
  final int charOffset;
  final String content;
  final String quotedText;

  factory NoteRecord.fromMap(Map<String, Object?> m) => NoteRecord(
        id: m['id'] as int?,
        bookId: (m['book_id'] as String?) ?? '',
        sectionIndex: (m['section_index'] as int?) ?? 0,
        cfi: (m['cfi'] as String?) ?? '',
        charOffset: (m['char_offset'] as int?) ?? 0,
        content: (m['content'] as String?) ?? '',
        quotedText: (m['quoted_text'] as String?) ?? '',
      );
}

class BookmarkRecord {
  BookmarkRecord({
    this.id,
    required this.bookId,
    required this.sectionIndex,
    required this.cfi,
    required this.charOffset,
    required this.label,
  });

  final int? id;
  final String bookId;
  final int sectionIndex;
  final String cfi;
  final int charOffset;
  final String label;

  factory BookmarkRecord.fromMap(Map<String, Object?> m) => BookmarkRecord(
        id: m['id'] as int?,
        bookId: (m['book_id'] as String?) ?? '',
        sectionIndex: (m['section_index'] as int?) ?? 0,
        cfi: (m['cfi'] as String?) ?? '',
        charOffset: (m['char_offset'] as int?) ?? 0,
        label: (m['label'] as String?) ?? '',
      );
}

class CollectionRecord {
  CollectionRecord({this.id, required this.name, required this.createdAt});

  final int? id;
  final String name;
  final int createdAt;

  factory CollectionRecord.fromMap(Map<String, Object?> m) => CollectionRecord(
        id: m['id'] as int?,
        name: (m['name'] as String?) ?? '',
        createdAt: (m['created_at'] as int?) ?? 0,
      );
}

class ReaderSettingsData {
  ReaderSettingsData({
    required this.fontFamily,
    required this.fontSizePx,
    required this.lineHeight,
    required this.marginPx,
    required this.alignment,
    required this.theme,
  });

  final String fontFamily;
  final int fontSizePx;
  final double lineHeight;
  final int marginPx;
  final String alignment;
  final String theme;

  factory ReaderSettingsData.fromMap(Map<String, Object?> m) => ReaderSettingsData(
        fontFamily: (m['font_family'] as String?) ?? 'System',
        fontSizePx: (m['font_size_px'] as int?) ?? 18,
        lineHeight: ((m['line_height'] as num?) ?? 1.5).toDouble(),
        marginPx: (m['margin_px'] as int?) ?? 48,
        alignment: (m['alignment'] as String?) ?? 'start',
        theme: (m['theme'] as String?) ?? 'light',
      );

  Map<String, Object?> toMap() => {
        'font_family': fontFamily,
        'font_size_px': fontSizePx,
        'line_height': lineHeight,
        'margin_px': marginPx,
        'alignment': alignment,
        'theme': theme,
      };
}
