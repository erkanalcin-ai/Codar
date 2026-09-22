// Silent reconciliation of externally deleted Downloads/CodarLib/ files.
//
// If the user (or another app/cleanup tool) deletes a book file outside
// Codar, the MediaStore entry disappears. Keeping a dead DB row would show
// a ghost book that can never open, so on launch the library diffs the
// stored MediaStore URIs against the live listing and purges orphaned
// rows — silently, without dialogs. Annotations die with the book via
// ON DELETE CASCADE; the app-private staged copy and cover are removed
// too. Nothing is ever written to CodarLib (books only, no sidecars).

import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/storage/codar_lib.dart';

/// Returns the number of orphaned books purged.
Future<int> reconcileExternalDeletions({
  required BooksRepository books,
  required ImportService import,
  required CodarLibStorage storage,
}) async {
  late final List<CodarLibFile> live;
  try {
    live = await storage.listCodarLib();
  } catch (_) {
    // Channel unavailable (desktop/tests) or transient failure: never
    // purge on uncertain data.
    return 0;
  }
  final liveUris = {for (final f in live) f.uri};
  final all = await books.listBooks(order: 'recent');
  var purged = 0;
  for (final b in all) {
    final file = await books.getFile(b.bookId, 'original');
    final uri = file?.mediastoreUri ?? '';
    if (uri.isEmpty) continue;
    if (!liveUris.contains(uri)) {
      try {
        await import.deleteBook(b.bookId, deleteFile: false);
        purged++;
      } catch (_) {}
    }
  }
  return purged;
}
