// Silent reconciliation of externally deleted Downloads/CodarLib/ files.
//
// Reconciliation removes a row only after the stored URI is confirmed to be
// a missing file under Codar's managed root. SAF and MediaStore can expose
// different URIs for one physical file; external or uncertain URIs are kept.

import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/storage/codar_lib.dart';

bool shouldPurgeReconciledFile({
  required bool uriListed,
  required ManagedFileState state,
}) => !uriListed && state == ManagedFileState.managedMissing;

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
    final uriListed = liveUris.contains(uri);
    if (!uriListed &&
        shouldPurgeReconciledFile(
          uriListed: false,
          state: await storage.managedFileState(uri),
        )) {
      try {
        await import.deleteBook(b.bookId, deleteFile: false);
        purged++;
      } catch (_) {}
    }
  }
  return purged;
}
