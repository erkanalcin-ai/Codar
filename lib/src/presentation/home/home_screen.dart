// Home: Favorites, Continue Reading, Recently Read, Library entry.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final dbAsync = ref.watch(databaseProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr(locale, 'appTitle'))),
      body: dbAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${tr(locale, 'errorPrefix')}: $e')),
        data: (_) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_homeDataProvider);
          },
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Section(
                title: tr(locale, 'continueReading'),
                child: _BookRow(kind: _HomeKind.continueReading),
              ),
              _Section(
                title: tr(locale, 'favorites'),
                child: _BookRow(kind: _HomeKind.favorites),
              ),
              _Section(
                title: tr(locale, 'recentlyRead'),
                child: _BookRow(kind: _HomeKind.recent),
              ),
              _Section(
                title: tr(locale, 'allBooks'),
                child: _BookRow(kind: _HomeKind.all),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _HomeKind { continueReading, favorites, recent, all }

final _homeDataProvider = FutureProvider<void>((ref) async {
  ref.watch(libraryRefreshProvider);
});

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        child,
        const SizedBox(height: 8),
      ],
    );
  }
}

class _BookRow extends ConsumerWidget {
  const _BookRow({required this.kind});
  final _HomeKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(_homeDataProvider);
    final locale = ref.watch(localeProvider);
    final booksRepo = ref.watch(booksRepoProvider);
    final libRepo = ref.watch(libraryRepoProvider);
    final future = switch (kind) {
      _HomeKind.continueReading => booksRepo.continueReading(limit: 10),
      _HomeKind.favorites => libRepo.favorites(),
      _HomeKind.recent => booksRepo.recentlyRead(limit: 10),
      _HomeKind.all => booksRepo.listBooks(order: 'recent'),
    };
    return FutureBuilder<List<BookRecord>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()));
        }
        final items = (snap.data ?? []).take(10).toList();
        if (items.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(tr(locale, 'noBooks'),
                style: Theme.of(context).textTheme.bodySmall),
          );
        }
        return SizedBox(
          height: 190,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final b = items[i];
              return InkWell(
                onTap: () => context.push('/book/${Uri.encodeComponent(b.bookId)}'),
                child: SizedBox(
                  width: 96,
                  child: Column(
                    children: [
                      BookCover(book: b),
                      const SizedBox(height: 4),
                      Text(b.title.isEmpty ? '—' : b.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}


