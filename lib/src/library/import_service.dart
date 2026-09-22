// Product import flow: SAF picker -> validate -> move into CodarLib.
//
// A picked source is never moved until Reader Core proves it is openable.
// Invalid/unopenable sources therefore remain where the user selected them;
// successful local imports leave one physical book file in CodarLib.

import 'dart:io';
import 'dart:typed_data';

// file_picker's Android implementation is already pinned transitively by
// file_picker. Its public SAF types are required to request write access and
// recover the original content URI instead of the plugin's temporary cache
// path.
// ignore: depend_on_referenced_packages
import 'package:android_file_picker/android_file_picker.dart' as android;
import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/library/book_id.dart';
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
  ImportResult({
    required this.bookId,
    required this.title,
    required this.isNew,
  });
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

  // Serializes imports: two rapid picks of the same file must not both
  // pass the duplicate check and create two MediaStore entries.
  Future<void> _tail = Future.value();

  /// Interactive import: opens the system picker (SAF on Android).
  /// Returns null when the user cancels.
  Future<ImportResult?> importWithPicker() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: _allowedExtensions.keys.toList(),
      androidOptions: const android.FilePickerAndroidOptions(
        safOptions: android.AndroidSAFOptions(
          accessMode: android.AndroidSAFAccessMode.readWrite,
          grant: android.AndroidSAFGrant.lifetime,
          persistGrant: true,
        ),
      ),
    );
    if (picked == null) return null;
    final androidPicked = picked is android.AndroidPlatformFile ? picked : null;
    final sourceUri = androidPicked?.safHandle?.uri.toString();
    final pickerCachePath = androidPicked?.path;
    try {
      // Size gate BEFORE reading bytes: readAsBytes materializes the whole
      // file in RAM, so an oversized pick must be rejected up front.
      final pickedSize = await picked.length();
      if (pickedSize > maxImportBytes) {
        throw ImportException('bad-size');
      }
      if (sourceUri == null || sourceUri.isEmpty) {
        // Moving a picker cache path would leave the real Downloads file in
        // place and violate the single-physical-file contract.
        throw ImportException('source-unavailable');
      }
      final bytes = await picked.readAsBytes();
      return await importBytes(
        displayName: picked.name,
        bytes: bytes,
        sourceUri: sourceUri,
        validationPath: pickerCachePath,
      );
    } finally {
      // file_picker materializes an app-private cache copy for SAF files.
      // It is only a validation bridge and must not remain as a second book.
      if (pickerCachePath != null) {
        final cache = File(pickerCachePath);
        try {
          if (await cache.exists()) await cache.delete();
        } catch (_) {}
      }
      try {
        await androidPicked?.safHandle?.releaseGrant();
      } catch (_) {}
    }
  }

  /// Non-interactive import of known bytes (used by tests/seeding).
  Future<ImportResult> importBytes({
    required String displayName,
    required List<int> bytes,
    String? sourceUri,
    String? validationPath,
  }) async {
    final next = _tail.then(
      (_) => _importBytesInner(
        displayName,
        bytes,
        sourceUri: sourceUri,
        validationPath: validationPath,
      ),
    );
    _tail = next.then((_) {}, onError: (_) {});
    return next;
  }

  Future<ImportResult> _importBytesInner(
    String displayName,
    List<int> bytes, {
    String? sourceUri,
    String? validationPath,
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
    final probe = validationPath == null
        ? File(
            p.join(
              probeDir.path,
              'codar_probe_${DateTime.now().microsecondsSinceEpoch}.$ext',
            ),
          )
        : File(validationPath);
    final ownsProbe = validationPath == null;
    late final String bookId;
    late String title;
    late final String author;
    late final String language;
    late final String format;
    late final int sectionCount;
    late final String fingerprint;
    try {
      if (ownsProbe) await probe.writeAsBytes(bytes, flush: true);
      if (!await probe.exists()) throw ImportException('source-unavailable');
      await reader.withBook(probe.path, (s) async {
        final info = await reader.getDocumentInfo(s);
        title = _clean(info.title);
        author = _clean(info.authors.join(', '));
        language = info.language ?? '';
        format = info.format;
        sectionCount = info.sectionCount.toInt();
        fingerprint = info.fingerprint;
        if (title.isEmpty) title = p.basenameWithoutExtension(displayName);
        bookId = stableBookId(bytes);
      });
    } finally {
      if (ownsProbe && await probe.exists()) await probe.delete();
    }

    // Reuse a legacy row when it was created by the pre-stable-ID build.
    // This preserves its annotations/progress without recreating the book.
    final existing =
        await books.getBook(bookId) ??
        await books.findByFingerprint(fingerprint);
    if (existing != null) {
      await books.touchOpened(existing.bookId);
      return ImportResult(
        bookId: existing.bookId,
        title: existing.title,
        isNew: false,
      );
    }

    // A picker import is a move: Reader Core has already proven the source
    // openable, and native storage removes the source only after the
    // CodarLib stream completes successfully. Byte imports remain available
    // for bundled fixtures/tests and use the existing copy path.
    final uri = sourceUri == null
        ? await storage.importFile(
            name: displayName,
            bytes: Uint8List.fromList(bytes),
            mime: mime,
          )
        : await storage.movePickedFile(
            name: displayName,
            mime: mime,
            sourceUri: sourceUri,
            size: bytes.length,
          );

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
        final out = File(p.join(dirPath, '$bookId.cover'));
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

  /// Deletes the library entry. When [deleteFile] is true (user default,
  /// see Settings) the Downloads/CodarLib/ copy is removed as well;
  /// otherwise only the DB row + app-private staged copy/cover are purged
  /// (used when the file is already gone, or the user chose to keep it).
  Future<void> deleteBook(String bookId, {bool deleteFile = true}) async {
    if (deleteFile) {
      final file = await books.getFile(bookId, 'original');
      if (file != null && file.mediastoreUri.isNotEmpty) {
        try {
          await storage.deleteFile(file.mediastoreUri);
        } catch (_) {}
      }
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
