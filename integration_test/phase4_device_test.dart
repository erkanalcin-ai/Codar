// Phase 4 on-device smoke/regression (A065, Android 16/API 36).
//
// Runs the REAL app + REAL engine + REAL MediaStore on hardware:
// SAF-independent service paths (import/stage/delete/reconcile),
// CFI progress restore, annotations, backup snapshot, tab navigation,
// locale toggle, and reader rendering of a bundled fixture.
//
// Cleans up after itself (test book + staged copy + cover removed).

import 'package:codar/main.dart' as app;
import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/backup_service.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/library/reconcile_service.dart';
import 'package:codar/src/presentation/reader/reader_screen.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('phase4 device smoke: engine, storage, CFI, UI', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final db = await container.read(databaseProvider.future);
    final books = container.read(booksRepoProvider);
    final progress = container.read(progressRepoProvider);
    final ann = container.read(annotationsRepoProvider);
    final reader = container.read(readerServiceProvider);
    for (var i = 0; i < 200 && !reader.isReady; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    expect(reader.isReady, isTrue, reason: 'engine failed to init');

    final storage = CodarLibStorage();
    final import = ImportService(
      reader: reader,
      books: books,
      storage: storage,
    );

    // 1. Import bundled fixture through the real pipeline.
    final asset = await rootBundle.load('assets/spike/min.epub');
    final bytes = asset.buffer.asUint8List();
    final first = await import.importBytes(
      displayName: 'min.epub',
      bytes: bytes,
    );
    expect(first.isNew, isTrue);
    expect(first.title.isNotEmpty, isTrue);

    // 2. Duplicate import dedupes (no second MediaStore entry path taken).
    final dup = await import.importBytes(displayName: 'min.epub', bytes: bytes);
    expect(dup.isNew, isFalse);
    expect(dup.bookId, first.bookId);

    // 3. Engine on ARM64: info, content, search, CFI round-trip.
    final staged = await import.stagedPathForReading(first.bookId, 'epub');
    expect(staged, isNotNull);
    await reader.withBook(staged!, (s) async {
      final info = await reader.getDocumentInfo(s);
      expect(info.sectionCount.toInt() >= 2, isTrue);
      final c0 = await reader.getContent(s, 0);
      expect(c0.plainText, contains('CodarSpikePhrase'));
      expect(c0.plainText, contains('İstanbul'));
      final hits = await reader.search(s, 'CodarSpikePhrase');
      expect(hits.isNotEmpty, isTrue);
      final start = c0.plainText.indexOf('CodarSpikePhrase');
      expect(start >= 0, isTrue);
      final locator = await reader.getLocator(s, 0, start);
      expect(locator, contains('cfi'));
      final restored = await reader.restoreLocator(s, locator);
      expect(restored.sectionIndex.toInt(), 0);
      final p = await reader.getProgress(s, 0, start);
      expect(p.locatorJson, locator);
      await progress.saveProgress(
        bookId: first.bookId,
        locatorJson: p.locatorJson,
        sectionIndex: 0,
        charOffset: start,
        progression: p.progression,
      );
    });
    final saved = await progress.loadProgress(first.bookId);
    expect(saved, isNotNull);
    expect(saved!.locatorJson, contains('cfi'));

    // 4. Annotations with exact CFI anchors.
    final hlId = await ann.addHighlight(
      HighlightRecord(
        bookId: first.bookId,
        sectionIndex: 0,
        startOffset: saved.charOffset,
        endOffset: saved.charOffset + 'CodarSpikePhrase'.length,
        cfi: _cfiOf(saved.locatorJson),
        color: 0xFFFFFF00,
        quotedText: 'CodarSpikePhrase',
        note: '',
      ),
    );
    expect(hlId > 0, isTrue);
    expect(_cfiOf(saved.locatorJson).isNotEmpty, isTrue);
    await ann.addNote(
      NoteRecord(
        bookId: first.bookId,
        sectionIndex: 0,
        cfi: _cfiOf(saved.locatorJson),
        charOffset: saved.charOffset,
        content: 'cihaz notu ğüşöçı',
        quotedText: 'CodarSpikePhrase',
      ),
    );
    await ann.addBookmark(
      BookmarkRecord(
        bookId: first.bookId,
        sectionIndex: 0,
        cfi: _cfiOf(saved.locatorJson),
        charOffset: saved.charOffset,
        label: 'test',
      ),
    );
    expect((await ann.allHighlights(first.bookId)).length, 1);
    expect((await ann.allNotes(first.bookId)).length, 1);
    expect((await ann.allBookmarks(first.bookId)).length, 1);

    // 5. Backup snapshot sees the book (no dialogs involved).
    final snap = await BackupService(db).snapshot();
    expect(snap['books']!.where((r) => r['book_id'] == first.bookId).length, 1);

    // 6. External delete + silent reconcile purges exactly this book.
    final file = await books.getFile(first.bookId, 'original');
    expect(file, isNotNull);
    await storage.deleteFile(file!.mediastoreUri);
    final purged = await reconcileExternalDeletions(
      books: books,
      import: import,
      storage: storage,
    );
    expect(purged, 1);
    expect(await books.getBook(first.bookId), isNull);

    // 7. Re-import so the UI phase has a live book.
    final again = await import.importBytes(
      displayName: 'min.epub',
      bytes: bytes,
    );
    expect(again.isNew, isTrue);

    // 7b. PDF opens through the same pipeline on device.
    final pdfAsset = await rootBundle.load('assets/spike/spike.pdf');
    final pdfBytes = pdfAsset.buffer.asUint8List();
    final pdf = await import.importBytes(
      displayName: 'spike.pdf',
      bytes: pdfBytes,
    );
    expect(pdf.isNew, isTrue);
    final pdfStaged = await import.stagedPathForReading(pdf.bookId, 'pdf');
    expect(pdfStaged, isNotNull);
    await reader.withBook(pdfStaged!, (s) async {
      final info = await reader.getDocumentInfo(s);
      expect(info.sectionCount.toInt() >= 1, isTrue);
      final c0 = await reader.getContent(s, 0);
      expect(c0.plainText.isNotEmpty, isTrue);
    });
    await import.deleteBook(pdf.bookId, deleteFile: true);
    expect(await books.getBook(pdf.bookId), isNull);

    // ---- UI phase (fresh scope, real launch path incl. reconcile) ----
    await tester.pumpWidget(const ProviderScope(child: app.CodarApp()));
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Home renders Turkish by default.
    expect(find.text(tr('tr', 'continueReading')), findsOneWidget);
    try {
      await binding.takeScreenshot('phase4-home');
    } catch (_) {}

    // Library tab shows the imported book; open detail.
    await tester.tap(find.text(tr('tr', 'library')));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text(again.title), findsWidgets);
    await tester.tap(find.text(again.title).first);
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text(tr('tr', 'details')), findsOneWidget);

    // Reader renders engine text with Turkish glyphs.
    await tester.tap(find.text(tr('tr', 'read')));
    await tester.pumpAndSettle(const Duration(seconds: 15));
    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.textContaining('CodarSpikePhrase'), findsWidgets);
    expect(find.textContaining('İstanbul'), findsWidgets);
    // Reader -> detail -> library tab.
    // Codar uses MaterialApp.router + GoRouter; WidgetTester.pageBack()
    // specifically looks for a Cupertino back-button and is not applicable.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Collections is a primary tab; records remain reachable from its
    // contextual records action (may be empty, but must render safely).
    await tester.tap(find.text(tr('tr', 'collections')));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await tester.tap(find.text(tr('tr', 'records')).first);
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.text(tr('tr', 'records')), findsWidgets);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle(const Duration(seconds: 10));

    // Settings: toggle EN then back to TR.
    await tester.tap(find.text(tr('tr', 'settings')));
    await tester.pumpAndSettle(const Duration(seconds: 10));
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    // Title text appears in both the AppBar and the bottom nav.
    expect(find.text(tr('en', 'settings')), findsWidgets);
    await tester.tap(find.byType(DropdownButton<String>).first);
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('Türkçe').last);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.text(tr('tr', 'settings')), findsWidgets);

    // ---- Cleanup: leave neither DB rows nor CodarLib files behind ----
    await import.deleteBook(again.bookId, deleteFile: true);
    expect(await books.getBook(again.bookId), isNull);
  });
}

String _cfiOf(String locatorJson) {
  final m = RegExp(r'"cfi"\s*:\s*"([^"]*)"').firstMatch(locatorJson);
  return m?.group(1) ?? '';
}
