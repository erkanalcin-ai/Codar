// Product import flow: SAF picker/folder -> validate -> CodarLib.
//
// A picked source is never moved until Reader Core proves it is openable.
// Invalid/unopenable sources therefore remain where the user selected them;
// successful file-picker imports remove the selected source after the book
// and CodarLib copy are recorded. If source removal fails, the user is told.
// Folder imports retain selected originals; large PDFs are streamed from the
// folder source to avoid a full Dart-side byte buffer.

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
  'markdown': 'text/markdown',
};

/// Keep the engine out of pathological territory.
const maxImportBytes = 200 * 1024 * 1024;

class ImportResult {
  ImportResult({
    required this.bookId,
    required this.title,
    required this.isNew,
    this.sourceRetained = false,
    this.fileReattached = false,
  });
  final String bookId;
  final String title;
  final bool isNew;
  final bool sourceRetained;
  final bool fileReattached;
}

class ImportProgress {
  ImportProgress({
    required this.completed,
    required this.total,
    required this.currentName,
  });

  final int completed;
  final int total;
  final String currentName;
}

typedef ImportProgressCallback = void Function(ImportProgress progress);

class ImportBatchResult {
  ImportBatchResult({
    required this.selectedCount,
    required this.importedCount,
    required this.duplicateCount,
    required this.skippedUnsupportedCount,
    required this.failedCount,
    required this.sourceRetainedCount,
    required this.results,
  });

  final int selectedCount;
  final int importedCount;
  final int duplicateCount;
  final int skippedUnsupportedCount;
  final int failedCount;
  final int sourceRetainedCount;
  final List<ImportResult> results;
}

class _FolderCandidate {
  _FolderCandidate({
    required this.displayName,
    required this.size,
    required this.readBytes,
    this.sourceUri,
    this.localPath,
  });

  final String displayName;
  final int size;
  final Future<List<int>> Function() readBytes;
  final String? sourceUri;
  final String? localPath;
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

  /// Backward-compatible single-result entry point. The picker itself now
  /// supports multiple selection; all selected files are processed before the
  /// first result is returned.
  Future<ImportResult?> importWithPicker() async {
    final batch = await importFilesWithPicker();
    if (batch == null || batch.results.isEmpty) return null;
    return batch.results.first;
  }

  Future<ImportBatchResult?> importFilesWithPicker({
    ImportProgressCallback? onProgress,
  }) async {
    final picked = await FilePicker.pickFiles(
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
    if (picked.isEmpty) return null;

    var imported = 0;
    var duplicates = 0;
    var skippedUnsupported = 0;
    var failed = 0;
    var sourceRetained = 0;
    var completed = 0;
    final results = <ImportResult>[];
    onProgress?.call(
      ImportProgress(completed: 0, total: picked.length, currentName: ''),
    );

    for (final file in picked) {
      try {
        if (_allowedExtensions[_extension(file.name)] == null) {
          skippedUnsupported++;
        } else {
          final result = await _importPickedFile(file);
          results.add(result);
          if (result.sourceRetained) sourceRetained++;
          if (result.isNew) {
            imported++;
          } else {
            duplicates++;
          }
        }
      } catch (_) {
        failed++;
      } finally {
        completed++;
        onProgress?.call(
          ImportProgress(
            completed: completed,
            total: picked.length,
            currentName: file.name,
          ),
        );
      }
    }

    return ImportBatchResult(
      selectedCount: picked.length,
      importedCount: imported,
      duplicateCount: duplicates,
      skippedUnsupportedCount: skippedUnsupported,
      failedCount: failed,
      sourceRetainedCount: sourceRetained,
      results: results,
    );
  }

  Future<ImportBatchResult?> importFolderWithPicker({
    ImportProgressCallback? onProgress,
  }) async {
    final selected = await FilePicker.getDirectoryPath(
      androidOptions: const android.FilePickerAndroidOptions(
        safOptions: android.AndroidSAFOptions(
          accessMode: android.AndroidSAFAccessMode.readOnly,
          grant: android.AndroidSAFGrant.lifetime,
          persistGrant: true,
        ),
      ),
    );
    if (selected == null || selected.isEmpty) return null;

    final candidates = await _folderCandidates(selected);
    var imported = 0;
    var duplicates = 0;
    var skippedUnsupported = 0;
    var failed = 0;
    var completed = 0;
    final results = <ImportResult>[];
    onProgress?.call(
      ImportProgress(completed: 0, total: candidates.length, currentName: ''),
    );

    for (final candidate in candidates) {
      try {
        if (_allowedExtensions[_extension(candidate.displayName)] == null) {
          skippedUnsupported++;
        } else {
          if (candidate.size > maxImportBytes) {
            throw ImportException('bad-size');
          }
          // Stream large PDFs from their source and retain folder originals;
          // other folder formats keep the existing byte-copy path.
          final result =
              _extension(candidate.displayName) == 'pdf' &&
                  candidate.sourceUri != null &&
                  candidate.size > 0
              ? await _importFolderPdf(candidate)
              : await importBytes(
                  displayName: candidate.displayName,
                  bytes: await candidate.readBytes(),
                );
          results.add(result);
          if (result.isNew) {
            imported++;
          } else {
            duplicates++;
          }
        }
      } catch (_) {
        failed++;
      } finally {
        completed++;
        onProgress?.call(
          ImportProgress(
            completed: completed,
            total: candidates.length,
            currentName: candidate.displayName,
          ),
        );
      }
    }

    return ImportBatchResult(
      selectedCount: candidates.length,
      importedCount: imported,
      duplicateCount: duplicates,
      skippedUnsupportedCount: skippedUnsupported,
      failedCount: failed,
      sourceRetainedCount: 0,
      results: results,
    );
  }

  Future<ImportResult> _importPickedFile(PlatformFile picked) async {
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
      final ext = _extension(picked.name);
      // SAF exposes a cache file for validation. Hash PDFs from that file in
      // chunks instead of also materializing the complete PDF in Dart memory.
      final bytes = ext == 'pdf' ? const <int>[] : await picked.readAsBytes();
      return await importBytes(
        displayName: picked.name,
        bytes: bytes,
        sourceUri: sourceUri,
        validationPath: pickerCachePath,
        sourceSize: pickedSize,
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

  Future<List<_FolderCandidate>> _folderCandidates(String selected) async {
    try {
      if (selected.startsWith('content://')) {
        final files = await storage.listTreeFiles(selected);
        return files
            .map(
              (file) => _FolderCandidate(
                displayName: file.name,
                size: file.size,
                sourceUri: file.uri,
                readBytes: () => storage.readFile(
                  file.uri,
                  maxBytes: maxImportBytes,
                ),
              ),
            )
            .toList();
      }

      final directory = Directory(selected);
      if (!await directory.exists()) {
        throw ImportException('folder-unavailable');
      }
      final entities = await directory
          .list(recursive: true, followLinks: false)
          .where((entity) => entity is File)
          .toList();
      final candidates = <_FolderCandidate>[];
      for (final file in entities.cast<File>()) {
        candidates.add(
          _FolderCandidate(
            displayName: p.basename(file.path),
            size: await file.length(),
            sourceUri: file.uri.toString(),
            localPath: file.path,
            readBytes: file.readAsBytes,
          ),
        );
      }
      return candidates;
    } on ImportException {
      rethrow;
    } catch (_) {
      throw ImportException('folder-unavailable');
    }
  }

  Future<ImportResult> _importFolderPdf(_FolderCandidate candidate) async {
    final sourceUri = candidate.sourceUri!;
    final localPath = candidate.localPath;
    final validationPath =
        localPath ??
        p.join(
          (await getTemporaryDirectory()).path,
          'codar_folder_pdf_${DateTime.now().microsecondsSinceEpoch}.pdf',
        );
    final ownsValidationFile = localPath == null;
    try {
      if (ownsValidationFile) {
        final copied = await storage.copyFileToPath(
          uri: sourceUri,
          path: validationPath,
          size: candidate.size,
        );
        if (!copied) throw ImportException('source-unavailable');
      }
      return await importBytes(
        displayName: candidate.displayName,
        bytes: const [],
        sourceUri: sourceUri,
        validationPath: validationPath,
        sourceSize: candidate.size,
        removeSource: false,
      );
    } finally {
      if (ownsValidationFile) {
        try {
          final validationFile = File(validationPath);
          if (await validationFile.exists()) await validationFile.delete();
        } catch (_) {}
      }
    }
  }

  /// Non-interactive import of known bytes (used by tests/seeding).
  Future<ImportResult> importBytes({
    required String displayName,
    required List<int> bytes,
    String? sourceUri,
    String? validationPath,
    int? sourceSize,
    bool removeSource = true,
  }) async {
    final next = _tail.then(
      (_) => _importBytesInner(
        displayName,
        bytes,
        sourceUri: sourceUri,
        validationPath: validationPath,
        sourceSize: sourceSize,
        removeSource: removeSource,
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
    int? sourceSize,
    bool removeSource = true,
  }) async {
    final ext = _extension(displayName);
    final mime = _allowedExtensions[ext];
    if (mime == null) {
      throw ImportException('unsupported-type');
    }
    final fileSize = sourceSize ?? bytes.length;
    if (fileSize <= 0 || fileSize > maxImportBytes) {
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
        bookId = bytes.isEmpty && validationPath != null
            ? await stableBookIdFromFile(probe)
            : stableBookId(bytes);
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
      final existingFile = await books.getFile(existing.bookId, 'original');
      if (existingFile == null || existingFile.mediastoreUri.isEmpty) {
        // A JSON backup can preserve the book and its annotations without a
        // physical file. Reattach that file in place instead of creating a
        // second book or replacing any user data.
        final uri = await _storeImportedFile(
          displayName: displayName,
          bytes: bytes,
          mime: mime,
          sourceUri: sourceUri,
          size: fileSize,
        );
        try {
          await books.upsertFile(
            bookId: existing.bookId,
            kind: 'original',
            displayName: displayName,
            mime: mime,
            mediastoreUri: uri,
            cachePath: '',
            size: fileSize,
          );
        } catch (_) {
          await _discardUnregisteredCopy(uri);
          rethrow;
        }
        await books.touchOpened(existing.bookId);
        final sourceRetained = removeSource
            ? await _removeCommittedSource(sourceUri)
            : false;
        return ImportResult(
          bookId: existing.bookId,
          title: existing.title,
          isNew: false,
          sourceRetained: sourceRetained,
          fileReattached: true,
        );
      }
      await books.touchOpened(existing.bookId);
      return ImportResult(
        bookId: existing.bookId,
        title: existing.title,
        isNew: false,
      );
    }

    // Keep the selected source until both database rows have committed.
    final uri = await _storeImportedFile(
      displayName: displayName,
      bytes: bytes,
      mime: mime,
      sourceUri: sourceUri,
      size: fileSize,
    );

    try {
      await books.addImportedBook(
        bookId: bookId,
        title: title,
        author: author,
        language: language,
        format: format,
        sectionCount: sectionCount,
        fileSize: fileSize,
        fingerprint: fingerprint,
        displayName: displayName,
        mime: mime,
        mediastoreUri: uri,
      );
    } catch (_) {
      await _discardUnregisteredCopy(uri);
      rethrow;
    }
    final sourceRetained = removeSource
        ? await _removeCommittedSource(sourceUri)
        : false;

    // Private cover extraction (never touches the original).
    if (ext != 'pdf') await _extractCover(bookId, ext);

    return ImportResult(
      bookId: bookId,
      title: title,
      isNew: true,
      sourceRetained: sourceRetained,
    );
  }

  Future<void> _discardUnregisteredCopy(String uri) async {
    try {
      await storage.deleteFile(uri);
    } catch (_) {
      // The selected source still exists; keep the original failure.
    }
  }

  Future<bool> _removeCommittedSource(String? sourceUri) async {
    if (sourceUri == null) return false;
    try {
      return !await storage.deletePickedSource(sourceUri);
    } catch (_) {
      return true;
    }
  }

  Future<String> _storeImportedFile({
    required String displayName,
    required List<int> bytes,
    required String mime,
    required int size,
    String? sourceUri,
  }) async {
    return sourceUri == null
        ? await storage.importFile(
            name: displayName,
            bytes: Uint8List.fromList(bytes),
            mime: mime,
          )
        : await storage.copyPickedFile(
            name: displayName,
            mime: mime,
            sourceUri: sourceUri,
            size: size,
          );
  }

  Future<void> _extractCover(String bookId, String ext) async {
    try {
      final staged = await stagedPathForReading(bookId, ext);
      if (staged == null) return;
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
    final copied = await storage.copyFileToPath(
      uri: file.mediastoreUri,
      path: staged.path,
      size: file.size,
    );
    if (!copied) throw ImportException('source-unavailable');
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
          if (!await storage.deleteFile(file.mediastoreUri)) {
            throw ImportException('delete-file-failed');
          }
        } catch (_) {
          throw ImportException('delete-file-failed');
        }
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

  static String _extension(String name) =>
      p.extension(name).replaceFirst('.', '').toLowerCase();
}

class ImportException implements Exception {
  ImportException(this.code);
  final String code;
  @override
  String toString() => 'ImportException($code)';
}
