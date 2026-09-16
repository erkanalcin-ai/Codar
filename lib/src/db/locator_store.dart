// Phase 1 SQLite seed: proves Readium locator JSON persistence round-trip.
// Full product schema comes later; this is the minimum locator store.

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class LocatorStore {
  LocatorStore._(this._db);
  final Database _db;

  static Future<LocatorStore> open({String? pathOverride}) async {
    final dir = await getApplicationDocumentsDirectory();
    final path = pathOverride ?? p.join(dir.path, 'codar_spike.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE books(
            book_id TEXT PRIMARY KEY,
            locator_json TEXT NOT NULL,
            updated_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return LocatorStore._(db);
  }

  Future<void> saveLocator(String bookId, String locatorJson) async {
    await _db.insert(
      'books',
      {
        'book_id': bookId,
        'locator_json': locatorJson,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> loadLocator(String bookId) async {
    final rows = await _db.query(
      'books',
      columns: ['locator_json'],
      where: 'book_id = ?',
      whereArgs: [bookId],
    );
    if (rows.isEmpty) return null;
    return rows.first['locator_json'] as String?;
  }

  Future<void> close() => _db.close();
}
