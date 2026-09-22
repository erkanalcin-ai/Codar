// Phase 3 unit tests: pure-Dart contracts (no engine, no plugins).
//
// Covers: new TR/EN keys, CFI deep-link round-trip, adaptive grid
// breakpoints, backup encode/decode validation.

import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/book_id.dart';
import 'package:codar/src/library/backup_service.dart';
import 'package:codar/src/library/enrichment_service.dart';
import 'package:codar/src/presentation/book_detail/book_detail_screen.dart';
import 'package:codar/src/reader/locator_nav.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert' show jsonEncode;

void main() {
  test('Phase 3 keys exist in both locales', () {
    const keys = [
      'sortAdded',
      'recentlyAdded',
      'favoritesOnly',
      'bookInfo',
      'deleteBookTitle',
      'keepFile',
      'storageSettings',
      'deleteFileDefault',
      'enrichSettings',
      'enrichOnline',
      'enrichHint',
      'enrichNow',
      'enrichOk',
      'enrichFailed',
      'editMetadata',
      'publisher',
      'published',
      'description',
      'isbn',
      'pages',
      'onlineBadge',
      'myRecordsForBook',
      'backupSettings',
      'backupExport',
      'backupImport',
      'backupOk',
      'restoreOk',
      'backupFailed',
      'restoreFailed',
      'restoreConfirmQ',
      'tagline',
      'version',
      'cfiMismatch',
      'missingFile',
      'missingFileReimport',
      'recolor',
    ];
    for (final k in keys) {
      expect(tr('en', k), isNot(k), reason: 'missing EN key: $k');
      expect(tr('tr', k), isNot(k), reason: 'missing TR key: $k');
    }
    expect(tr('tr', 'recentlyAdded'), 'Son Eklenenler');
    // Turkish glyphs present in new strings.
    expect(tr('tr', 'favoritesOnly'), contains('ı'));
    expect(tr('tr', 'recolor'), contains('ğ'));
  });

  test('reader deep link round-trips section+offset+CFI', () {
    const cfi = 'epubcfi(/6/2!/4/2:10)';
    final route = readerRouteFor(
      'book 1/epub',
      section: 3,
      offset: 42,
      cfi: cfi,
    );
    expect(route, startsWith('/reader/'));
    final uri = Uri.parse(route);
    final target = ReaderTarget.parse(uri.queryParameters);
    expect(target.section, 3);
    expect(target.offset, 42);
    expect(target.cfi, cfi);
  });

  test('reader deep link tolerates missing params', () {
    final bare = readerRouteFor('b');
    expect(bare, '/reader/b');
    final t = ReaderTarget.parse(Uri.parse(bare).queryParameters);
    expect(t.section, isNull);
    expect(t.offset, isNull);
    expect(t.cfi, isNull);
    final bad = ReaderTarget.parse({'section': 'x', 'offset': ''});
    expect(bad.section, isNull);
    expect(bad.offset, isNull);
  });

  test('book IDs are deterministic for the same content', () {
    final first = stableBookId(const [1, 2, 3, 4]);
    expect(stableBookId(const [1, 2, 3, 4]), first);
    expect(stableBookId(const [1, 2, 3, 5]), isNot(first));
    expect(first, startsWith('b_'));
  });

  test('grid columns adapt to width', () {
    expect(libraryGridColumns(320), 3);
    expect(libraryGridColumns(599), 3);
    expect(libraryGridColumns(600), 4);
    expect(libraryGridColumns(899), 4);
    expect(libraryGridColumns(900), 5);
    expect(libraryGridColumns(1199), 5);
    expect(libraryGridColumns(1200), 6);
  });

  test('backup encode/decode round-trips table rows', () {
    final rows = {
      'books': [
        {'book_id': 'b1', 'title': 'İstanbul', 'added_at': 1},
      ],
      'highlights': [
        {
          'book_id': 'b1',
          'section_index': 2,
          'start_offset': 5,
          'end_offset': 9,
          'quoted_text': 'alıntı ğüşöçı',
        },
      ],
    };
    final doc = encodeBackup({
      for (final e in rows.entries) e.key: List.of(e.value),
    });
    final back = decodeBackup(
      // JSON round-trip proves glyph + shape survival.
      jsonEncode(doc),
    );
    expect(back['books']!.first['title'], 'İstanbul');
    expect(back['highlights']!.first['quoted_text'], 'alıntı ğüşöçı');
    // Missing tables default to empty (forward-compatible).
    expect(back['notes'], isEmpty);
  });

  test('restored book files discard device-bound paths', () {
    final row = normalizeRestoredBookFile({
      'book_id': 'backup-id',
      'kind': 'original',
      'display_name': 'Kitap.epub',
      'mime': 'application/epub+zip',
      'mediastore_uri': 'content://old-device/book',
      'cache_path': '/old-device/cache/book.epub',
      'size': 123,
    }, canonicalBookId: 'local-id');
    expect(row['book_id'], 'local-id');
    expect(row['display_name'], 'Kitap.epub');
    expect(row['mime'], 'application/epub+zip');
    expect(row['size'], 123);
    expect(row['mediastore_uri'], isEmpty);
    expect(row['cache_path'], isEmpty);
  });

  test('backup decode rejects bad input', () {
    expect(() => decodeBackup('not json'), throwsA(isA<Exception>()));
    expect(
      () => decodeBackup('{"format":"x"}'),
      throwsA(isA<BackupException>()),
    );
    expect(
      () => decodeBackup('{"format":"codar-backup","version":999,"tables":{}}'),
      throwsA(isA<BackupException>()),
    );
    expect(
      () => decodeBackup(
        '{"format":"codar-backup","version":1,"tables":{"books":{}}}',
      ),
      throwsA(isA<BackupException>()),
    );
  });

  test(
    'Open Library page count is accepted only when present and positive',
    () {
      expect(parseOpenLibraryPageCount(240), 240);
      expect(parseOpenLibraryPageCount('240'), 240);
      expect(parseOpenLibraryPageCount(null), isNull);
      expect(parseOpenLibraryPageCount(''), isNull);
      expect(parseOpenLibraryPageCount(0), isNull);
    },
  );

  test('book detail formats the exact page count without guessing', () {
    expect(pageCountLabel('240', 'tr'), '240 sayfa');
    expect(pageCountLabel('240', 'en'), '240 pages');
    expect(pageCountLabel(null, 'tr'), isNull);
    expect(pageCountLabel('unknown', 'tr'), isNull);
  });
}
