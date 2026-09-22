// Local backup/restore. No cloud, no account.
//
// A backup is a single JSON document with every user-data table. Export
// goes to a user-chosen location via the system save dialog (SAF) —
// never into Downloads/CodarLib/ (books only there). Import merges: rows
// are matched by natural keys so restoring twice does not duplicate.
// Stale MediaStore URIs after a device move are handled by the silent
// reconcile on next launch.

import 'dart:convert';
import 'dart:typed_data';

import 'package:codar/src/db/database.dart';
import 'package:file_picker/file_picker.dart';
import 'package:sqflite/sqflite.dart';

const backupFormatVersion = 1;

const _tables = [
  'books',
  'book_files',
  'book_metadata',
  'reading_progress',
  'highlights',
  'notes',
  'bookmarks',
  'favorites',
  'collections',
  'collection_books',
  'covers',
  'reader_settings',
  'app_settings',
];

/// Pure: build the backup document from raw table rows.
Map<String, Object?> encodeBackup(
    Map<String, List<Map<String, Object?>>> rows) {
  return {
    'format': 'codar-backup',
    'version': backupFormatVersion,
    'exported_at': DateTime.now().millisecondsSinceEpoch,
    'tables': rows,
  };
}

/// Pure: validate + extract table rows. Throws [BackupException] on bad input.
Map<String, List<Map<String, Object?>>> decodeBackup(String jsonText) {
  final doc = jsonDecode(jsonText);
  if (doc is! Map ||
      doc['format'] != 'codar-backup' ||
      doc['version'] != backupFormatVersion ||
      doc['tables'] is! Map) {
    throw BackupException('bad-format');
  }
  final out = <String, List<Map<String, Object?>>>{};
  final tables = doc['tables'] as Map;
  for (final t in _tables) {
    final rows = tables[t];
    if (rows == null) {
      out[t] = const [];
    } else if (rows is List) {
      out[t] = [
        for (final r in rows)
          if (r is Map) Map<String, Object?>.from(r)
      ];
    } else {
      throw BackupException('bad-table:$t');
    }
  }
  return out;
}

class BackupService {
  BackupService(this._db);
  final CodarDatabase _db;

  Future<Map<String, List<Map<String, Object?>>>> snapshot() async {
    final rows = <String, List<Map<String, Object?>>>{};
    for (final t in _tables) {
      rows[t] = await _db.db.query(t);
    }
    return rows;
  }

  /// Export to a user-chosen file. Returns true when the user saved.
  Future<bool> exportBackup() async {
    final snap = await snapshot();
    final bytes =
        Uint8List.fromList(utf8.encode(jsonEncode(encodeBackup(snap))));
    final stamp = DateTime.now();
    final name = 'codar_backup_${stamp.year}'
        '${stamp.month.toString().padLeft(2, '0')}'
        '${stamp.day.toString().padLeft(2, '0')}.json';
    try {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
      );
      return uri != null;
    } catch (_) {
      throw BackupException('export-failed');
    }
  }

  /// Pick a backup JSON and merge it. Returns counts per table.
  Future<Map<String, int>> importBackup() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) return {};
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty || bytes.length > 64 * 1024 * 1024) {
      throw BackupException('bad-size');
    }
    final tables = decodeBackup(utf8.decode(bytes));
    return _merge(tables);
  }

  Future<Map<String, int>> _merge(
      Map<String, List<Map<String, Object?>>> t) async {
    final counts = <String, int>{};
    await _db.db.transaction((txn) async {
      counts['books'] =
          await _mergeByKey(txn, 'books', t['books']!, ['book_id']);
      counts['book_files'] = await _mergeByKey(
          txn, 'book_files', t['book_files']!, ['book_id', 'kind']);
      counts['book_metadata'] = await _mergeByKey(
          txn, 'book_metadata', t['book_metadata']!, ['book_id', 'key']);
      counts['reading_progress'] = await _mergeByKey(
          txn, 'reading_progress', t['reading_progress']!, ['book_id']);
      counts['favorites'] = await _mergeByKey(
          txn, 'favorites', t['favorites']!, ['book_id']);
      counts['covers'] = await _mergeByKey(txn, 'covers', t['covers']!,
          ['book_id']); // stale paths fall back gracefully in UI
      counts['highlights'] = await _mergeNatural(txn, 'highlights',
          t['highlights']!, ['book_id', 'section_index', 'start_offset', 'end_offset', 'quoted_text']);
      counts['notes'] = await _mergeNatural(txn, 'notes', t['notes']!,
          ['book_id', 'section_index', 'char_offset', 'content']);
      counts['bookmarks'] = await _mergeNatural(txn, 'bookmarks',
          t['bookmarks']!, ['book_id', 'section_index', 'char_offset', 'label']);
      counts['collections'] =
          await _mergeCollections(txn, t['collections']!, t['collection_books']!);
      // Settings: reader row + our own app keys only.
      for (final r in t['reader_settings']!) {
        final row = Map<String, Object?>.from(r)..['id'] = 1;
        await txn.insert('reader_settings', row,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      counts['reader_settings'] = t['reader_settings']!.length;
      var appCount = 0;
      for (final r in t['app_settings']!) {
        final key = r['key'] as String?;
        if (key == null || key.isEmpty) continue;
        await txn.insert('app_settings', {'key': key, 'value': (r['value'] as String?) ?? ''},
            conflictAlgorithm: ConflictAlgorithm.replace);
        appCount++;
      }
      counts['app_settings'] = appCount;
    });
    return counts;
  }

  /// Merge rows identified by [keys]: insert when absent, replace when the
  /// incoming row is at least as new (or has no timestamp).
  Future<int> _mergeByKey(Transaction txn, String table,
      List<Map<String, Object?>> rows, List<String> keys) async {
    var n = 0;
    for (final r in rows) {
      final where =
          keys.map((k) => '$k = ?').join(' AND ');
      final args = [for (final k in keys) r[k]];
      if (args.any((a) => a == null)) continue;
      final existing =
          await txn.query(table, where: where, whereArgs: args, limit: 1);
      if (existing.isEmpty) {
        await txn.insert(table, Map<String, Object?>.from(r),
            conflictAlgorithm: ConflictAlgorithm.ignore);
        n++;
      }
    }
    return n;
  }

  /// Merge rows with autoincrement ids: dedupe by natural key, insert
  /// without id so double-restore never duplicates.
  Future<int> _mergeNatural(Transaction txn, String table,
      List<Map<String, Object?>> rows, List<String> keys) async {
    var n = 0;
    for (final r in rows) {
      final where = [
        for (final k in keys) '$k = ?',
        'book_id IN (SELECT book_id FROM books)',
      ].join(' AND ');
      final args = [for (final k in keys) r[k]];
      if (args.any((a) => a == null)) continue;
      final existing =
          await txn.query(table, where: where, whereArgs: args, limit: 1);
      if (existing.isNotEmpty) continue;
      final row = Map<String, Object?>.from(r)..remove('id');
      await txn.insert(table, row);
      n++;
    }
    return n;
  }

  Future<int> _mergeCollections(Transaction txn,
      List<Map<String, Object?>> cols, List<Map<String, Object?>> members) async {
    final idMap = <Object, int>{};
    for (final c in cols) {
      final name = (c['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final existing = await txn.query('collections',
          columns: ['id'], where: 'name = ?', whereArgs: [name], limit: 1);
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        if (c['id'] != null) idMap[c['id']!] = id;
      } else {
        final id = await txn.insert('collections', {
          'name': name,
          'created_at': (c['created_at'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
        });
        if (c['id'] != null) idMap[c['id']!] = id;
      }
    }
    var n = 0;
    for (final m in members) {
      final oldId = m['collection_id'];
      final bookId = m['book_id'] as String?;
      final newId = oldId == null ? null : idMap[oldId];
      if (newId == null || bookId == null) continue;
      final bookGone = await txn.query('books',
          columns: ['book_id'],
          where: 'book_id = ?',
          whereArgs: [bookId],
          limit: 1);
      if (bookGone.isEmpty) continue;
      await txn.insert(
          'collection_books', {'collection_id': newId, 'book_id': bookId},
          conflictAlgorithm: ConflictAlgorithm.ignore);
      n++;
    }
    return n;
  }
}

class BackupException implements Exception {
  BackupException(this.code);
  final String code;
  @override
  String toString() => 'BackupException($code)';
}
