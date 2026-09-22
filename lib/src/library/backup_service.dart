// Local backup/restore. No cloud, no account.
//
// A backup is a single JSON document with every user-data table. Export
// goes to a user-chosen location via the system save dialog (SAF) —
// never into Downloads/CodarLib/ (books only there). Import merges: rows
// are matched by natural keys so restoring twice does not duplicate.
// Device-bound MediaStore/cache paths are not portable and are cleared while
// restoring a metadata-only book. The silent reconcile therefore keeps those
// rows while continuing to purge normal imports whose URI disappeared.

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

/// Device-bound paths from a JSON backup are never valid restore references.
/// Keep the descriptive file metadata, but leave the physical file detached.
Map<String, Object?> normalizeRestoredBookFile(
  Map<String, Object?> row, {
  String? canonicalBookId,
}) {
  final normalized = Map<String, Object?>.from(row)
    ..['mediastore_uri'] = ''
    ..['cache_path'] = '';
  if (canonicalBookId != null) normalized['book_id'] = canonicalBookId;
  return normalized;
}

Map<String, Object?> _normalizeRestoredCover(
  Map<String, Object?> row, {
  required String canonicalBookId,
}) {
  return Map<String, Object?>.from(row)
    ..['book_id'] = canonicalBookId
    // The cover bytes are not part of a JSON backup; the old absolute path is
    // therefore not portable. The UI will use its normal cover fallback.
    ..['path'] = '';
}

/// Pure: build the backup document from raw table rows.
Map<String, Object?> encodeBackup(
  Map<String, List<Map<String, Object?>>> rows,
) {
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
          if (r is Map) Map<String, Object?>.from(r),
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
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(encodeBackup(snap))),
    );
    final stamp = DateTime.now();
    final name =
        'codar_backup_${stamp.year}'
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
    Map<String, List<Map<String, Object?>>> t,
  ) async {
    final counts = <String, int>{};
    await _db.db.transaction((txn) async {
      final bookIdMap = <String, String>{};
      counts['books'] = await _mergeBooks(txn, t['books']!, bookIdMap);
      counts['book_files'] = await _mergeMappedByKey(
        txn,
        'book_files',
        t['book_files']!,
        ['book_id', 'kind'],
        bookIdMap,
        normalizeBookFile: true,
      );
      counts['book_metadata'] = await _mergeMappedByKey(
        txn,
        'book_metadata',
        t['book_metadata']!,
        ['book_id', 'key'],
        bookIdMap,
      );
      counts['reading_progress'] = await _mergeMappedByKey(
        txn,
        'reading_progress',
        t['reading_progress']!,
        ['book_id'],
        bookIdMap,
      );
      counts['favorites'] = await _mergeMappedByKey(
        txn,
        'favorites',
        t['favorites']!,
        ['book_id'],
        bookIdMap,
      );
      counts['covers'] = await _mergeMappedByKey(
        txn,
        'covers',
        t['covers']!,
        ['book_id'],
        bookIdMap,
        normalizeCover: true,
      );
      counts['highlights'] = await _mergeNatural(
        txn,
        'highlights',
        _remapBookIds(t['highlights']!, bookIdMap),
        [
          'book_id',
          'section_index',
          'start_offset',
          'end_offset',
          'quoted_text',
        ],
      );
      counts['notes'] = await _mergeNatural(
        txn,
        'notes',
        _remapBookIds(t['notes']!, bookIdMap),
        ['book_id', 'section_index', 'char_offset', 'content'],
      );
      counts['bookmarks'] = await _mergeNatural(
        txn,
        'bookmarks',
        _remapBookIds(t['bookmarks']!, bookIdMap),
        ['book_id', 'section_index', 'char_offset', 'label'],
      );
      counts['collections'] = await _mergeCollections(
        txn,
        t['collections']!,
        t['collection_books']!,
        bookIdMap,
      );

      // Keep existing local settings. A backup may fill a missing key, but it
      // must not silently replace the current device preference.
      var readerCount = 0;
      for (final r in t['reader_settings']!) {
        final row = Map<String, Object?>.from(r)..['id'] = 1;
        final existing = await txn.query(
          'reader_settings',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [1],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert(
            'reader_settings',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          readerCount++;
        }
      }
      counts['reader_settings'] = readerCount;
      var appCount = 0;
      for (final r in t['app_settings']!) {
        final key = r['key'] as String?;
        if (key == null || key.isEmpty) continue;
        final existing = await txn.query(
          'app_settings',
          columns: ['key'],
          where: 'key = ?',
          whereArgs: [key],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('app_settings', {
            'key': key,
            'value': (r['value'] as String?) ?? '',
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
          appCount++;
        }
      }
      counts['app_settings'] = appCount;
    });
    return counts;
  }

  Future<int> _mergeBooks(
    Transaction txn,
    List<Map<String, Object?>> rows,
    Map<String, String> bookIdMap,
  ) async {
    var n = 0;
    for (final source in rows) {
      final sourceId = source['book_id'] as String?;
      if (sourceId == null || sourceId.isEmpty) continue;
      final fingerprint = (source['fingerprint'] as String?)?.trim() ?? '';
      var existing = await txn.query(
        'books',
        where: 'book_id = ?',
        whereArgs: [sourceId],
        limit: 1,
      );
      if (existing.isEmpty && fingerprint.isNotEmpty) {
        existing = await txn.query(
          'books',
          where: 'fingerprint = ?',
          whereArgs: [fingerprint],
          orderBy: 'added_at ASC',
          limit: 1,
        );
      }

      if (existing.isNotEmpty) {
        bookIdMap[sourceId] = existing.first['book_id'] as String;
        continue;
      }

      await txn.insert(
        'books',
        Map<String, Object?>.from(source),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      bookIdMap[sourceId] = sourceId;
      n++;
    }
    return n;
  }

  List<Map<String, Object?>> _remapBookIds(
    List<Map<String, Object?>> rows,
    Map<String, String> bookIdMap,
  ) {
    final remapped = <Map<String, Object?>>[];
    for (final source in rows) {
      final sourceId = source['book_id'] as String?;
      final canonicalId = sourceId == null ? null : bookIdMap[sourceId];
      if (canonicalId == null) continue;
      remapped.add(
        Map<String, Object?>.from(source)..['book_id'] = canonicalId,
      );
    }
    return remapped;
  }

  Future<int> _mergeMappedByKey(
    Transaction txn,
    String table,
    List<Map<String, Object?>> rows,
    List<String> keys,
    Map<String, String> bookIdMap, {
    bool normalizeBookFile = false,
    bool normalizeCover = false,
  }) async {
    final remapped = <Map<String, Object?>>[];
    for (final source in rows) {
      final sourceId = source['book_id'] as String?;
      final canonicalId = sourceId == null ? null : bookIdMap[sourceId];
      if (canonicalId == null) continue;
      if (normalizeBookFile) {
        remapped.add(
          normalizeRestoredBookFile(source, canonicalBookId: canonicalId),
        );
      } else if (normalizeCover) {
        remapped.add(
          _normalizeRestoredCover(source, canonicalBookId: canonicalId),
        );
      } else {
        remapped.add(
          Map<String, Object?>.from(source)..['book_id'] = canonicalId,
        );
      }
    }
    return _mergeByKey(txn, table, remapped, keys);
  }

  /// Merge rows identified by [keys] without replacing existing local data.
  Future<int> _mergeByKey(
    Transaction txn,
    String table,
    List<Map<String, Object?>> rows,
    List<String> keys,
  ) async {
    var n = 0;
    for (final r in rows) {
      final where = keys.map((k) => '$k = ?').join(' AND ');
      final args = [for (final k in keys) r[k]];
      if (args.any((a) => a == null)) continue;
      final existing = await txn.query(
        table,
        where: where,
        whereArgs: args,
        limit: 1,
      );
      if (existing.isEmpty) {
        await txn.insert(
          table,
          Map<String, Object?>.from(r),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        n++;
      }
    }
    return n;
  }

  /// Merge rows with autoincrement ids: dedupe by natural key, insert
  /// without id so double-restore never duplicates.
  Future<int> _mergeNatural(
    Transaction txn,
    String table,
    List<Map<String, Object?>> rows,
    List<String> keys,
  ) async {
    var n = 0;
    for (final r in rows) {
      final where = [
        for (final k in keys) '$k = ?',
        'book_id IN (SELECT book_id FROM books)',
      ].join(' AND ');
      final args = [for (final k in keys) r[k]];
      if (args.any((a) => a == null)) continue;
      final existing = await txn.query(
        table,
        where: where,
        whereArgs: args,
        limit: 1,
      );
      if (existing.isNotEmpty) continue;
      final row = Map<String, Object?>.from(r)..remove('id');
      await txn.insert(table, row);
      n++;
    }
    return n;
  }

  Future<int> _mergeCollections(
    Transaction txn,
    List<Map<String, Object?>> cols,
    List<Map<String, Object?>> members,
    Map<String, String> bookIdMap,
  ) async {
    final idMap = <Object, int>{};
    for (final c in cols) {
      final name = (c['name'] as String?)?.trim() ?? '';
      if (name.isEmpty) continue;
      final existing = await txn.query(
        'collections',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [name],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        final id = existing.first['id'] as int;
        if (c['id'] != null) idMap[c['id']!] = id;
      } else {
        final id = await txn.insert('collections', {
          'name': name,
          'created_at':
              (c['created_at'] as int?) ??
              DateTime.now().millisecondsSinceEpoch,
        });
        if (c['id'] != null) idMap[c['id']!] = id;
      }
    }
    var n = 0;
    for (final m in members) {
      final oldId = m['collection_id'];
      final sourceBookId = m['book_id'] as String?;
      final bookId = sourceBookId == null ? null : bookIdMap[sourceBookId];
      final newId = oldId == null ? null : idMap[oldId];
      if (newId == null || bookId == null) continue;
      final bookGone = await txn.query(
        'books',
        columns: ['book_id'],
        where: 'book_id = ?',
        whereArgs: [bookId],
        limit: 1,
      );
      if (bookGone.isEmpty) continue;
      await txn.insert('collection_books', {
        'collection_id': newId,
        'book_id': bookId,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
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
