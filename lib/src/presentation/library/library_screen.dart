// Library: grid/list, search, sort, favorites filter, collections, import.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final query = ref.watch(libraryQueryProvider);
    final booksAsync = ref.watch(booksListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(locale, 'library')),
        actions: [
          IconButton(
            tooltip: tr(locale, query.grid ? 'listView' : 'gridView'),
            icon: Icon(query.grid ? Icons.view_list : Icons.grid_view),
            onPressed: () => ref
                .read(libraryQueryProvider.notifier)
                .set(query.copyWith(grid: !query.grid)),
          ),
          PopupMenuButton<String>(
            tooltip: tr(locale, 'sortRecent'),
            icon: const Icon(Icons.sort),
            onSelected: (v) => ref
                .read(libraryQueryProvider.notifier)
                .set(query.copyWith(order: v)),
            itemBuilder: (c) => [
              PopupMenuItem(value: 'recent', child: Text(tr(locale, 'sortRecent'))),
              PopupMenuItem(value: 'title', child: Text(tr(locale, 'sortTitle'))),
              PopupMenuItem(value: 'author', child: Text(tr(locale, 'sortAuthor'))),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: tr(locale, 'searchHint'),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => ref
                  .read(libraryQueryProvider.notifier)
                  .set(query.copyWith(text: v)),
            ),
          ),
          const _CollectionsStrip(),
          Expanded(
            child: booksAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('${tr(locale, 'errorPrefix')}: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return Center(
                      child: Text(query.text.isEmpty
                          ? tr(locale, 'noBooks')
                          : tr(locale, 'noResults')));
                }
                if (query.grid) {
                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.62,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: items.length,
                    itemBuilder: (c, i) =>
                        _GridTile(book: items[i], locale: locale),
                  );
                }
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (c, i) =>
                      _ListTile(book: items[i], locale: locale),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _import(context, ref),
        icon: const Icon(Icons.add),
        label: Text(tr(locale, 'importBook')),
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr(locale, 'importing'))));
    try {
      final res = await ref.read(importServiceProvider).importWithPicker();
      if (res == null) return;
      ref.read(libraryRefreshProvider.notifier).bump();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.isNew
              ? tr(locale, 'importOk')
              : tr(locale, 'alreadyImported'))));
    } on Exception catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr(locale, 'importFailed')}: $e')));
    }
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({required this.book, required this.locale});
  final BookRecord book;
  final String locale;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/book/${Uri.encodeComponent(book.bookId)}'),
      child: Column(
        children: [
          BookCover(book: book),
          const SizedBox(height: 4),
          Text(book.title.isEmpty ? '—' : book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ListTile extends ConsumerWidget {
  const _ListTile({required this.book, required this.locale});
  final BookRecord book;
  final String locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: BookCover(book: book, width: 44, height: 66),
      title: Text(book.title.isEmpty ? '—' : book.title,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [book.author, book.format.toUpperCase()]
              .where((s) => s.isNotEmpty)
              .join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: FutureBuilder<bool>(
        future: ref.watch(libraryRepoProvider).isFavorite(book.bookId),
        builder: (c, snap) => Icon(
          (snap.data ?? false) ? Icons.favorite : Icons.favorite_border,
          color: (snap.data ?? false) ? Colors.red : null,
        ),
      ),
      onTap: () => context.push('/book/${Uri.encodeComponent(book.bookId)}'),
    );
  }
}

class _CollectionsStrip extends ConsumerWidget {
  const _CollectionsStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    ref.watch(libraryRefreshProvider);
    return FutureBuilder<List<CollectionRecord>>(
      future: ref.watch(libraryRepoProvider).collections(),
      builder: (context, snap) {
        final items = snap.data ?? [];
        return SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              ActionChip(
                label: Text('+ ${tr(locale, 'newCollection')}'),
                onPressed: () => _newCollection(context, ref),
              ),
              for (final c in items) ...[
                const SizedBox(width: 8),
                InputChip(
                  label: Text(c.name),
                  onPressed: () => _openCollection(context, ref, c),
                  onDeleted: () => _deleteCollection(context, ref, c),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _newCollection(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(locale, 'newCollection')),
        content: TextField(
            controller: ctrl,
            decoration:
                InputDecoration(hintText: tr(locale, 'collectionNameHint'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr(locale, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(tr(locale, 'create'))),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(libraryRepoProvider).createCollection(name);
    ref.read(libraryRefreshProvider.notifier).bump();
  }

  Future<void> _openCollection(
      BuildContext context, WidgetRef ref, CollectionRecord c) async {
    final locale = ref.read(localeProvider);
    final books =
        await ref.read(libraryRepoProvider).collectionBooks(c.id!);
    if (!context.mounted) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
                title: Text(c.name,
                    style: Theme.of(ctx).textTheme.titleMedium)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final b in books)
                    ListTile(
                      leading: BookCover(book: b, width: 36, height: 54),
                      title: Text(b.title.isEmpty ? '—' : b.title,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: IconButton(
                        tooltip: tr(locale, 'removeFromCollection'),
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: () async {
                          await ref
                              .read(libraryRepoProvider)
                              .setBookInCollection(c.id!, b.bookId, false);
                          ref.read(libraryRefreshProvider.notifier).bump();
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        context.push(
                            '/book/${Uri.encodeComponent(b.bookId)}');
                      },
                    ),
                  if (books.isEmpty)
                    ListTile(title: Text(tr(locale, 'noBooks'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCollection(
      BuildContext context, WidgetRef ref, CollectionRecord c) async {
    final locale = ref.read(localeProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(c.name),
        content: Text(tr(locale, 'deleteCollectionQ')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr(locale, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr(locale, 'delete'))),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(libraryRepoProvider).deleteCollection(c.id!);
    ref.read(libraryRefreshProvider.notifier).bump();
  }
}


