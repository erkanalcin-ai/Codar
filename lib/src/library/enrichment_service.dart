// Metadata/cover enrichment chain.
//
// Priority: embedded engine metadata (already stored at import) → local
// DB cache (book_metadata/covers) → Open Library (free, no key) → user
// edit (Book Detail UI). Background runs only when the user enabled
// `enrich_online` in Settings; an explicit tap always counts as consent.
// Everything is cached on-device; user-edited core fields are never
// overwritten; original book files are never touched.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:codar/src/db/repositories.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class EnrichResult {
  EnrichResult({required this.enriched, this.fields = const []});
  final bool enriched;
  final List<String> fields;
}

class EnrichmentService {
  EnrichmentService({required this.books});
  final BooksRepository books;

  /// [onlineAllowed] must be true only with explicit user consent
  /// (manual tap) or the `enrich_online` setting.
  Future<EnrichResult> enrich(
    String bookId, {
    required bool onlineAllowed,
  }) async {
    final book = await books.getBook(bookId);
    if (book == null) return EnrichResult(enriched: false);
    final meta = await books.getMetadata(bookId);
    if (!onlineAllowed) return EnrichResult(enriched: false);
    final cachedPath = await books.coverPath(bookId);
    final hasCachedCover =
        cachedPath != null && await File(cachedPath).exists();
    final cachedMetadata =
        meta['enrich_source'] == 'openlibrary' && meta['enrich_at'] != null;
    if (cachedMetadata && hasCachedCover) {
      return EnrichResult(enriched: false);
    }
    // A failed/no-cover lookup is also cached for a day. This keeps a grid of
    // coverless books from issuing the same request on every rebuild.
    final lastCoverAttempt = int.tryParse(meta['cover_attempt_at'] ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (lastCoverAttempt > 0 && now - lastCoverAttempt < 24 * 60 * 60 * 1000) {
      return EnrichResult(enriched: false);
    }
    await books.setMetadata(bookId, 'cover_attempt_at', '$now');
    try {
      final hit = await _search(
        book.title,
        book.author,
        isbn: meta['isbn'] ?? '',
      ).timeout(const Duration(seconds: 12));
      if (hit == null) return EnrichResult(enriched: false);
      final updated = <String>[];
      final userEdited = meta['user_edited'] == '1';
      if (!userEdited) {
        if (book.title.isEmpty && hit.title.isNotEmpty) {
          await books.updateBookFields(bookId, title: hit.title);
          // updateBookFields stamps user_edited; this one is machine-made.
          await books.setMetadata(bookId, 'user_edited', '0');
          updated.add('title');
        }
        if (book.author.isEmpty && hit.author.isNotEmpty) {
          await books.updateBookFields(bookId, author: hit.author);
          await books.setMetadata(bookId, 'user_edited', '0');
          updated.add('author');
        }
      }
      if ((meta['description'] ?? '').isEmpty && hit.description.isNotEmpty) {
        await books.setMetadata(
          bookId,
          'description',
          _sanitize(hit.description),
        );
        updated.add('description');
      }
      if ((meta['publisher'] ?? '').isEmpty && hit.publisher.isNotEmpty) {
        await books.setMetadata(bookId, 'publisher', hit.publisher);
        updated.add('publisher');
      }
      if ((meta['published'] ?? '').isEmpty && hit.published.isNotEmpty) {
        await books.setMetadata(bookId, 'published', hit.published);
        updated.add('published');
      }
      if ((meta['isbn'] ?? '').isEmpty && hit.isbn.isNotEmpty) {
        await books.setMetadata(bookId, 'isbn', hit.isbn);
        updated.add('isbn');
      }
      final pageCount = hit.numberOfPages;
      if ((meta['number_of_pages'] ?? '').isEmpty && pageCount != null) {
        await books.setMetadata(
          bookId,
          'number_of_pages',
          pageCount.toString(),
        );
        updated.add('number_of_pages');
      }
      if (hit.coverId > 0 && !hasCachedCover) {
        final saved = await _fetchCover(bookId, hit.coverId);
        if (saved) updated.add('cover');
      }
      await books.setMetadata(bookId, 'enrich_source', 'openlibrary');
      await books.setMetadata(
        bookId,
        'enrich_at',
        DateTime.now().millisecondsSinceEpoch.toString(),
      );
      return EnrichResult(enriched: updated.isNotEmpty, fields: updated);
    } catch (_) {
      return EnrichResult(enriched: false);
    }
  }

  Future<_OlHit?> _search(
    String title,
    String author, {
    String isbn = '',
  }) async {
    if (title.trim().isEmpty && isbn.trim().isEmpty) return null;
    final q = {
      if (isbn.trim().isNotEmpty) 'isbn': isbn.trim(),
      if (isbn.trim().isEmpty && title.trim().isNotEmpty) 'title': title.trim(),
      if (isbn.trim().isEmpty && author.trim().isNotEmpty)
        'author': author.trim(),
      'limit': '1',
    };
    final uri = Uri.https('openlibrary.org', '/search.json', q);
    final doc = await _getJson(uri);
    final docs = (doc?['docs'] as List?) ?? const [];
    if (docs.isEmpty) return null;
    final d = docs.first as Map<String, dynamic>;
    final key = (d['key'] as String?) ?? '';
    var description = '';
    var publisher = '';
    var published = '';
    var foundIsbn = '';
    if (key.isNotEmpty) {
      final work = await _getJson(Uri.https('openlibrary.org', '$key.json'));
      if (work != null) {
        description = _strOrValue(work['description']);
        final pubs = work['publishers'] as List?;
        if (pubs != null && pubs.isNotEmpty) {
          publisher = pubs.first.toString();
        }
        published =
            (work['publish_date'] as String?) ??
            (work['first_publish_date'] as String?) ??
            '';
      }
    }
    final pubs = d['publisher'] as List?;
    publisher = publisher.isNotEmpty
        ? publisher
        : (pubs != null && pubs.isNotEmpty ? pubs.first.toString() : '');
    published = published.isNotEmpty
        ? published
        : (d['first_publish_year']?.toString() ?? '');
    final isbns = d['isbn'] as List?;
    foundIsbn = isbns != null && isbns.isNotEmpty ? isbns.first.toString() : '';
    final numberOfPages = await _editionPageCount(
      d,
      isbn: isbn.trim().isNotEmpty ? isbn.trim() : foundIsbn,
    );
    final authors = d['author_name'] as List?;
    return _OlHit(
      title: (d['title'] as String?) ?? '',
      author: authors != null && authors.isNotEmpty
          ? authors.first.toString()
          : '',
      description: description,
      publisher: publisher,
      published: published,
      isbn: foundIsbn,
      numberOfPages: numberOfPages,
      coverId: (d['cover_i'] as num?)?.toInt() ?? 0,
    );
  }

  Future<int?> _editionPageCount(
    Map<String, dynamic> searchDoc, {
    required String isbn,
  }) async {
    String? editionKey;
    if (isbn.trim().isNotEmpty) {
      final edition = await _getJson(
        Uri.https('openlibrary.org', '/isbn/${isbn.trim()}.json'),
      );
      editionKey = edition?['key'] as String?;
    }
    if (editionKey == null || editionKey.isEmpty) {
      final keys = searchDoc['edition_key'] as List?;
      editionKey = keys != null && keys.isNotEmpty
          ? keys.first.toString()
          : null;
    }
    if (editionKey == null || editionKey.isEmpty) return null;
    final edition = await _getJson(
      Uri.https('openlibrary.org', '/books/$editionKey.json'),
    );
    return parseOpenLibraryPageCount(edition?['number_of_pages']);
  }

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'Codar/1.0 (offline-first reader)');
      req.headers.set('Accept', 'application/json');
      final res = await req.close().timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      if (body.isEmpty || body.length > 512 * 1024) return null;
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close(force: true);
    }
  }

  Future<bool> _fetchCover(String bookId, int coverId) async {
    final client = HttpClient();
    try {
      final uri = Uri.https('covers.openlibrary.org', '/b/id/$coverId-L.jpg');
      final req = await client.getUrl(uri).timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'Codar/1.0 (offline-first reader)');
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return false;
      final bytes = await res
          .fold<BytesBuilder>(BytesBuilder(), (b, d) => b..add(d))
          .then((b) => b.toBytes());
      if (bytes.lengthInBytes < 1024 || bytes.lengthInBytes > 8 * 1024 * 1024) {
        return false;
      }
      final dir = await getApplicationSupportDirectory();
      final dirPath = p.join(dir.path, 'covers');
      await Directory(dirPath).create(recursive: true);
      final out = File(p.join(dirPath, '$bookId.olcover'));
      await out.writeAsBytes(bytes, flush: true);
      await books.saveCover(bookId: bookId, path: out.path, mime: 'image/jpeg');
      return true;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  static String _strOrValue(Object? v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is Map) return (v['value'] as String?) ?? '';
    return '';
  }

  /// Strip any markup that slipped in from online sources: the UI renders
  /// plain text only, so tags must never reach the screen.
  static String _sanitize(String s) {
    var out = s.replaceAll(RegExp(r'<[^>]*>'), '');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (out.length > 4000) out = '${out.substring(0, 4000)}…';
    return out;
  }
}

class _OlHit {
  _OlHit({
    required this.title,
    required this.author,
    required this.description,
    required this.publisher,
    required this.published,
    required this.isbn,
    required this.numberOfPages,
    required this.coverId,
  });
  final String title;
  final String author;
  final String description;
  final String publisher;
  final String published;
  final String isbn;
  final int? numberOfPages;
  final int coverId;
}

int? parseOpenLibraryPageCount(Object? value) {
  final pages = value is num
      ? value.toInt()
      : int.tryParse(value?.toString().trim() ?? '');
  return pages != null && pages > 0 ? pages : null;
}
