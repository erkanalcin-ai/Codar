// Reader: section-by-section reading with CFI persistence.
//
// No WebView: engine HTML is parsed by [parseSectionHtml] into blocks and
// rendered as Flutter text. Highlights anchor on engine plain-text offsets
// plus quoted text; the CFI is the stable cross-session key.

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_riverpod/flutter_riverpod.dart';

const highlightPalette = [
  0xFFFFFF00, // yellow
  0xFF90EE90, // green
  0xFFADD8E6, // blue
  0xFFFFB6C1, // pink
  0xFFFFA500, // orange
];

class ReaderThemeColors {
  const ReaderThemeColors(this.background, this.text, this.weak);
  final Color background;
  final Color text;
  final Color weak;

  static ReaderThemeColors of(String theme, BuildContext context) {
    return switch (theme) {
      'dark' => const ReaderThemeColors(Color(0xFF121212), Color(0xFFE8E8E8),
          Color(0xFF9E9E9E)),
      'sepia' => const ReaderThemeColors(Color(0xFFF4ECD8), Color(0xFF433422),
          Color(0xFF8A7B5C)),
      'warm' => const ReaderThemeColors(Color(0xFFFFF8E7), Color(0xFF333333),
          Color(0xFF8D8D8D)),
      'black' => const ReaderThemeColors(Colors.black, Color(0xFFD6D6D6),
          Color(0xFF757575)),
      _ => ReaderThemeColors(Colors.white, const Color(0xFF1A1A1A),
          Theme.of(context).colorScheme.onSurfaceVariant),
    };
  }
}

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.bookId, this.initialSection});
  final String bookId;
  final int? initialSection;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _PendingSelection {
  _PendingSelection({required this.text, required this.start, required this.end});
  final String text;
  final int start;
  final int end;
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ReaderSession? _session;
  String? _error;
  BookRecord? _book;
  int _section = 0;
  int _sectionCount = 1;
  List<TextBlock> _blocks = const [];
  String _enginePlain = '';
  int _engineChars = 0;
  // Whitespace-normalized engine text + back-map to original offsets, so
  // multi-line native selections resolve even when newline runs differ.
  String _normPlain = '';
  List<int> _normToOrig = const [];
  List<HighlightRecord> _highlights = const [];
  _PendingSelection? _pending;
  int _pendingColor = highlightPalette[0];
  String _granularity = 'paragraph';
  bool _loading = true;
  bool _saving = false;
  final _scroll = ScrollController();
  final _selectableKey = GlobalKey();
  final _regionFocus = FocusNode();
  final _regionKey = GlobalKey<SelectableRegionState>();

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    final s = _session;
    _session = null;
    if (s != null) {
      ref.read(readerServiceProvider).closeSession(s);
    }
    _scroll.dispose();
    _regionFocus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final books = ref.read(booksRepoProvider);
      final book = await books.getBook(widget.bookId);
      if (book == null) throw StateError('book-missing');
      final file = await books.getFile(widget.bookId, 'original');
      final ext = _extOf(file?.displayName ?? book.title);
      final staged = await ref
          .read(importServiceProvider)
          .stagedPathForReading(widget.bookId, ext);
      if (staged == null) throw StateError('no-file');
      final svc = ref.read(readerServiceProvider);
      final session = await svc.openBook(staged);
      _session = session;
      final info = await svc.getDocumentInfo(session);
      var start = widget.initialSection ?? 0;
      final saved = await ref
          .read(progressRepoProvider)
          .loadProgress(widget.bookId);
      if (widget.initialSection == null && saved != null) {
        start = saved.sectionIndex.clamp(0, info.sectionCount.toInt() - 1);
      }
      await books.touchOpened(widget.bookId);
      ref.read(libraryRefreshProvider.notifier).bump();
      if (!mounted) {
        await svc.closeSession(session);
        return;
      }
      setState(() {
        _book = book;
        _sectionCount = info.sectionCount.toInt();
      });
      await _loadSection(start, force: true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSection(int index, {bool force = false}) async {
    final session = _session;
    if (session == null || (_loading && !force)) return;
    setState(() => _loading = true);
    try {
      final svc = ref.read(readerServiceProvider);
      final content = await svc.getContent(session, index);
      final blocks = parseSectionHtml(content.html);
      final highlights = await ref
          .read(annotationsRepoProvider)
          .highlightsForSection(widget.bookId, index);
      if (!mounted) return;
      final norm = _normalize(content.plainText);
      setState(() {
        _section = index;
        _blocks = blocks;
        _enginePlain = content.plainText;
        _engineChars = content.charCount.toInt();
        _normPlain = norm.text;
        _normToOrig = norm.map;
        _highlights = highlights;
        _pending = null;
        _loading = false;
      });
      if (_scroll.hasClients) _scroll.jumpTo(0);
      await _saveProgress(session, index, 0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _saveProgress(
      ReaderSession session, int section, int offset) async {
    try {
      final svc = ref.read(readerServiceProvider);
      final p = await svc.getProgress(session, section, offset);
      await ref.read(progressRepoProvider).saveProgress(
            bookId: widget.bookId,
            locatorJson: p.locatorJson,
            sectionIndex: section,
            charOffset: offset,
            progression: p.progression,
          );
    } catch (_) {
      // Progress is best-effort per navigation; the book stays readable.
    }
  }

  static _Normalized _normalize(String s) {
    final buf = StringBuffer();
    final map = <int>[];
    var inSpace = true; // trim leading
    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      final space = ch == ' ' || ch == '\n' || ch == '\r' || ch == '\t';
      if (space) {
        inSpace = true;
        continue;
      }
      if (inSpace && buf.isNotEmpty) {
        buf.write(' ');
        map.add(i);
      }
      inSpace = false;
      buf.write(ch);
      map.add(i);
    }
    return _Normalized(buf.toString(), map);
  }

  static String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0) return 'epub';
    return name.substring(i + 1).toLowerCase();
  }

  // ---- selection & highlights ----

  /// Map a raw selection to engine plain-text offsets via quoted text.
  /// Whitespace is normalized on both sides; offsets map back to the
  /// original engine text so CFI anchors stay exact.
  _PendingSelection? _resolveSelection(String selected) {
    final needle = _normalize(selected).text.trim();
    if (needle.isEmpty || _normPlain.isEmpty) return null;
    final idx = _normPlain.indexOf(needle);
    if (idx < 0) return null;
    final start = _normToOrig[idx];
    final end = _normToOrig[(idx + needle.length - 1).clamp(0, _normToOrig.length - 1)] + 1;
    return _PendingSelection(
        text: _enginePlain.substring(start, end.clamp(0, _enginePlain.length)),
        start: start,
        end: end.clamp(0, _enginePlain.length));
  }

  void _onSelectionChanged(SelectedContent? content) {
    final text = content?.plainText ?? '';
    if (text.trim().isEmpty) {
      setState(() => _pending = null);
      return;
    }
    var resolved = _resolveSelection(text);
    if (resolved != null && _granularity != 'paragraph') {
      resolved = _expand(resolved, _granularity);
    }
    setState(() => _pending = resolved);
  }

  _PendingSelection _expand(_PendingSelection sel, String mode) {
    bool isWordChar(String ch) => RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(ch);
    int s = sel.start.clamp(0, _enginePlain.length);
    int e = sel.end.clamp(0, _enginePlain.length);
    if (mode == 'word') {
      while (s > 0 && isWordChar(_enginePlain[s - 1])) {
        s--;
      }
      while (e < _enginePlain.length && isWordChar(_enginePlain[e])) {
        e++;
      }
    } else if (mode == 'sentence') {
      const ends = '.!?…';
      while (s > 0 && !ends.contains(_enginePlain[s - 1])) {
        s--;
      }
      while (e < _enginePlain.length && !ends.contains(_enginePlain[e - 1])) {
        e++;
      }
    }
    final text = _enginePlain.substring(s, e).trim();
    if (text.isEmpty) return sel;
    final off = _enginePlain.indexOf(text, s);
    return _PendingSelection(text: text, start: off < 0 ? s : off, end: (off < 0 ? s : off) + text.length);
  }

  Future<void> _saveHighlight({String note = ''}) async {
    final pending = _pending;
    final session = _session;
    if (pending == null || session == null || _saving) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(readerServiceProvider);
      final locator =
          await svc.getLocator(session, _section, pending.start);
      final cfi = _cfiOf(locator);
      await ref.read(annotationsRepoProvider).addHighlight(HighlightRecord(
            bookId: widget.bookId,
            sectionIndex: _section,
            startOffset: pending.start,
            endOffset: pending.end,
            cfi: cfi,
            color: _pendingColor,
            quotedText: pending.text,
            note: note,
          ));
      final fresh = await ref
          .read(annotationsRepoProvider)
          .highlightsForSection(widget.bookId, _section);
      _regionKey.currentState?.clearSelection();
      if (mounted) {
        setState(() {
          _highlights = fresh;
          _pending = null;
          _saving = false;
        });
      }
    } catch (e) {
      debugPrint('codar-highlight-failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancelPending() {
    _regionKey.currentState?.clearSelection();
    setState(() => _pending = null);
  }

  static String _cfiOf(String locatorJson) {
    final m = RegExp(r'"cfi"\s*:\s*"([^"]*)"').firstMatch(locatorJson);
    return m?.group(1) ?? '';
  }

  Future<void> _addBookmark() async {
    final session = _session;
    if (session == null) return;
    try {
      final svc = ref.read(readerServiceProvider);
      final locator = await svc.getLocator(session, _section, 0);
      await ref.read(annotationsRepoProvider).addBookmark(BookmarkRecord(
            bookId: widget.bookId,
            sectionIndex: _section,
            cfi: _cfiOf(locator),
            charOffset: 0,
            label: '${tr(ref.read(localeProvider), 'sectionOf')} ${_section + 1}',
          ));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(ref.read(localeProvider), 'bookmarkAdded'))));
      }
    } catch (_) {}
  }

  Future<void> _addNote() async {
    final locale = ref.read(localeProvider);
    final session = _session;
    if (session == null) return;
    final pending = _pending;
    final ctrl = TextEditingController(text: '');
    final content = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr(locale, 'addNote')),
        content: TextField(
            controller: ctrl,
            maxLines: 4,
            decoration: InputDecoration(hintText: tr(locale, 'noteHint'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr(locale, 'cancel'))),
          TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: Text(tr(locale, 'save'))),
        ],
      ),
    );
    if (content == null || content.isEmpty) return;
    try {
      final svc = ref.read(readerServiceProvider);
      final offset = pending?.start ?? 0;
      final locator = await svc.getLocator(session, _section, offset);
      await ref.read(annotationsRepoProvider).addNote(NoteRecord(
            bookId: widget.bookId,
            sectionIndex: _section,
            cfi: _cfiOf(locator),
            charOffset: offset,
            content: content,
            quotedText: pending?.text ?? '',
          ));
      _regionKey.currentState?.clearSelection();
      if (mounted) setState(() => _pending = null);
    } catch (_) {}
  }

  Future<void> _openChapters() async {
    final session = _session;
    if (session == null) return;
    final locale = ref.read(localeProvider);
    try {
      final svc = ref.read(readerServiceProvider);
      final chapters = await svc.getChapters(session);
      if (!mounted) return;
      final picked = await showModalBottomSheet<int>(
        context: context,
        builder: (c) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                  title: Text(tr(locale, 'chapters'),
                      style: Theme.of(c).textTheme.titleMedium)),
              for (var i = 0; i < chapters.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.only(
                      left: 16.0 + chapters[i].depth.toInt() * 16.0, right: 16),
                  title: Text(
                      chapters[i].title.isEmpty ? '—' : chapters[i].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(c, i),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      final href = chapters[picked].href;
      final found = href.isEmpty ? null : await svc.findSection(session, href);
      await _loadSection((found ?? picked).clamp(0, _sectionCount - 1));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(readerSettingsProvider);
    final colors = ReaderThemeColors.of(settings.theme, context);
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        foregroundColor: colors.text,
        title: Text(
            _book == null
                ? tr(locale, 'appTitle')
                : (_book!.title.isEmpty ? '—' : _book!.title),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: tr(locale, 'chapters'),
              icon: const Icon(Icons.list),
              onPressed: _session == null ? null : _openChapters),
          IconButton(
              tooltip: tr(locale, 'addBookmark'),
              icon: const Icon(Icons.bookmark_add_outlined),
              onPressed: _session == null ? null : _addBookmark),
          IconButton(
              tooltip: tr(locale, 'addNote'),
              icon: const Icon(Icons.note_add_outlined),
              onPressed: _session == null ? null : _addNote),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildBody(locale, settings, colors)),
          if (_pending != null) _highlightBar(locale, colors),
          _navBar(locale, colors),
        ],
      ),
    );
  }

  Widget _buildBody(
      String locale, ReaderSettingsData settings, ReaderThemeColors colors) {
    if (_loading && _blocks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _blocks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${tr(locale, 'errorPrefix')}: ${_displayError(_error!)}'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _open,
              child: Text(tr(locale, 'retry')),
            ),
          ],
        ),
      );
    }
    final align = switch (settings.alignment) {
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      _ => TextAlign.start,
    };
    final margin = settings.marginPx.toDouble().clamp(8.0, 96.0);
    return SelectableRegion(
      key: _regionKey,
      focusNode: _regionFocus,
      selectionControls: MaterialTextSelectionControls(),
      onSelectionChanged: _onSelectionChanged,
      child: ListView.builder(
        key: _selectableKey,
        controller: _scroll,
        padding: EdgeInsets.symmetric(horizontal: margin, vertical: 16),
        itemCount: _blocks.isEmpty ? 1 : _blocks.length,
        itemBuilder: (context, i) {
          if (_blocks.isEmpty) {
            return Text(tr(locale, 'emptySection'),
                style: TextStyle(color: colors.weak));
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _blockText(_blocks[i], settings, colors, align),
          );
        },
      ),
    );
  }

  Widget _blockText(TextBlock block, ReaderSettingsData settings,
      ReaderThemeColors colors, TextAlign align) {
    final fontSize = settings.fontSizePx.toDouble().clamp(12.0, 40.0);
    final height = settings.lineHeight.clamp(1.0, 2.5);
    final base = TextStyle(
      fontSize: fontSize,
      height: height,
      color: colors.text,
      fontFamily: _fontFamily(settings.fontFamily),
    );
    final spans = _spansFor(block, base);
    final style = block.isHeading
        ? base.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: base.fontSize! *
                (block.kind == 'h1'
                    ? 1.5
                    : block.kind == 'h2'
                        ? 1.35
                        : 1.2))
        : base;
    final prefix = block.kind == 'li' ? '• ' : '';
    return Text.rich(
      TextSpan(children: [
        if (prefix.isNotEmpty) TextSpan(text: prefix, style: style),
        ...spans.map((s) => TextSpan(
              text: s.text,
              style: style.copyWith(
                fontWeight: s.bold ? FontWeight.bold : null,
                fontStyle: s.italic ? FontStyle.italic : null,
                backgroundColor: s.background,
              ),
            )),
      ]),
      textAlign: align,
    );
  }

  List<_PaintSpan> _spansFor(TextBlock block, TextStyle base) {
    final text = block.plainText;
    if (text.isEmpty || _highlights.isEmpty) {
      return [
        for (final p in block.parts)
          _PaintSpan(p.text, p.bold, p.italic, null)
      ];
    }
    // Overlay highlight ranges located by quoted text (nearest relative pos).
    final ranges = <_Range>[];
    for (final h in _highlights) {
      if (h.quotedText.isEmpty) continue;
      var from = 0;
      final occs = <int>[];
      while (true) {
        final idx = text.indexOf(h.quotedText, from);
        if (idx < 0) break;
        occs.add(idx);
        from = idx + 1;
      }
      if (occs.isEmpty) continue;
      final rel = _engineChars <= 0
          ? 0.0
          : (h.startOffset / _engineChars).clamp(0.0, 1.0);
      var best = occs.first;
      var bestD = 1e18;
      for (final o in occs) {
        final d = ((o / text.length) - rel).abs();
        if (d < bestD) {
          bestD = d;
          best = o;
        }
      }
      ranges.add(_Range(best, best + h.quotedText.length, h.color));
    }
    ranges.sort((a, b) => a.start.compareTo(b.start));
    // Rebuild spans: walk original parts, splitting at range boundaries.
    final out = <_PaintSpan>[];
    var cursor = 0;
    var ri = 0;
    // Flatten parts with offsets.
    final flat = <_Flat>[];
    var pos = 0;
    for (final p in block.parts) {
      flat.add(_Flat(pos, pos + p.text.length, p));
      pos += p.text.length;
    }
    while (ri < ranges.length) {
      final r = ranges[ri];
      if (r.end <= cursor) {
        ri++;
        continue;
      }
      if (r.start > cursor) {
        _emitPlain(flat, cursor, r.start, out, null);
        cursor = r.start;
      }
      _emitPlain(flat, cursor, r.end, out, Color(r.color));
      cursor = r.end;
      ri++;
    }
    _emitPlain(flat, cursor, text.length, out, null);
    return out;
  }

  void _emitPlain(List<_Flat> flat, int from, int to, List<_PaintSpan> out,
      Color? background) {
    if (from >= to) return;
    for (final f in flat) {
      final s = from.clamp(f.start, f.end);
      final e = to.clamp(f.start, f.end);
      if (e > s) {
        out.add(_PaintSpan(f.part.text.substring(s - f.start, e - f.start),
            f.part.bold, f.part.italic, background));
      }
    }
  }

  static String? _fontFamily(String name) {
    return switch (name) {
      'Serif' => 'serif',
      'Monospace' => 'monospace',
      _ => null,
    };
  }

  static String _displayError(String raw) {
    // Never leak engine internals: show a short, safe tail.
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 160) return oneLine;
    return '${oneLine.substring(0, 160)}…';
  }

  Widget _navBar(String locale, ReaderThemeColors colors) {
    return Container(
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: tr(locale, 'prevSection'),
            color: colors.text,
            icon: const Icon(Icons.chevron_left),
            onPressed: _section > 0
                ? () => _loadSection(_section - 1)
                : null,
          ),
          Expanded(
            child: Text(
              '${tr(locale, 'sectionOf')} ${_section + 1} / $_sectionCount',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.weak),
            ),
          ),
          IconButton(
            tooltip: tr(locale, 'nextSection'),
            color: colors.text,
            icon: const Icon(Icons.chevron_right),
            onPressed: _section < _sectionCount - 1
                ? () => _loadSection(_section + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _highlightBar(String locale, ReaderThemeColors colors) {
    final pending = _pending;
    return Container(
      color: colors.background,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (pending != null)
              Text(
                pending.text.length > 80
                    ? '${pending.text.substring(0, 80)}…'
                    : pending.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.weak, fontSize: 12),
              ),
            Row(
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'word', label: Text(tr(locale, 'word'))),
                    ButtonSegment(
                        value: 'sentence',
                        label: Text(tr(locale, 'sentence'))),
                    ButtonSegment(
                        value: 'paragraph',
                        label: Text(tr(locale, 'paragraph'))),
                  ],
                  selected: {_granularity},
                  onSelectionChanged: (s) {
                    final mode = s.first;
                    setState(() => _granularity = mode);
                    if (pending != null && mode != 'paragraph') {
                      setState(
                          () => _pending = _expand(pending, mode));
                    }
                  },
                ),
              ],
            ),
            Row(
              children: [
                for (final c in highlightPalette)
                  GestureDetector(
                    onTap: () => setState(() => _pendingColor = c),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: _pendingColor == c
                            ? Border.all(color: colors.text, width: 2)
                            : null,
                      ),
                    ),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : _cancelPending,
                  child: Text(tr(locale, 'cancel')),
                ),
                FilledButton(
                  onPressed: _saving ? null : _saveHighlight,
                  child: Text(tr(locale, 'highlight')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Normalized {
  _Normalized(this.text, this.map);
  final String text;
  final List<int> map;
}

class _PaintSpan {
  _PaintSpan(this.text, this.bold, this.italic, this.background);
  final String text;
  final bool bold;
  final bool italic;
  final Color? background;
}

class _Range {
  _Range(this.start, this.end, this.color);
  final int start;
  final int end;
  final int color;
}

class _Flat {
  _Flat(this.start, this.end, this.part);
  final int start;
  final int end;
  final SpanPart part;
}
