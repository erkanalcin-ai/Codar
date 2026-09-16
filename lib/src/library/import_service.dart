// Product import flow: SAF picker -> validate -> Downloads/CodarLib/.
//
// Rules: originals are never modified; only book files land in CodarLib;
// DB/covers/cache stay app-private. Every import is proven openable by the
// engine before it is accepted.

import 'dart:io';
import 'dart:typed_data';

import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:codar/src/storage/codar_lib.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const _allowedExtensions = {
  'epub': 'application/epub+zip',
  'kepub': 'application/epub+zip',
  'mobi': 'application/x-mobipocket-ebook',
  'azw3': 'application/vnd.amazon.mobi8-ebook',
  'azw': 'application/vnd.amazon.mobi8-ebook',
  'fb2': 'application/x-fictionbook+xml',
  'lit': 'application/x-ms-reader',
  'cbz': 'application/x-cbz',
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'md': 'text/markdown',
};

/// Keep the engine out of pathological territory.
const maxImportBytes = 200 * 1024 * 1024;

class ImportResult {
  ImportResult({required this.bookId, required this.title, required this.isNew});
  final String bookId;
  final String title;
  final bool isNew;
}

class ImportService {
  ImportService({
    required this.reader,
    required this.books,
    required this.storage,
  });

  final CodarReaderService reader;
  final BooksRepository books;
  final CodarLibStorage storage;

  /// Interactive import: opens the system picker (SAF on Android).
  /// Returns null when the user cancels.
  Future<ImportResult?> importWithPicker() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.keys.toList(),
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    return importBytes(displayName: picked.name, bytes: bytes);
  }

  /// Non-interactive import of known bytes (used by tests/seeding).
  Future<ImportResult> importBytes({
    required String displayName,
    required List<int> bytes,
  }) async {
    final ext = p.extension(displayName).replaceFirst('.', '').toLowerCase();
    final mime = _allowedExtensions[ext];
    if (mime == null) {
      throw ImportException('unsupported-type');
    }
    if (bytes.isEmpty || bytes.length > maxImportBytes) {
      throw ImportException('bad-size');
    }

    // Prove the engine can actually open it before accepting.
    final probeDir = await getTemporaryDirectory();
    final probe = File(p.join(probeDir.path,
        'codar_probe_${DateTime.now().microsecondsSinceEpoch}.$ext'));
    late final String bookId;
    late String title;
    late final String author;
    late final String language;
    late final String format;
    late final int sectionCount;
    late final String fingerprint;
    try {
      await probe.writeAsBytes(bytes, flush: true);
      await reader.withBook(probe.path, (s) async {
        final info = await reader.getDocumentInfo(s);
        title = _clean(info.title);
        author = _clean(info.authors.join(', '));
        language = info.language ?? '';
        format = info.format;
        sectionCount = info.sectionCount.toInt();
        fingerprint = info.fingerprint;
        if (title.isEmpty) title = p.basenameWithoutExtension(displayName);
        bookId = fingerprint.isNotEmpty
            ? 'fp_${fingerprint.hashCode.toUnsigned(20).toRadixString(16)}'
            : 'f_${displayName.hashCode.toUnsigned(20).toRadixString(16)}_${bytes.length}';
      });
    } finally {
      if (await probe.exists()) await probe.delete();
    }

    final existing = await books.getBook(bookId);
    if (existing != null) {
      await books.touchOpened(bookId);
      return ImportResult(bookId: bookId, title: existing.title, isNew: false);
    }

    // Canonical user-visible copy.
    final uri = await storage.importFile(
        name: displayName, bytes: Uint8List.fromList(bytes), mime: mime);

    await books.upsertBook(
      bookId: bookId,
      title: title,
      author: author,
      language: language,
      format: format,
      sectionCount: sectionCount,
      fileSize: bytes.length,
      fingerprint: fingerprint,
    );
    await books.upsertFile(
      bookId: bookId,
      kind: 'original',
      displayName: displayName,
      mime: mime,
      mediastoreUri: uri,
      cachePath: '',
      size: bytes.length,
    );

    // Private cover extraction (never touches the original).
    await _extractCover(bookId, ext);

    return ImportResult(bookId: bookId, title: title, isNew: true);
  }

  Future<void> _extractCover(String bookId, String ext) async {
    final staged = await stagedPathForReading(bookId, ext);
    if (staged == null) return;
    try {
      await reader.withBook(staged, (s) async {
        final cover = await reader.getCover(s);
        if (cover == null || cover.data.isEmpty) return;
        final dir = await getApplicationSupportDirectory();
        final dirPath = p.join(dir.path, 'covers');
        await Directory(dirPath).create(recursive: true);
        final out =
            File(p.join(dirPath, '$bookId.cover'));
        await out.writeAsBytes(cover.data, flush: true);
        await books.saveCover(bookId: bookId, path: out.path, mime: cover.mime);
      });
    } catch (_) {
      // Cover is best-effort; the book itself is already imported.
    }
  }

  /// Filesystem path the engine can open: app-private staged copy.
  /// Re-stages from CodarLib when missing or size-changed.
  Future<String?> stagedPathForReading(String bookId, String ext) async {
    final file = await books.getFile(bookId, 'original');
    if (file == null) return null;
    final dir = await getApplicationSupportDirectory();
    final bookDir = Directory(p.join(dir.path, 'books', bookId));
    await bookDir.create(recursive: true);
    final staged = File(p.join(bookDir.path, 'content.$ext'));
    if (await staged.exists() && await staged.length() == file.size) {
      return staged.path;
    }
    if (file.mediastoreUri.isEmpty) return null;
    final bytes = await storage.readFile(file.mediastoreUri);
    await staged.writeAsBytes(bytes, flush: true);
    return staged.path;
  }

  Future<void> deleteBook(String bookId) async {
    final file = await books.getFile(bookId, 'original');
    if (file != null && file.mediastoreUri.isNotEmpty) {
      try {
        await storage.deleteFile(file.mediastoreUri);
      } catch (_) {}
    }
    final dir = await getApplicationSupportDirectory();
    final bookDir = Directory(p.join(dir.path, 'books', bookId));
    if (await bookDir.exists()) await bookDir.delete(recursive: true);
    final cover = await books.coverPath(bookId);
    if (cover != null) {
      final f = File(cover);
      if (await f.exists()) await f.delete();
    }
    await books.deleteBook(bookId);
  }

  static String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class ImportException implements Exception {
  ImportException(this.code);
  final String code;
  @override
  String toString() => 'ImportException($code)';
}
