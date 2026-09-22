import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/widgets/app_components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    ref.watch(libraryRefreshProvider);
    return Scaffold(
      backgroundColor: CodarColors.background,
      appBar: AppBar(title: Text(tr(locale, 'collections')), actions: [
        IconButton(tooltip: tr(locale, 'records'), onPressed: () => context.push('/records'), icon: const Icon(Icons.bookmark_border_rounded)),
        IconButton(tooltip: tr(locale, 'newCollection'), onPressed: () => _newCollection(context, ref), icon: const Icon(Icons.add_rounded)),
      ]),
      body: FutureBuilder<_Overview>(
        future: _load(ref),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: CodarColors.gold));
          final data = snap.data;
          if (data == null) return CodarEmptyState(icon: Icons.collections_bookmark_outlined, title: tr(locale, 'collections'), subtitle: tr(locale, 'noBooks'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 34),
            children: [
              Text('OKUMA ALANLARIN', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: CodarColors.gold)),
              const SizedBox(height: 12),
              _CollectionRow(title: tr(locale, 'favorites'), count: data.favorites.length, icon: Icons.favorite_border_rounded, onTap: () { ref.read(libraryQueryProvider.notifier).set(ref.read(libraryQueryProvider).copyWith(onlyFavorites: true, grid: true)); context.go('/library'); }),
              _CollectionRow(title: tr(locale, 'allBooks'), count: data.all.length, icon: Icons.auto_stories_outlined, onTap: () { ref.read(libraryQueryProvider.notifier).set(ref.read(libraryQueryProvider).copyWith(onlyFavorites: false, grid: true)); context.go('/library'); }),
              if (data.collections.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(tr(locale, 'collections'), style: Theme.of(context).textTheme.labelMedium?.copyWith(color: CodarColors.gold)),
                const SizedBox(height: 12),
                for (final item in data.collections) _CollectionRow(title: item.collection.name, count: item.books.length, icon: Icons.folder_open_outlined, onTap: () => _openCollection(context, locale, item.collection, item.books), onMore: () => _deleteCollection(context, ref, item.collection)),
              ],
              const SizedBox(height: 18),
              ListTile(leading: const Icon(Icons.bookmark_border_rounded, color: CodarColors.gold), title: Text(tr(locale, 'records')), subtitle: Text(tr(locale, 'goToLocation')), trailing: const Icon(Icons.arrow_forward_rounded), onTap: () => context.push('/records')),
            ],
          );
        },
      ),
    );
  }
  Future<_Overview> _load(WidgetRef ref) async {
    final books = ref.read(booksRepoProvider); final library = ref.read(libraryRepoProvider);
    final all = await books.listBooks(order: 'title'); final favorites = await library.favorites(); final collections = await library.collections();
    final entries = <_Entry>[]; for (final c in collections) { if (c.id != null) entries.add(_Entry(c, await library.collectionBooks(c.id!))); }
    return _Overview(all, favorites, entries);
  }
}
class _Overview { const _Overview(this.all, this.favorites, this.collections); final List<BookRecord> all; final List<BookRecord> favorites; final List<_Entry> collections; }
class _Entry { const _Entry(this.collection, this.books); final CollectionRecord collection; final List<BookRecord> books; }
class _CollectionRow extends StatelessWidget {
  const _CollectionRow({required this.title, required this.count, required this.icon, required this.onTap, this.onMore});
  final String title; final int count; final IconData icon; final VoidCallback onTap; final VoidCallback? onMore;
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(bottom: 10), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: CodarColors.surface, borderRadius: BorderRadius.circular(18)), child: Row(children: [Icon(icon, color: CodarColors.gold), const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.titleMedium), Text('$count', style: Theme.of(context).textTheme.bodySmall)])), if (onMore != null) IconButton(onPressed: onMore, icon: const Icon(Icons.more_vert_rounded)) else const Icon(Icons.arrow_forward_rounded, color: CodarColors.secondaryText)]))));
}
Future<void> _newCollection(BuildContext context, WidgetRef ref) async { final locale = ref.read(localeProvider); final controller = TextEditingController(); final name = await showDialog<String>(context: context, builder: (c) => AlertDialog(title: Text(tr(locale, 'newCollection')), content: TextField(controller: controller, autofocus: true, decoration: InputDecoration(hintText: tr(locale, 'collectionNameHint'))), actions: [TextButton(onPressed: () => Navigator.pop(c), child: Text(tr(locale, 'cancel'))), FilledButton(onPressed: () => Navigator.pop(c, controller.text.trim()), child: Text(tr(locale, 'create')))])); if (name == null || name.isEmpty) return; await ref.read(libraryRepoProvider).createCollection(name); ref.read(libraryRefreshProvider.notifier).bump(); }
Future<void> _openCollection(BuildContext context, String locale, CollectionRecord collection, List<BookRecord> books) async { await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (c) => SizedBox(height: MediaQuery.sizeOf(c).height * .72, child: ListView(padding: const EdgeInsets.fromLTRB(20, 10, 20, 30), children: [Text(collection.name, style: Theme.of(c).textTheme.headlineSmall), const SizedBox(height: 18), if (books.isEmpty) CodarEmptyState(icon: Icons.auto_stories_outlined, title: collection.name, subtitle: tr(locale, 'noBooks')) else for (final b in books) Padding(padding: const EdgeInsets.only(bottom: 10), child: BookCard(book: b, variant: BookCardVariant.horizontal, onTap: () { Navigator.pop(c); context.push('/book/${Uri.encodeComponent(b.bookId)}'); }))]))); }
Future<void> _deleteCollection(BuildContext context, WidgetRef ref, CollectionRecord collection) async { final locale = ref.read(localeProvider); if (collection.id == null) return; final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(title: Text(tr(locale, 'delete')), content: Text(tr(locale, 'deleteCollectionQ')), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(tr(locale, 'cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(tr(locale, 'delete')))])); if (ok == true) { await ref.read(libraryRepoProvider).deleteCollection(collection.id!); ref.read(libraryRefreshProvider.notifier).bump(); } }
