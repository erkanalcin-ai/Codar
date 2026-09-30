import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/reader/reader_screen.dart';
import 'package:codar/src/presentation/records/records_screen.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/locator.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/metadata.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _bookId = 'annotation-test-book';
const _text = 'Reader fixture text for annotations.';
const _storageChannel = MethodChannel('codar/storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_storageChannel, null);
  });

  testWidgets('bookmark write failure is shown and does not show success', (
    tester,
  ) async {
    final annotations = _FakeAnnotationsRepository()..failBookmarkWrites = true;
    await _pumpReader(tester, annotations);

    await tester.tap(find.byTooltip('Yer imi ekle'));
    await tester.pumpAndSettle();

    expect(find.text('Kayıt kaydedilemedi. Tekrar deneyin.'), findsOneWidget);
    expect(find.text('Yer imi eklendi'), findsNothing);
    expect(annotations.bookmarkWrites, 1);
    expect(annotations.bookmarks, isEmpty);
    expect(find.byIcon(Icons.bookmark_border_rounded), findsOneWidget);
  });

  test('annotation error messages exist in both locales', () {
    expect(tr('tr', 'annotationSaveFailed'), contains('kaydedilemedi'));
    expect(tr('en', 'annotationSaveFailed'), contains('could not be saved'));
    expect(tr('tr', 'annotationOperationFailed'), contains('tamamlanamadı'));
    expect(
      tr('en', 'annotationOperationFailed'),
      contains('could not be completed'),
    );
  });

  testWidgets('successful bookmark still updates the icon and feedback', (
    tester,
  ) async {
    final annotations = _FakeAnnotationsRepository();
    await _pumpReader(tester, annotations);

    await tester.tap(find.byTooltip('Yer imi ekle'));
    await tester.pumpAndSettle();

    expect(annotations.bookmarkWrites, 1);
    expect(annotations.bookmarks, hasLength(1));
    expect(find.text('Yer imi eklendi'), findsOneWidget);
    expect(find.text('Kayıt kaydedilemedi. Tekrar deneyin.'), findsNothing);
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);
  });

  testWidgets('quote write failure keeps the selection and reports failure', (
    tester,
  ) async {
    final annotations = _FakeAnnotationsRepository()..failQuoteWrites = true;
    await _pumpReader(tester, annotations);
    await _selectText(tester);

    await tester.tap(find.text('Alıntıla'));
    await tester.pumpAndSettle();

    expect(annotations.quoteWrites, 1);
    expect(annotations.highlightWrites, 0);
    expect(find.text('Kayıt kaydedilemedi. Tekrar deneyin.'), findsOneWidget);
    expect(find.text('Alıntıla'), findsOneWidget);
  });

  testWidgets(
    'highlight write failure reports failure and refreshes saved state',
    (tester) async {
      final annotations = _FakeAnnotationsRepository()
        ..failHighlightWrites = true;
      await _pumpReader(tester, annotations);
      await _selectText(tester);

      await tester.tap(find.bySemanticsLabel('Vurgu rengi').first);
      await tester.pumpAndSettle();

      expect(annotations.highlightWrites, 1);
      expect(annotations.highlights, isEmpty);
      expect(find.text('Kayıt kaydedilemedi. Tekrar deneyin.'), findsOneWidget);
    },
  );

  testWidgets('note write failure reports failure without clearing selection', (
    tester,
  ) async {
    final annotations = _FakeAnnotationsRepository()..failNoteWrites = true;
    await _pumpReader(tester, annotations);
    await _selectText(tester);

    await tester.tap(find.byTooltip('Not ekle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Test note');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();

    expect(annotations.noteWrites, 1);
    expect(annotations.notes, isEmpty);
    expect(find.text('Kayıt kaydedilemedi. Tekrar deneyin.'), findsOneWidget);
    expect(find.text('Alıntıla'), findsOneWidget);
  });

  testWidgets('quote and highlight actions stay independent on success', (
    tester,
  ) async {
    final annotations = _FakeAnnotationsRepository();
    await _pumpReader(tester, annotations);
    await _selectText(tester);

    await tester.tap(find.text('Alıntıla'));
    await tester.pumpAndSettle();

    expect(annotations.quoteWrites, 1);
    expect(annotations.highlightWrites, 0);
    expect(annotations.quotes, hasLength(1));

    await _selectText(tester);
    await tester.tap(find.bySemanticsLabel('Vurgu rengi').first);
    await tester.pumpAndSettle();

    expect(annotations.quoteWrites, 1);
    expect(annotations.highlightWrites, 1);
    expect(annotations.highlights, hasLength(1));
    expect(find.text('Kayıt kaydedilemedi. Tekrar deneyin.'), findsNothing);
  });

  testWidgets('quote write failure in Records reports failure and keeps row', (
    tester,
  ) async {
    final annotations = _FakeAnnotationsRepository()
      ..quotes.add(
        QuoteRecord(
          id: 4,
          bookId: _bookId,
          sectionIndex: 0,
          charOffset: 0,
          cfi: '',
          quotedText: 'Saved quote',
        ),
      )
      ..failQuoteDeletes = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          booksRepoProvider.overrideWithValue(_FakeBooksRepository()),
          annotationsRepoProvider.overrideWithValue(annotations),
        ],
        child: const MaterialApp(home: RecordsScreen(initialTab: 'quotes')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('İşlem tamamlanamadı. Tekrar deneyin.'), findsOneWidget);
    expect(find.text('Saved quote'), findsOneWidget);
    expect(annotations.quoteDeleteWrites, 1);
  });
}

Future<void> _pumpReader(
  WidgetTester tester,
  _FakeAnnotationsRepository annotations,
) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  final reader = _FakeReaderService();
  final books = _FakeBooksRepository();
  final progress = _FakeProgressRepository();
  final settings = _FakeSettingsRepository();
  final importer = _FakeImportService(reader: reader, books: books);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        booksRepoProvider.overrideWithValue(books),
        progressRepoProvider.overrideWithValue(progress),
        annotationsRepoProvider.overrideWithValue(annotations),
        settingsRepoProvider.overrideWithValue(settings),
        readerServiceProvider.overrideWithValue(reader),
        importServiceProvider.overrideWithValue(importer),
      ],
      child: const MaterialApp(home: ReaderScreen(bookId: _bookId)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tapAt(tester.getCenter(find.text(_text, findRichText: true)));
  await tester.pumpAndSettle();
}

Future<void> _selectText(WidgetTester tester) async {
  final text = find.text(_text, findRichText: true);
  expect(text, findsOneWidget);
  await tester.longPressAt(tester.getCenter(text));
  await tester.pumpAndSettle();
  expect(find.text('Alıntıla'), findsOneWidget);
}

BookRecord _book() => BookRecord(
  bookId: _bookId,
  title: 'Test book',
  author: '',
  language: 'tr',
  format: 'epub',
  sectionCount: 1,
  fileSize: 1,
  fingerprint: 'test',
  addedAt: 1,
  lastOpenedAt: 1,
);

class _FakeBooksRepository implements BooksRepository {
  @override
  Future<BookRecord?> getBook(String bookId) async => _book();

  @override
  Future<FileRecord?> getFile(String bookId, String kind) async => FileRecord(
    displayName: 'fixture.epub',
    mime: 'application/epub+zip',
    mediastoreUri: 'test://fixture',
    cachePath: '',
    size: 1,
  );

  @override
  Future<void> touchOpened(String bookId) async {}

  @override
  Future<List<BookRecord>> listBooks({
    String? query,
    String order = 'recent',
    bool onlyFavorites = false,
  }) async => [_book()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProgressRepository implements ProgressRepository {
  @override
  Future<ProgressRecord?> loadProgress(String bookId) async => null;

  @override
  Future<void> saveProgress({
    required String bookId,
    required String locatorJson,
    required int sectionIndex,
    required int charOffset,
    required double progression,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepository implements SettingsRepository {
  @override
  Future<String> appValue(String key, String fallback) async => fallback;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAnnotationsRepository implements AnnotationsRepository {
  bool failBookmarkWrites = false;
  bool failQuoteWrites = false;
  bool failHighlightWrites = false;
  bool failNoteWrites = false;
  bool failQuoteDeletes = false;
  int bookmarkWrites = 0;
  int quoteWrites = 0;
  int highlightWrites = 0;
  int noteWrites = 0;
  int quoteDeleteWrites = 0;
  final bookmarks = <BookmarkRecord>[];
  final quotes = <QuoteRecord>[];
  final highlights = <HighlightRecord>[];
  final notes = <NoteRecord>[];

  @override
  Future<int> addBookmark(BookmarkRecord bookmark) async {
    bookmarkWrites++;
    if (failBookmarkWrites) {
      throw StateError('simulated database write failure');
    }
    final stored = BookmarkRecord(
      id: bookmarks.length + 1,
      bookId: bookmark.bookId,
      sectionIndex: bookmark.sectionIndex,
      cfi: bookmark.cfi,
      charOffset: bookmark.charOffset,
      label: bookmark.label,
    );
    bookmarks.add(stored);
    return stored.id!;
  }

  @override
  Future<int> addHighlight(HighlightRecord highlight) async {
    highlightWrites++;
    if (failHighlightWrites) {
      throw StateError('simulated database write failure');
    }
    highlights.add(
      HighlightRecord(
        id: highlights.length + 1,
        bookId: highlight.bookId,
        sectionIndex: highlight.sectionIndex,
        startOffset: highlight.startOffset,
        endOffset: highlight.endOffset,
        cfi: highlight.cfi,
        color: highlight.color,
        quotedText: highlight.quotedText,
        note: highlight.note,
        offsetUnit: 'rust_scalar',
      ),
    );
    return highlights.length;
  }

  @override
  Future<QuoteRecord?> toggleQuote(QuoteRecord quote) async {
    quoteWrites++;
    if (failQuoteWrites) throw StateError('simulated database write failure');
    final stored = QuoteRecord(
      id: quotes.length + 1,
      bookId: quote.bookId,
      sectionIndex: quote.sectionIndex,
      charOffset: quote.charOffset,
      cfi: quote.cfi,
      quotedText: quote.quotedText,
      ranges: quote.ranges,
    );
    quotes.add(stored);
    return stored;
  }

  @override
  Future<int> addNote(NoteRecord note) async {
    noteWrites++;
    if (failNoteWrites) throw StateError('simulated database write failure');
    notes.add(note);
    return notes.length;
  }

  @override
  Future<void> deleteQuote(int id) async {
    quoteDeleteWrites++;
    if (failQuoteDeletes) throw StateError('simulated database write failure');
    quotes.removeWhere((quote) => quote.id == id);
  }

  @override
  Future<List<BookmarkRecord>> allBookmarks(String bookId) async => bookmarks;

  @override
  Future<List<HighlightRecord>> allHighlights(String bookId) async =>
      highlights;

  @override
  Future<List<NoteRecord>> allNotes(String bookId) async => notes;

  @override
  Future<List<QuoteRecord>> allQuotes(String bookId) async => quotes;

  @override
  Future<List<HighlightRecord>> highlightsForSection(
    String bookId,
    int sectionIndex,
  ) async => highlights
      .where((highlight) => highlight.sectionIndex == sectionIndex)
      .toList();

  @override
  Future<void> updateHighlightOffsetsAsRustScalars(
    int id,
    int startOffset,
    int endOffset,
  ) async {}

  @override
  Future<int> deleteBookmarksAt({
    required String bookId,
    required int sectionIndex,
    required int charOffset,
  }) async {
    bookmarks.removeWhere(
      (bookmark) =>
          bookmark.bookId == bookId &&
          bookmark.sectionIndex == sectionIndex &&
          bookmark.charOffset == charOffset,
    );
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeImportService extends ImportService {
  _FakeImportService({required super.reader, required super.books})
    : super(storage: CodarLibStorage());

  @override
  Future<String?> stagedPathForReading(String bookId, String ext) async =>
      'fixture.epub';
}

class _FakeReaderService extends CodarReaderService {
  final _info = DocumentInfo(
    title: 'Test book',
    authors: const [],
    format: 'epub',
    sectionCount: BigInt.one,
    hasCover: false,
    fingerprint: 'test',
  );

  @override
  Future<ReaderSession> openBook(String path) async =>
      ReaderSession(BigInt.one, _info);

  @override
  Future<DocumentInfo> getDocumentInfo(ReaderSession session) async => _info;

  @override
  Future<SectionContent> getContent(
    ReaderSession session,
    int sectionIndex,
  ) async => _sectionContent(sectionIndex);

  @override
  Future<SectionContent> getContentForPageCount(
    ReaderSession session,
    int sectionIndex,
  ) async => _sectionContent(sectionIndex);

  @override
  Future<String> getLocator(
    ReaderSession session,
    int sectionIndex,
    int charOffset,
  ) async => '{"cfi":"fixture-$sectionIndex-$charOffset"}';

  @override
  Future<ProgressInfo> getProgress(
    ReaderSession session,
    int sectionIndex,
    int charOffset,
  ) async => ProgressInfo(
    sectionIndex: BigInt.from(sectionIndex),
    charOffset: BigInt.from(charOffset),
    progression: 0,
    totalProgression: 0,
    locatorJson: '{"cfi":"fixture"}',
  );

  @override
  Future<bool> closeSession(ReaderSession session) async {
    session.markClosed();
    return true;
  }

  SectionContent _sectionContent(int sectionIndex) => SectionContent(
    index: BigInt.from(sectionIndex),
    idref: 'fixture',
    href: 'fixture.xhtml',
    html: '<p>$_text</p>',
    plainText: _text,
    charCount: BigInt.from(_text.length),
    images: const [],
  );
}
