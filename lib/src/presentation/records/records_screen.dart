// "Benim Kayıtlarım": highlights / notes / bookmarks across books.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/presentation/reader/reader_screen.dart'
    show highlightPalette;
import 'package:codar/src/reader/locator_nav.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key, this.initialTab});
  final String? initialTab;

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 4,
      initialIndex: switch (widget.initialTab) {
        'quotes' => 3,
        'notes' => 1,
        'bookmarks' => 2,
        _ => 0,
      },
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    ref.watch(libraryRefreshProvider);
    return Theme(
      data: CodarColors.dark(),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: CodarColors.navyDeep,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: CodarColors.background,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            title: Text(tr(locale, 'records')),
            bottom: TabBar(
              controller: _tabs,
              tabs: [
                Tab(
                  icon: const Icon(Icons.format_quote_rounded),
                  text: tr(locale, 'highlights'),
                ),
                Tab(
                  icon: const Icon(Icons.sticky_note_2_outlined),
                  text: tr(locale, 'notes'),
                ),
                Tab(
                  icon: const Icon(Icons.bookmark_outline),
                  text: tr(locale, 'bookmarks'),
                ),
                Tab(
                  icon: const Icon(Icons.format_quote_rounded),
                  text: tr(locale, 'quotes'),
                ),
              ],
            ),
          ),
          body: FutureBuilder<_AllRecords>(
            future: _load(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snap.data ?? _AllRecords.empty();
              return TabBarView(
                controller: _tabs,
                children: [
                  _HighlightsTab(items: all.highlights),
                  _NotesTab(items: all.notes),
                  _BookmarksTab(items: all.bookmarks),
                  _QuotesTab(items: all.quotes),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<_AllRecords> _load() async {
    final books = await ref.read(booksRepoProvider).listBooks(order: 'title');
    final ann = ref.read(annotationsRepoProvider);
    final h = <(String, HighlightRecord)>[];
    final n = <(String, NoteRecord)>[];
    final b = <(String, BookmarkRecord)>[];
    final q = <(String, QuoteRecord)>[];
    for (final book in books) {
      for (final x in await ann.allHighlights(book.bookId)) {
        h.add((book.title, x));
      }
      for (final x in await ann.allNotes(book.bookId)) {
        n.add((book.title, x));
      }
      for (final x in await ann.allBookmarks(book.bookId)) {
        b.add((book.title, x));
      }
      for (final x in await ann.allQuotes(book.bookId)) {
        q.add((book.title, x));
      }
    }
    return _AllRecords(highlights: h, notes: n, bookmarks: b, quotes: q);
  }
}

class _AllRecords {
  _AllRecords({
    required this.highlights,
    required this.notes,
    required this.bookmarks,
    required this.quotes,
  });
  final List<(String, HighlightRecord)> highlights;
  final List<(String, NoteRecord)> notes;
  final List<(String, BookmarkRecord)> bookmarks;
  final List<(String, QuoteRecord)> quotes;

  factory _AllRecords.empty() => _AllRecords(
    highlights: const [],
    notes: const [],
    bookmarks: const [],
    quotes: const [],
  );
}

void _jump(
  BuildContext context,
  String bookId, {
  required int section,
  int offset = 0,
  String? cfi,
}) {
  context.push(
    readerRouteFor(bookId, section: section, offset: offset, cfi: cfi),
  );
}

String _safe(String s, int max) {
  final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (one.isEmpty) return '—';
  return one.length <= max ? one : '${one.substring(0, max)}…';
}

void _showAnnotationOperationFailure(BuildContext context, WidgetRef ref) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(tr(ref.read(localeProvider), 'annotationOperationFailed')),
    ),
  );
}

class _HighlightsTab extends ConsumerWidget {
  const _HighlightsTab({required this.items});
  final List<(String, HighlightRecord)> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    if (items.isEmpty) {
      return CodarEmptyState(
        icon: Icons.format_quote_rounded,
        title: tr(locale, 'highlights'),
        subtitle: tr(locale, 'noHighlights'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (c, i) {
        final (title, h) = items[i];
        return Card(
          child: ListTile(
            leading: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: Color(h.color),
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            title: Text(_safe(h.quotedText, 120), maxLines: 2),
            subtitle: Text(
              '${_safe(title, 40)}${h.note.isNotEmpty ? ' · ${_safe(h.note, 60)}' : ''}',
              maxLines: 2,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<int>(
                  tooltip: tr(locale, 'recolor'),
                  icon: const Icon(Icons.palette_outlined),
                  onSelected: (color) async {
                    try {
                      await ref
                          .read(annotationsRepoProvider)
                          .updateHighlightColor(h.id!, color);
                      if (!context.mounted) return;
                      ref.read(libraryRefreshProvider.notifier).bump();
                    } catch (_) {
                      _showAnnotationOperationFailure(context, ref);
                    }
                  },
                  itemBuilder: (c) => [
                    for (final color in highlightPalette)
                      PopupMenuItem(
                        value: color,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Color(color),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.grey),
                          ),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  tooltip: tr(locale, 'delete'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    try {
                      await ref
                          .read(annotationsRepoProvider)
                          .deleteHighlight(h.id!);
                      if (!context.mounted) return;
                      ref.read(libraryRefreshProvider.notifier).bump();
                    } catch (_) {
                      _showAnnotationOperationFailure(context, ref);
                    }
                  },
                ),
              ],
            ),
            onTap: () => _jump(
              context,
              h.bookId,
              section: h.sectionIndex,
              offset: h.startOffset,
              cfi: h.cfi,
            ),
          ),
        );
      },
    );
  }
}

class _NotesTab extends ConsumerWidget {
  const _NotesTab({required this.items});
  final List<(String, NoteRecord)> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    if (items.isEmpty) {
      return CodarEmptyState(
        icon: Icons.sticky_note_2_outlined,
        title: tr(locale, 'notes'),
        subtitle: tr(locale, 'noNotes'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (c, i) {
        final (title, n) = items[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.note_outlined),
            title: Text(_safe(n.content, 140), maxLines: 3),
            subtitle: Text(_safe(title, 60), maxLines: 1),
            trailing: IconButton(
              tooltip: tr(locale, 'delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await ref.read(annotationsRepoProvider).deleteNote(n.id!);
                  if (!context.mounted) return;
                  ref.read(libraryRefreshProvider.notifier).bump();
                } catch (_) {
                  _showAnnotationOperationFailure(context, ref);
                }
              },
            ),
            onTap: () => _jump(
              context,
              n.bookId,
              section: n.sectionIndex,
              offset: n.charOffset,
              cfi: n.cfi,
            ),
          ),
        );
      },
    );
  }
}

class _BookmarksTab extends ConsumerWidget {
  const _BookmarksTab({required this.items});
  final List<(String, BookmarkRecord)> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    if (items.isEmpty) {
      return CodarEmptyState(
        icon: Icons.bookmark_outline,
        title: tr(locale, 'bookmarks'),
        subtitle: tr(locale, 'noBookmarks'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (c, i) {
        final (title, b) = items[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: Text(
              b.label.isEmpty ? _safe(title, 80) : _safe(b.label, 80),
            ),
            subtitle: Text(
              '${_safe(title, 60)} · ${tr(locale, 'sectionOf')} ${b.sectionIndex + 1}',
            ),
            trailing: IconButton(
              tooltip: tr(locale, 'delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                try {
                  await ref.read(annotationsRepoProvider).deleteBookmark(b.id!);
                  if (!context.mounted) return;
                  ref.read(libraryRefreshProvider.notifier).bump();
                } catch (_) {
                  _showAnnotationOperationFailure(context, ref);
                }
              },
            ),
            onTap: () => _jump(
              context,
              b.bookId,
              section: b.sectionIndex,
              offset: b.charOffset,
              cfi: b.cfi,
            ),
          ),
        );
      },
    );
  }
}

class _QuotesTab extends ConsumerWidget {
  const _QuotesTab({required this.items});
  final List<(String, QuoteRecord)> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    if (items.isEmpty) {
      return CodarEmptyState(
        icon: Icons.format_quote_rounded,
        title: tr(locale, 'quotes'),
        subtitle: tr(locale, 'noQuotes'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final (title, quote) = items[index];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.format_quote_rounded),
            title: Text(quote.quotedText, softWrap: true),
            subtitle: Text(_safe(title, 60), maxLines: 1),
            trailing: IconButton(
              tooltip: tr(locale, 'delete'),
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (quote.id == null) return;
                try {
                  await ref
                      .read(annotationsRepoProvider)
                      .deleteQuote(quote.id!);
                  if (!context.mounted) return;
                  ref.read(libraryRefreshProvider.notifier).bump();
                } catch (_) {
                  _showAnnotationOperationFailure(context, ref);
                }
              },
            ),
            onTap: () => _jump(
              context,
              quote.bookId,
              section: quote.sectionIndex,
              offset: quote.charOffset,
              cfi: quote.cfi,
            ),
          ),
        );
      },
    );
  }
}
