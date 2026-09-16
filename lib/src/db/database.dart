// Codar local database: full Phase 2 schema (12 tables).
//
// Private data lives ONLY here (app documents dir). Downloads/CodarLib/
// contains book files and nothing else. Original book files are never
// modified — metadata/annotations live in this database.

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class CodarDatabase {
  CodarDatabase._(this.db);
  final Database db;

  static const _name = 'codar.db';
  static const version = 1;

  static Future<CodarDatabase> open({String? pathOverride}) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = pathOverride ?? p.join(dir.path, _name);
    final db = await openDatabase(path, version: version,
        onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE books(
          book_id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          author TEXT NOT NULL DEFAULT '',
          language TEXT NOT NULL DEFAULT '',
          format TEXT NOT NULL,
          section_count INTEGER NOT NULL DEFAULT 0,
          file_size INTEGER NOT NULL DEFAULT 0,
          fingerprint TEXT NOT NULL DEFAULT '',
          added_at INTEGER NOT NULL,
          last_opened_at INTEGER NOT NULL DEFAULT 0
        )''');
      await db.execute('''
        CREATE TABLE book_files(
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          kind TEXT NOT NULL,
          display_name TEXT NOT NULL,
          mime TEXT NOT NULL DEFAULT '',
          mediastore_uri TEXT NOT NULL DEFAULT '',
          cache_path TEXT NOT NULL DEFAULT '',
          size INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (book_id, kind)
        )''');
      await db.execute('''
        CREATE TABLE book_metadata(
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          key TEXT NOT NULL,
          value TEXT NOT NULL DEFAULT '',
          PRIMARY KEY (book_id, key)
        )''');
      await db.execute('''
        CREATE TABLE reading_progress(
          book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
          locator_json TEXT NOT NULL,
          section_index INTEGER NOT NULL DEFAULT 0,
          char_offset INTEGER NOT NULL DEFAULT 0,
          progression REAL NOT NULL DEFAULT 0,
          updated_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE highlights(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          section_index INTEGER NOT NULL,
          start_offset INTEGER NOT NULL,
          end_offset INTEGER NOT NULL,
          cfi TEXT NOT NULL DEFAULT '',
          color INTEGER NOT NULL,
          quoted_text TEXT NOT NULL DEFAULT '',
          note TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE notes(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          section_index INTEGER NOT NULL,
          cfi TEXT NOT NULL DEFAULT '',
          char_offset INTEGER NOT NULL DEFAULT 0,
          content TEXT NOT NULL,
          quoted_text TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE bookmarks(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          section_index INTEGER NOT NULL,
          cfi TEXT NOT NULL DEFAULT '',
          char_offset INTEGER NOT NULL DEFAULT 0,
          label TEXT NOT NULL DEFAULT '',
          created_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE favorites(
          book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
          created_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE collections(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          created_at INTEGER NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE collection_books(
          collection_id INTEGER NOT NULL REFERENCES collections(id) ON DELETE CASCADE,
          book_id TEXT NOT NULL REFERENCES books(book_id) ON DELETE CASCADE,
          PRIMARY KEY (collection_id, book_id)
        )''');
      await db.execute('''
        CREATE TABLE covers(
          book_id TEXT PRIMARY KEY REFERENCES books(book_id) ON DELETE CASCADE,
          path TEXT NOT NULL,
          mime TEXT NOT NULL DEFAULT '',
          width INTEGER NOT NULL DEFAULT 0,
          height INTEGER NOT NULL DEFAULT 0
        )''');
      await db.execute('''
        CREATE TABLE reader_settings(
          id INTEGER PRIMARY KEY CHECK (id = 1),
          font_family TEXT NOT NULL DEFAULT 'System',
          font_size_px INTEGER NOT NULL DEFAULT 18,
          line_height REAL NOT NULL DEFAULT 1.5,
          margin_px INTEGER NOT NULL DEFAULT 48,
          alignment TEXT NOT NULL DEFAULT 'start',
          theme TEXT NOT NULL DEFAULT 'light'
        )''');
      await db.execute('''
        CREATE TABLE app_settings(
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL DEFAULT ''
        )''');
      await db.insert('reader_settings', {'id': 1});
      await db.insert('app_settings', {'key': 'locale', 'value': 'tr'});
    }, onConfigure: (db) async {
      await db.execute('PRAGMA foreign_keys = ON');
    });
    return CodarDatabase._(db);
  }

  Future<void> close() => db.close();
}
