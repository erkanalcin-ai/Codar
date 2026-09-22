// Reader: page-by-page reading with CFI persistence.
//
// No WebView: engine HTML is parsed by [parseSectionHtml] into blocks and
// rendered as Flutter text. Highlights anchor on engine plain-text offsets
// plus quoted text; the CFI is the stable cross-session key.

import 'dart:async';
import 'dart:math' as math;

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
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
      'dark' => const ReaderThemeColors(
        Color(0xFF121212),
        Color(0xFFE8E8E8),
        Color(0xFF9E9E9E),
      ),
      'sepia' => const ReaderThemeColors(
        Color(0xFFF4ECD8),
        Color(0xFF433422),
        Color(0xFF8A7B5C),
      ),
      'warm' => const ReaderThemeColors(
        Color(0xFFFFF8E7),
        Color(0xFF333333),
        Color(0xFF8D8D8D),
      ),
      'black' => const ReaderThemeColors(
        Colors.black,
        Color(0xFFD6D6D6),
        Color(0xFF757575),
      ),
      _ => ReaderThemeColors(
        CodarColors.readerBackground,
        CodarColors.readerText,
        const Color(0xFF6D6251),
      ),
    };
  }
}

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    super.key,
    required this.bookId,
    this.initialSection,
    this.initialOffset,
    this.initialCfi,
  });
  final String bookId;
  final int? initialSection;

  /// Exact char offset in engine plain text (from a CFI-anchored record).
  final int? initialOffset;

  /// Expected CFI: verified on arrival via `getLocator`; drift is
  /// reported instead of silently landing on the wrong text.
  final String? initialCfi;

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _PendingSelection {
  _PendingSelection({
    required this.text,
    required this.start,
    required this.end,
  });
  final String text;
  final int start;
  final int end;
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ReaderSession? _session;
  // Cached in initState: ref is unsafe to touch in dispose().
  late final CodarReaderService _readerSvc;
  String? _error;
  BookRecord? _book;
  int _section = 0;
  int _sectionCount = 1;
  List<TextBlock> _blocks = const [];
  List<_ReaderPage> _pages = const [];
  List<_ContinuousPage> _continuousPages = const [];
  int _pageIndex = 0;
  int _continuousIndex = 0;
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
  bool _controlsVisible = false;
  Timer? _controlsTimer;
  Offset? _pointerDown;
  bool _programmaticPageChange = false;
  final _pageController = PageController();
  final _scrollController = ScrollController();
  final _regionFocus = FocusNode();
  final _regionKey = GlobalKey<SelectableRegionState>();
  static const _pageTopPadding = 88.0;
  static const _pageBottomPadding = 88.0;

  @override
  void initState() {
    super.initState();
    _readerSvc = ref.read(readerServiceProvider);
    _scrollController.addListener(_onContinuousScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _setReaderSystemUi(ref.read(readerSettingsProvider).theme);
    });
    _open();
  }

  @override
  void dispose() {
    final s = _session;
    _session = null;
    if (s != null) {
      // Fire-and-forget: dispose() cannot await, and the session close is
      // best-effort (the service also sweeps on its own dispose).
      _readerSvc.closeSession(s);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controlsTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
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
      var startOffset = widget.initialOffset ?? 0;
      double? startProgression;
      var keepSavedLocator = false;
      final saved = await ref
          .read(progressRepoProvider)
          .loadProgress(widget.bookId);
      if (widget.initialSection == null && saved != null) {
        start = saved.sectionIndex.clamp(0, info.sectionCount.toInt() - 1);
        startOffset = saved.charOffset;
        if (saved.locatorJson.trim().isNotEmpty) {
          try {
            // The persisted Readium locator is authoritative. Section/offset
            // remain the compatibility fallback for old or damaged rows.
            final restored = await svc.restoreLocator(
              session,
              saved.locatorJson,
            );
            start = restored.sectionIndex.toInt();
            // SQLite progression is book-wide. The page picker expects a
            // section-local ratio, so restore the exact local offset instead.
            startProgression = null;
            keepSavedLocator = true;
          } catch (_) {
            // Fall through to the saved section and character offset.
          }
        }
      }
      start = start.clamp(0, info.sectionCount.toInt() - 1);
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
      await _loadBook(
        start,
        offset: startOffset,
        progression: startProgression,
        verifyCfi: widget.initialCfi,
        persistProgress: !keepSavedLocator,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  /// Builds one continuous vertical reading stream from every readable spine
  /// section. Section indexes remain attached to each page for CFI, progress,
  /// highlights, notes, and bookmarks; they are no longer a user-facing page
  /// transition boundary.
  Future<void> _loadBook(
    int startSection, {
    required int offset,
    double? progression,
    String? verifyCfi,
    required bool persistProgress,
  }) async {
    final session = _session;
    if (session == null) return;
    setState(() => _loading = true);
    try {
      final svc = ref.read(readerServiceProvider);
      final settings = ref.read(readerSettingsProvider);
      final viewport = MediaQuery.sizeOf(context);
      final pages = <_ContinuousPage>[];

      for (var index = 0; index < _sectionCount; index++) {
        final content = await svc.getContent(session, index);
        final blocks = parseSectionHtml(content.html);
        final highlights = await ref
            .read(annotationsRepoProvider)
            .highlightsForSection(widget.bookId, index);
        final sectionPages = _paginateBlocks(
          blocks,
          settings,
          viewportWidth: viewport.width,
          viewportHeight: _paginationViewportHeight(viewport.height),
          engineChars: content.charCount.toInt(),
        );
        if (sectionPages.length == 1 && sectionPages.first.blocks.isEmpty) {
          continue;
        }
        final section = _ReaderSection(
          index: index,
          blocks: blocks,
          pages: sectionPages,
          enginePlain: content.plainText,
          engineChars: content.charCount.toInt(),
          normalized: _normalize(content.plainText),
          highlights: highlights,
        );
        pages.addAll(
          sectionPages.map(
            (page) => _ContinuousPage(section: section, page: page),
          ),
        );
      }

      if (pages.isEmpty) throw StateError('empty-book');
      var firstForSection = pages.indexWhere(
        (page) => page.section.index >= startSection,
      );
      if (firstForSection < 0) firstForSection = pages.length - 1;
      final section = pages[firstForSection].section;
      final pageInSection = progression == null
          ? _pageForOffset(section.pages, offset)
          : _pageForProgress(section.pages, progression);
      final target =
          (firstForSection + pageInSection.clamp(0, section.pages.length - 1))
              .clamp(0, pages.length - 1)
              .toInt();
      final active = pages[target];

      if (!mounted) return;
      setState(() {
        _continuousPages = pages;
        _section = active.section.index;
        _blocks = active.section.blocks;
        _pages = active.section.pages;
        _pageIndex = active.section.pages.indexOf(active.page);
        _enginePlain = active.section.enginePlain;
        _engineChars = active.section.engineChars;
        _normPlain = active.section.normalized.text;
        _normToOrig = active.section.normalized.map;
        _highlights = active.section.highlights;
        _pending = null;
        _loading = false;
      });
      _programmaticPageChange = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final extent = _readerPageExtent;
        _scrollController.jumpTo(
          (target * extent)
              .clamp(0.0, _scrollController.position.maxScrollExtent)
              .toDouble(),
        );
        _programmaticPageChange = false;
      });

      if (persistProgress) {
        await _saveProgress(session, active.section.index, offset);
      }
      if (verifyCfi != null && verifyCfi.isNotEmpty) {
        await _verifyCfi(session, startSection, offset, verifyCfi);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadSection(
    int index, {
    bool force = false,
    int offset = 0,
    int? targetPage,
    double? progression,
    String? verifyCfi,
    bool persistProgress = true,
  }) async {
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
      final settings = ref.read(readerSettingsProvider);
      final viewport = MediaQuery.sizeOf(context);
      final pages = _paginateBlocks(
        blocks,
        settings,
        viewportWidth: viewport.width,
        viewportHeight: _paginationViewportHeight(viewport.height),
        engineChars: content.charCount.toInt(),
      );
      // Some EPUBs contain navigation/cover/empty spine items. They must not
      // trap vertical reading on a blank chapter: continue to the nearest
      // section that has readable content while preserving the existing
      // section/offset/CFI persistence contract.
      if (pages.length == 1 && pages.first.blocks.isEmpty) {
        final next = await _findAdjacentNonEmptySection(index, 1);
        if (next != null) {
          await _loadSection(
            next,
            force: true,
            offset: 0,
            targetPage: 0,
            persistProgress: persistProgress,
          );
          return;
        }
      }
      final requestedPage = targetPage == -1
          ? pages.length - 1
          : targetPage ??
                (progression == null
                    ? _pageForOffset(pages, offset)
                    : _pageForProgress(pages, progression));
      final page = requestedPage.clamp(0, pages.length - 1).toInt();
      setState(() {
        _section = index;
        _blocks = blocks;
        _pages = pages;
        _pageIndex = page;
        _enginePlain = content.plainText;
        _engineChars = content.charCount.toInt();
        _normPlain = norm.text;
        _normToOrig = norm.map;
        _highlights = highlights;
        _pending = null;
        _loading = false;
      });
      _programmaticPageChange = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pageController.hasClients) _pageController.jumpToPage(page);
        _programmaticPageChange = false;
      });
      // Persist the exact anchor (CFI-first locator), not just the section.
      if (persistProgress) await _saveProgress(session, index, offset);
      if (verifyCfi != null && verifyCfi.isNotEmpty) {
        await _verifyCfi(session, index, offset, verifyCfi);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  double get _readerPageExtent => MediaQuery.sizeOf(context).height;

  void _onContinuousScroll() {
    if (!mounted || !_scrollController.hasClients || _continuousPages.isEmpty) {
      return;
    }
    final extent = _readerPageExtent;
    if (extent <= 0) return;
    final index = (_scrollController.offset / extent)
        .round()
        .clamp(0, _continuousPages.length - 1)
        .toInt();
    if (index == _continuousIndex) return;
    final active = _continuousPages[index];
    setState(() {
      _continuousIndex = index;
      _section = active.section.index;
      _blocks = active.section.blocks;
      _pages = active.section.pages;
      _pageIndex = active.section.pages.indexOf(active.page);
      _enginePlain = active.section.enginePlain;
      _engineChars = active.section.engineChars;
      _normPlain = active.section.normalized.text;
      _normToOrig = active.section.normalized.map;
      _highlights = active.section.highlights;
      _pending = null;
    });
    if (_programmaticPageChange) return;
    final session = _session;
    if (session != null) {
      _saveProgress(session, active.section.index, active.page.startOffset);
    }
  }

  Future<void> _jumpToSection(int sectionIndex) async {
    if (!_scrollController.hasClients || _continuousPages.isEmpty) return;
    final index = _continuousPages.indexWhere(
      (page) => page.section.index >= sectionIndex,
    );
    if (index < 0) return;
    await _scrollController.animateTo(
      (index * _readerPageExtent).toDouble(),
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _scrollToContinuousIndex(int index) async {
    if (!_scrollController.hasClients || _continuousPages.isEmpty) return;
    await _scrollController.animateTo(
      (index.clamp(0, _continuousPages.length - 1) * _readerPageExtent)
          .toDouble(),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  Future<int?> _findAdjacentNonEmptySection(int from, int direction) async {
    final session = _session;
    if (session == null) return null;
    final svc = ref.read(readerServiceProvider);
    for (
      var index = from + direction;
      index >= 0 && index < _sectionCount;
      index += direction
    ) {
      final content = await svc.getContent(session, index);
      final blocks = parseSectionHtml(content.html);
      if (blocks.any((block) => block.plainText.trim().isNotEmpty)) {
        return index;
      }
    }
    return null;
  }

  Future<void> _saveProgress(
    ReaderSession session,
    int section,
    int offset,
  ) async {
    try {
      final svc = ref.read(readerServiceProvider);
      final p = await svc.getProgress(session, section, offset);
      await ref
          .read(progressRepoProvider)
          .saveProgress(
            bookId: widget.bookId,
            locatorJson: p.locatorJson,
            sectionIndex: section,
            charOffset: offset,
            progression: p.totalProgression,
          );
    } catch (_) {
      // Progress is best-effort per navigation; the book stays readable.
    }
  }

  List<_ReaderPage> _paginateBlocks(
    List<TextBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
  }) {
    final margin = settings.marginPx.toDouble().clamp(8.0, 96.0).toDouble();
    final width = math.max(120.0, viewportWidth - margin * 2).toDouble();
    final height = math.max(220.0, viewportHeight - 42.0).toDouble();
    final align = switch (settings.alignment) {
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      _ => TextAlign.start,
    };
    final parsedLength = blocks.fold<int>(
      0,
      (total, block) => total + block.plainText.length,
    );
    final rawPages = <_RawReaderPage>[];
    final current = <TextBlock>[];
    var used = 0.0;
    var currentStart = 0;
    var parsedCursor = 0;

    void flush() {
      if (current.isEmpty) return;
      rawPages.add(_RawReaderPage(List.of(current), currentStart));
      current.clear();
      used = 0;
    }

    for (final block in blocks) {
      final text = block.plainText;
      if (text.isEmpty) continue;
      var cursor = 0;
      while (cursor < text.length) {
        final spacing = current.isEmpty ? 0.0 : 12.0;
        final available = height - used - spacing;
        final end = _fitEnd(
          block,
          cursor,
          width,
          math.max(1.0, available).toDouble(),
          settings,
          align,
        );
        if (end <= cursor) {
          if (current.isNotEmpty) {
            flush();
            continue;
          }
          // A single glyph can still exceed the calculated budget on a very
          // small viewport or with a large accessibility font. Keep progress
          // moving and let the page clip only that unavoidable glyph.
          currentStart = parsedCursor + cursor;
          final forcedEnd = math.min(cursor + 1, text.length);
          current.add(_sliceBlock(block, cursor, forcedEnd));
          used = _measureBlock(current.single, width, settings, align);
          cursor = forcedEnd;
          if (cursor < text.length) flush();
          continue;
        }
        if (current.isEmpty) currentStart = parsedCursor + cursor;
        final piece = _sliceBlock(block, cursor, end);
        current.add(piece);
        used += spacing + _measureBlock(piece, width, settings, align);
        cursor = end;
        if (cursor < text.length) flush();
      }
      parsedCursor += text.length;
    }
    flush();
    if (rawPages.isEmpty) {
      return [const _ReaderPage(blocks: [], startOffset: 0)];
    }
    return [
      for (final page in rawPages)
        _ReaderPage(
          blocks: page.blocks,
          startOffset: parsedLength == 0
              ? 0
              : ((page.start / parsedLength) * engineChars)
                    .round()
                    .clamp(0, engineChars)
                    .toInt(),
        ),
    ];
  }

  int _fitEnd(
    TextBlock block,
    int start,
    double width,
    double available,
    ReaderSettingsData settings,
    TextAlign align,
  ) {
    final text = block.plainText;
    final remaining = text.substring(start);
    if (_measureText(block, remaining, width, settings, align) <= available) {
      return text.length;
    }
    var low = start + 1;
    var high = text.length;
    var best = start;
    while (low <= high) {
      final mid = (low + high) ~/ 2;
      final candidate = text.substring(start, mid);
      if (_measureText(block, candidate, width, settings, align) <= available) {
        best = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    if (best <= start) return start;
    var boundary = best;
    while (boundary > start && !RegExp(r'\s').hasMatch(text[boundary - 1])) {
      boundary--;
    }
    return boundary > start ? boundary : best;
  }

  double _measureBlock(
    TextBlock block,
    double width,
    ReaderSettingsData settings,
    TextAlign align,
  ) => _measureText(block, block.plainText, width, settings, align);

  double _measureText(
    TextBlock block,
    String text,
    double width,
    ReaderSettingsData settings,
    TextAlign align,
  ) {
    final style = _styleForBlock(block, settings, const Color(0xFF111111));
    final prefix = block.kind == 'li' ? '• ' : '';
    final painter = TextPainter(
      text: TextSpan(text: '$prefix$text', style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return painter.height;
  }

  TextBlock _sliceBlock(TextBlock block, int start, int end) {
    final parts = <SpanPart>[];
    var cursor = 0;
    for (final part in block.parts) {
      final partEnd = cursor + part.text.length;
      final from = math.max(start, cursor);
      final to = math.min(end, partEnd);
      if (to > from) {
        parts.add(
          SpanPart(
            part.text.substring(from - cursor, to - cursor),
            bold: part.bold,
            italic: part.italic,
          ),
        );
      }
      cursor = partEnd;
      if (cursor >= end) break;
    }
    return TextBlock(kind: block.kind, parts: parts);
  }

  int _pageForOffset(List<_ReaderPage> pages, int offset) {
    if (pages.length <= 1 || offset <= 0) return 0;
    var selected = 0;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].startOffset <= offset) selected = i;
    }
    return selected;
  }

  int _pageForProgress(List<_ReaderPage> pages, double progression) {
    if (pages.length <= 1) return 0;
    final ratio = progression.clamp(0.0, 1.0).toDouble();
    return (ratio * (pages.length - 1))
        .round()
        .clamp(0, pages.length - 1)
        .toInt();
  }

  static double _paginationViewportHeight(double height) =>
      height - _pageTopPadding - _pageBottomPadding + 42.0;

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
    final end =
        _normToOrig[(idx + needle.length - 1).clamp(
          0,
          _normToOrig.length - 1,
        )] +
        1;
    return _PendingSelection(
      text: _enginePlain.substring(start, end.clamp(0, _enginePlain.length)),
      start: start,
      end: end.clamp(0, _enginePlain.length),
    );
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
    if (resolved != null) _showControls();
  }

  _PendingSelection _expand(_PendingSelection sel, String mode) {
    bool isWordChar(String ch) =>
        RegExp(r'[\p{L}\p{N}_]', unicode: true).hasMatch(ch);
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
    return _PendingSelection(
      text: text,
      start: off < 0 ? s : off,
      end: (off < 0 ? s : off) + text.length,
    );
  }

  Future<void> _saveHighlight({String note = ''}) async {
    final pending = _pending;
    final session = _session;
    if (pending == null || session == null || _saving) return;
    setState(() => _saving = true);
    try {
      final svc = ref.read(readerServiceProvider);
      final locator = await svc.getLocator(session, _section, pending.start);
      final cfi = _cfiOf(locator);
      await ref
          .read(annotationsRepoProvider)
          .addHighlight(
            HighlightRecord(
              bookId: widget.bookId,
              sectionIndex: _section,
              startOffset: pending.start,
              endOffset: pending.end,
              cfi: cfi,
              color: _pendingColor,
              quotedText: pending.text,
              note: note,
            ),
          );
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
    } catch (_) {
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

  /// Verify the live CFI for (section, offset) against the expected one.
  /// On drift the section is still shown (offsets stay authoritative for
  /// rendering) but the user is told the anchor did not verify.
  Future<void> _verifyCfi(
    ReaderSession session,
    int section,
    int offset,
    String expected,
  ) async {
    try {
      final svc = ref.read(readerServiceProvider);
      final locator = await svc.getLocator(session, section, offset);
      final live = _cfiOf(locator);
      if (live.isEmpty || live != expected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr(ref.read(localeProvider), 'cfiMismatch')),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _addBookmark() async {
    final session = _session;
    if (session == null) return;
    try {
      final svc = ref.read(readerServiceProvider);
      final offset = _currentPageOffset;
      final locator = await svc.getLocator(session, _section, offset);
      await ref
          .read(annotationsRepoProvider)
          .addBookmark(
            BookmarkRecord(
              bookId: widget.bookId,
              sectionIndex: _section,
              cfi: _cfiOf(locator),
              charOffset: offset,
              label:
                  '${tr(ref.read(localeProvider), 'sectionOf')} ${_section + 1}',
            ),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(ref.read(localeProvider), 'bookmarkAdded')),
          ),
        );
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
          decoration: InputDecoration(hintText: tr(locale, 'noteHint')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr(locale, 'cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: Text(tr(locale, 'save')),
          ),
        ],
      ),
    );
    if (content == null || content.isEmpty) return;
    try {
      final svc = ref.read(readerServiceProvider);
      final offset = pending?.start ?? 0;
      final locator = await svc.getLocator(session, _section, offset);
      await ref
          .read(annotationsRepoProvider)
          .addNote(
            NoteRecord(
              bookId: widget.bookId,
              sectionIndex: _section,
              cfi: _cfiOf(locator),
              charOffset: offset,
              content: content,
              quotedText: pending?.text ?? '',
            ),
          );
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
                title: Text(
                  tr(locale, 'chapters'),
                  style: Theme.of(c).textTheme.titleMedium,
                ),
              ),
              for (var i = 0; i < chapters.length; i++)
                ListTile(
                  contentPadding: EdgeInsets.only(
                    left: 16.0 + chapters[i].depth.toInt() * 16.0,
                    right: 16,
                  ),
                  title: Text(
                    chapters[i].title.isEmpty ? '—' : chapters[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.pop(c, i),
                ),
            ],
          ),
        ),
      );
      if (picked == null) return;
      final href = chapters[picked].href;
      final found = href.isEmpty ? null : await svc.findSection(session, href);
      await _jumpToSection((found ?? picked).clamp(0, _sectionCount - 1));
    } catch (_) {}
  }

  Future<void> _showReaderSettings(String locale) async {
    var draft = ref.read(readerSettingsProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(ReaderSettingsData next) {
            draft = next;
            setSheetState(() {});
            ref.read(readerSettingsProvider.notifier).set(next);
            ref.read(settingsRepoProvider).saveReaderSettings(next);
            _setReaderSystemUi(next.theme);
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(locale, 'readerSettings'),
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: Text(tr(locale, 'fontFamily'))),
                      DropdownButton<String>(
                        value: draft.fontFamily,
                        underline: const SizedBox.shrink(),
                        items: const ['System', 'Serif', 'Monospace']
                            .map(
                              (font) => DropdownMenuItem(
                                value: font,
                                child: Text(font),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => update(
                          draft.copyWith(fontFamily: value ?? 'System'),
                        ),
                      ),
                    ],
                  ),
                  _ReaderSliderRow(
                    label: tr(locale, 'fontSize'),
                    value: draft.fontSizePx.toDouble(),
                    min: 12,
                    max: 32,
                    divisions: 20,
                    display: '${draft.fontSizePx}',
                    onChanged: (value) =>
                        update(draft.copyWith(fontSizePx: value.round())),
                  ),
                  _ReaderSliderRow(
                    label: tr(locale, 'lineHeight'),
                    value: draft.lineHeight,
                    min: 1,
                    max: 2.2,
                    divisions: 12,
                    display: draft.lineHeight.toStringAsFixed(2),
                    onChanged: (value) =>
                        update(draft.copyWith(lineHeight: value)),
                  ),
                  Row(
                    children: [
                      Expanded(child: Text(tr(locale, 'theme'))),
                      DropdownButton<String>(
                        value: draft.theme,
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final theme in [
                            'light',
                            'dark',
                            'sepia',
                            'warm',
                            'black',
                          ])
                            DropdownMenuItem(
                              value: theme,
                              child: Text(tr(locale, 'theme${_cap(theme)}')),
                            ),
                        ],
                        onChanged: (value) =>
                            update(draft.copyWith(theme: value ?? 'light')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  static String _cap(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  void _setReaderSystemUi(String theme) {
    final lightStatusBar = theme != 'dark' && theme != 'black';
    final colors = ReaderThemeColors.of(theme, context);
    final style = lightStatusBar
        ? SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
            systemNavigationBarColor: colors.background,
            systemNavigationBarIconBrightness: Brightness.dark,
            systemNavigationBarDividerColor: colors.background,
          )
        : SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
            systemNavigationBarColor: colors.background,
            systemNavigationBarIconBrightness: Brightness.light,
            systemNavigationBarDividerColor: colors.background,
          );
    SystemChrome.setSystemUIOverlayStyle(style);
    const MethodChannel('codar/storage').invokeMethod<void>(
      'setSystemUi',
      <String, Object>{'lightStatusBar': lightStatusBar},
    );
  }

  int get _currentPageOffset {
    if (_continuousPages.isNotEmpty) {
      return _continuousPages[_continuousIndex].page.startOffset;
    }
    return _pages.isEmpty
        ? 0
        : _pages[_pageIndex.clamp(0, _pages.length - 1).toInt()].startOffset;
  }

  void _scheduleControlsHide() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _showControls() {
    if (!mounted) return;
    setState(() => _controlsVisible = true);
    _scheduleControlsHide();
  }

  void _toggleControls() {
    if (!mounted) return;
    if (_controlsVisible) {
      _controlsTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _showControls();
    }
  }

  void _onReaderPointerDown(PointerDownEvent event) {
    _pointerDown = event.position;
  }

  void _onReaderPointerUp(PointerUpEvent event) {
    final start = _pointerDown;
    _pointerDown = null;
    if (start == null || (event.position - start).distance > 12) return;
    if (_controlsVisible) {
      final height = MediaQuery.sizeOf(context).height;
      if (event.position.dy < 160 || event.position.dy > height - 160) {
        return;
      }
    }
    _toggleControls();
  }

  void _onPageChanged(int page) {
    if (!mounted || page < 0 || page >= _pages.length) return;
    setState(() => _pageIndex = page);
    if (_programmaticPageChange) return;
    final session = _session;
    if (session != null) {
      _saveProgress(session, _section, _pages[page].startOffset);
    }
    if (page == _pages.length - 1 && _section < _sectionCount - 1) {
      _loadAdjacentSection(1);
    } else if (page == 0 && _section > 0) {
      _loadAdjacentSection(-1);
    }
  }

  Future<void> _loadAdjacentSection(int direction) async {
    if (_loading) return;
    final next = await _findAdjacentNonEmptySection(_section, direction);
    if (!mounted || next == null) return;
    await _loadSection(
      next,
      force: true,
      offset: 0,
      targetPage: direction < 0 ? -1 : 0,
      persistProgress: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final settings = ref.watch(readerSettingsProvider);
    final colors = ReaderThemeColors.of(settings.theme, context);
    final lightSystemBars =
        settings.theme != 'dark' && settings.theme != 'black';
    final overlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: lightSystemBars
          ? Brightness.dark
          : Brightness.light,
      statusBarBrightness: lightSystemBars ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: colors.background,
      systemNavigationBarIconBrightness: lightSystemBars
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarDividerColor: colors.background,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: colors.background,
        body: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _onReaderPointerDown,
          onPointerUp: _onReaderPointerUp,
          onPointerCancel: (_) => _pointerDown = null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildBody(locale, settings, colors),
              if (_pending != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _highlightBar(locale, colors),
                ),
              _readerTopControls(locale, colors),
              _readerBottomControls(locale, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    String locale,
    ReaderSettingsData settings,
    ReaderThemeColors colors,
  ) {
    if (_loading && _pages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _pages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${tr(locale, 'errorPrefix')}: '
              '${_displayError(_error!, locale)}',
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _open,
              child: Text(tr(locale, 'retry')),
            ),
          ],
        ),
      );
    }
    final margin = settings.marginPx.toDouble().clamp(8.0, 96.0).toDouble();
    final align = switch (settings.alignment) {
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      _ => TextAlign.start,
    };
    final pages = _pages.isEmpty
        ? _paginateBlocks(
            _blocks,
            settings,
            viewportWidth: MediaQuery.sizeOf(context).width,
            viewportHeight: _paginationViewportHeight(
              MediaQuery.sizeOf(context).height,
            ),
            engineChars: _engineChars,
          )
        : _pages;
    if (pages.isEmpty) return const SizedBox.shrink();
    if (_continuousPages.isNotEmpty) {
      return ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        itemCount: _continuousPages.length,
        itemBuilder: (context, i) => _buildContinuousPage(
          _continuousPages[i],
          i,
          locale,
          settings,
          colors,
          margin,
          align,
        ),
      );
    }
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      padEnds: false,
      itemCount: pages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, i) {
        final page = pages[i];
        return Semantics(
          label: '${tr(locale, 'pageOf')} ${i + 1} / ${pages.length}',
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              margin,
              _pageTopPadding,
              margin,
              _pageBottomPadding,
            ),
            child: SelectableRegion(
              key: i == _pageIndex ? _regionKey : null,
              focusNode: i == _pageIndex ? _regionFocus : null,
              selectionControls: MaterialTextSelectionControls(),
              onSelectionChanged: _onSelectionChanged,
              child: page.blocks.isEmpty
                  ? Text(
                      tr(locale, 'emptySection'),
                      style: TextStyle(color: colors.weak),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var j = 0; j < page.blocks.length; j++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: j == page.blocks.length - 1 ? 0 : 12,
                            ),
                            child: _blockText(
                              page.blocks[j],
                              settings,
                              colors,
                              align,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContinuousPage(
    _ContinuousPage entry,
    int index,
    String locale,
    ReaderSettingsData settings,
    ReaderThemeColors colors,
    double margin,
    TextAlign align,
  ) {
    final page = entry.page;
    final section = entry.section;
    return Semantics(
      label:
          '${tr(locale, 'pageOf')} ${index + 1} / ${_continuousPages.length}',
      child: SizedBox(
        height: _readerPageExtent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            margin,
            _pageTopPadding,
            margin,
            _pageBottomPadding,
          ),
          child: SelectableRegion(
            key: index == _continuousIndex ? _regionKey : null,
            focusNode: index == _continuousIndex ? _regionFocus : null,
            selectionControls: MaterialTextSelectionControls(),
            onSelectionChanged: _onSelectionChanged,
            child: page.blocks.isEmpty
                ? Text(
                    tr(locale, 'emptySection'),
                    style: TextStyle(color: colors.weak),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var j = 0; j < page.blocks.length; j++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: j == page.blocks.length - 1 ? 0 : 12,
                          ),
                          child: _blockText(
                            page.blocks[j],
                            settings,
                            colors,
                            align,
                            highlights: section.highlights,
                            engineChars: section.engineChars,
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _blockText(
    TextBlock block,
    ReaderSettingsData settings,
    ReaderThemeColors colors,
    TextAlign align, {
    List<HighlightRecord>? highlights,
    int? engineChars,
  }) {
    final base = _styleForBlock(block, settings, colors.text);
    final spans = _spansFor(
      block,
      base,
      highlights: highlights,
      engineChars: engineChars,
    );
    final style = base;
    final prefix = block.kind == 'li' ? '• ' : '';
    return Text.rich(
      TextSpan(
        children: [
          if (prefix.isNotEmpty) TextSpan(text: prefix, style: style),
          ...spans.map(
            (s) => TextSpan(
              text: s.text,
              style: style.copyWith(
                fontWeight: s.bold ? FontWeight.bold : null,
                fontStyle: s.italic ? FontStyle.italic : null,
                backgroundColor: s.background,
              ),
            ),
          ),
        ],
      ),
      textAlign: align,
    );
  }

  TextStyle _styleForBlock(
    TextBlock block,
    ReaderSettingsData settings,
    Color color,
  ) {
    final fontSize = settings.fontSizePx
        .toDouble()
        .clamp(12.0, 40.0)
        .toDouble();
    final height = settings.lineHeight.clamp(1.0, 2.5).toDouble();
    final base = TextStyle(
      fontSize: fontSize,
      height: height,
      color: color,
      fontFamily: _fontFamily(settings.fontFamily),
    );
    if (!block.isHeading) return base;
    return base.copyWith(
      fontWeight: FontWeight.bold,
      fontSize:
          base.fontSize! *
          (block.kind == 'h1'
              ? 1.5
              : block.kind == 'h2'
              ? 1.35
              : 1.2),
    );
  }

  List<_PaintSpan> _spansFor(
    TextBlock block,
    TextStyle base, {
    List<HighlightRecord>? highlights,
    int? engineChars,
  }) {
    final activeHighlights = highlights ?? _highlights;
    final activeEngineChars = engineChars ?? _engineChars;
    final text = block.plainText;
    if (text.isEmpty || activeHighlights.isEmpty) {
      return [
        for (final p in block.parts) _PaintSpan(p.text, p.bold, p.italic, null),
      ];
    }
    // Overlay highlight ranges located by quoted text (nearest relative pos).
    final ranges = <_Range>[];
    for (final h in activeHighlights) {
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
      final rel = activeEngineChars <= 0
          ? 0.0
          : (h.startOffset / activeEngineChars).clamp(0.0, 1.0);
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

  void _emitPlain(
    List<_Flat> flat,
    int from,
    int to,
    List<_PaintSpan> out,
    Color? background,
  ) {
    if (from >= to) return;
    for (final f in flat) {
      final s = from.clamp(f.start, f.end);
      final e = to.clamp(f.start, f.end);
      if (e > s) {
        out.add(
          _PaintSpan(
            f.part.text.substring(s - f.start, e - f.start),
            f.part.bold,
            f.part.italic,
            background,
          ),
        );
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

  static String _displayError(String raw, String locale) {
    if (raw.contains('no-file')) {
      return tr(locale, 'missingFileReimport');
    }
    // Never leak engine internals: show a short, safe tail.
    final oneLine = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= 160) return oneLine;
    return '${oneLine.substring(0, 160)}…';
  }

  Widget _readerTopControls(String locale, ReaderThemeColors colors) {
    final title = _book?.title.isNotEmpty == true
        ? _book!.title
        : tr(locale, 'appTitle');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _controlsVisible ? 1 : 0,
          child: SafeArea(
            bottom: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.background.withValues(alpha: 0.98),
                    colors.background.withValues(alpha: 0.84),
                    colors.background.withValues(alpha: 0),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 18),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr(locale, 'backToLibrary'),
                      color: colors.text,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.weak,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                    Semantics(
                      label: tr(locale, 'pageOf'),
                      value: _continuousPages.isEmpty
                          ? tr(locale, 'loading')
                          : '${_continuousIndex + 1} / ${_continuousPages.length}',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          _continuousPages.isEmpty
                              ? '—'
                              : '${_continuousIndex + 1} / ${_continuousPages.length}',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr(locale, 'readerSettings'),
                      color: colors.text,
                      icon: const Icon(Icons.text_fields_rounded),
                      onPressed: () => _showReaderSettings(locale),
                    ),
                    IconButton(
                      tooltip: tr(locale, 'addBookmark'),
                      color: colors.text,
                      icon: const Icon(Icons.bookmark_border_rounded),
                      onPressed: _session == null ? null : _addBookmark,
                    ),
                    PopupMenuButton<String>(
                      tooltip: tr(locale, 'more'),
                      icon: Icon(Icons.more_horiz_rounded, color: colors.text),
                      onSelected: (value) {
                        if (value == 'chapters') {
                          _openChapters();
                        } else if (value == 'note') {
                          _addNote();
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'chapters',
                          enabled: _session != null,
                          child: Row(
                            children: [
                              const Icon(Icons.menu_book_outlined),
                              const SizedBox(width: 12),
                              Text(tr(locale, 'chapters')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'note',
                          enabled: _session != null,
                          child: Row(
                            children: [
                              const Icon(Icons.edit_note_rounded),
                              const SizedBox(width: 12),
                              Text(tr(locale, 'addNote')),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _readerBottomControls(String locale, ReaderThemeColors colors) {
    final total = _continuousPages.isNotEmpty
        ? _continuousPages.length
        : _pages.length;
    final current = _continuousPages.isNotEmpty ? _continuousIndex : _pageIndex;
    final progress = total <= 1 ? 0.0 : current / (total - 1);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        ignoring: !_controlsVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: _controlsVisible ? 1 : 0,
          child: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.background.withValues(alpha: 0),
                    colors.background.withValues(alpha: 0.86),
                    colors.background.withValues(alpha: 0.98),
                  ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 18, 12, 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr(locale, 'previousPage'),
                      color: colors.text,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      onPressed: current > 0
                          ? () => _continuousPages.isNotEmpty
                                ? _scrollToContinuousIndex(current - 1)
                                : _pageController.previousPage(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                  )
                          : null,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 180),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 2,
                              color: colors.text,
                              backgroundColor: colors.weak.withValues(
                                alpha: 0.22,
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            total == 0
                                ? tr(locale, 'loading')
                                : '${current + 1} / $total',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.weak,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr(locale, 'nextPage'),
                      color: colors.text,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      onPressed: current < total - 1
                          ? () => _continuousPages.isNotEmpty
                                ? _scrollToContinuousIndex(current + 1)
                                : _pageController.nextPage(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOut,
                                  )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
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
                      value: 'word',
                      label: Text(tr(locale, 'word')),
                    ),
                    ButtonSegment(
                      value: 'sentence',
                      label: Text(tr(locale, 'sentence')),
                    ),
                    ButtonSegment(
                      value: 'paragraph',
                      label: Text(tr(locale, 'paragraph')),
                    ),
                  ],
                  selected: {_granularity},
                  onSelectionChanged: (s) {
                    final mode = s.first;
                    setState(() => _granularity = mode);
                    if (pending != null && mode != 'paragraph') {
                      setState(() => _pending = _expand(pending, mode));
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

extension _ReaderSettingsCopy on ReaderSettingsData {
  ReaderSettingsData copyWith({
    String? fontFamily,
    int? fontSizePx,
    double? lineHeight,
    int? marginPx,
    String? alignment,
    String? theme,
  }) => ReaderSettingsData(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSizePx: fontSizePx ?? this.fontSizePx,
    lineHeight: lineHeight ?? this.lineHeight,
    marginPx: marginPx ?? this.marginPx,
    alignment: alignment ?? this.alignment,
    theme: theme ?? this.theme,
  );
}

class _ReaderSliderRow extends StatelessWidget {
  const _ReaderSliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text(display, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _RawReaderPage {
  _RawReaderPage(this.blocks, this.start);
  final List<TextBlock> blocks;
  final int start;
}

class _ReaderPage {
  const _ReaderPage({required this.blocks, required this.startOffset});
  final List<TextBlock> blocks;
  final int startOffset;
}

class _ReaderSection {
  const _ReaderSection({
    required this.index,
    required this.blocks,
    required this.pages,
    required this.enginePlain,
    required this.engineChars,
    required this.normalized,
    required this.highlights,
  });

  final int index;
  final List<TextBlock> blocks;
  final List<_ReaderPage> pages;
  final String enginePlain;
  final int engineChars;
  final _Normalized normalized;
  final List<HighlightRecord> highlights;
}

class _ContinuousPage {
  const _ContinuousPage({required this.section, required this.page});

  final _ReaderSection section;
  final _ReaderPage page;
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
