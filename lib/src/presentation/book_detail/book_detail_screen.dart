// Book detail: cover, metadata, progress, actions, collections,
// per-book records with exact-CFI jumps, enrichment, user edit.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/library/book_actions.dart';
import 'package:codar/src/library/enrichment_service.dart';
import 'package:codar/src/presentation/widgets/book_widgets.dart';
import 'package:codar/src/reader/locator_nav.dart';
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
      backgroundColor: CodarColors.navyDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: CodarColors.cream,
        title: const SizedBox.shrink(),
        actions: [
          PopupMenuButton<String>(
            tooltip: tr(locale, 'bookInfo'),
            icon: const Icon(Icons.more_vert_rounded),
            onSelected: (value) {
              switch (value) {
                case 'edit':
                  _editMetadata(context, ref);
                case 'delete':
                  _delete(context, ref);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(tr(locale, 'editMetadata')),
              ),
              PopupMenuItem(value: 'delete', child: Text(tr(locale, 'delete'))),
            ],
          ),
        ],
      ),
      body: Theme(
        data: CodarColors.dark(),
        child: FutureBuilder<BookRecord?>(
          future: ref.watch(booksRepoProvider).getBook(bookId),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: CodarColors.gold),
              );
            }
            final book = snap.data;
            if (book == null) {
              return Center(child: Text(tr(locale, 'noResults')));
            }
            return _DetailBody(book: book, locale: locale);
          },
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final deleted = await confirmDeleteBook(context, ref, bookId);
    if (deleted && context.mounted) context.pop();
  }

  Future<void> _editMetadata(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final repo = ref.read(booksRepoProvider);
    final book = await repo.getBook(bookId);
    if (book == null || !context.mounted) return;
    final meta = await repo.getMetadata(bookId);
    final title = TextEditingController(text: book.title);
    final author = TextEditingController(text: book.author);
    final language = TextEditingController(text: book.language);
    final publisher = TextEditingController(text: meta['publisher'] ?? '');
    final published = TextEditingController(text: meta['published'] ?? '');
    final description = TextEditingController(text: meta['description'] ?? '');
    if (!context.mounted) return;
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(locale, 'editMetadata')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(labelText: tr(locale, 'title')),
              ),
              TextField(
                controller: author,
                decoration: InputDecoration(labelText: tr(locale, 'author')),
              ),
              TextField(
                controller: language,
                decoration: InputDecoration(labelText: tr(locale, 'language')),
              ),
              TextField(
                controller: publisher,
                decoration: InputDecoration(labelText: tr(locale, 'publisher')),
              ),
              TextField(
                controller: published,
                decoration: InputDecoration(labelText: tr(locale, 'published')),
              ),
              TextField(
                controller: description,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: tr(locale, 'description'),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr(locale, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr(locale, 'save')),
          ),
        ],
      ),
    );
    if (save != true) return;
    await repo.updateBookFields(
      bookId,
      title: title.text.trim(),
      author: author.text.trim(),
      language: language.text.trim(),
    );
    await repo.setMetadata(bookId, 'publisher', publisher.text.trim());
    await repo.setMetadata(bookId, 'published', published.text.trim());
    await repo.setMetadata(bookId, 'description', _clean(description.text));
    ref.read(libraryRefreshProvider.notifier).bump();
  }

  static String _clean(String s) => s
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? pageCountLabel(String? raw, String locale) {
  final pages = parseOpenLibraryPageCount(raw);
  if (pages == null || pages <= 0) return null;
  return '$pages ${locale == 'tr' ? 'sayfa' : 'pages'}';
}

class _DetailBody extends ConsumerStatefulWidget {
  const _DetailBody({required this.book, required this.locale});
  final BookRecord book;
  final String locale;

  @override
  ConsumerState<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends ConsumerState<_DetailBody> {
  bool _enrichTried = false;

  @override
  void initState() {
    super.initState();
    // Background enrichment only with explicit opt-in; never blocks UI.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeEnrich());
  }

  Future<void> _maybeEnrich() async {
    if (_enrichTried) return;
    _enrichTried = true;
    try {
      final settings = ref.read(settingsRepoProvider);
      final enabled = await settings.appValue('enrich_online', '0') == '1';
      if (!enabled || !mounted) return;
      final res = await ref
          .read(enrichmentServiceProvider)
          .enrich(widget.book.bookId, onlineAllowed: true);
      if (res.enriched && mounted) {
        ref.read(libraryRefreshProvider.notifier).bump();
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _enrichNow() async {
    final locale = ref.read(localeProvider);
    try {
      final res = await ref
          .read(enrichmentServiceProvider)
          .enrich(widget.book.bookId, onlineAllowed: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr(locale, res.enriched ? 'enrichOk' : 'enrichFailed')),
        ),
      );
      if (res.enriched) {
        ref.read(libraryRefreshProvider.notifier).bump();
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(tr(locale, 'enrichFailed'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    final locale = widget.locale;
    return OrientationBuilder(
      builder: (c, orientation) {
        final landscape = orientation == Orientation.landscape;
        final header = Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(book: book, width: 132, height: 198),
              const SizedBox(width: 18),
              Expanded(
                child: _TitleBlock(bookId: book.bookId, book: book),
              ),
            ],
          ),
        );
        final actions = Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: CodarColors.gold,
                  foregroundColor: CodarColors.navyDeep,
                ),
                icon: const Icon(Icons.menu_book),
                label: Text(tr(locale, 'read')),
                onPressed: () =>
                    context.push('/reader/${Uri.encodeComponent(book.bookId)}'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: tr(locale, 'addToCollection'),
              style: IconButton.styleFrom(
                backgroundColor: CodarColors.navySoft,
                foregroundColor: CodarColors.cream,
              ),
              icon: const Icon(Icons.folder_open_outlined),
              onPressed: () => showCollectionEditor(context, ref, book),
            ),
            const SizedBox(width: 4),
            _FavoriteButton(bookId: book.bookId),
          ],
        );
        final about = Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr(locale, 'about'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: CodarColors.cream,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FutureBuilder<Map<String, String>>(
                    future: ref
                        .watch(booksRepoProvider)
                        .getMetadata(book.bookId),
                    builder: (c, msnap) {
                      final enriched =
                          (msnap.data ?? {})['enrich_source'] == 'openlibrary';
                      if (!enriched) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Icon(
                          Icons.cloud_done_outlined,
                          color: CodarColors.gold,
                          size: 18,
                          semanticLabel: tr(locale, 'onlineBadge'),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    tooltip: tr(locale, 'enrichNow'),
                    icon: const Icon(Icons.cloud_download_outlined, size: 20),
                    onPressed: _enrichNow,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Divider(color: CodarColors.creamDark.withValues(alpha: 0.18)),
              const SizedBox(height: 8),
              FutureBuilder<Map<String, String>>(
                future: ref.watch(booksRepoProvider).getMetadata(book.bookId),
                builder: (c, msnap) {
                  final meta = msnap.data ?? {};
                  final desc = meta['description'] ?? '';
                  return Text(
                    desc.isEmpty ? '—' : desc,
                    style: const TextStyle(
                      color: CodarColors.creamDark,
                      height: 1.55,
                    ),
                  );
                },
              ),
            ],
          ),
        );
        final records = _MyRecords(bookId: book.bookId);
        if (!landscape) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              header,
              const SizedBox(height: 22),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: actions,
              ),
              about,
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: records,
              ),
            ],
          );
        }
        // Landscape/tablet: preserve the two-pane layout while keeping the
        // same visual hierarchy as the phone detail surface.
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 28),
                children: [
                  header,
                  const SizedBox(height: 22),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: actions,
                  ),
                  about,
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                children: [records],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TitleBlock extends ConsumerWidget {
  const _TitleBlock({required this.bookId, required this.book});
  final String bookId;
  final BookRecord book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          book.title.isEmpty ? '—' : book.title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: CodarColors.cream,
            fontWeight: FontWeight.w800,
            height: 1.08,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          book.author.isEmpty ? '—' : book.author,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: CodarColors.creamDark),
        ),
        const SizedBox(height: 8),
        _MetaRow(label: tr(locale, 'format'), value: book.format.toUpperCase()),
        _MetaRow(
          label: tr(locale, 'language'),
          value: book.language.isEmpty ? '—' : book.language,
        ),
        _MetaRow(label: tr(locale, 'sections'), value: '${book.sectionCount}'),
        _MetaRow(
          label: tr(locale, 'added'),
          value: formatDate(book.addedAt, locale),
        ),
        FutureBuilder<Map<String, String>>(
          future: ref.watch(booksRepoProvider).getMetadata(bookId),
          builder: (c, msnap) {
            final meta = msnap.data ?? {};
            final pub = meta['publisher'] ?? '';
            final date = meta['published'] ?? '';
            final isbn = meta['isbn'] ?? '';
            final pages = pageCountLabel(meta['number_of_pages'], locale);
            if (pub.isEmpty && date.isEmpty && isbn.isEmpty && pages == null) {
              return const SizedBox.shrink();
            }
            return Column(
              children: [
                if (pub.isNotEmpty)
                  _MetaRow(label: tr(locale, 'publisher'), value: pub),
                if (date.isNotEmpty)
                  _MetaRow(label: tr(locale, 'published'), value: date),
                if (isbn.isNotEmpty)
                  _MetaRow(label: tr(locale, 'isbn'), value: isbn),
                if (pages != null)
                  _MetaRow(label: tr(locale, 'pages'), value: pages),
              ],
            );
          },
        ),
        FutureBuilder<ProgressRecord?>(
          future: ref.watch(progressRepoProvider).loadProgress(bookId),
          builder: (c, psnap) {
            final pr = psnap.data;
            if (pr == null) return const SizedBox.shrink();
            // Engine progression is supplementary data from hostile files:
            // never let NaN/out-of-range reach the progress indicator
            // (it asserts 0..1 and would crash the frame).
            final pct = pr.progression.isFinite
                ? pr.progression.clamp(0.0, 1.0)
                : 0.0;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text(
                  '${tr(locale, 'progress')}: %${(pct * 100).toStringAsFixed(0)}',
                  style: const TextStyle(color: CodarColors.creamDark),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    color: CodarColors.gold,
                    backgroundColor: CodarColors.creamDark.withValues(
                      alpha: 0.18,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MyRecords extends ConsumerWidget {
  const _MyRecords({required this.bookId});
  final String bookId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final ann = ref.watch(annotationsRepoProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(locale, 'myRecordsForBook'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        FutureBuilder<List<HighlightRecord>>(
          future: ann.allHighlights(bookId),
          builder: (c, snap) {
            final items = snap.data ?? [];
            return _RecordGroup(
              title: tr(locale, 'highlights'),
              empty: tr(locale, 'noHighlights'),
              count: items.length,
              children: [
                for (final h in items.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: Color(h.color),
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    title: Text(
                      _safe(h.quotedText, 100),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => context.push(
                      readerRouteFor(
                        bookId,
                        section: h.sectionIndex,
                        offset: h.startOffset,
                        cfi: h.cfi,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        FutureBuilder<List<NoteRecord>>(
          future: ann.allNotes(bookId),
          builder: (c, snap) {
            final items = snap.data ?? [];
            return _RecordGroup(
              title: tr(locale, 'notes'),
              empty: tr(locale, 'noNotes'),
              count: items.length,
              children: [
                for (final n in items.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.note_outlined, size: 18),
                    title: Text(
                      _safe(n.content, 100),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => context.push(
                      readerRouteFor(
                        bookId,
                        section: n.sectionIndex,
                        offset: n.charOffset,
                        cfi: n.cfi,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        FutureBuilder<List<BookmarkRecord>>(
          future: ann.allBookmarks(bookId),
          builder: (c, snap) {
            final items = snap.data ?? [];
            return _RecordGroup(
              title: tr(locale, 'bookmarks'),
              empty: tr(locale, 'noBookmarks'),
              count: items.length,
              children: [
                for (final b in items.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.bookmark_outline, size: 18),
                    title: Text(
                      b.label.isEmpty
                          ? '${tr(locale, 'sectionOf')} ${b.sectionIndex + 1}'
                          : _safe(b.label, 100),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => context.push(
                      readerRouteFor(
                        bookId,
                        section: b.sectionIndex,
                        offset: b.charOffset,
                        cfi: b.cfi,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  static String _safe(String s, int max) {
    final one = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (one.isEmpty) return '—';
    return one.length <= max ? one : '${one.substring(0, max)}…';
  }
}

class _RecordGroup extends StatelessWidget {
  const _RecordGroup({
    required this.title,
    required this.empty,
    required this.count,
    required this.children,
  });
  final String title;
  final String empty;
  final int count;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title ($count)',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (children.isEmpty)
            Text(empty, style: Theme.of(context).textTheme.bodySmall),
          ...children,
        ],
      ),
    );
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
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CodarColors.creamDark.withValues(alpha: 0.72),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: CodarColors.cream),
            ),
          ),
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
          tooltip: fav
              ? tr(locale, 'removeFavorite')
              : tr(locale, 'addFavorite'),
          icon: Icon(
            fav ? Icons.favorite : Icons.favorite_border,
            color: fav ? Colors.red : null,
          ),
          onPressed: () async {
            await ref.read(libraryRepoProvider).setFavorite(bookId, !fav);
            ref.read(libraryRefreshProvider.notifier).bump();
          },
        );
      },
    );
  }
}
