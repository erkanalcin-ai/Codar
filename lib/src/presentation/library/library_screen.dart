import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/import_service.dart';
import 'package:codar/src/presentation/widgets/app_components.dart';
import 'package:codar/src/reader/locator_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _ImportMode { files, folder }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;
  int _completed = 0;
  int _total = 0;
  String _currentName = '';

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final query = ref.watch(libraryQueryProvider);
    final books = ref.watch(libraryBooksProvider);
    ref.watch(reconcileProvider);
    ref.watch(_coverWarmupProvider);

    return Scaffold(
      backgroundColor: CodarColors.background,
      appBar: AppBar(
        title: Text(tr(locale, 'library')),
        actions: [
          IconButton(
            tooltip: query.grid
                ? tr(locale, 'listView')
                : tr(locale, 'gridView'),
            onPressed: _importing
                ? null
                : () => ref
                      .read(libraryQueryProvider.notifier)
                      .set(query.copyWith(grid: !query.grid)),
            icon: Icon(
              query.grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
            ),
          ),
          PopupMenuButton<String>(
            enabled: !_importing,
            onSelected: (v) => ref
                .read(libraryQueryProvider.notifier)
                .set(query.copyWith(order: v)),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'recent',
                child: Text(tr(locale, 'sortRecent')),
              ),
              PopupMenuItem(
                value: 'added',
                child: Text(tr(locale, 'sortAdded')),
              ),
              PopupMenuItem(
                value: 'title',
                child: Text(tr(locale, 'sortTitle')),
              ),
              PopupMenuItem(
                value: 'author',
                child: Text(tr(locale, 'sortAuthor')),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (_importing)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: _total == 0 ? null : _completed / _total,
                    color: CodarColors.gold,
                    backgroundColor: CodarColors.surface,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr(locale, 'importProgress')
                        .replaceAll('{done}', '$_completed')
                        .replaceAll('{total}', '$_total'),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (_currentName.isNotEmpty)
                    Text(
                      _currentName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: AppSearchField(
              hint: tr(locale, 'searchHint'),
              value: query.text,
              onChanged: (v) {
                if (_importing) return;
                ref
                    .read(libraryQueryProvider.notifier)
                    .set(query.copyWith(text: v));
              },
              onClear: _importing
                  ? null
                  : () => ref
                        .read(libraryQueryProvider.notifier)
                        .set(query.copyWith(text: '')),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 20, right: 20, bottom: 16),
            child: Row(
              children: [
                AppChip(
                  label: tr(locale, 'all'),
                  selected: !query.onlyFavorites,
                  onSelected: (_) {
                    if (_importing) return;
                    ref
                        .read(libraryQueryProvider.notifier)
                        .set(query.copyWith(onlyFavorites: false));
                  },
                ),
                const SizedBox(width: 8),
                AppChip(
                  label: tr(locale, 'favorites'),
                  selected: query.onlyFavorites,
                  onSelected: (v) {
                    if (_importing) return;
                    ref
                        .read(libraryQueryProvider.notifier)
                        .set(query.copyWith(onlyFavorites: v));
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: books.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: CodarColors.gold),
              ),
              error: (e, _) =>
                  Center(child: Text('${tr(locale, 'errorPrefix')}: $e')),
              data: (items) {
                if (items.isEmpty) {
                  return CodarEmptyState(
                    icon: query.text.isEmpty
                        ? Icons.auto_stories_outlined
                        : Icons.search_off_rounded,
                    title: query.text.isEmpty
                        ? tr(locale, 'library')
                        : tr(locale, 'noResults'),
                    subtitle: query.text.isEmpty
                        ? tr(locale, 'noBooks')
                        : tr(locale, 'noResults'),
                    actionLabel: query.text.isEmpty
                        ? tr(locale, 'importBook')
                        : null,
                    onAction: query.text.isEmpty && !_importing
                        ? () => _import(context)
                        : null,
                  );
                }
                return LayoutBuilder(
                  builder: (c, size) {
                    final grid = query.grid;
                    if (!grid) {
                      return ListView.separated(
                        key: const PageStorageKey<String>(
                          'library-list-scroll',
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (_, i) => SizedBox(
                          height: 116,
                          child: BookCard(
                            book: items[i].book,
                            variant: BookCardVariant.horizontal,
                            progress: items[i].progress?.progression ?? 0.0,
                          ),
                        ),
                      );
                    }
                    return GridView.builder(
                      key: const PageStorageKey<String>('library-grid-scroll'),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: libraryGridColumns(size.maxWidth),
                        mainAxisExtent: 250,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 22,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => BookCard(book: items[i].book),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: CodarColors.gold,
        foregroundColor: CodarColors.background,
        onPressed: _importing ? null : () => _import(context),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Future<void> _import(BuildContext context) async {
    if (_importing) return;
    final locale = ref.read(localeProvider);
    final mode = await showModalBottomSheet<_ImportMode>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: Text(tr(locale, 'chooseImportSource')),
              leading: const Icon(Icons.library_add_outlined),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(tr(locale, 'pickFiles')),
              onTap: () => Navigator.pop(sheetContext, _ImportMode.files),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(tr(locale, 'pickFolder')),
              onTap: () => Navigator.pop(sheetContext, _ImportMode.folder),
            ),
          ],
        ),
      ),
    );
    if (!mounted || mode == null) return;

    setState(() {
      _importing = true;
      _completed = 0;
      _total = 0;
      _currentName = '';
    });

    try {
      final service = ref.read(importServiceProvider);
      final result = mode == _ImportMode.files
          ? await service.importFilesWithPicker(onProgress: _onProgress)
          : await service.importFolderWithPicker(onProgress: _onProgress);
      if (!mounted || !context.mounted || result == null) return;
      if (result.importedCount > 0) {
        ref.read(libraryRefreshProvider.notifier).bump();
      }
      await _showBatchSummary(context, locale, result);
    } on ImportException catch (error) {
      if (!mounted || !context.mounted) return;
      final message = error.code == 'folder-unavailable'
          ? tr(locale, 'folderImportFailed')
          : '${tr(locale, 'importFailed')}: ${error.code}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Exception catch (error) {
      if (mounted && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${tr(locale, 'importFailed')}: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _currentName = '';
        });
      }
    }
  }

  void _onProgress(ImportProgress progress) {
    if (!mounted) return;
    setState(() {
      _completed = progress.completed;
      _total = progress.total;
      _currentName = progress.currentName;
    });
  }

  Future<void> _showBatchSummary(
    BuildContext context,
    String locale,
    ImportBatchResult result,
  ) {
    final summary = tr(locale, 'importSummary')
        .replaceAll('{imported}', '${result.importedCount}')
        .replaceAll('{duplicates}', '${result.duplicateCount}')
        .replaceAll('{skipped}', '${result.skippedUnsupportedCount}')
        .replaceAll('{failed}', '${result.failedCount}');
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(locale, 'importBook')),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(tr(locale, 'close')),
          ),
        ],
      ),
    );
  }
}

final _coverWarmupProvider = FutureProvider<void>((ref) async {
  final enabled =
      await ref.read(settingsRepoProvider).appValue('enrich_online', '0') ==
      '1';
  if (!enabled) return;
  final books = await ref.read(booksRepoProvider).listBooks(order: 'recent');
  final enrichment = ref.read(enrichmentServiceProvider);
  for (final b in books) {
    await enrichment.enrich(b.bookId, onlineAllowed: true);
  }
});
