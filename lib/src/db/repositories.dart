// Repository layer over CodarDatabase. One class per aggregate.

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';

int _now() => DateTime.now().millisecondsSinceEpoch;

class BooksRepository {
  BooksRepository(this._db);
  final CodarDatabase _db;

  /// Commit a new book and its physical-file reference together.
  Future<void> addImportedBook({
    required String bookId,
    required String title,
    required String author,
    required String language,
    required String format,
    required int sectionCount,
    required int fileSize,
    required String fingerprint,
    required String displayName,
    required String mime,
    required String mediastoreUri,
    String titleSource = 'embedded',
  }) async {
    final now = _now();
    await _db.db.transaction((txn) async {
      await txn.insert('books', {
        'book_id': bookId,
        'title': title,
        'author': author,
        'language': language,
        'format': format,
        'section_count': sectionCount,
        'file_size': fileSize,
        'fingerprint': fingerprint,
        'added_at': now,
        'last_opened_at': now,
      });
      await txn.insert('book_files', {
        'book_id': bookId,
        'kind': 'original',
        'display_name': displayName,
        'mime': mime,
        'mediastore_uri': mediastoreUri,
        'cache_path': '',
        'size': fileSize,
      });
      await txn.insert('book_metadata', {
        'book_id': bookId,
        'key': 'title_source',
        'value': titleSource,
      });
    });
  }

  Future<void> upsertBook({
    required String bookId,
    required String title,
    required String author,
    required String language,
    required String format,
    required int sectionCount,
    required int fileSize,
    required String fingerprint,
  }) async {
    final existing = await _db.db.query(
      'books',
      columns: ['added_at'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    final addedAt = existing.isEmpty
        ? _now()
        : (existing.first['added_at'] as int?) ?? _now();
    await _db.db.insert('books', {
      'book_id': bookId,
      'title': title,
      'author': author,
      'language': language,
      'format': format,
      'section_count': sectionCount,
      'file_size': fileSize,
      'fingerprint': fingerprint,
      'added_at': addedAt,
      'last_opened_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<BookRecord?> getBook(String bookId) async {
    final rows = await _db.db.query(
      'books',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookRecord.fromMap(rows.first);
  }

  Future<BookRecord?> findByFingerprint(String fingerprint) async {
    if (fingerprint.isEmpty) return null;
    final rows = await _db.db.query(
      'books',
      where: 'fingerprint = ?',
      whereArgs: [fingerprint],
      orderBy: 'added_at ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return BookRecord.fromMap(rows.first);
  }

  Future<List<BookRecord>> listBooks({
    String? query,
    String order = 'recent',
    bool onlyFavorites = false,
  }) async {
    final orderBy = switch (order) {
      'title' => 'b.title COLLATE NOCASE ASC',
      'author' => 'b.author COLLATE NOCASE ASC, b.title COLLATE NOCASE ASC',
      'added' => 'b.added_at DESC',
      _ => 'b.last_opened_at DESC, b.added_at DESC',
    };
    final favJoin = onlyFavorites
        ? 'JOIN favorites f ON f.book_id = b.book_id'
        : '';
    if (query == null || query.trim().isEmpty) {
      final rows = await _db.db.rawQuery(
        'SELECT b.* FROM books b $favJoin ORDER BY $orderBy',
      );
      return rows.map(BookRecord.fromMap).toList();
    }
    // Escape LIKE wildcards so a literal '%', '_' or '\' in the query
    // cannot broaden the match (ESCAPE clause is already present).
    final escaped = query
        .trim()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final like = '%$escaped%';
    final rows = await _db.db.rawQuery(
      'SELECT b.* FROM books b $favJoin '
      'WHERE b.title LIKE ? ESCAPE "\\" OR b.author LIKE ? ESCAPE "\\" OR '
      'EXISTS (SELECT 1 FROM book_files bf WHERE bf.book_id = b.book_id '
      'AND bf.kind = \'original\' AND bf.display_name LIKE ? ESCAPE "\\") '
      'ORDER BY $orderBy',
      [like, like, like],
    );
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<List<LibraryBookRecord>> listLibraryBooks({
    String? query,
    String order = 'recent',
    bool onlyFavorites = false,
  }) async {
    final orderBy = switch (order) {
      'title' => 'b.title COLLATE NOCASE ASC',
      'author' => 'b.author COLLATE NOCASE ASC, b.title COLLATE NOCASE ASC',
      'added' => 'b.added_at DESC',
      _ => 'b.last_opened_at DESC, b.added_at DESC',
    };
    final favJoin = onlyFavorites
        ? 'JOIN favorites f ON f.book_id = b.book_id'
        : '';
    const progressColumns = '''
      p.locator_json AS progress_locator_json,
      p.section_index AS progress_section_index,
      p.char_offset AS progress_char_offset,
      p.progression AS progress_progression,
      p.updated_at AS progress_updated_at
    ''';
    final escaped = query
        ?.trim()
        .replaceAll('\\', '\\\\')
        .replaceAll('%', '\\%')
        .replaceAll('_', '\\_');
    final like = escaped == null ? null : '%$escaped%';

    final rows = like == null || like == '%%'
        ? await _db.db.rawQuery(
            'SELECT b.*, $progressColumns FROM books b '
            '$favJoin LEFT JOIN reading_progress p ON p.book_id = b.book_id '
            'ORDER BY $orderBy',
          )
        : await _db.db.rawQuery(
            'SELECT b.*, $progressColumns FROM books b '
            '$favJoin LEFT JOIN reading_progress p ON p.book_id = b.book_id '
            'WHERE b.title LIKE ? ESCAPE "\\" OR '
            'b.author LIKE ? ESCAPE "\\" OR EXISTS ('
            'SELECT 1 FROM book_files bf WHERE bf.book_id = b.book_id '
            'AND bf.kind = \'original\' AND bf.display_name LIKE ? ESCAPE "\\") '
            'ORDER BY $orderBy',
            [like, like, like],
          );
    return rows.map(LibraryBookRecord.fromMap).toList();
  }

  Future<List<BookRecord>> continueReading({int limit = 10}) async {
    final rows = await _db.db.rawQuery(
      '''
      SELECT b.* FROM books b
      JOIN reading_progress p ON p.book_id = b.book_id
      WHERE p.char_offset > 0 OR p.progression > 0
      ORDER BY p.updated_at DESC LIMIT ?
    ''',
      [limit],
    );
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<List<BookRecord>> recentlyRead({int limit = 10}) async {
    final rows = await _db.db.query(
      'books',
      where: 'last_opened_at > 0',
      orderBy: 'last_opened_at DESC',
      limit: limit,
    );
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<List<BookRecord>> recentlyAdded({int limit = 10}) async {
    final rows = await _db.db.rawQuery(
      '''
      SELECT b.* FROM books b
      WHERE NOT EXISTS (
        SELECT 1 FROM book_metadata bm
        WHERE bm.book_id = b.book_id
          AND bm.key = 'bundled_sample'
          AND bm.value = '1'
      )
      ORDER BY b.added_at DESC
      LIMIT ?
      ''',
      [limit],
    );
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<void> touchOpened(String bookId) async {
    await _db.db.update(
      'books',
      {'last_opened_at': _now()},
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
  }

  /// User-edited core fields. Stored in the DB only; the original
  /// book file is never modified.
  Future<void> updateBookFields(
    String bookId, {
    String? title,
    String? author,
    String? language,
  }) async {
    final patch = <String, Object?>{};
    if (title != null) patch['title'] = title;
    if (author != null) patch['author'] = author;
    if (language != null) patch['language'] = language;
    if (patch.isEmpty) return;
    await _db.db.update(
      'books',
      patch,
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    await setMetadata(bookId, 'user_edited', '1');
  }

  /// Updates only import-derived fields while retaining the existing book ID
  /// and every progress/annotation relation.
  Future<void> updateMachineDerivedBookFields(
    String bookId, {
    required String title,
    String? author,
    required String titleSource,
  }) async {
    await _db.db.transaction((txn) async {
      await txn.update(
        'books',
        <String, Object?>{'title': title, 'author': ?author},
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
      await txn.insert('book_metadata', {
        'book_id': bookId,
        'key': 'title_source',
        'value': titleSource,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('book_metadata', {
        'book_id': bookId,
        'key': 'user_edited',
        'value': '0',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> deleteBook(String bookId) async {
    await _db.db.delete('books', where: 'book_id = ?', whereArgs: [bookId]);
  }

  Future<void> upsertFile({
    required String bookId,
    required String kind,
    required String displayName,
    required String mime,
    required String mediastoreUri,
    required String cachePath,
    required int size,
  }) async {
    await _db.db.insert('book_files', {
      'book_id': bookId,
      'kind': kind,
      'display_name': displayName,
      'mime': mime,
      'mediastore_uri': mediastoreUri,
      'cache_path': cachePath,
      'size': size,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<FileRecord?> getFile(String bookId, String kind) async {
    final rows = await _db.db.query(
      'book_files',
      where: 'book_id = ? AND kind = ?',
      whereArgs: [bookId, kind],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return FileRecord.fromMap(rows.first);
  }

  Future<void> setMetadata(String bookId, String key, String value) async {
    await _db.db.insert('book_metadata', {
      'book_id': bookId,
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getMetadata(String bookId) async {
    final rows = await _db.db.query(
      'book_metadata',
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    return {
      for (final r in rows) (r['key'] as String): (r['value'] as String?) ?? '',
    };
  }

  Future<void> saveCover({
    required String bookId,
    required String path,
    required String mime,
  }) async {
    await _db.db.insert('covers', {
      'book_id': bookId,
      'path': path,
      'mime': mime,
      'width': 0,
      'height': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> coverPath(String bookId) async {
    final rows = await _db.db.query(
      'covers',
      columns: ['path'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['path'] as String?;
  }
}

class ProgressRepository {
  ProgressRepository(this._db);
  final CodarDatabase _db;

  Future<void> saveProgress({
    required String bookId,
    required String locatorJson,
    required int sectionIndex,
    required int charOffset,
    required double progression,
  }) async {
    await _db.db.insert('reading_progress', {
      'book_id': bookId,
      'locator_json': locatorJson,
      'section_index': sectionIndex,
      'char_offset': charOffset,
      'progression': progression,
      'updated_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<ProgressRecord?> loadProgress(String bookId) async {
    final rows = await _db.db.query(
      'reading_progress',
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ProgressRecord.fromMap(rows.first);
  }
}

class AnnotationsRepository {
  AnnotationsRepository(this._db);
  final CodarDatabase _db;

  Future<int> addHighlight(HighlightRecord h) async {
    final t = _now();
    return _db.db.insert('highlights', {
      'book_id': h.bookId,
      'section_index': h.sectionIndex,
      'start_offset': h.startOffset,
      'end_offset': h.endOffset,
      'offset_unit': 'rust_scalar',
      'cfi': h.cfi,
      'color': h.color,
      'quoted_text': h.quotedText,
      'note': h.note,
      'created_at': t,
      'updated_at': t,
    });
  }

  Future<void> updateHighlightNote(int id, String note) async {
    await _db.db.update(
      'highlights',
      {'note': note, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateHighlightColor(int id, int color) async {
    await _db.db.update(
      'highlights',
      {'color': color, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateHighlightRange(int id, HighlightRecord highlight) async {
    await _db.db.update(
      'highlights',
      {
        'start_offset': highlight.startOffset,
        'end_offset': highlight.endOffset,
        'offset_unit': 'rust_scalar',
        'cfi': highlight.cfi,
        'quoted_text': highlight.quotedText,
        'updated_at': _now(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateHighlightOffsetsAsRustScalars(
    int id,
    int startOffset,
    int endOffset,
  ) async {
    await _db.db.update(
      'highlights',
      {
        'start_offset': startOffset,
        'end_offset': endOffset,
        'offset_unit': 'rust_scalar',
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteHighlight(int id) async {
    await _db.db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<HighlightRecord>> highlightsForSection(
    String bookId,
    int sectionIndex,
  ) async {
    final rows = await _db.db.query(
      'highlights',
      where: 'book_id = ? AND section_index = ?',
      whereArgs: [bookId, sectionIndex],
      orderBy: 'start_offset ASC',
    );
    return rows.map(HighlightRecord.fromMap).toList();
  }

  Future<List<HighlightRecord>> allHighlights(String bookId) async {
    final rows = await _db.db.query(
      'highlights',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(HighlightRecord.fromMap).toList();
  }

  Future<int> addNote(NoteRecord n) async {
    final t = _now();
    return _db.db.insert('notes', {
      'book_id': n.bookId,
      'section_index': n.sectionIndex,
      'cfi': n.cfi,
      'char_offset': n.charOffset,
      'content': n.content,
      'quoted_text': n.quotedText,
      'created_at': t,
      'updated_at': t,
    });
  }

  Future<void> updateNote(int id, String content) async {
    await _db.db.update(
      'notes',
      {'content': content, 'updated_at': _now()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteNote(int id) async {
    await _db.db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NoteRecord>> allNotes(String bookId) async {
    final rows = await _db.db.query(
      'notes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(NoteRecord.fromMap).toList();
  }

  Future<int> addBookmark(BookmarkRecord b) async {
    return _db.db.transaction((txn) async {
      final existing = await txn.query(
        'bookmarks',
        columns: ['id'],
        where: 'book_id = ? AND section_index = ? AND char_offset = ?',
        whereArgs: [b.bookId, b.sectionIndex, b.charOffset],
        limit: 1,
      );
      if (existing.isNotEmpty) return existing.first['id'] as int;
      return txn.insert('bookmarks', {
        'book_id': b.bookId,
        'section_index': b.sectionIndex,
        'cfi': b.cfi,
        'char_offset': b.charOffset,
        'label': b.label,
        'created_at': _now(),
      });
    });
  }

  Future<void> deleteBookmark(int id) async {
    await _db.db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteBookmarksAt({
    required String bookId,
    required int sectionIndex,
    required int charOffset,
  }) async =>
      _db.db.delete(
        'bookmarks',
        where: 'book_id = ? AND section_index = ? AND char_offset = ?',
        whereArgs: [bookId, sectionIndex, charOffset],
      );

  Future<List<BookmarkRecord>> allBookmarks(String bookId) async {
    final rows = await _db.db.query(
      'bookmarks',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    return rows.map(BookmarkRecord.fromMap).toList();
  }

  Future<int> addQuote(QuoteRecord quote) async =>
      _db.db.transaction((txn) async {
        final id = await txn.insert('quotes', {
          'book_id': quote.bookId,
          'section_index': quote.sectionIndex,
          'char_offset': quote.charOffset,
          'cfi': quote.cfi,
          'quoted_text': quote.quotedText,
          'created_at': _now(),
        });
        for (var index = 0; index < quote.ranges.length; index++) {
          final range = quote.ranges[index];
          await txn.insert('quote_ranges', {
            'quote_id': id,
            'range_index': index,
            'section_index': range.sectionIndex,
            'start_offset': range.startOffset,
            'end_offset': range.endOffset,
          });
        }
        return id;
      });

  /// Atomically toggles one quote at its persisted source location.
  /// Any legacy duplicate rows for the same selection are removed together.
  Future<QuoteRecord?> toggleQuote(
    QuoteRecord quote,
  ) async => _db.db.transaction((txn) async {
    final where =
        'book_id = ? AND section_index = ? AND char_offset = ? AND quoted_text = ?';
    final whereArgs = [
      quote.bookId,
      quote.sectionIndex,
      quote.charOffset,
      quote.quotedText,
    ];
    final existing = await txn.query(
      'quotes',
      columns: ['id'],
      where: where,
      whereArgs: whereArgs,
      limit: 1,
    );
    if (existing.isNotEmpty) {
      await txn.delete('quotes', where: where, whereArgs: whereArgs);
      return null;
    }

    final createdAt = _now();
    final id = await txn.insert('quotes', {
      'book_id': quote.bookId,
      'section_index': quote.sectionIndex,
      'char_offset': quote.charOffset,
      'cfi': quote.cfi,
      'quoted_text': quote.quotedText,
      'created_at': createdAt,
    });
    for (var index = 0; index < quote.ranges.length; index++) {
      final range = quote.ranges[index];
      await txn.insert('quote_ranges', {
        'quote_id': id,
        'range_index': index,
        'section_index': range.sectionIndex,
        'start_offset': range.startOffset,
        'end_offset': range.endOffset,
      });
    }
    return QuoteRecord(
      id: id,
      bookId: quote.bookId,
      sectionIndex: quote.sectionIndex,
      charOffset: quote.charOffset,
      cfi: quote.cfi,
      quotedText: quote.quotedText,
      createdAt: createdAt,
      ranges: List.unmodifiable(quote.ranges),
    );
  });

  Future<void> deleteQuote(int id) async {
    await _db.db.delete('quotes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<QuoteRecord>> allQuotes(String bookId) async {
    final rows = await _db.db.query(
      'quotes',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'created_at DESC',
    );
    if (rows.isEmpty) return const [];
    final ranges = await _db.db.query(
      'quote_ranges',
      where: 'quote_id IN (SELECT id FROM quotes WHERE book_id = ?)',
      whereArgs: [bookId],
      orderBy: 'quote_id, range_index',
    );
    final rangesByQuote = <int, List<QuoteRangeRecord>>{};
    for (final range in ranges) {
      final quoteId = range['quote_id'] as int;
      (rangesByQuote[quoteId] ??= []).add(
        QuoteRangeRecord(
          sectionIndex: range['section_index'] as int,
          startOffset: range['start_offset'] as int,
          endOffset: range['end_offset'] as int,
        ),
      );
    }
    return rows.map((row) {
      final quote = QuoteRecord.fromMap(row);
      return quote.withRanges(rangesByQuote[quote.id] ?? const []);
    }).toList();
  }

  Future<int> quoteCount() async {
    final rows = await _db.db.rawQuery('SELECT COUNT(*) AS count FROM quotes');
    return (rows.first['count'] as int?) ?? 0;
  }
}

class LibraryRepository {
  LibraryRepository(this._db);
  final CodarDatabase _db;

  Future<bool> isFavorite(String bookId) async {
    final rows = await _db.db.query(
      'favorites',
      columns: ['book_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<void> setFavorite(String bookId, bool favorite) async {
    if (favorite) {
      await _db.db.insert('favorites', {
        'book_id': bookId,
        'created_at': _now(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.db.delete(
        'favorites',
        where: 'book_id = ?',
        whereArgs: [bookId],
      );
    }
  }

  Future<List<BookRecord>> favorites() async {
    final rows = await _db.db.rawQuery('''
      SELECT b.* FROM books b JOIN favorites f ON f.book_id = b.book_id
      ORDER BY f.created_at DESC
    ''');
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<int> createCollection(String name) async {
    return _db.db.insert('collections', {
      'name': name.trim(),
      'created_at': _now(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> deleteCollection(int id) async {
    await _db.db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<CollectionRecord>> collections() async {
    final rows = await _db.db.query('collections', orderBy: 'created_at ASC');
    return rows.map(CollectionRecord.fromMap).toList();
  }

  Future<Set<int>> collectionIdsForBook(String bookId) async {
    final rows = await _db.db.query(
      'collection_books',
      columns: ['collection_id'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    return {for (final r in rows) (r['collection_id'] as int?) ?? -1}
      ..remove(-1);
  }

  Future<void> setBookInCollection(
    int collectionId,
    String bookId,
    bool member,
  ) async {
    if (member) {
      await _db.db.insert('collection_books', {
        'collection_id': collectionId,
        'book_id': bookId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.db.delete(
        'collection_books',
        where: 'collection_id = ? AND book_id = ?',
        whereArgs: [collectionId, bookId],
      );
    }
  }

  Future<List<BookRecord>> collectionBooks(int collectionId) async {
    final rows = await _db.db.rawQuery(
      '''
      SELECT b.* FROM books b
      JOIN collection_books cb ON cb.book_id = b.book_id
      WHERE cb.collection_id = ? ORDER BY b.title COLLATE NOCASE ASC
    ''',
      [collectionId],
    );
    return rows.map(BookRecord.fromMap).toList();
  }
}

class SettingsRepository {
  SettingsRepository(this._db);
  final CodarDatabase _db;

  Future<ReaderSettingsData> readerSettings() async {
    final rows = await _db.db.query(
      'reader_settings',
      where: 'id = 1',
      limit: 1,
    );
    if (rows.isEmpty) return ReaderSettingsData.fromMap({});
    return ReaderSettingsData.fromMap(rows.first);
  }

  Future<void> saveReaderSettings(ReaderSettingsData s) async {
    final map = s.toMap()..['id'] = 1;
    await _db.db.insert(
      'reader_settings',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> appValue(String key, String fallback) async {
    final rows = await _db.db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return fallback;
    return (rows.first['value'] as String?) ?? fallback;
  }

  Future<void> setAppValue(String key, String value) async {
    await _db.db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
