// Shared book management sheet: long-press anywhere on a book tile/row.
//
// Actions: Read, Book Info (= detail page), Favorite toggle,
// Collections editor, Remove (with keep-file choice honoring the
// Settings default). One code path so grid/list/home/detail behave
// identically.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/reader/locator_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

Future<void> showBookActionsSheet(
  BuildContext context,
  WidgetRef ref,
  BookRecord book,
) async {
  final locale = ref.read(localeProvider);
  final lib = ref.read(libraryRepoProvider);
  final fav = await lib.isFavorite(book.bookId);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.menu_book_outlined),
            title: Text(
              book.title.isEmpty ? '—' : book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: book.author.isEmpty
                ? null
                : Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.menu_book),
            title: Text(tr(locale, 'read')),
            onTap: () {
              Navigator.pop(ctx);
              context.push(readerRouteFor(book.bookId));
            },
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr(locale, 'bookInfo')),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/book/${Uri.encodeComponent(book.bookId)}');
            },
          ),
          ListTile(
            leading: Icon(
              fav ? Icons.favorite : Icons.favorite_border,
              color: fav ? Colors.red : null,
            ),
            title: Text(tr(locale, fav ? 'removeFavorite' : 'addFavorite')),
            onTap: () async {
              Navigator.pop(ctx);
              await ref
                  .read(libraryRepoProvider)
                  .setFavorite(book.bookId, !fav);
              ref.read(libraryRefreshProvider.notifier).bump();
            },
          ),
          ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(tr(locale, 'collections')),
            onTap: () async {
              Navigator.pop(ctx);
              await showCollectionEditor(context, ref, book);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: Text(tr(locale, 'delete')),
            onTap: () async {
              Navigator.pop(ctx);
              await confirmDeleteBook(context, ref, book.bookId);
            },
          ),
        ],
      ),
    ),
  );
}

/// Collection membership editor with checkmarks.
Future<void> showCollectionEditor(
  BuildContext context,
  WidgetRef ref,
  BookRecord book,
) async {
  final repo = ref.read(libraryRepoProvider);
  final cols = await repo.collections();
  final member = await repo.collectionIdsForBook(book.bookId);
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final locale = ref.read(localeProvider);
      final selected = Set<int>.of(member);
      return StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr(locale, 'collections')),
          content: SizedBox(
            width: double.maxFinite,
            child: cols.isEmpty
                ? Text(tr(locale, 'noBooks'))
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in cols)
                        CheckboxListTile(
                          title: Text(c.name),
                          value: c.id != null && selected.contains(c.id),
                          onChanged: (v) async {
                            if (c.id == null) return;
                            await repo.setBookInCollection(
                              c.id!,
                              book.bookId,
                              v ?? false,
                            );
                            setState(() {
                              if (v ?? false) {
                                selected.add(c.id!);
                              } else {
                                selected.remove(c.id!);
                              }
                            });
                            ref.read(libraryRefreshProvider.notifier).bump();
                          },
                        ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr(locale, 'cancel')),
            ),
          ],
        ),
      );
    },
  );
}

/// Delete confirmation with the keep-file choice. The checkbox defaults
/// to the Settings preference (`delete_file_default`, default: delete).
/// Returns true only when the book was actually deleted.
Future<bool> confirmDeleteBook(
  BuildContext context,
  WidgetRef ref,
  String bookId,
) async {
  final locale = ref.read(localeProvider);
  final settings = ref.read(settingsRepoProvider);
  final defaultDeleteFile =
      await settings.appValue('delete_file_default', '1') == '1';
  var deleteFile = defaultDeleteFile;
  if (!context.mounted) return false;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(tr(locale, 'deleteBookTitle')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr(locale, 'deleteBookQ')),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(tr(locale, 'keepFile')),
              value: !deleteFile,
              onChanged: (v) => setState(() => deleteFile = !(v ?? false)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(locale, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(locale, 'delete')),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return false;
  try {
    await ref
        .read(importServiceProvider)
        .deleteBook(bookId, deleteFile: deleteFile);
  } on ImportException {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr(locale, 'deleteFileFailed'))));
    }
    return false;
  }
  ref.read(libraryRefreshProvider.notifier).bump();
  return true;
}
