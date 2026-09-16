// Repository layer over CodarDatabase. One class per aggregate.

import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'models.dart';

int _now() => DateTime.now().millisecondsSinceEpoch;

class BooksRepository {
  BooksRepository(this._db);
  final CodarDatabase _db;

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
    final existing = await _db.db.query('books',
        columns: ['added_at'], where: 'book_id = ?', whereArgs: [bookId]);
    final addedAt =
        existing.isEmpty ? _now() : (existing.first['added_at'] as int?) ?? _now();
    await _db.db.insert(
      'books',
      {
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
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<BookRecord?> getBook(String bookId) async {
    final rows = await _db.db
        .query('books', where: 'book_id = ?', whereArgs: [bookId], limit: 1);
    if (rows.isEmpty) return null;
    return BookRecord.fromMap(rows.first);
  }

  Future<List<BookRecord>> listBooks({String? query, String order = 'recent'}) async {
    final orderBy = switch (order) {
      'title' => 'title COLLATE NOCASE ASC',
      'author' => 'author COLLATE NOCASE ASC, title COLLATE NOCASE ASC',
      _ => 'last_opened_at DESC, added_at DESC',
    };
    if (query == null || query.trim().isEmpty) {
      final rows = await _db.db.query('books', orderBy: orderBy);
      return rows.map(BookRecord.fromMap).toList();
    }
    final like = '%${query.trim()}%';
    final rows = await _db.db.query('books',
        where: 'title LIKE ? ESCAPE "\\" OR author LIKE ? ESCAPE "\\"',
        whereArgs: [like, like],
        orderBy: orderBy);
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<List<BookRecord>> continueReading({int limit = 10}) async {
    final rows = await _db.db.rawQuery('''
      SELECT b.* FROM books b
      JOIN reading_progress p ON p.book_id = b.book_id
      ORDER BY p.updated_at DESC LIMIT ?
    ''', [limit]);
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<List<BookRecord>> recentlyRead({int limit = 10}) async {
    final rows = await _db.db.query('books',
        where: 'last_opened_at > 0',
        orderBy: 'last_opened_at DESC',
        limit: limit);
    return rows.map(BookRecord.fromMap).toList();
  }

  Future<void> touchOpened(String bookId) async {
    await _db.db.update('books', {'last_opened_at': _now()},
        where: 'book_id = ?', whereArgs: [bookId]);
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
    await _db.db.insert(
      'book_files',
      {
        'book_id': bookId,
        'kind': kind,
        'display_name': displayName,
        'mime': mime,
        'mediastore_uri': mediastoreUri,
        'cache_path': cachePath,
        'size': size,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<FileRecord?> getFile(String bookId, String kind) async {
    final rows = await _db.db.query('book_files',
        where: 'book_id = ? AND kind = ?', whereArgs: [bookId, kind], limit: 1);
    if (rows.isEmpty) return null;
    return FileRecord.fromMap(rows.first);
  }

  Future<void> setMetadata(String bookId, String key, String value) async {
    await _db.db.insert(
      'book_metadata',
      {'book_id': bookId, 'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Map<String, String>> getMetadata(String bookId) async {
    final rows = await _db.db.query('book_metadata',
        where: 'book_id = ?', whereArgs: [bookId]);
    return {
      for (final r in rows) (r['key'] as String): (r['value'] as String?) ?? ''
    };
  }

  Future<void> saveCover({
    required String bookId,
    required String path,
    required String mime,
  }) async {
    await _db.db.insert(
      'covers',
      {'book_id': bookId, 'path': path, 'mime': mime, 'width': 0, 'height': 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> coverPath(String bookId) async {
    final rows = await _db.db.query('covers',
        columns: ['path'], where: 'book_id = ?', whereArgs: [bookId], limit: 1);
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
    await _db.db.insert(
      'reading_progress',
      {
        'book_id': bookId,
        'locator_json': locatorJson,
        'section_index': sectionIndex,
        'char_offset': charOffset,
        'progression': progression,
        'updated_at': _now(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<ProgressRecord?> loadProgress(String bookId) async {
    final rows = await _db.db.query('reading_progress',
        where: 'book_id = ?', whereArgs: [bookId], limit: 1);
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
      'cfi': h.cfi,
      'color': h.color,
      'quoted_text': h.quotedText,
      'note': h.note,
      'created_at': t,
      'updated_at': t,
    });
  }

  Future<void> updateHighlightNote(int id, String note) async {
    await _db.db.update('highlights', {'note': note, 'updated_at': _now()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteHighlight(int id) async {
    await _db.db.delete('highlights', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<HighlightRecord>> highlightsForSection(
      String bookId, int sectionIndex) async {
    final rows = await _db.db.query('highlights',
        where: 'book_id = ? AND section_index = ?',
        whereArgs: [bookId, sectionIndex],
        orderBy: 'start_offset ASC');
    return rows.map(HighlightRecord.fromMap).toList();
  }

  Future<List<HighlightRecord>> allHighlights(String bookId) async {
    final rows = await _db.db.query('highlights',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
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
    await _db.db.update('notes', {'content': content, 'updated_at': _now()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteNote(int id) async {
    await _db.db.delete('notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<NoteRecord>> allNotes(String bookId) async {
    final rows = await _db.db.query('notes',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
    return rows.map(NoteRecord.fromMap).toList();
  }

  Future<int> addBookmark(BookmarkRecord b) async {
    return _db.db.insert('bookmarks', {
      'book_id': b.bookId,
      'section_index': b.sectionIndex,
      'cfi': b.cfi,
      'char_offset': b.charOffset,
      'label': b.label,
      'created_at': _now(),
    });
  }

  Future<void> deleteBookmark(int id) async {
    await _db.db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<BookmarkRecord>> allBookmarks(String bookId) async {
    final rows = await _db.db.query('bookmarks',
        where: 'book_id = ?', whereArgs: [bookId], orderBy: 'created_at DESC');
    return rows.map(BookmarkRecord.fromMap).toList();
  }
}

class LibraryRepository {
  LibraryRepository(this._db);
  final CodarDatabase _db;

  Future<bool> isFavorite(String bookId) async {
    final rows = await _db.db.query('favorites',
        columns: ['book_id'], where: 'book_id = ?', whereArgs: [bookId], limit: 1);
    return rows.isNotEmpty;
  }

  Future<void> setFavorite(String bookId, bool favorite) async {
    if (favorite) {
      await _db.db.insert(
        'favorites',
        {'book_id': bookId, 'created_at': _now()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await _db.db
          .delete('favorites', where: 'book_id = ?', whereArgs: [bookId]);
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
    return _db.db.insert(
      'collections',
      {'name': name.trim(), 'created_at': _now()},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> deleteCollection(int id) async {
    await _db.db.delete('collections', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<CollectionRecord>> collections() async {
    final rows =
        await _db.db.query('collections', orderBy: 'created_at ASC');
    return rows.map(CollectionRecord.fromMap).toList();
  }

  Future<void> setBookInCollection(
      int collectionId, String bookId, bool member) async {
    if (member) {
      await _db.db.insert(
        'collection_books',
        {'collection_id': collectionId, 'book_id': bookId},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      await _db.db.delete('collection_books',
          where: 'collection_id = ? AND book_id = ?',
          whereArgs: [collectionId, bookId]);
    }
  }

  Future<List<BookRecord>> collectionBooks(int collectionId) async {
    final rows = await _db.db.rawQuery('''
      SELECT b.* FROM books b
      JOIN collection_books cb ON cb.book_id = b.book_id
      WHERE cb.collection_id = ? ORDER BY b.title COLLATE NOCASE ASC
    ''', [collectionId]);
    return rows.map(BookRecord.fromMap).toList();
  }
}

class SettingsRepository {
  SettingsRepository(this._db);
  final CodarDatabase _db;

  Future<ReaderSettingsData> readerSettings() async {
    final rows =
        await _db.db.query('reader_settings', where: 'id = 1', limit: 1);
    if (rows.isEmpty) return ReaderSettingsData.fromMap({});
    return ReaderSettingsData.fromMap(rows.first);
  }

  Future<void> saveReaderSettings(ReaderSettingsData s) async {
    final map = s.toMap()..['id'] = 1;
    await _db.db.insert('reader_settings', map,
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String> appValue(String key, String fallback) async {
    final rows = await _db.db.query('app_settings',
        columns: ['value'], where: 'key = ?', whereArgs: [key], limit: 1);
    if (rows.isEmpty) return fallback;
    return (rows.first['value'] as String?) ?? fallback;
  }

  Future<void> setAppValue(String key, String value) async {
    await _db.db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
