// Book detail: cover, metadata, progress, actions, collections.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({super.key, required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    ref.watch(libraryRefreshProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(locale, 'details')),
        actions: [
          IconButton(
            tooltip: tr(locale, 'delete'),
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: FutureBuilder<BookRecord?>(
        future: ref.watch(booksRepoProvider).getBook(bookId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final book = snap.data;
          if (book == null) {
            return Center(child: Text(tr(locale, 'noResults')));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BookCover(book: book, width: 120, height: 180),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title.isEmpty ? '—' : book.title,
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 4),
                        Text(book.author.isEmpty ? '—' : book.author,
                            style: Theme.of(context).textTheme.bodyMedium),
                        const SizedBox(height: 8),
                        _MetaRow(
                            label: tr(locale, 'format'),
                            value: book.format.toUpperCase()),
                        _MetaRow(
                            label: tr(locale, 'language'),
                            value: book.language.isEmpty ? '—' : book.language),
                        _MetaRow(
                            label: tr(locale, 'sections'),
                            value: '${book.sectionCount}'),
                        _MetaRow(
                            label: tr(locale, 'added'),
                            value: formatDate(book.addedAt, locale)),
                        FutureBuilder<ProgressRecord?>(
                          future: ref
                              .watch(progressRepoProvider)
                              .loadProgress(bookId),
                          builder: (c, psnap) {
                            final pr = psnap.data;
                            if (pr == null) return const SizedBox.shrink();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                    '${tr(locale, 'progress')}: %${(pr.progression * 100).toStringAsFixed(0)}'),
                                LinearProgressIndicator(value: pr.progression),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.menu_book),
                      label: Text(tr(locale, 'read')),
                      onPressed: () => context.push(
                          '/reader/${Uri.encodeComponent(bookId)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _FavoriteButton(bookId: bookId),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.folder_outlined),
                label: Text(tr(locale, 'addToCollection')),
                onPressed: () => _addToCollection(context, ref),
              ),
              const SizedBox(height: 16),
              Text(tr(locale, 'about'),
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              FutureBuilder<Map<String, String>>(
                future:
                    ref.watch(booksRepoProvider).getMetadata(bookId),
                builder: (c, msnap) {
                  final meta = msnap.data ?? {};
                  final desc = meta['description'] ?? '';
                  if (desc.isEmpty) return Text('—');
                  return Text(desc);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        content: Text(tr(locale, 'deleteBookQ')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: Text(tr(locale, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: Text(tr(locale, 'delete'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await ref.read(importServiceProvider).deleteBook(bookId);
    ref.read(libraryRefreshProvider.notifier).bump();
    if (context.mounted) context.pop();
  }

  Future<void> _addToCollection(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(libraryRepoProvider);
    final items = await repo.collections();
    if (!context.mounted) return;
    final picked = await showDialog<CollectionRecord>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(tr(ref.read(localeProvider), 'collections')),
        children: [
          for (final col in items)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, col),
              child: Text(col.name),
            ),
        ],
      ),
    );
    if (picked == null || picked.id == null) return;
    await repo.setBookInCollection(picked.id!, bookId, true);
    ref.read(libraryRefreshProvider.notifier).bump();
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
              width: 88,
              child: Text(label,
                  style: Theme.of(context).textTheme.bodySmall)),
          Expanded(child: Text(value, maxLines: 2, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _FavoriteButton extends ConsumerWidget {
  const _FavoriteButton({required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    ref.watch(libraryRefreshProvider);
    return FutureBuilder<bool>(
      future: ref.watch(libraryRepoProvider).isFavorite(bookId),
      builder: (c, snap) {
        final fav = snap.data ?? false;
        return IconButton.outlined(
          tooltip:
              fav ? tr(locale, 'removeFavorite') : tr(locale, 'addFavorite'),
          icon: Icon(fav ? Icons.favorite : Icons.favorite_border,
              color: fav ? Colors.red : null),
          onPressed: () async {
            await ref.read(libraryRepoProvider).setFavorite(bookId, !fav);
            ref.read(libraryRefreshProvider.notifier).bump();
          },
        );
      },
    );
  }
}
