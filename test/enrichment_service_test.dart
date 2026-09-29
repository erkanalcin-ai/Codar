import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codar/src/db/models.dart';
import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/library/enrichment_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('confident Open Library match persists metadata and cover', () async {
    final repository = _MemoryBooksRepository(
      _book(title: 'A Safe Book', author: 'A. Author'),
      {'title_source': 'embedded'},
    );
    final requested = <Uri>[];
    final responder = _openLibraryResponder(
      requested,
      _candidate(
        title: 'A Safe Book',
        author: 'A. Author',
        isbn: '9780000000001',
        publisher: 'Trusted Press',
        coverId: 4242,
      ),
    );
    final supportDirectory = await Directory.systemTemp.createTemp(
      'codar-enrichment-cover-',
    );
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProvider, (call) async {
          expect(call.method, 'getApplicationSupportDirectory');
          return supportDirectory.path;
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(pathProvider, null);
      if (await supportDirectory.exists()) {
        await supportDirectory.delete(recursive: true);
      }
    });

    final result = await HttpOverrides.runZoned(
      () =>
          EnrichmentService(books: repository)
              .enrich(repository.book.bookId, onlineAllowed: true),
      createHttpClient: (_) => _FakeHttpClient(requested, responder),
    );

    expect(result.enriched, isTrue);
    expect(repository.metadata['description'], 'A trusted description.');
    expect(repository.metadata['publisher'], 'Trusted Press');
    expect(repository.metadata['published'], '2001');
    expect(repository.metadata['isbn'], '9780000000001');
    expect(repository.metadata['number_of_pages'], '321');
    expect(repository.metadata['enrich_source'], 'openlibrary');
    expect(repository.savedCoverPath, isNotNull);
    expect(await File(repository.savedCoverPath!).exists(), isTrue);
    expect(
      requested.any((uri) => uri.host == 'covers.openlibrary.org'),
      isTrue,
    );
  });

  test('unconfident candidate writes no bibliographic data or cover', () async {
    final repository = _MemoryBooksRepository(
      _book(title: 'Local Book Name', author: 'Local Author'),
      {'title_source': 'embedded'},
    );
    final requested = <Uri>[];
    final responder = _openLibraryResponder(
      requested,
      _candidate(
        title: 'Unrelated Candidate',
        author: 'Different Author',
        isbn: '9789999999999',
        publisher: 'Wrong Press',
        coverId: 9876,
      ),
    );

    final firstResult = await HttpOverrides.runZoned(
      () =>
          EnrichmentService(books: repository)
              .enrich(repository.book.bookId, onlineAllowed: true),
      createHttpClient: (_) => _FakeHttpClient(requested, responder),
    );

    expect(firstResult.enriched, isFalse);
    expect(repository.book.title, 'Local Book Name');
    expect(repository.book.author, 'Local Author');
    for (final key in [
      'description',
      'publisher',
      'published',
      'isbn',
      'number_of_pages',
      'enrich_source',
      'enrich_at',
    ]) {
      expect(repository.metadata, isNot(contains(key)), reason: key);
    }
    expect(repository.savedCoverPath, isNull);
    expect(
      requested.any((uri) => uri.host == 'covers.openlibrary.org'),
      isFalse,
    );

    // Simulate the retry window elapsing. The rejected ISBN must not become
    // the identity used by the next Open Library query.
    repository.metadata.remove('cover_attempt_at');
    await HttpOverrides.runZoned(
      () =>
          EnrichmentService(books: repository)
              .enrich(repository.book.bookId, onlineAllowed: true),
      createHttpClient: (_) => _FakeHttpClient(requested, responder),
    );
    final searchRequests = requested
        .where((uri) => uri.path == '/search.json')
        .toList();
    expect(searchRequests, hasLength(2));
    expect(
      searchRequests.every((uri) => uri.queryParameters.containsKey('title')),
      isTrue,
    );
    expect(
      searchRequests.every((uri) => !uri.queryParameters.containsKey('isbn')),
      isTrue,
    );
  });

  test(
    'unconfident candidate preserves trusted local ISBN and metadata',
    () async {
      final repository = _MemoryBooksRepository(
        _book(title: 'User Chosen Title', author: 'User Chosen Author'),
        {
          'user_edited': '1',
          'title_source': 'user',
          'isbn': '9781111111111',
          'description': 'Local description.',
          'publisher': 'Local Press',
          'published': '1999',
          'number_of_pages': '200',
        },
      );
      final requested = <Uri>[];
      final responder = _openLibraryResponder(
        requested,
        _candidate(
          title: 'Different Work',
          author: 'Someone Else',
          isbn: '9789999999999',
          publisher: 'Wrong Press',
          coverId: 3333,
        ),
      );

      await HttpOverrides.runZoned(
        () =>
            EnrichmentService(books: repository)
                .enrich(repository.book.bookId, onlineAllowed: true),
        createHttpClient: (_) => _FakeHttpClient(requested, responder),
      );

      expect(repository.metadata['isbn'], '9781111111111');
      expect(repository.metadata['description'], 'Local description.');
      expect(repository.metadata['publisher'], 'Local Press');
      expect(repository.metadata['published'], '1999');
      expect(repository.metadata['number_of_pages'], '200');
      expect(repository.book.title, 'User Chosen Title');
      expect(repository.book.author, 'User Chosen Author');
      expect(repository.savedCoverPath, isNull);
      final search = requested.singleWhere((uri) => uri.path == '/search.json');
      expect(search.queryParameters['isbn'], '9781111111111');
    },
  );
}

BookRecord _book({required String title, required String author}) => BookRecord(
  bookId: 'metadata-test-book',
  title: title,
  author: author,
  language: 'en',
  format: 'EPUB',
  sectionCount: 1,
  fileSize: 100,
  fingerprint: 'test-fingerprint',
  addedAt: 1,
  lastOpenedAt: 1,
);

Map<String, dynamic> _candidate({
  required String title,
  required String author,
  required String isbn,
  required String publisher,
  required int coverId,
}) => {
  'key': '/works/OL123W',
  'title': title,
  'author_name': [author],
  'isbn': [isbn],
  'publisher': [publisher],
  'first_publish_year': 2001,
  'cover_i': coverId,
};

_ResponseFactory _openLibraryResponder(
  List<Uri> requested,
  Map<String, dynamic> candidate,
) {
  return (uri) {
    requested.add(uri);
    if (uri.host == 'openlibrary.org' && uri.path == '/search.json') {
      return _jsonResponse({
        'docs': [candidate],
      });
    }
    if (uri.host == 'openlibrary.org' && uri.path == '/works/OL123W.json') {
      return _jsonResponse({
        'description': {'value': 'A trusted description.'},
        'publishers': ['Trusted Press'],
        'publish_date': '2001',
      });
    }
    if (uri.host == 'openlibrary.org' && uri.path.startsWith('/isbn/')) {
      return _jsonResponse({'key': 'OL123M'});
    }
    if (uri.host == 'openlibrary.org' && uri.path == '/books/OL123M.json') {
      return _jsonResponse({'number_of_pages': 321});
    }
    if (uri.host == 'covers.openlibrary.org') {
      return _FakeHttpClientResponse(200, List<int>.filled(2048, 7));
    }
    return _FakeHttpClientResponse(404, const []);
  };
}

_FakeHttpClientResponse _jsonResponse(Map<String, Object?> value) =>
    _FakeHttpClientResponse(200, utf8.encode(jsonEncode(value)));

typedef _ResponseFactory = _FakeHttpClientResponse Function(Uri uri);

class _FakeHttpClient extends Fake implements HttpClient {
  _FakeHttpClient(this.requested, this.responseFactory);

  final List<Uri> requested;
  final _ResponseFactory responseFactory;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest(url, responseFactory(url));

  @override
  void close({bool force = false}) {}
}

class _FakeHttpClientRequest extends Fake implements HttpClientRequest {
  _FakeHttpClientRequest(this.uri, this.response);

  @override
  final Uri uri;

  final HttpClientResponse response;
  final HttpHeaders _headers = _FakeHttpHeaders();

  @override
  HttpHeaders get headers => _headers;

  @override
  Future<HttpClientResponse> close() async => response;
}

class _FakeHttpHeaders extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeHttpClientResponse extends StreamView<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(this.statusCode, List<int> body)
    : super(Stream<List<int>>.value(body));

  @override
  final int statusCode;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MemoryBooksRepository extends Fake implements BooksRepository {
  _MemoryBooksRepository(this.book, Map<String, String> metadata)
    : metadata = Map.of(metadata);

  BookRecord book;
  final Map<String, String> metadata;
  String? savedCoverPath;

  @override
  Future<BookRecord?> getBook(String bookId) async =>
      bookId == book.bookId ? book : null;

  @override
  Future<Map<String, String>> getMetadata(String bookId) async =>
      Map.of(metadata);

  @override
  Future<FileRecord?> getFile(String bookId, String kind) async => null;

  @override
  Future<String?> coverPath(String bookId) async => null;

  @override
  Future<void> setMetadata(String bookId, String key, String value) async {
    metadata[key] = value;
  }

  @override
  Future<void> updateMachineDerivedBookFields(
    String bookId, {
    required String title,
    String? author,
    required String titleSource,
  }) async {
    book = BookRecord(
      bookId: book.bookId,
      title: title,
      author: author ?? book.author,
      language: book.language,
      format: book.format,
      sectionCount: book.sectionCount,
      fileSize: book.fileSize,
      fingerprint: book.fingerprint,
      addedAt: book.addedAt,
      lastOpenedAt: book.lastOpenedAt,
    );
    metadata['title_source'] = titleSource;
    metadata['user_edited'] = '0';
  }

  @override
  Future<void> saveCover({
    required String bookId,
    required String path,
    required String mime,
  }) async {
    savedCoverPath = path;
  }
}
