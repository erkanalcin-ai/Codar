// Reader: page-by-page reading with CFI persistence.
//
// No WebView: engine HTML is parsed by [parseSectionHtml] into blocks and
// rendered as Flutter text. Highlights anchor on engine plain-text offsets
// plus quoted text; the CFI is the stable cross-session key.

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:codar/src/app/providers.dart';
import 'package:codar/src/brand/codar_brand.dart';
import 'package:codar/src/db/models.dart';
import 'package:codar/src/db/repositories.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/highlight_range.dart';
import 'package:codar/src/reader/page_count_index.dart';
import 'package:codar/src/reader/page_count_cache.dart';
import 'package:codar/src/reader/reader_progress_display.dart';
import 'package:codar/src/reader/reader_page_snap.dart';
import 'package:codar/src/reader/reader_pagination.dart';
import 'package:codar/src/reader/reader_image_view.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:codar/src/reader/reader_bookmark_state.dart';
import 'package:codar/src/reader/quote_range.dart';
import 'package:codar/src/reader/reader_reflow_coalescer.dart';
import 'package:codar/src/reader/selection_geometry.dart';
import 'package:codar/src/reader/selection_popup_placement.dart';
import 'package:codar/src/reader/text_selection_offsets.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart'
    as reader_dto;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ScrollCacheExtent, SelectedContent, SelectedContentRange;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const highlightPalette = [
  0xFFFFFF00, // yellow
  0xFF90EE90, // green
  0xFFADD8E6, // blue
  0xFFFFB6C1, // pink
  0xFFFFA500, // orange
];

final _readerSelectionControls = _ReaderSelectionControls();

// The WCAG black/white contrast crossover is about 0.179 relative luminance.
Color _highlightForeground(Color background) =>
    background.computeLuminance() > 0.179 ? Colors.black : Colors.white;

class ReaderThemeColors {
  const ReaderThemeColors(
    this.background,
    this.text,
    this.weak,
    this.accent,
    this.onAccent,
    this.progressTrack,
  );
  final Color background;
  final Color text;
  final Color weak;
  final Color accent;
  final Color onAccent;
  final Color progressTrack;

  bool get isDark => background.computeLuminance() < 0.1;

  static ReaderThemeColors of(String theme) {
    return switch (theme) {
      'dark' => const ReaderThemeColors(
        Color(0xFF26313D),
        Color(0xFFE7EAF0),
        Color(0xFFADB5C1),
        CodarColors.brightGold,
        CodarColors.background,
        Color(0xFF75808C),
      ),
      'sepia' => const ReaderThemeColors(
        Color(0xFFF3E0B2),
        Color(0xFF3D301C),
        Color(0xFF6B5731),
        Color(0xFF755A2D),
        Colors.white,
        Color(0xFF8E7955),
      ),
      'warm' => const ReaderThemeColors(
        Color(0xFFFFF4DE),
        Color(0xFF3C3325),
        Color(0xFF71654D),
        Color(0xFF755A2D),
        Colors.white,
        Color(0xFF958872),
      ),
      'black' => const ReaderThemeColors(
        Colors.black,
        Color(0xFFE5E5E5),
        Color(0xFFA0A0A0),
        CodarColors.brightGold,
        CodarColors.background,
        Color(0xFF5B5B5B),
      ),
      _ => const ReaderThemeColors(
        Colors.white,
        Color(0xFF25211C),
        Color(0xFF68645E),
        Color(0xFF755A2D),
        Colors.white,
        Color(0xFF92908C),
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
  _PendingSelection({required this.text, required this.ranges});
  final String text;
  final List<_SectionSelection> ranges;
}

class _ReaderLayoutSuperseded implements Exception {
  const _ReaderLayoutSuperseded();
}

class _SectionSelection {
  const _SectionSelection(this.sectionIndex, this.start, this.end);
  final int sectionIndex;
  final int start;
  final int end;
}

class _BlockSelection {
  const _BlockSelection(this.sectionIndex, this.start, this.end);
  final int sectionIndex;
  final int start;
  final int end;
}

class _PendingProgressSave {
  const _PendingProgressSave(
    this.session,
    this.section,
    this.offset,
    this.revision,
  );

  final ReaderSession session;
  final int section;
  final int offset;
  final int revision;
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ReaderSession? _session;
  // Cached in initState: ref is unsafe to touch in dispose().
  late final CodarReaderService _readerSvc;
  late final ProgressRepository _progressRepo;
  String? _error;
  BookRecord? _book;
  int _section = 0;
  int _sectionCount = 1;
  bool _isPdf = false;
  bool _isCbz = false;
  final LinkedHashMap<int, _ReaderSection> _pdfSectionCache =
      LinkedHashMap<int, _ReaderSection>();
  final Map<int, Object> _pdfSectionErrors = {};
  int? _pdfRequestedIndex;
  int _pdfPrefetchDirection = 1;
  Future<void>? _pdfLoadWorker;
  int? _continuousSectionRequestedIndex;
  Future<void>? _continuousSectionLoadWorker;
  final Set<int> _loadingContinuousSections = {};
  final Map<int, Object> _continuousSectionErrors = {};
  List<ReaderBlock> _blocks = const [];
  List<_ReaderPage> _pages = const [];
  List<_ContinuousPage> _continuousPages = const [];
  ReaderPageCountIndex? _continuousPageCountIndex;
  int _continuousPageCountJobRevision = 0;
  int _pageIndex = 0;
  int _continuousIndex = 0;
  String _enginePlain = '';
  int _engineChars = 0;
  List<HighlightRecord> _highlights = const [];
  final ReaderBookmarkState _bookmarkState = ReaderBookmarkState();
  List<QuoteRecord> _quotes = const [];
  final Map<int, List<ReaderQuoteRange>> _quoteHighlightsBySection = {};
  _PendingSelection? _pending;
  final Map<Object, _BlockSelection> _selectedBlockRanges = {};
  final Map<Object, List<Rect>> _selectedBlockRects = {};
  bool _selectionChanging = false;
  bool _keepSelectionAfterHighlightUpdate = false;
  Offset? _selectionAnchor;
  bool _loading = true;
  ReaderProgressDisplayMode _progressDisplayMode =
      ReaderProgressDisplayMode.pageAndPercent;
  double? _currentTotalProgression;
  int _progressRequestRevision = 0;
  bool _saving = false;
  bool _bookmarkSaving = false;
  bool _controlsVisible = false;
  Timer? _controlsTimer;
  Timer? _progressSaveTimer;
  Timer? _layoutReflowTimer;
  _PendingProgressSave? _pendingProgressSave;
  Future<void> _progressSaveTail = Future.value();
  Offset? _pointerDown;
  bool _programmaticPageChange = false;
  Size? _paginationViewport;
  bool _viewportReflowScheduled = false;
  bool _pendingViewportReflow = false;
  int _layoutReflowRevision = 0;
  int? _activeLayoutReflowRevision;
  bool _layoutReflowPending = false;
  Object? _layoutReflowError;
  final _pageController = PageController();
  final _scrollController = ScrollController();
  final _continuousPageNotifier = ValueNotifier<int>(0);
  final _reflowCoalescer = ReaderReflowCoalescer();
  final _regionFocus = FocusNode();
  final _regionKey = GlobalKey<SelectableRegionState>();
  final _readerStackKey = GlobalKey();
  static const _pageTopPadding = ReaderPagination.pageTopPadding;
  static const _pageBottomPadding = ReaderPagination.pageBottomPadding;

  @override
  void initState() {
    super.initState();
    _readerSvc = ref.read(readerServiceProvider);
    _progressRepo = ref.read(progressRepoProvider);
    _scrollController.addListener(_onContinuousScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      _setReaderSystemUi(ref.read(readerSettingsProvider).theme);
      _setReaderBrightness(ref.read(readerSettingsProvider).brightness);
    });
    ref.listenManual(readerSettingsProvider, (previous, next) {
      _setReaderBrightness(next.brightness);
      final layoutChanged =
          previous != null &&
          (previous.fontFamily != next.fontFamily ||
              previous.fontSizePx != next.fontSizePx ||
              previous.lineHeight != next.lineHeight ||
              previous.marginPx != next.marginPx ||
              previous.alignment != next.alignment);
      if (layoutChanged) {
        if (!_isPdf && !_isCbz) _continuousPageCountJobRevision++;
        final revision = ++_layoutReflowRevision;
        _markLayoutReflowPending();
        if (_isPdf) {
          _scheduleDebouncedLayoutReflow(revision);
          return;
        }
        final scheduledRevision = _reflowCoalescer.request(revision);
        if (scheduledRevision != null) {
          _scheduleDebouncedLayoutReflow(scheduledRevision);
        }
      }
    });
    unawaited(_loadProgressDisplayPreference());
    _open();
  }

  Future<void> _loadProgressDisplayPreference() async {
    try {
      final value = await ref
          .read(settingsRepoProvider)
          .appValue('reader_progress_display', 'page_and_percent');
      if (!mounted) return;
      setState(() {
        _progressDisplayMode = ReaderProgressDisplayMode.fromStored(value);
      });
    } catch (_) {
      // A missing or unreadable optional preference uses the documented default.
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final viewport = MediaQuery.sizeOf(context);
    final previous = _paginationViewport;
    _paginationViewport = viewport;
    if (previous != null && previous != viewport && _session != null) {
      if (!_isPdf && !_isCbz) _continuousPageCountJobRevision++;
      final revision = ++_layoutReflowRevision;
      _markLayoutReflowPending();
      _scheduleViewportReflow(revision: revision);
    }
  }

  void _markLayoutReflowPending() {
    if (!mounted || (_layoutReflowPending && _layoutReflowError == null)) {
      return;
    }
    setState(() {
      _layoutReflowPending = true;
      _layoutReflowError = null;
      if (!_isPdf && !_isCbz) _continuousPageCountIndex = null;
    });
  }

  void _retryLayoutReflow() {
    _markLayoutReflowPending();
    _scheduleViewportReflow(revision: _layoutReflowRevision);
  }

  void _scheduleDebouncedLayoutReflow(int revision) {
    _layoutReflowTimer?.cancel();
    _layoutReflowTimer = Timer(
      const Duration(milliseconds: 180),
      () => _scheduleViewportReflow(revision: revision),
    );
  }

  void _beginLayoutSliderChange() {
    _reflowCoalescer.beginInteraction();
    _layoutReflowTimer?.cancel();
    if (_layoutReflowPending) {
      _reflowCoalescer.defer(_layoutReflowRevision);
    }
  }

  void _endLayoutSliderChange() {
    final revision = _reflowCoalescer.endInteraction();
    if (revision != null) _scheduleDebouncedLayoutReflow(revision);
  }

  void _scheduleViewportReflow({int? revision}) {
    final requestedRevision = revision ?? _layoutReflowRevision;
    if (_viewportReflowScheduled) return;
    _viewportReflowScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _viewportReflowScheduled = false;
      if (!mounted) return;
      if (_session == null) {
        _pendingViewportReflow = true;
        return;
      }
      if (requestedRevision != _layoutReflowRevision) {
        _scheduleViewportReflow(revision: _layoutReflowRevision);
        return;
      }
      if (_loading) {
        _pendingViewportReflow = true;
        return;
      }
      _pendingViewportReflow = false;
      if (_continuousPages.isEmpty) {
        unawaited(_reflowCurrentSection(requestedRevision));
        return;
      }
      final active =
          _continuousPages[_continuousIndex.clamp(
            0,
            _continuousPages.length - 1,
          )];
      final section = active.section.index;
      final offset = active.page.startOffset;
      final reusableSections = <int, _ReaderSection>{};
      if (!_isPdf) {
        for (final page in _continuousPages) {
          if (!page.section.isPlaceholder) {
            reusableSections.putIfAbsent(
              page.section.index,
              () => page.section,
            );
          }
        }
      }
      if (_isPdf) _pdfSectionCache.clear();
      unawaited(
        _loadBook(
          section,
          offset: offset,
          persistProgress: false,
          layoutRevision: requestedRevision,
          reusableSections: reusableSections,
        ),
      );
    });
  }

  Future<void> _reflowCurrentSection(int revision) async {
    if (_blocks.isEmpty) {
      if (mounted && revision == _layoutReflowRevision) {
        setState(() => _layoutReflowPending = false);
      }
      return;
    }
    if (_activeLayoutReflowRevision == revision) return;
    _activeLayoutReflowRevision = revision;
    final previousOffset = _currentPageOffset;
    final settings = ref.read(readerSettingsProvider);
    final viewport = MediaQuery.sizeOf(context);
    try {
      final pages = await _paginateBlocksCooperatively(
        _blocks,
        settings,
        viewportWidth: viewport.width,
        viewportHeight: _paginationViewportHeight(viewport.height),
        engineChars: _engineChars,
      );
      if (!mounted || revision != _layoutReflowRevision) return;
      final page = _pageForOffset(pages, previousOffset);
      setState(() {
        _pages = pages;
        _pageIndex = page;
        _layoutReflowPending = false;
        _layoutReflowError = null;
      });
      if (_activeLayoutReflowRevision == revision) {
        _activeLayoutReflowRevision = null;
      }
      _programmaticPageChange = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _layoutReflowRevision) {
          if (_pageController.hasClients) _pageController.jumpToPage(page);
        }
        _programmaticPageChange = false;
      });
    } catch (error) {
      if (!mounted || revision != _layoutReflowRevision) return;
      if (_activeLayoutReflowRevision == revision) {
        _activeLayoutReflowRevision = null;
      }
      setState(() {
        _layoutReflowPending = false;
        _layoutReflowError = error;
      });
    }
  }

  @override
  void dispose() {
    final s = _session;
    _session = null;
    if (s != null) {
      // Fire-and-forget: dispose() cannot await, and the session close is
      // best-effort (the service also sweeps on its own dispose).
      unawaited(_closeSessionAfterSavingProgress(s));
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _setReaderBrightness(null);
    _controlsTimer?.cancel();
    _progressSaveTimer?.cancel();
    _layoutReflowTimer?.cancel();
    _pageController.dispose();
    _scrollController.dispose();
    _continuousPageNotifier.dispose();
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
      _currentTotalProgression = _validTotalProgression(saved?.progression);
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
        _isPdf = info.format.toLowerCase() == 'pdf';
        _isCbz = info.format.toLowerCase() == 'cbz';
      });
      await _loadBook(
        start,
        offset: startOffset,
        progression: startProgression,
        verifyCfi: widget.initialCfi,
        persistProgress: !keepSavedLocator,
      );
      try {
        final bookmarks = await ref
            .read(annotationsRepoProvider)
            .allBookmarks(widget.bookId);
        if (!mounted) return;
        setState(() {
          _bookmarkState.restore(bookmarks);
        });
      } catch (_) {
        // Bookmark state is optional UI metadata; opening the book stays usable.
      }
      try {
        final quotes = await ref
            .read(annotationsRepoProvider)
            .allQuotes(widget.bookId);
        if (!mounted) return;
        setState(() {
          _quotes = quotes;
          _quoteHighlightsBySection.clear();
        });
      } catch (_) {
        // Quote styling is optional UI metadata; saved records remain intact.
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

  /// Builds a continuous stream from the opening section and lightweight
  /// placeholders; later sections are prepared when the reader reaches them.
  Future<void> _loadBook(
    int startSection, {
    required int offset,
    double? progression,
    String? verifyCfi,
    required bool persistProgress,
    int? layoutRevision,
    Map<int, _ReaderSection> reusableSections = const {},
  }) async {
    final session = _session;
    if (session == null) return;
    if (layoutRevision != null) {
      if (_activeLayoutReflowRevision == layoutRevision) return;
      _activeLayoutReflowRevision = layoutRevision;
    }
    var pageCountJobRevision = _continuousPageCountJobRevision;
    if (layoutRevision == null) setState(() => _loading = true);
    try {
      // Give the Reader-specific loading view a frame before pagination work.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (_isObsoleteLayout(layoutRevision)) return;
      final pages = <_ContinuousPage>[];
      var preparedSectionIndex = startSection;
      ReaderPageCountIndex? pageCountIndex;
      ReaderPageCountAccumulator? progressiveCounts;
      if (_isPdf) {
        // Resolve the opening page before building the stream so its extracted
        // reader pages can occupy separate, fixed-height scroll entries.
        await _loadPdfSection(startSection);
        if (_isObsoleteLayout(layoutRevision)) return;
        for (var index = 0; index < _sectionCount; index++) {
          final loaded = _pdfSectionCache[index];
          pages.addAll(
            loaded == null
                ? _pdfPagePlaceholders(index, const [])
                : _pdfPagePlaceholders(index, loaded.pages),
          );
        }
      } else {
        pageCountJobRevision = ++_continuousPageCountJobRevision;
        final paginationSettings = ref.read(readerSettingsProvider);
        final paginationViewport = MediaQuery.sizeOf(context);
        if (!_isCbz) {
          progressiveCounts = ReaderPageCountAccumulator(_sectionCount);
        }

        Future<_ReaderSection> prepareSection(int index) {
          final cached = reusableSections[index];
          return cached == null
              ? _readContinuousSection(
                  index,
                  paginationSettings: paginationSettings,
                  paginationViewport: paginationViewport,
                  isCurrent: () => !_isObsoleteLayout(layoutRevision),
                )
              : _reflowLoadedContinuousSection(
                  cached,
                  paginationSettings,
                  paginationViewport,
                  isCurrent: () => !_isObsoleteLayout(layoutRevision),
                );
        }

        void recordCount(_ReaderSection section) {
          progressiveCounts?.record(
            section.index,
            _isEmptyContinuousSection(section) ? 0 : section.pages.length,
          );
        }

        var openingSection = await prepareSection(startSection);
        if (_isObsoleteLayout(layoutRevision)) return;
        recordCount(openingSection);
        if (_isEmptyContinuousSection(openingSection)) {
          for (var index = startSection + 1; index < _sectionCount; index++) {
            final candidate = await prepareSection(index);
            if (_isObsoleteLayout(layoutRevision)) return;
            recordCount(candidate);
            if (!_isEmptyContinuousSection(candidate)) {
              openingSection = candidate;
              break;
            }
          }
        }
        if (_isEmptyContinuousSection(openingSection)) {
          for (var index = startSection - 1; index >= 0; index--) {
            final candidate = await prepareSection(index);
            if (_isObsoleteLayout(layoutRevision)) return;
            recordCount(candidate);
            if (!_isEmptyContinuousSection(candidate)) {
              openingSection = candidate;
              break;
            }
          }
        }
        if (_isEmptyContinuousSection(openingSection)) {
          throw StateError('empty-book');
        }
        preparedSectionIndex = openingSection.index;

        if (progressiveCounts != null) {
          // Reuse only exact counts for the same content identity and layout.
          // Missing sections are counted after the opening page is visible.
          for (var index = 0; index < _sectionCount; index++) {
            if (progressiveCounts.countFor(index) != null) continue;
            final cachedCount = readerPageCountCache.get(
              _continuousPageCountCacheKey(
                index,
                paginationSettings,
                paginationViewport,
              ),
            );
            if (cachedCount != null) {
              progressiveCounts.record(index, cachedCount);
            }
          }
          pageCountIndex = progressiveCounts.exactIndex;
        }

        for (var index = 0; index < _sectionCount; index++) {
          pages.addAll(
            index == openingSection.index
                ? _continuousEntriesForSection(openingSection)
                : [_continuousSectionPlaceholder(index)],
          );
        }
      }

      if (pages.isEmpty) throw StateError('empty-book');
      var firstForSection = pages.indexWhere(
        (page) => _isPdf
            ? page.section.index >= startSection
            : page.section.index == preparedSectionIndex,
      );
      if (firstForSection < 0) firstForSection = pages.length - 1;
      final firstEntry = pages[firstForSection];
      final section = _isPdf
          ? (_pdfSectionCache[firstEntry.section.index] ?? firstEntry.section)
          : firstEntry.section;
      final usesRestoredPosition = section.index == startSection;
      final effectiveOffset = usesRestoredPosition ? offset : 0;
      final effectiveProgression = usesRestoredPosition ? progression : null;
      final pageInSection = effectiveProgression == null
          ? _pageForOffset(section.pages, effectiveOffset)
          : _pageForProgress(section.pages, effectiveProgression);
      final target =
          (firstForSection + pageInSection.clamp(0, section.pages.length - 1))
              .clamp(0, pages.length - 1)
              .toInt();
      final active = pages[target];
      final activeSection = _isPdf
          ? (_pdfSectionCache[active.section.index] ?? active.section)
          : active.section;
      final activePage = _isPdf
          ? activeSection.pages[active.sectionPageIndex
                .clamp(0, activeSection.pages.length - 1)
                .toInt()]
          : active.page;

      if (!mounted || _isObsoleteLayout(layoutRevision)) return;
      setState(() {
        _continuousPages = pages;
        _continuousPageCountIndex = pageCountIndex;
        _continuousIndex = target;
        _section = activeSection.index;
        _blocks = activeSection.blocks;
        _pages = activeSection.pages;
        _pageIndex = activeSection.pages.indexOf(activePage);
        _enginePlain = activeSection.enginePlain;
        _engineChars = activeSection.engineChars;
        _highlights = activeSection.highlights;
        _pending = null;
        _loading = false;
        if (layoutRevision != null) {
          _layoutReflowPending = false;
          _layoutReflowError = null;
        }
      });
      if (layoutRevision != null &&
          _activeLayoutReflowRevision == layoutRevision) {
        _activeLayoutReflowRevision = null;
      }
      _continuousPageNotifier.value = target;
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

      final countsToFinish = progressiveCounts;
      if (countsToFinish != null && pageCountIndex == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(
            _completeContinuousPageCounts(
              session: session,
              startSection: active.section.index,
              settings: ref.read(readerSettingsProvider),
              viewport: MediaQuery.sizeOf(context),
              counts: countsToFinish,
              jobRevision: pageCountJobRevision,
              layoutRevision: layoutRevision,
            ),
          );
        });
      }

      if (persistProgress) {
        final progressRevision = ++_progressRequestRevision;
        unawaited(
          _saveProgress(
            session,
            active.section.index,
            effectiveOffset,
            revision: progressRevision,
          ),
        );
      }
      if (_isPdf) _requestPdfWindow(active.section.index);
      if (verifyCfi != null && verifyCfi.isNotEmpty) {
        unawaited(_verifyCfi(session, startSection, offset, verifyCfi));
      }
      if (_pendingViewportReflow) {
        _pendingViewportReflow = false;
        _scheduleViewportReflow();
      }
    } catch (e) {
      if (e is _ReaderLayoutSuperseded || _isObsoleteLayout(layoutRevision)) {
        return;
      }
      if (mounted) {
        if (layoutRevision != null &&
            _activeLayoutReflowRevision == layoutRevision) {
          _activeLayoutReflowRevision = null;
        }
        setState(() {
          _error = '$e';
          _loading = false;
          if (layoutRevision != null) {
            _layoutReflowPending = false;
            _layoutReflowError = e;
          }
        });
      }
      _pendingViewportReflow = false;
    }
  }

  Future<void> _completeContinuousPageCounts({
    required ReaderSession session,
    required int startSection,
    required ReaderSettingsData settings,
    required Size viewport,
    required ReaderPageCountAccumulator counts,
    required int jobRevision,
    required int? layoutRevision,
  }) async {
    bool isCurrent() =>
        mounted &&
        identical(session, _session) &&
        jobRevision == _continuousPageCountJobRevision &&
        !_isObsoleteLayout(layoutRevision);

    try {
      for (final index in _pageCountSectionOrder(startSection)) {
        if (!isCurrent()) return;
        if (counts.countFor(index) != null) continue;

        final cacheKey = _continuousPageCountCacheKey(
          index,
          settings,
          viewport,
        );
        final cachedCount = readerPageCountCache.get(cacheKey);
        if (cachedCount != null) {
          counts.record(index, cachedCount);
          continue;
        }

        // Let the target page paint before starting exact count work for the
        // next unopened section. Page bodies remain lazy and are discarded.
        await WidgetsBinding.instance.endOfFrame;
        if (!isCurrent()) return;
        final loadedSection = _loadedContinuousSection(index);
        final count = loadedSection == null
            ? await _countContinuousSectionPages(
                index,
                settings: settings,
                viewport: viewport,
                isCurrent: isCurrent,
              )
            : await _countLoadedContinuousSectionPages(
                loadedSection,
                settings: settings,
                viewport: viewport,
                isCurrent: isCurrent,
              );
        if (count == null || !isCurrent()) return;
        counts.record(index, count);
      }

      final exactIndex = counts.exactIndex;
      if (exactIndex == null || !isCurrent()) return;
      setState(() => _continuousPageCountIndex = exactIndex);
    } catch (error) {
      if (isCurrent()) {
        debugPrint('Reader exact page count was not completed: $error');
      }
    }
  }

  Iterable<int> _pageCountSectionOrder(int startSection) sync* {
    yield startSection;
    for (var distance = 1; distance < _sectionCount; distance++) {
      final next = startSection + distance;
      if (next < _sectionCount) yield next;
      final previous = startSection - distance;
      if (previous >= 0) yield previous;
    }
  }

  _ReaderSection? _loadedContinuousSection(int index) {
    for (final page in _continuousPages) {
      if (page.section.index == index && !page.section.isPlaceholder) {
        return page.section;
      }
    }
    return null;
  }

  bool _isObsoleteLayout(int? revision) =>
      revision != null && revision != _layoutReflowRevision;

  Future<_ReaderSection> _readContinuousSection(
    int index, {
    ReaderSettingsData? paginationSettings,
    Size? paginationViewport,
    bool Function()? isCurrent,
  }) async {
    final session = _session;
    if (session == null) throw StateError('reader-closed');
    if (isCurrent != null && !isCurrent()) {
      throw const _ReaderLayoutSuperseded();
    }
    final settings = paginationSettings ?? ref.read(readerSettingsProvider);
    final viewport = paginationViewport ?? MediaQuery.sizeOf(context);
    final content = await _readerSvc.getContent(session, index);
    if (!mounted) throw StateError('reader-closed');
    if (isCurrent != null && !isCurrent()) {
      throw const _ReaderLayoutSuperseded();
    }
    final blocks = _parseReaderBlocks(content);
    final storedHighlights = await ref
        .read(annotationsRepoProvider)
        .highlightsForSection(widget.bookId, index);
    final highlights = await _resolveHighlightCoordinates(
      index,
      content.plainText,
      blocks,
      storedHighlights,
    );
    if (isCurrent != null && !isCurrent()) {
      throw const _ReaderLayoutSuperseded();
    }
    final sectionPages = await _paginateBlocksCooperatively(
      blocks,
      settings!,
      viewportWidth: viewport.width,
      viewportHeight: _paginationViewportHeight(viewport.height),
      engineChars: content.charCount.toInt(),
      isCurrent: isCurrent,
    );
    if (isCurrent != null && !isCurrent()) {
      throw const _ReaderLayoutSuperseded();
    }
    final pageCount =
        sectionPages.length == 1 && sectionPages.first.blocks.isEmpty
        ? 0
        : sectionPages.length;
    readerPageCountCache.put(
      _continuousPageCountCacheKey(index, settings, viewport),
      pageCount,
    );
    return _ReaderSection(
      index: index,
      blocks: blocks,
      pages: sectionPages,
      enginePlain: content.plainText,
      engineChars: content.charCount.toInt(),
      highlights: highlights,
    );
  }

  Future<_ReaderSection> _reflowLoadedContinuousSection(
    _ReaderSection section,
    ReaderSettingsData settings,
    Size viewport, {
    bool Function()? isCurrent,
  }) async {
    final pages = await _paginateBlocksCooperatively(
      section.blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: _paginationViewportHeight(viewport.height),
      engineChars: section.engineChars,
      isCurrent: isCurrent,
    );
    if (isCurrent != null && !isCurrent()) {
      throw const _ReaderLayoutSuperseded();
    }
    readerPageCountCache.put(
      _continuousPageCountCacheKey(section.index, settings, viewport),
      pages.length == 1 && pages.first.blocks.isEmpty ? 0 : pages.length,
    );
    return _ReaderSection(
      index: section.index,
      blocks: section.blocks,
      pages: pages,
      enginePlain: section.enginePlain,
      engineChars: section.engineChars,
      highlights: section.highlights,
    );
  }

  Future<int?> _countContinuousSectionPages(
    int index, {
    required ReaderSettingsData settings,
    required Size viewport,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return null;
    final cacheKey = _continuousPageCountCacheKey(index, settings, viewport);
    final cachedCount = readerPageCountCache.get(cacheKey);
    if (cachedCount != null) return cachedCount;

    final session = _session;
    if (session == null) throw StateError('reader-closed');
    final content = await _readerSvc.getContentForPageCount(session, index);
    if (!mounted) throw StateError('reader-closed');
    if (isCurrent != null && !isCurrent()) return null;
    final blocks = ReaderPagination.parseSectionContent(
      content,
      countOnlyImages: true,
    );
    if (blocks.isEmpty) {
      readerPageCountCache.put(cacheKey, 0);
      return 0;
    }
    final count = await ReaderPagination.countPagesCooperativelyUntil(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: _paginationViewportHeight(viewport.height),
      engineChars: content.charCount.toInt(),
      yieldFrame: () => WidgetsBinding.instance.endOfFrame,
      isCurrent: isCurrent ?? () => mounted,
    );
    if (count == null || (isCurrent != null && !isCurrent())) return null;
    readerPageCountCache.put(cacheKey, count);
    return count;
  }

  Future<int?> _countLoadedContinuousSectionPages(
    _ReaderSection section, {
    required ReaderSettingsData settings,
    required Size viewport,
    bool Function()? isCurrent,
  }) async {
    if (isCurrent != null && !isCurrent()) return null;
    final cacheKey = _continuousPageCountCacheKey(
      section.index,
      settings,
      viewport,
    );
    final cachedCount = readerPageCountCache.get(cacheKey);
    if (cachedCount != null) return cachedCount;
    if (section.blocks.isEmpty) {
      readerPageCountCache.put(cacheKey, 0);
      return 0;
    }
    final count = await ReaderPagination.countPagesCooperativelyUntil(
      section.blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: _paginationViewportHeight(viewport.height),
      engineChars: section.engineChars,
      yieldFrame: () => WidgetsBinding.instance.endOfFrame,
      isCurrent: isCurrent ?? () => mounted,
    );
    if (count == null || (isCurrent != null && !isCurrent())) return null;
    readerPageCountCache.put(cacheKey, count);
    return count;
  }

  String _continuousPageCountCacheKey(
    int sectionIndex,
    ReaderSettingsData settings,
    Size viewport,
  ) => ReaderPageCountCache.layoutKeyFor(
    bookId: widget.bookId,
    sectionIndex: sectionIndex,
    settings: settings,
    viewportWidth: viewport.width,
    viewportHeight: _paginationViewportHeight(viewport.height),
  );

  bool _isEmptyContinuousSection(_ReaderSection section) =>
      section.pages.length == 1 && section.pages.first.blocks.isEmpty;

  List<ReaderBlock> _parseReaderBlocks(reader_dto.SectionContent content) {
    return ReaderTextSelectionOffsets.alignBlocks(
      ReaderPagination.parseSectionContent(
        content,
        preserveEmptyTextBlocks: true,
      ),
      content.plainText,
      sourceHtml: content.html,
    );
  }

  Future<List<HighlightRecord>> _resolveHighlightCoordinates(
    int sectionIndex,
    String sourceText,
    List<ReaderBlock> blocks,
    List<HighlightRecord> storedHighlights,
  ) async {
    final annotations = ref.read(annotationsRepoProvider);
    final resolved = <HighlightRecord>[];
    for (final highlight in storedHighlights) {
      final range = ReaderTextSelectionOffsets.resolveStoredHighlightRange(
        sourceText,
        blocks,
        start: highlight.startOffset,
        end: highlight.endOffset,
        quotedText: highlight.quotedText,
        offsetUnit: highlight.offsetUnit,
      );
      if (range == null) {
        // Keep the persisted row intact, but do not paint an uncertain range.
        debugPrint(
          'Reader highlight ${highlight.id} could not be aligned in '
          'section $sectionIndex; stored coordinates were preserved.',
        );
        continue;
      }
      if (highlight.offsetUnit != 'rust_scalar' && highlight.id != null) {
        await annotations.updateHighlightOffsetsAsRustScalars(
          highlight.id!,
          range.$1,
          range.$2,
        );
      }
      resolved.add(
        HighlightRecord(
          id: highlight.id,
          bookId: highlight.bookId,
          sectionIndex: highlight.sectionIndex,
          startOffset: range.$1,
          endOffset: range.$2,
          cfi: highlight.cfi,
          color: highlight.color,
          quotedText: highlight.quotedText,
          note: highlight.note,
          offsetUnit: 'rust_scalar',
        ),
      );
    }
    return resolved;
  }

  List<ReaderBlock>? _blocksForSection(int index) {
    if (_isPdf) return _pdfSectionCache[index]?.blocks;
    if (_continuousPages.isEmpty) {
      return index == _section ? _blocks : null;
    }
    for (final page in _continuousPages) {
      if (page.section.index == index && !page.section.isPlaceholder) {
        return page.section.blocks;
      }
    }
    return null;
  }

  String _renderedTextForSectionRange(int index, int start, int end) {
    final blocks = _blocksForSection(index);
    if (blocks == null) return '';
    return ReaderTextSelectionOffsets.renderedTextForRange(blocks, start, end);
  }

  List<_ContinuousPage> _continuousEntriesForSection(_ReaderSection section) =>
      [
        for (var index = 0; index < section.pages.length; index++)
          _ContinuousPage(
            section: section,
            page: section.pages[index],
            sectionPageIndex: index,
          ),
      ];

  _ContinuousPage _continuousSectionPlaceholder(int index) {
    final section = _ReaderSection(
      index: index,
      blocks: const [],
      pages: const [_ReaderPage(blocks: [], startOffset: 0)],
      enginePlain: '',
      engineChars: 0,
      highlights: const [],
      isPlaceholder: true,
    );
    return _ContinuousPage(
      section: section,
      page: section.pages.first,
      sectionPageIndex: 0,
    );
  }

  void _requestContinuousSection(int index, {bool retry = false}) {
    if (_isPdf || index < 0 || index >= _sectionCount || !mounted) return;
    final hasPlaceholder = _continuousPages.any(
      (page) => page.section.index == index && page.section.isPlaceholder,
    );
    if (!hasPlaceholder) return;
    if (!_loadingContinuousSections.contains(index) || retry) {
      setState(() {
        _loadingContinuousSections.add(index);
        _continuousSectionErrors.remove(index);
      });
    }
    _continuousSectionRequestedIndex = index;
    if (_continuousSectionLoadWorker != null) return;
    _continuousSectionLoadWorker = _drainContinuousSectionRequests()
        .whenComplete(() {
          _continuousSectionLoadWorker = null;
          final pending = _continuousSectionRequestedIndex;
          if (mounted && pending != null) {
            _requestContinuousSection(pending);
          }
        });
  }

  Future<void> _drainContinuousSectionRequests() async {
    while (mounted && _continuousSectionRequestedIndex != null) {
      final index = _continuousSectionRequestedIndex!;
      _continuousSectionRequestedIndex = null;
      try {
        await _loadContinuousSection(index);
      } catch (error) {
        if (mounted) {
          setState(() {
            _loadingContinuousSections.remove(index);
            _continuousSectionErrors[index] = error;
          });
        }
      }
    }
  }

  Future<void> _loadContinuousSection(int index) async {
    final firstIndex = _continuousPages.indexWhere(
      (page) => page.section.index == index && page.section.isPlaceholder,
    );
    if (firstIndex < 0) {
      _loadingContinuousSections.remove(index);
      return;
    }
    final section = await _readContinuousSection(index);
    if (!mounted) return;
    assert(
      _continuousPageCountIndex == null ||
          _continuousPageCountIndex!.sectionPageCounts[index] ==
              (_isEmptyContinuousSection(section) ? 0 : section.pages.length),
      'Lazy section pagination changed after the book page count was fixed.',
    );
    var endIndex = firstIndex;
    while (endIndex < _continuousPages.length &&
        _continuousPages[endIndex].section.index == index) {
      endIndex++;
    }
    final active =
        _continuousIndex >= 0 && _continuousIndex < _continuousPages.length
        ? _continuousPages[_continuousIndex]
        : null;
    final replacement = _continuousEntriesForSection(section);
    final delta = replacement.length - (endIndex - firstIndex);
    var currentIndex = _continuousIndex;
    if (active?.section.index == index) {
      currentIndex =
          firstIndex +
          active!.sectionPageIndex.clamp(0, replacement.length - 1);
    } else if (currentIndex >= endIndex) {
      currentIndex += delta;
    }
    final pages = [
      ..._continuousPages.take(firstIndex),
      ...replacement,
      ..._continuousPages.skip(endIndex),
    ];
    final current = currentIndex >= 0 && currentIndex < pages.length
        ? pages[currentIndex]
        : null;
    final shouldReposition = currentIndex != _continuousIndex;
    if (shouldReposition) _programmaticPageChange = true;
    setState(() {
      _continuousPages = pages;
      _continuousIndex = currentIndex;
      _loadingContinuousSections.remove(index);
      _continuousSectionErrors.remove(index);
      if (current != null && !current.section.isPlaceholder) {
        final currentSection = current.section;
        _section = currentSection.index;
        _blocks = currentSection.blocks;
        _pages = currentSection.pages;
        _pageIndex = currentSection.pages
            .indexOf(current.page)
            .clamp(0, currentSection.pages.length - 1)
            .toInt();
        _enginePlain = currentSection.enginePlain;
        _engineChars = currentSection.engineChars;
        _highlights = currentSection.highlights;
      }
    });
    _continuousPageNotifier.value = currentIndex;
    if (shouldReposition) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(
          (currentIndex * _readerPageExtent)
              .clamp(0.0, _scrollController.position.maxScrollExtent)
              .toDouble(),
        );
        _programmaticPageChange = false;
      });
    }
    if (active?.section.index == index && current != null) {
      final session = _session;
      if (session != null) {
        _queueProgressSave(session, index, current.page.startOffset);
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
      final blocks = _parseReaderBlocks(content);
      final storedHighlights = await ref
          .read(annotationsRepoProvider)
          .highlightsForSection(widget.bookId, index);
      final highlights = await _resolveHighlightCoordinates(
        index,
        content.plainText,
        blocks,
        storedHighlights,
      );
      if (!mounted) return;
      final settings = ref.read(readerSettingsProvider);
      final viewport = MediaQuery.sizeOf(context);
      final pages = await _paginateBlocksCooperatively(
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

  _ReaderSection _emptyPdfSection(int index) => _ReaderSection(
    index: index,
    blocks: const [],
    pages: const [_ReaderPage(blocks: [], startOffset: 0)],
    enginePlain: '',
    engineChars: 0,
    highlights: const [],
  );

  List<_ContinuousPage> _pdfPagePlaceholders(
    int sectionIndex,
    List<_ReaderPage> extractedPages,
  ) {
    final emptySection = _emptyPdfSection(sectionIndex);
    final pageCount = math.max(1, extractedPages.length);
    return [
      for (var pageIndex = 0; pageIndex < pageCount; pageIndex++)
        _ContinuousPage(
          section: emptySection,
          page: _ReaderPage(
            blocks: const [],
            startOffset: extractedPages.isEmpty
                ? 0
                : extractedPages[pageIndex].startOffset,
          ),
          sectionPageIndex: pageIndex,
        ),
    ];
  }

  Future<_ReaderSection> _readPdfSection(int index) async {
    final session = _session;
    if (session == null) throw StateError('reader-closed');
    final viewport = MediaQuery.sizeOf(context);
    final settings = ref.read(readerSettingsProvider);
    final content = await _readerSvc.getContent(session, index);
    final blocks = _parseReaderBlocks(content);
    final storedHighlights = await ref
        .read(annotationsRepoProvider)
        .highlightsForSection(widget.bookId, index);
    final highlights = await _resolveHighlightCoordinates(
      index,
      content.plainText,
      blocks,
      storedHighlights,
    );
    final pages = _paginateBlocks(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: _paginationViewportHeight(viewport.height),
      engineChars: content.charCount.toInt(),
    );
    final section = _ReaderSection(
      index: index,
      blocks: blocks,
      pages: pages,
      enginePlain: content.plainText,
      engineChars: content.charCount.toInt(),
      highlights: highlights,
    );
    return section;
  }

  Future<void> _loadPdfSection(int index) async {
    final cached = _pdfSectionCache.remove(index);
    if (cached != null) {
      _pdfSectionCache[index] = cached;
      return;
    }
    if (_pdfSectionErrors.remove(index) != null && mounted) {
      setState(() {});
    }
    try {
      final section = await _readPdfSection(index);
      if (!mounted) return;
      _pdfSectionCache[index] = section;
      _pdfSectionErrors.remove(index);
      while (_pdfSectionCache.length > 3) {
        final oldest = _pdfSectionCache.keys.firstWhere(
          (key) =>
              key !=
              (_continuousIndex >= 0 &&
                      _continuousIndex < _continuousPages.length
                  ? _continuousPages[_continuousIndex].section.index
                  : -1),
          orElse: () => _pdfSectionCache.keys.first,
        );
        _pdfSectionCache.remove(oldest);
      }

      final firstContinuousIndex = _continuousPages.indexWhere(
        (page) => page.section.index == index,
      );
      var updatedPages = _continuousPages;
      var updatedCurrentIndex = _continuousIndex;
      var shouldReposition = false;
      if (firstContinuousIndex >= 0) {
        var endContinuousIndex = firstContinuousIndex;
        while (endContinuousIndex < _continuousPages.length &&
            _continuousPages[endContinuousIndex].section.index == index) {
          endContinuousIndex++;
        }
        final oldCount = endContinuousIndex - firstContinuousIndex;
        final replacement = _pdfPagePlaceholders(index, section.pages);
        final delta = replacement.length - oldCount;
        final active =
            _continuousIndex >= 0 && _continuousIndex < _continuousPages.length
            ? _continuousPages[_continuousIndex]
            : null;
        if (active?.section.index == index) {
          updatedCurrentIndex =
              firstContinuousIndex +
              active!.sectionPageIndex.clamp(0, replacement.length - 1);
        } else if (_continuousIndex >= endContinuousIndex) {
          updatedCurrentIndex += delta;
        }
        shouldReposition = updatedCurrentIndex != _continuousIndex;
        updatedPages = [
          ..._continuousPages.take(firstContinuousIndex),
          ...replacement,
          ..._continuousPages.skip(endContinuousIndex),
        ];
      }

      final current =
          updatedCurrentIndex >= 0 && updatedCurrentIndex < updatedPages.length
          ? updatedPages[updatedCurrentIndex]
          : null;
      final activeSection = current == null
          ? null
          : (_pdfSectionCache[current.section.index] ?? current.section);
      final activePageIndex = activeSection == null
          ? 0
          : current!.sectionPageIndex
                .clamp(0, activeSection.pages.length - 1)
                .toInt();
      if (shouldReposition) _programmaticPageChange = true;
      setState(() {
        _continuousPages = updatedPages;
        _continuousIndex = updatedCurrentIndex;
        if (current != null && activeSection != null) {
          _section = activeSection.index;
          _blocks = activeSection.blocks;
          _pages = activeSection.pages;
          _pageIndex = activePageIndex;
          _enginePlain = activeSection.enginePlain;
          _engineChars = activeSection.engineChars;
          _highlights = activeSection.highlights;
        }
      });
      _continuousPageNotifier.value = updatedCurrentIndex;
      if (shouldReposition) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          _scrollController.jumpTo(
            (updatedCurrentIndex * _readerPageExtent)
                .clamp(0.0, _scrollController.position.maxScrollExtent)
                .toDouble(),
          );
          _programmaticPageChange = false;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _pdfSectionErrors[index] = error);
      rethrow;
    }
  }

  void _requestPdfWindow(int index) {
    _pdfRequestedIndex = index.clamp(0, _sectionCount - 1);
    if (_pdfLoadWorker != null) return;
    _pdfLoadWorker = _drainPdfRequests().whenComplete(() {
      _pdfLoadWorker = null;
      if (mounted && _pdfRequestedIndex != null) {
        _requestPdfWindow(_pdfRequestedIndex!);
      }
    });
  }

  Future<void> _drainPdfRequests() async {
    while (mounted && _pdfRequestedIndex != null) {
      final target = _pdfRequestedIndex!;
      _pdfRequestedIndex = null;
      for (final index in [
        target,
        target + _pdfPrefetchDirection,
        target - _pdfPrefetchDirection,
      ]) {
        if (index < 0 || index >= _sectionCount) continue;
        if (_pdfSectionCache.containsKey(index)) continue;
        try {
          await _loadPdfSection(index);
        } catch (_) {
          // A failed or stale prefetch must not interrupt reading.
        }
        if (_pdfRequestedIndex != null) break;
      }
    }
  }

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
    if (!_isPdf && active.section.isPlaceholder) {
      _continuousIndex = index;
      _continuousPageNotifier.value = index;
      if (_pending != null) setState(() => _pending = null);
      _requestContinuousSection(active.section.index);
      return;
    }
    if (_isPdf) {
      _pdfPrefetchDirection = index > _continuousIndex ? 1 : -1;
      _requestPdfWindow(active.section.index);
    }
    final resolvedSection = _isPdf
        ? (_pdfSectionCache[active.section.index] ?? active.section)
        : active.section;
    final sectionChanged = _section != resolvedSection.index;
    final clearSelection = _pending != null;
    _continuousIndex = index;
    _pageIndex = _isPdf
        ? active.sectionPageIndex
              .clamp(0, resolvedSection.pages.length - 1)
              .toInt()
        : resolvedSection.pages.indexOf(active.page);
    if (_pageIndex < 0) _pageIndex = 0;
    if (sectionChanged || clearSelection) {
      setState(() {
        _section = resolvedSection.index;
        _blocks = resolvedSection.blocks;
        _pages = resolvedSection.pages;
        _enginePlain = resolvedSection.enginePlain;
        _engineChars = resolvedSection.engineChars;
        _highlights = resolvedSection.highlights;
        _pending = null;
      });
    }
    _continuousPageNotifier.value = index;
    if (_programmaticPageChange) return;
    final session = _session;
    if (session != null) {
      _queueProgressSave(
        session,
        active.section.index,
        _isPdf ? 0 : active.page.startOffset,
      );
    }
  }

  void _snapEpubPageAfterScroll(ScrollMetrics metrics) {
    if (_isPdf || _isCbz || !_scrollController.hasClients) return;
    final target = readerPageSnapTarget(
      pixels: metrics.pixels,
      pageExtent: _readerPageExtent,
      minScrollExtent: metrics.minScrollExtent,
      maxScrollExtent: metrics.maxScrollExtent,
    );
    if (target == null || (target - metrics.pixels).abs() < 1) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (position.isScrollingNotifier.value) return;
      final currentTarget = readerPageSnapTarget(
        pixels: position.pixels,
        pageExtent: _readerPageExtent,
        minScrollExtent: position.minScrollExtent,
        maxScrollExtent: position.maxScrollExtent,
      );
      if (currentTarget == null ||
          (currentTarget - position.pixels).abs() < 1) {
        return;
      }
      unawaited(
        _scrollController.animateTo(
          currentTarget,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _queueProgressSave(ReaderSession session, int section, int offset) {
    final revision = ++_progressRequestRevision;
    _currentTotalProgression = null;
    _pendingProgressSave = _PendingProgressSave(
      session,
      section,
      offset,
      revision,
    );
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _drainProgressSave();
    });
  }

  void _drainProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = null;
    final pending = _pendingProgressSave;
    _pendingProgressSave = null;
    if (pending == null) return;
    _progressSaveTail = _progressSaveTail.then(
      (_) => _saveProgress(
        pending.session,
        pending.section,
        pending.offset,
        revision: pending.revision,
      ),
    );
  }

  Future<void> _closeSessionAfterSavingProgress(ReaderSession session) async {
    _progressSaveTimer?.cancel();
    final pending = _pendingProgressSave;
    _pendingProgressSave = null;
    await _progressSaveTail;
    if (pending != null) {
      await _saveProgress(
        pending.session,
        pending.section,
        pending.offset,
        revision: pending.revision,
      );
    }
    await _readerSvc.closeSession(session);
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
      final blocks = _parseReaderBlocks(content);
      if (blocks.any(
        (block) => block is ImageBlock || block.plainText.trim().isNotEmpty,
      )) {
        return index;
      }
    }
    return null;
  }

  Future<void> _saveProgress(
    ReaderSession session,
    int section,
    int offset, {
    int? revision,
  }) async {
    final requestRevision = revision ?? ++_progressRequestRevision;
    try {
      final p = await _readerSvc.getProgress(session, section, offset);
      await _progressRepo.saveProgress(
        bookId: widget.bookId,
        locatorJson: p.locatorJson,
        sectionIndex: section,
        charOffset: offset,
        progression: p.totalProgression,
      );
      if (mounted && requestRevision == _progressRequestRevision) {
        final current = _validTotalProgression(p.totalProgression);
        if (_currentTotalProgression != current) {
          setState(() => _currentTotalProgression = current);
        }
      }
    } catch (_) {
      // Progress is best-effort per navigation; the book stays readable.
    }
  }

  static double? _validTotalProgression(double? progression) =>
      progression != null &&
          progression.isFinite &&
          progression >= 0 &&
          progression <= 1
      ? progression
      : null;

  List<_ReaderPage> _paginateBlocks(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
  }) => ReaderPagination.paginate(
    blocks,
    settings,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    engineChars: engineChars,
  );

  Future<List<_ReaderPage>> _paginateBlocksCooperatively(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
    bool Function()? isCurrent,
  }) async {
    Future<void> yieldFrame() => WidgetsBinding.instance.endOfFrame;
    if (isCurrent == null) {
      return ReaderPagination.paginateCooperatively(
        blocks,
        settings,
        viewportWidth: viewportWidth,
        viewportHeight: viewportHeight,
        engineChars: engineChars,
        yieldFrame: yieldFrame,
      );
    }
    final pages = await ReaderPagination.paginateCooperativelyUntil(
      blocks,
      settings,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      engineChars: engineChars,
      yieldFrame: yieldFrame,
      isCurrent: isCurrent,
    );
    if (pages == null) throw const _ReaderLayoutSuperseded();
    return pages;
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
      ReaderPagination.paginationViewportHeight(height);

  static String _extOf(String name) {
    final i = name.lastIndexOf('.');
    if (i < 0) return 'epub';
    return name.substring(i + 1).toLowerCase();
  }

  // ---- selection, highlights and quotes ----

  void _onSelectionChanged(SelectedContent? content) {
    if ((content?.plainText ?? '').trim().isEmpty) {
      _selectedBlockRanges.clear();
      _selectedBlockRects.clear();
      if (mounted) {
        setState(() {
          _pending = null;
          _selectionAnchor = null;
        });
      }
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_selectionChanging) _refreshPendingSelection();
    });
  }

  void _onSelectionStatusChanged(SelectableRegionSelectionStatus status) {
    if (status == SelectableRegionSelectionStatus.changing) {
      _keepSelectionAfterHighlightUpdate = false;
    }
    _selectionChanging = status == SelectableRegionSelectionStatus.changing;
    if (_selectionChanging) {
      if (_pending != null && mounted) setState(() => _pending = null);
    } else {
      _refreshPendingSelection();
    }
  }

  void _onBlockSelectionChanged(
    Object blockKey,
    int sectionIndex,
    TextBlock block,
    SelectedContentRange? range,
    List<Rect> selectionRects,
  ) {
    // Repainting TextSpan boundaries after a highlight can make Flutter emit
    // a transient local range for the same live selection. Keep the source
    // range that the user acted on until their next selection gesture.
    if (_keepSelectionAfterHighlightUpdate) return;
    if (range == null) {
      _selectedBlockRanges.remove(blockKey);
      _selectedBlockRects.remove(blockKey);
    } else {
      final mapped = ReaderTextSelectionOffsets.sourceRangeFor(
        block,
        range.startOffset,
        range.endOffset,
      );
      if (mapped == null) {
        _selectedBlockRanges.remove(blockKey);
        _selectedBlockRects.remove(blockKey);
      } else {
        _selectedBlockRanges[blockKey] = _BlockSelection(
          sectionIndex,
          mapped.$1,
          mapped.$2,
        );
        if (selectionRects.isEmpty) {
          _selectedBlockRects.remove(blockKey);
        } else {
          _selectedBlockRects[blockKey] = selectionRects;
        }
      }
    }
    if (!_selectionChanging) _refreshPendingSelection();
  }

  void _refreshPendingSelection() {
    if (!mounted ||
        _selectionChanging ||
        _keepSelectionAfterHighlightUpdate ||
        _selectedBlockRanges.isEmpty) {
      return;
    }
    final grouped = <int, (int, int)>{};
    for (final selected in _selectedBlockRanges.values) {
      final current = grouped[selected.sectionIndex];
      grouped[selected.sectionIndex] = current == null
          ? (selected.start, selected.end)
          : (
              math.min(current.$1, selected.start),
              math.max(current.$2, selected.end),
            );
    }
    final ranges = [
      for (final entry in grouped.entries)
        _SectionSelection(entry.key, entry.value.$1, entry.value.$2),
    ]..sort((a, b) => a.sectionIndex.compareTo(b.sectionIndex));
    final snippets = <String>[];
    for (final range in ranges) {
      snippets.add(
        _renderedTextForSectionRange(
          range.sectionIndex,
          range.start,
          range.end,
        ),
      );
    }
    final text = snippets.join('\n').trim();
    if (text.isEmpty) return;
    setState(() => _pending = _PendingSelection(text: text, ranges: ranges));
  }

  String? _sourceTextForSection(int index) {
    if (index == _section && _enginePlain.isNotEmpty) return _enginePlain;
    final loaded = _continuousPages.where(
      (page) => page.section.index == index && !page.section.isPlaceholder,
    );
    if (loaded.isNotEmpty) return loaded.first.section.enginePlain;
    return _pdfSectionCache[index]?.enginePlain;
  }

  List<HighlightRecord> _highlightsForSection(int index) {
    if (index == _section) return _highlights;
    final loaded = _continuousPages.where(
      (page) => page.section.index == index && !page.section.isPlaceholder,
    );
    if (loaded.isNotEmpty) return loaded.first.section.highlights;
    return _pdfSectionCache[index]?.highlights ?? const [];
  }

  int? _uniformSelectedColor() {
    final pending = _pending;
    if (pending == null || pending.ranges.isEmpty) return null;
    int? selectedColor;
    for (final selection in pending.ranges) {
      final color = uniformHighlightColor(
        HighlightRange(selection.start, selection.end),
        _highlightsForSection(selection.sectionIndex).map(
          (item) =>
              HighlightColorRange(item.startOffset, item.endOffset, item.color),
        ),
      );
      if (color == null || (selectedColor != null && selectedColor != color)) {
        return null;
      }
      selectedColor = color;
    }
    return selectedColor;
  }

  bool _selectionIntersectsHighlight() {
    final pending = _pending;
    if (pending == null) return false;
    return pending.ranges.any(
      (selection) => _highlightsForSection(selection.sectionIndex).any(
        (highlight) =>
            highlight.startOffset < selection.end &&
            highlight.endOffset > selection.start,
      ),
    );
  }

  Future<void> _saveQuote() async {
    final pending = _pending;
    final session = _session;
    if (pending == null ||
        pending.ranges.isEmpty ||
        session == null ||
        _saving) {
      return;
    }
    setState(() => _saving = true);
    try {
      final first = pending.ranges.first;
      final locator = await _readerSvc.getLocator(
        session,
        first.sectionIndex,
        first.start,
      );
      final stored = await ref
          .read(annotationsRepoProvider)
          .toggleQuote(
            QuoteRecord(
              bookId: widget.bookId,
              sectionIndex: first.sectionIndex,
              charOffset: first.start,
              cfi: _cfiOf(locator),
              quotedText: pending.text,
            ),
          );
      if (!mounted) return;
      setState(() {
        _quotes = [
          ?stored,
          ..._quotes.where(
            (quote) =>
                quote.bookId != widget.bookId ||
                quote.sectionIndex != first.sectionIndex ||
                quote.charOffset != first.start ||
                quote.quotedText != pending.text,
          ),
        ];
        _quoteHighlightsBySection.remove(first.sectionIndex);
        _saving = false;
      });
      _clearSelection();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _showAnnotationSaveFailure();
      }
    }
  }

  Future<void> _applySelectionColor(int color, {bool clear = false}) async {
    final pending = _pending;
    final session = _session;
    if (pending == null ||
        pending.ranges.isEmpty ||
        session == null ||
        _saving) {
      return;
    }
    final remove = clear || _uniformSelectedColor() == color;
    _keepSelectionAfterHighlightUpdate = true;
    setState(() => _saving = true);
    try {
      final annotations = ref.read(annotationsRepoProvider);
      for (final selection in pending.ranges) {
        final source = _sourceTextForSection(selection.sectionIndex);
        final sectionBlocks = _blocksForSection(selection.sectionIndex);
        if (source == null ||
            sectionBlocks == null ||
            selection.start >= selection.end) {
          continue;
        }
        final storedExisting = await annotations.highlightsForSection(
          widget.bookId,
          selection.sectionIndex,
        );
        final existing = await _resolveHighlightCoordinates(
          selection.sectionIndex,
          source,
          sectionBlocks,
          storedExisting,
        );
        final selectedRange = HighlightRange(selection.start, selection.end);
        for (final highlight in existing) {
          final id = highlight.id;
          if (id == null ||
              highlight.startOffset >= selection.end ||
              highlight.endOffset <= selection.start) {
            continue;
          }
          final fragments = subtractHighlightRange(
            HighlightRange(highlight.startOffset, highlight.endOffset),
            selectedRange,
          );
          if (fragments.isEmpty) {
            await annotations.deleteHighlight(id);
            continue;
          }
          for (var i = 0; i < fragments.length; i++) {
            final fragment = fragments[i];
            final locator = await _readerSvc.getLocator(
              session,
              selection.sectionIndex,
              fragment.start,
            );
            final updated = HighlightRecord(
              id: i == 0 ? id : null,
              bookId: widget.bookId,
              sectionIndex: selection.sectionIndex,
              startOffset: fragment.start,
              endOffset: fragment.end,
              cfi: _cfiOf(locator),
              color: highlight.color,
              quotedText: _renderedTextForSectionRange(
                selection.sectionIndex,
                fragment.start,
                fragment.end,
              ),
              note: i == 0 ? highlight.note : '',
            );
            if (i == 0) {
              await annotations.updateHighlightRange(id, updated);
            } else {
              await annotations.addHighlight(updated);
            }
          }
        }
        if (!remove) {
          final locator = await _readerSvc.getLocator(
            session,
            selection.sectionIndex,
            selection.start,
          );
          await annotations.addHighlight(
            HighlightRecord(
              bookId: widget.bookId,
              sectionIndex: selection.sectionIndex,
              startOffset: selection.start,
              endOffset: selection.end,
              cfi: _cfiOf(locator),
              color: color,
              quotedText: _renderedTextForSectionRange(
                selection.sectionIndex,
                selection.start,
                selection.end,
              ),
              note: '',
            ),
          );
        }
        final storedFresh = await annotations.highlightsForSection(
          widget.bookId,
          selection.sectionIndex,
        );
        final fresh = await _resolveHighlightCoordinates(
          selection.sectionIndex,
          source,
          sectionBlocks,
          storedFresh,
        );
        _replaceCachedSectionHighlights(selection.sectionIndex, fresh);
        if (selection.sectionIndex == _section) _highlights = fresh;
      }
      if (mounted) setState(() => _saving = false);
    } catch (_) {
      try {
        await _refreshSelectionHighlightsAfterFailure(pending);
      } catch (_) {
        // The save failure remains visible below; this read only reconciles
        // any highlight fragments that committed before the failed write.
      }
      _keepSelectionAfterHighlightUpdate = false;
      if (mounted) {
        setState(() => _saving = false);
        _showAnnotationSaveFailure();
      }
    }
  }

  Future<void> _refreshSelectionHighlightsAfterFailure(
    _PendingSelection pending,
  ) async {
    final annotations = ref.read(annotationsRepoProvider);
    for (final selection in pending.ranges) {
      final source = _sourceTextForSection(selection.sectionIndex);
      final blocks = _blocksForSection(selection.sectionIndex);
      if (source == null || blocks == null) continue;
      final stored = await annotations.highlightsForSection(
        widget.bookId,
        selection.sectionIndex,
      );
      final resolved = await _resolveHighlightCoordinates(
        selection.sectionIndex,
        source,
        blocks,
        stored,
      );
      _replaceCachedSectionHighlights(selection.sectionIndex, resolved);
      if (selection.sectionIndex == _section) _highlights = resolved;
    }
  }

  void _clearSelection() {
    _keepSelectionAfterHighlightUpdate = false;
    _selectedBlockRanges.clear();
    _selectedBlockRects.clear();
    _regionKey.currentState?.clearSelection();
    if (mounted) {
      setState(() {
        _pending = null;
        _selectionAnchor = null;
      });
    }
  }

  void _replaceCachedSectionHighlights(
    int sectionIndex,
    List<HighlightRecord> highlights,
  ) {
    if (_isPdf) {
      final cached = _pdfSectionCache[sectionIndex];
      if (cached != null) {
        _pdfSectionCache[sectionIndex] = cached.copyWithHighlights(highlights);
      }
      return;
    }
    final firstIndex = _continuousPages.indexWhere(
      (page) =>
          page.section.index == sectionIndex && !page.section.isPlaceholder,
    );
    if (firstIndex < 0) return;
    final section = _continuousPages[firstIndex].section.copyWithHighlights(
      highlights,
    );
    _continuousPages = [
      for (final page in _continuousPages)
        if (page.section.index == sectionIndex && !page.section.isPlaceholder)
          _ContinuousPage(
            section: section,
            page: page.page,
            sectionPageIndex: page.sectionPageIndex,
          )
        else
          page,
    ];
  }

  void _cancelPending() {
    _clearSelection();
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

  Future<void> _toggleBookmark() async {
    final session = _session;
    final sectionIndex = _section;
    final offset = _currentPageOffset;
    if (session == null || _bookmarkSaving) return;
    setState(() => _bookmarkSaving = true);
    try {
      final annotations = ref.read(annotationsRepoProvider);
      if (_bookmarkState.contains(sectionIndex, offset)) {
        await annotations.deleteBookmarksAt(
          bookId: widget.bookId,
          sectionIndex: sectionIndex,
          charOffset: offset,
        );
        if (mounted) {
          setState(() {
            _bookmarkState.remove(sectionIndex, offset);
            _bookmarkSaving = false;
          });
        }
        return;
      }
      final svc = ref.read(readerServiceProvider);
      final locator = await svc.getLocator(session, sectionIndex, offset);
      await annotations.addBookmark(
        BookmarkRecord(
          bookId: widget.bookId,
          sectionIndex: sectionIndex,
          cfi: _cfiOf(locator),
          charOffset: offset,
          label:
              '${tr(ref.read(localeProvider), 'sectionOf')} ${sectionIndex + 1}',
        ),
      );
      if (mounted) {
        setState(() {
          _bookmarkState.add(sectionIndex, offset);
          _bookmarkSaving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr(ref.read(localeProvider), 'bookmarkAdded')),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _bookmarkSaving = false);
        _showAnnotationSaveFailure();
      }
    }
  }

  bool get _currentPageHasBookmark =>
      _bookmarkState.contains(_section, _currentPageOffset);

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
      final selection = pending != null && pending.ranges.isNotEmpty
          ? pending.ranges.first
          : null;
      final offset = selection?.start ?? _currentPageOffset;
      final sectionIndex = selection?.sectionIndex ?? _section;
      final locator = await svc.getLocator(session, sectionIndex, offset);
      await ref
          .read(annotationsRepoProvider)
          .addNote(
            NoteRecord(
              bookId: widget.bookId,
              sectionIndex: sectionIndex,
              cfi: _cfiOf(locator),
              charOffset: offset,
              content: content,
              quotedText: pending?.text ?? '',
            ),
          );
      _clearSelection();
    } catch (_) {
      _showAnnotationSaveFailure();
    }
  }

  void _showAnnotationSaveFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(ref.read(localeProvider), 'annotationSaveFailed')),
      ),
    );
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
    var progressDisplayDraft = _progressDisplayMode;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .78,
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          void update(ReaderSettingsData next) {
            draft = next;
            setSheetState(() {});
            ref.read(readerSettingsProvider.notifier).set(next);
            unawaited(ref.read(settingsRepoProvider).saveReaderSettings(next));
            _setReaderSystemUi(next.theme);
          }

          void finishLayoutSliderChange(double _) =>
              _endLayoutSliderChange();

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(sheetContext).height * .72,
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
                          items:
                              const [
                                    'System',
                                    'Serif',
                                    'Monospace',
                                    'Literata',
                                    'Lora',
                                    'Atkinson Hyperlegible',
                                  ]
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
                      onChangeStart: _isPdf
                          ? null
                          : (_) => _beginLayoutSliderChange(),
                      onChangeEnd: _isPdf ? null : finishLayoutSliderChange,
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
                      onChangeStart: _isPdf
                          ? null
                          : (_) => _beginLayoutSliderChange(),
                      onChangeEnd: _isPdf ? null : finishLayoutSliderChange,
                    ),
                    _ReaderSliderRow(
                      label: tr(locale, 'margin'),
                      value: draft.marginPx.toDouble(),
                      min: 8,
                      max: 96,
                      divisions: 22,
                      display: '${draft.marginPx} px',
                      onChanged: (value) =>
                          update(draft.copyWith(marginPx: value.round())),
                      onChangeStart: _isPdf
                          ? null
                          : (_) => _beginLayoutSliderChange(),
                      onChangeEnd: _isPdf ? null : finishLayoutSliderChange,
                    ),
                    _ReaderSliderRow(
                      label: tr(locale, 'brightness'),
                      value: draft.brightness ?? 1.0,
                      min: 0.05,
                      max: 1,
                      divisions: 95,
                      display: draft.brightness == null
                          ? tr(locale, 'systemBrightness')
                          : '${(draft.brightness! * 100).round()}%',
                      onChanged: (value) =>
                          update(draft.copyWith(brightness: value)),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: draft.brightness == null
                            ? null
                            : () =>
                                  update(draft.copyWith(clearBrightness: true)),
                        child: Text(tr(locale, 'systemBrightness')),
                      ),
                    ),
                    _ReaderAlignmentRow(
                      locale: locale,
                      alignment: draft.alignment,
                      onChanged: (value) =>
                          update(draft.copyWith(alignment: value)),
                    ),
                    if (!_isPdf && !_isCbz)
                      Row(
                        children: [
                          Expanded(
                            child: Text(tr(locale, 'readerProgressDisplay')),
                          ),
                          DropdownButton<ReaderProgressDisplayMode>(
                            value: progressDisplayDraft,
                            underline: const SizedBox.shrink(),
                            items: [
                              for (final mode
                                  in ReaderProgressDisplayMode.values)
                                DropdownMenuItem(
                                  value: mode,
                                  child: Text(
                                    tr(locale, switch (mode) {
                                      ReaderProgressDisplayMode
                                          .pageAndPercent =>
                                        'progressPageAndPercent',
                                      ReaderProgressDisplayMode.pageOnly =>
                                        'progressPageOnly',
                                      ReaderProgressDisplayMode.percentOnly =>
                                        'progressPercentOnly',
                                      ReaderProgressDisplayMode.hidden =>
                                        'progressHidden',
                                    }),
                                  ),
                                ),
                            ],
                            onChanged: (mode) {
                              if (mode == null ||
                                  mode == progressDisplayDraft) {
                                return;
                              }
                              final previous = progressDisplayDraft;
                              progressDisplayDraft = mode;
                              setSheetState(() {});
                              setState(() => _progressDisplayMode = mode);
                              unawaited(() async {
                                try {
                                  await ref
                                      .read(settingsRepoProvider)
                                      .setAppValue(
                                        'reader_progress_display',
                                        mode.storageValue,
                                      );
                                } catch (_) {
                                  if (!mounted ||
                                      _progressDisplayMode != mode) {
                                    return;
                                  }
                                  setState(
                                    () => _progressDisplayMode = previous,
                                  );
                                  if (sheetContext.mounted) {
                                    progressDisplayDraft = previous;
                                    setSheetState(() {});
                                  }
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr(locale, 'settingsSaveFailed'),
                                      ),
                                    ),
                                  );
                                }
                              }());
                            },
                          ),
                        ],
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
    final colors = ReaderThemeColors.of(theme);
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

  void _setReaderBrightness(double? brightness) {
    unawaited(
      const MethodChannel('codar/storage')
          .invokeMethod<void>('setReaderBrightness', <String, Object>{
            'brightness': brightness ?? -1.0,
          })
          .catchError((Object _) {}),
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

  int? _displayContinuousPageIndex(int index) {
    if ((_isPdf || _isCbz) && index >= 0 && index < _continuousPages.length) {
      return _continuousPages[index].section.index;
    }
    if (index >= 0 && index < _continuousPages.length) {
      final entry = _continuousPages[index];
      final pageCountIndex = _continuousPageCountIndex;
      if (pageCountIndex != null) {
        return pageCountIndex.pageIndexFor(
          entry.section.index,
          entry.sectionPageIndex,
        );
      }
    }
    return null;
  }

  int? get _displayContinuousPageCount => (_isPdf || _isCbz)
      ? _sectionCount
      : _continuousPageCountIndex?.totalPages;

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
    if (_pending != null || _selectionChanging) return;
    _selectionAnchor = event.localPosition;
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
    final colors = ReaderThemeColors.of(settings.theme);
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
      child: Theme(
        data: _themeForReader(Theme.of(context), colors),
        child: Scaffold(
          backgroundColor: colors.background,
          body: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onReaderPointerDown,
            onPointerUp: _onReaderPointerUp,
            onPointerCancel: (_) => _pointerDown = null,
            child: Stack(
              key: _readerStackKey,
              fit: StackFit.expand,
              children: [
                SelectableRegion(
                  key: _regionKey,
                  focusNode: _regionFocus,
                  selectionControls: _readerSelectionControls,
                  contextMenuBuilder: (context, state) =>
                      const SizedBox.shrink(),
                  onSelectionChanged: _onSelectionChanged,
                  child: _SelectionStatusObserver(
                    onChanged: _onSelectionStatusChanged,
                    child: _buildBody(locale, settings, colors),
                  ),
                ),
                if (_pending != null && !_selectionChanging)
                  _positionedHighlightPanel(locale, colors),
                _readerTopControls(locale, colors),
                if (_pending == null) _readerBottomControls(locale, colors),
              ],
            ),
          ),
        ),
      ),
    );
  }

  ThemeData _themeForReader(ThemeData base, ReaderThemeColors colors) {
    final brightness = colors.isDark ? Brightness.dark : Brightness.light;
    final colorScheme = base.colorScheme.copyWith(
      brightness: brightness,
      primary: colors.accent,
      onPrimary: colors.onAccent,
      secondary: colors.accent,
      onSecondary: colors.onAccent,
      tertiary: colors.accent,
      onTertiary: colors.onAccent,
      surface: colors.background,
      onSurface: colors.text,
      surfaceContainerHighest: colors.background,
      onSurfaceVariant: colors.weak,
      outline: colors.weak,
      outlineVariant: colors.weak.withValues(alpha: 0.55),
    );
    return base.copyWith(
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: colors.background,
      textTheme: base.textTheme.apply(
        bodyColor: colors.text,
        displayColor: colors.text,
      ),
      iconTheme: base.iconTheme.copyWith(color: colors.text),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: colors.background,
        textStyle: TextStyle(color: colors.text),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: colors.background,
      ),
      textSelectionTheme: base.textSelectionTheme.copyWith(
        cursorColor: colors.accent,
        selectionColor: colors.accent.withValues(alpha: 0.25),
        selectionHandleColor: colors.accent,
      ),
    );
  }

  Widget _buildBody(
    String locale,
    ReaderSettingsData settings,
    ReaderThemeColors colors,
  ) {
    if (_layoutReflowPending) {
      return Center(
        child: CircularProgressIndicator(
          color: colors.accent,
          strokeWidth: 2.5,
        ),
      );
    }
    final layoutError = _layoutReflowError;
    if (layoutError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${tr(locale, 'errorPrefix')}: '
              '${_displayError('$layoutError', locale)}',
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _retryLayoutReflow,
              child: Text(tr(locale, 'retry')),
            ),
          ],
        ),
      );
    }
    if (_loading && _pages.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: colors.accent,
          strokeWidth: 2.5,
        ),
      );
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
      'end' => TextAlign.end,
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
      final continuousList = ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        itemExtent: _readerPageExtent,
        scrollCacheExtent: const ScrollCacheExtent.viewport(1),
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
      if (_isPdf || _isCbz) return continuousList;
      return NotificationListener<ScrollEndNotification>(
        onNotification: (notification) {
          if (notification.depth == 0) {
            _snapEpubPageAfterScroll(notification.metrics);
          }
          return false;
        },
        child: continuousList,
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
                            sectionIndex: _section,
                            selectionKey: '$_section:$i:$j',
                          ),
                        ),
                    ],
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
    if (_isPdf && !_pdfSectionCache.containsKey(entry.section.index)) {
      final error = _pdfSectionErrors[entry.section.index];
      return SizedBox(
        height: _readerPageExtent,
        child: Center(
          child: error == null
              ? CircularProgressIndicator(
                  color: colors.accent,
                  strokeWidth: 2.5,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${tr(locale, 'errorPrefix')}: '
                      '${_displayError('$error', locale)}',
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _requestPdfWindow(entry.section.index),
                      child: Text(tr(locale, 'retry')),
                    ),
                  ],
                ),
        ),
      );
    }
    if (entry.section.isPlaceholder) {
      final error = _continuousSectionErrors[entry.section.index];
      return SizedBox(
        height: _readerPageExtent,
        child: Center(
          child: error == null
              ? (_loadingContinuousSections.contains(entry.section.index)
                    ? CircularProgressIndicator(
                        color: colors.accent,
                        strokeWidth: 2.5,
                      )
                    : const SizedBox.shrink())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${tr(locale, 'errorPrefix')}: '
                      '${_displayError('$error', locale)}',
                    ),
                    const SizedBox(height: 8),
                    FilledButton.tonal(
                      onPressed: () => _requestContinuousSection(
                        entry.section.index,
                        retry: true,
                      ),
                      child: Text(tr(locale, 'retry')),
                    ),
                  ],
                ),
        ),
      );
    }
    final section = _isPdf
        ? (_pdfSectionCache[entry.section.index] ?? entry.section)
        : entry.section;
    final page = _isPdf && entry.sectionPageIndex < section.pages.length
        ? section.pages[entry.sectionPageIndex]
        : entry.page;
    final displayPage = _displayContinuousPageIndex(index);
    final displayTotal = _displayContinuousPageCount;
    final pageLabel = displayPage != null && displayTotal != null
        ? '${tr(locale, 'pageOf')} ${displayPage + 1} / $displayTotal'
        : '${tr(locale, 'sectionOf')} ${entry.section.index + 1} / '
              '$_sectionCount · ${tr(locale, 'pageOf')} '
              '${entry.sectionPageIndex + 1}';
    final contentBlocks = page.blocks;
    final contentColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var j = 0; j < contentBlocks.length; j++)
          Padding(
            padding: EdgeInsets.only(
              bottom: j == contentBlocks.length - 1 ? 0 : 12,
            ),
            child: _blockText(
              contentBlocks[j],
              settings,
              colors,
              align,
              sectionIndex: entry.section.index,
              selectionKey:
                  '${entry.section.index}:${entry.sectionPageIndex}:$j',
              highlights: section.highlights,
              engineChars: section.engineChars,
            ),
          ),
      ],
    );
    return Semantics(
      key: ValueKey(
        'reader-page-${entry.section.index}-${entry.sectionPageIndex}',
      ),
      label: pageLabel,
      child: SizedBox(
        height: _readerPageExtent,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            margin,
            _pageTopPadding,
            margin,
            _pageBottomPadding,
          ),
          child: contentBlocks.isEmpty
              ? Text(
                  tr(locale, 'emptySection'),
                  style: TextStyle(color: colors.weak),
                )
              : contentColumn,
        ),
      ),
    );
  }

  Widget _blockText(
    ReaderBlock block,
    ReaderSettingsData settings,
    ReaderThemeColors colors,
    TextAlign align, {
    required int sectionIndex,
    required Object selectionKey,
    List<HighlightRecord>? highlights,
    int? engineChars,
  }) {
    if (block is ImageBlock) return _readerImageBlock(block);
    if (block is! TextBlock) return const SizedBox.shrink();
    final textBlock = block;
    final base = _styleForBlock(
      textBlock,
      settings,
      textBlock.isHeading ? colors.accent : colors.text,
    );
    final spans = _spansFor(
      textBlock,
      base,
      sectionIndex: sectionIndex,
      highlights: highlights,
      engineChars: engineChars,
    );
    final style = base;
    final text = Text.rich(
      TextSpan(
        children: [
          ...spans.map(
            (s) => TextSpan(
              text: s.text,
              style: style.copyWith(
                color: s.background == null
                    ? colors.text
                    : _highlightForeground(s.background!),
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
    final selectable = _ReaderSelectableBlock(
      key: ValueKey('select-$selectionKey'),
      blockKey: selectionKey,
      sectionIndex: sectionIndex,
      block: textBlock,
      onRangeChanged: _onBlockSelectionChanged,
      child: text,
    );
    if (textBlock.kind != 'li') return selectable;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•', style: style),
        const SizedBox(width: 8),
        Expanded(child: selectable),
      ],
    );
  }

  Widget _readerImageBlock(ImageBlock block) {
    if (block.images.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final screen = MediaQuery.sizeOf(context);
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : screen.width;
        final maxHeight = math.max(
          120.0,
          screen.height - _pageTopPadding - _pageBottomPadding,
        );
        if (!block.isPdfPage) {
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: ReaderImageView(
                image: block.images.first,
                fit: BoxFit.contain,
              ),
            ),
          );
        }

        final first = block.images.first;
        final pageWidth = first.pageWidth;
        final pageHeight = first.pageHeight;
        if (pageWidth <= 0 || pageHeight <= 0) {
          return ReaderImageView(image: first, fit: BoxFit.contain);
        }
        final pageRatio = pageWidth / pageHeight;
        final width = math.min(maxWidth, maxHeight * pageRatio);
        final height = width / pageRatio;
        final scaleX = width / pageWidth;
        final scaleY = height / pageHeight;
        return Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final image in block.images)
                  if (image.displayWidth > 0 && image.displayHeight > 0)
                    Positioned(
                      left: (image.left * scaleX).clamp(0.0, width),
                      top: (image.top * scaleY).clamp(0.0, height),
                      width: (image.displayWidth * scaleX).clamp(0.0, width),
                      height: (image.displayHeight * scaleY).clamp(0.0, height),
                      child: RotatedBox(
                        quarterTurns:
                            ((image.rotationDegrees ~/ 90) % 4 + 4) % 4,
                        child: ReaderImageView(image: image, fit: BoxFit.fill),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }

  TextStyle _styleForBlock(
    TextBlock block,
    ReaderSettingsData settings,
    Color color,
  ) => ReaderPagination.styleForBlock(block, settings, color);

  List<ReaderQuoteRange> _quoteRangesForSection(int sectionIndex) {
    final cached = _quoteHighlightsBySection[sectionIndex];
    if (cached != null) return cached;
    final blocks = _blocksForSection(sectionIndex);
    if (blocks == null) return const [];
    final ranges = [
      for (final quote in _quotes)
        if (quote.sectionIndex == sectionIndex)
          ?ReaderQuoteRangeResolver.resolve(quote, blocks),
    ];
    final resolved = List<ReaderQuoteRange>.unmodifiable(ranges);
    _quoteHighlightsBySection[sectionIndex] = resolved;
    return resolved;
  }

  List<_PaintSpan> _spansFor(
    TextBlock block,
    TextStyle base, {
    required int sectionIndex,
    List<HighlightRecord>? highlights,
    int? engineChars,
  }) {
    final quoteColor = ReaderThemeColors.of(
      ref.read(readerSettingsProvider).theme,
    ).accent.toARGB32();
    final activeHighlights = <HighlightRecord>[
      ...(highlights ?? _highlights),
      for (final range in _quoteRangesForSection(sectionIndex))
          HighlightRecord(
            bookId: widget.bookId,
            sectionIndex: sectionIndex,
            startOffset: range.start,
            endOffset: range.end,
            cfi: '',
            color: quoteColor,
            quotedText: '',
            note: '',
            offsetUnit: 'rust_scalar',
          ),
    ];
    final text = block.plainText;
    if (text.isEmpty || activeHighlights.isEmpty) {
      return [
        for (final p in block.parts) _PaintSpan(p.text, p.bold, p.italic, null),
      ];
    }
    if (block.sourceStartOffsets.length != text.length ||
        block.sourceEndOffsets.length != text.length) {
      return [
        for (final p in block.parts) _PaintSpan(p.text, p.bold, p.italic, null),
      ];
    }
    // Paint against the exact Rust scalar ranges carried by each rendered
    // UTF-16 code unit. Repeated phrases therefore cannot jump to another
    // occurrence in the same paragraph or section.
    final colors = List<int?>.filled(text.length, null);
    for (final highlight in activeHighlights) {
      for (var i = 0; i < text.length; i++) {
        if (block.sourceStartOffsets[i] < highlight.endOffset &&
            block.sourceEndOffsets[i] > highlight.startOffset) {
          colors[i] = highlight.color;
        }
      }
    }
    final ranges = <_Range>[];
    var runStart = 0;
    while (runStart < colors.length) {
      final color = colors[runStart];
      var runEnd = runStart + 1;
      while (runEnd < colors.length && colors[runEnd] == color) {
        runEnd++;
      }
      if (color != null) ranges.add(_Range(runStart, runEnd, color));
      runStart = runEnd;
    }
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
                    ValueListenableBuilder<int>(
                      valueListenable: _continuousPageNotifier,
                      builder: (context, pageIndex, _) {
                        if (!_isPdf &&
                            !_isCbz &&
                            !_progressDisplayMode.showsPage) {
                          return const SizedBox.shrink();
                        }
                        final hasEntry =
                            pageIndex >= 0 &&
                            pageIndex < _continuousPages.length;
                        final entry = hasEntry
                            ? _continuousPages[pageIndex]
                            : null;
                        final displayIndex = _displayContinuousPageIndex(
                          pageIndex,
                        );
                        final displayCount = _displayContinuousPageCount;
                        final value =
                            displayIndex != null && displayCount != null
                            ? '${displayIndex + 1} / $displayCount'
                            : entry == null
                            ? '—'
                            : '${tr(locale, 'sectionOf')} '
                                  '${entry.section.index + 1} · '
                                  '${tr(locale, 'pageOf')} '
                                  '${entry.sectionPageIndex + 1}';
                        final semanticsValue =
                            displayIndex != null && displayCount != null
                            ? value
                            : entry == null
                            ? tr(locale, 'loading')
                            : '${tr(locale, 'sectionOf')} '
                                  '${entry.section.index + 1} / $_sectionCount, '
                                  '${tr(locale, 'pageOf')} '
                                  '${entry.sectionPageIndex + 1}';
                        return Semantics(
                          label: tr(locale, 'pageOf'),
                          value: semanticsValue,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              _continuousPages.isEmpty ? '—' : value,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      tooltip: tr(locale, 'readerSettings'),
                      color: colors.text,
                      icon: const Icon(Icons.text_fields_rounded),
                      onPressed: () => _showReaderSettings(locale),
                    ),
                    ValueListenableBuilder<int>(
                      valueListenable: _continuousPageNotifier,
                      builder: (context, _, _) => IconButton(
                        tooltip: tr(locale, 'addBookmark'),
                        color: _currentPageHasBookmark
                            ? colors.accent
                            : colors.text,
                        icon: Icon(
                          _currentPageHasBookmark
                              ? Icons.bookmark_rounded
                              : Icons.bookmark_border_rounded,
                        ),
                        onPressed: _session == null || _bookmarkSaving
                            ? null
                            : _toggleBookmark,
                      ),
                    ),
                    IconButton(
                      tooltip: tr(locale, 'chapters'),
                      color: colors.text,
                      icon: const Icon(Icons.menu_book_outlined),
                      onPressed: _session == null ? null : _openChapters,
                    ),
                    IconButton(
                      tooltip: tr(locale, 'addNote'),
                      color: colors.text,
                      icon: const Icon(Icons.edit_note_rounded),
                      onPressed: _session == null ? null : _addNote,
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
    final navigationCount = _continuousPages.isNotEmpty
        ? _continuousPages.length
        : _pages.length;
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
              child: ValueListenableBuilder<int>(
                valueListenable: _continuousPageNotifier,
                builder: (context, pageIndex, _) {
                  final current = _continuousPages.isNotEmpty
                      ? pageIndex
                      : _pageIndex;
                  final entry =
                      _continuousPages.isNotEmpty &&
                          pageIndex >= 0 &&
                          pageIndex < _continuousPages.length
                      ? _continuousPages[pageIndex]
                      : null;
                  final localPageIndex = entry?.sectionPageIndex ?? _pageIndex;
                  final sectionIndex = entry?.section.index ?? _section;
                  final fixedPageFormat = _isPdf || _isCbz;
                  final displayIndex = _continuousPages.isNotEmpty
                      ? _displayContinuousPageIndex(pageIndex)
                      : _pageIndex;
                  final displayTotal = _continuousPages.isNotEmpty
                      ? _displayContinuousPageCount
                      : _pages.length;
                  final exactProgress =
                      displayIndex != null &&
                          displayTotal != null &&
                          displayTotal > 0
                      ? ((displayIndex + 1) / displayTotal)
                            .clamp(0.0, 1.0)
                            .toDouble()
                      : null;
                  final progressValue = fixedPageFormat
                      ? displayIndex == null ||
                                displayTotal == null ||
                                displayTotal <= 1
                            ? 0.0
                            : (displayIndex / (displayTotal - 1))
                                  .clamp(0.0, 1.0)
                                  .toDouble()
                      : exactProgress ?? _currentTotalProgression;
                  final percentLabel = progressValue == null
                      ? null
                      : '${(progressValue * 100).round()}%';
                  final exactPageLabel =
                      displayIndex != null && displayTotal != null
                      ? '${tr(locale, 'pageOf')} ${displayIndex + 1} / $displayTotal'
                      : null;
                  final pageLabel =
                      exactPageLabel ??
                      '${tr(locale, 'sectionOf')} ${sectionIndex + 1} / '
                          '$_sectionCount · ${tr(locale, 'pageOf')} '
                          '${localPageIndex + 1}';
                  final positionLabel = fixedPageFormat
                      ? displayIndex == null || displayTotal == null
                            ? null
                            : '${tr(locale, 'sectionOf')} ${sectionIndex + 1} / '
                                  '$_sectionCount · ${tr(locale, 'pageOf')} '
                                  '${displayIndex + 1} / $displayTotal'
                      : switch (_progressDisplayMode) {
                          ReaderProgressDisplayMode.pageAndPercent =>
                            exactPageLabel == null
                                ? '${tr(locale, 'sectionOf')} ${sectionIndex + 1} / '
                                      '$_sectionCount'
                                      '${percentLabel == null ? '' : ' · $percentLabel'}'
                                : '$pageLabel'
                                      '${percentLabel == null ? '' : ' · $percentLabel'}',
                          ReaderProgressDisplayMode.pageOnly => pageLabel,
                          ReaderProgressDisplayMode.percentOnly => percentLabel,
                          ReaderProgressDisplayMode.hidden => null,
                        };
                  final showProgressBar =
                      fixedPageFormat ||
                      (_progressDisplayMode.showsPercent &&
                          progressValue != null);
                  return Padding(
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
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOut,
                                      )
                              : null,
                        ),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (showProgressBar) ...[
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 180,
                                  ),
                                  child: LinearProgressIndicator(
                                    value: progressValue,
                                    minHeight: 2,
                                    color: colors.text,
                                    backgroundColor: colors.progressTrack,
                                  ),
                                ),
                                if (positionLabel != null)
                                  const SizedBox(height: 6),
                              ],
                              if (positionLabel != null)
                                Text(
                                  positionLabel,
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
                          onPressed: current < navigationCount - 1
                              ? () => _continuousPages.isNotEmpty
                                    ? _scrollToContinuousIndex(current + 1)
                                    : _pageController.nextPage(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        curve: Curves.easeOut,
                                      )
                              : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _highlightBar(String locale, ReaderThemeColors colors) {
    final pending = _pending;
    final uniform = _uniformSelectedColor();
    return Material(
      color: Colors.transparent,
      child: Card(
        color: colors.background,
        elevation: 8,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: colors.weak.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending != null)
                Text(
                  pending.text.length > 110
                      ? '${pending.text.substring(0, 110)}…'
                      : pending.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.weak, fontSize: 12),
                ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 10,
                children: [
                  Semantics(
                    label: tr(locale, 'clearHighlight'),
                    button: true,
                    child: InkResponse(
                      radius: 28,
                      onTap: _saving
                          ? null
                          : () => _applySelectionColor(0, clear: true),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colors.background,
                          border: Border.all(
                            color: _selectionIntersectsHighlight()
                                ? colors.accent
                                : colors.weak,
                            width: _selectionIntersectsHighlight() ? 2.5 : 1,
                          ),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Icon(
                              Icons.format_color_reset_rounded,
                              color: colors.text,
                              size: 21,
                            ),
                            CustomPaint(
                              size: const Size(20, 20),
                              painter: _SelectionStrikePainter(colors.text),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  for (final color in highlightPalette)
                    Semantics(
                      label: tr(locale, 'highlightColor'),
                      button: true,
                      child: InkResponse(
                        radius: 28,
                        onTap: _saving
                            ? null
                            : () => _applySelectionColor(color),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: uniform == color
                                  ? colors.text
                                  : colors.weak,
                              width: uniform == color ? 2.5 : 1,
                            ),
                          ),
                          child: uniform == color
                              ? CustomPaint(
                                  size: const Size(22, 22),
                                  painter: _SelectionStrikePainter(
                                    _highlightForeground(Color(color)),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : _cancelPending,
                    child: Text(tr(locale, 'cancel')),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.format_quote_rounded),
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: colors.onAccent,
                    ),
                    onPressed: _saving ? null : _saveQuote,
                    label: Text(tr(locale, 'quote')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _positionedHighlightPanel(String locale, ReaderThemeColors colors) {
    final screenSize = MediaQuery.sizeOf(context);
    final safePadding = MediaQuery.paddingOf(context);
    final stackObject = _readerStackKey.currentContext?.findRenderObject();
    final stackBox = stackObject is RenderBox ? stackObject : null;
    final size = stackBox?.size ?? screenSize;
    final globalSafeBounds = Rect.fromLTRB(
      safePadding.left,
      safePadding.top,
      screenSize.width - safePadding.right,
      screenSize.height - safePadding.bottom,
    );
    final safeBounds = stackBox == null
        ? globalSafeBounds
        : Rect.fromPoints(
            stackBox.globalToLocal(globalSafeBounds.topLeft),
            stackBox.globalToLocal(globalSafeBounds.bottomRight),
          ).intersect(Offset.zero & size);
    final width = math
        .min(380.0, math.max(1.0, safeBounds.width - 24))
        .toDouble();
    const panelHeight = 190.0;
    final anchor =
        _selectionAnchor ?? Offset(size.width / 2, size.height * .55);
    final selectionRects = <Rect>[
      for (final rect in _selectedBlockRects.values.expand((items) => items))
        if (stackBox != null)
          Rect.fromPoints(
            stackBox.globalToLocal(rect.topLeft),
            stackBox.globalToLocal(rect.bottomRight),
          ),
    ];
    final placement = placeSelectionPopup(
      viewportSize: size,
      safeBounds: safeBounds,
      selectionRects: selectionRects,
      fallbackAnchor: anchor,
      popupSize: Size(width, panelHeight),
    );
    return Positioned(
      left: placement.left,
      top: placement.top,
      width: width,
      child: _highlightBar(locale, colors),
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
    double? brightness,
    bool clearBrightness = false,
  }) => ReaderSettingsData(
    fontFamily: fontFamily ?? this.fontFamily,
    fontSizePx: fontSizePx ?? this.fontSizePx,
    lineHeight: lineHeight ?? this.lineHeight,
    marginPx: marginPx ?? this.marginPx,
    alignment: alignment ?? this.alignment,
    theme: theme ?? this.theme,
    brightness: clearBrightness ? null : brightness ?? this.brightness,
  );
}

class _ReaderAlignmentRow extends StatelessWidget {
  const _ReaderAlignmentRow({
    required this.locale,
    required this.alignment,
    required this.onChanged,
  });

  final String locale;
  final String alignment;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr(locale, 'alignment')),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: 'start',
                label: Text(tr(locale, 'alignStart')),
              ),
              ButtonSegment(value: 'end', label: Text(tr(locale, 'alignEnd'))),
              ButtonSegment(
                value: 'center',
                label: Text(tr(locale, 'alignCenter')),
              ),
              ButtonSegment(
                value: 'justify',
                label: Text(tr(locale, 'alignJustify')),
              ),
            ],
            selected: {alignment},
            onSelectionChanged: (value) => onChanged(value.first),
          ),
        ),
      ],
    ),
  );
}

class _SelectionStrikePainter extends CustomPainter {
  const _SelectionStrikePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(size.width * .12, size.height * .88),
      Offset(size.width * .88, size.height * .12),
      Paint()
        ..color = color
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_SelectionStrikePainter oldDelegate) =>
      oldDelegate.color != color;
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
    this.onChangeStart,
    this.onChangeEnd,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;

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
          onChangeStart: onChangeStart,
          onChangeEnd: onChangeEnd,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

typedef _ReaderPage = ReaderPage;

class _ReaderSelectionControls extends MaterialTextSelectionControls
    with TextSelectionHandleControls {}

class _ReaderSelectableBlock extends StatefulWidget {
  const _ReaderSelectableBlock({
    super.key,
    required this.blockKey,
    required this.sectionIndex,
    required this.block,
    required this.onRangeChanged,
    required this.child,
  });

  final Object blockKey;
  final int sectionIndex;
  final TextBlock block;
  final void Function(
    Object blockKey,
    int sectionIndex,
    TextBlock block,
    SelectedContentRange? range,
    List<Rect> selectionRects,
  )
  onRangeChanged;
  final Widget child;

  @override
  State<_ReaderSelectableBlock> createState() => _ReaderSelectableBlockState();
}

class _ReaderSelectableBlockState extends State<_ReaderSelectableBlock> {
  final SelectionListenerNotifier _notifier = SelectionListenerNotifier();
  final GlobalKey _paragraphKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _notifier.addListener(_selectionChanged);
  }

  void _selectionChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_notifier.registered) return;
      final range = _notifier.selection.range;
      final renderObject = _paragraphKey.currentContext?.findRenderObject();
      final rects = range == null
          ? const <Rect>[]
          : globalTextSelectionRects(
              renderObject,
              TextSelection(
                baseOffset: range.startOffset,
                extentOffset: range.endOffset,
              ),
            );
      widget.onRangeChanged(
        widget.blockKey,
        widget.sectionIndex,
        widget.block,
        range,
        rects,
      );
    });
  }

  @override
  void dispose() {
    _notifier.removeListener(_selectionChanged);
    _notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionListener(
    selectionNotifier: _notifier,
    child: KeyedSubtree(key: _paragraphKey, child: widget.child),
  );
}

class _SelectionStatusObserver extends StatefulWidget {
  const _SelectionStatusObserver({
    required this.onChanged,
    required this.child,
  });
  final ValueChanged<SelectableRegionSelectionStatus> onChanged;
  final Widget child;

  @override
  State<_SelectionStatusObserver> createState() =>
      _SelectionStatusObserverState();
}

class _SelectionStatusObserverState extends State<_SelectionStatusObserver> {
  ValueListenable<SelectableRegionSelectionStatus>? _status;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SelectableRegionSelectionStatusScope.maybeOf(context);
    if (next == _status) return;
    _status?.removeListener(_statusChanged);
    _status = next;
    _status?.addListener(_statusChanged);
    _statusChanged();
  }

  void _statusChanged() {
    final status = _status;
    if (mounted && status != null) widget.onChanged(status.value);
  }

  @override
  void dispose() {
    _status?.removeListener(_statusChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ReaderSection {
  const _ReaderSection({
    required this.index,
    required this.blocks,
    required this.pages,
    required this.enginePlain,
    required this.engineChars,
    required this.highlights,
    this.isPlaceholder = false,
  });

  final int index;
  final List<ReaderBlock> blocks;
  final List<_ReaderPage> pages;
  final String enginePlain;
  final int engineChars;
  final List<HighlightRecord> highlights;
  final bool isPlaceholder;

  _ReaderSection copyWithHighlights(List<HighlightRecord> value) =>
      _ReaderSection(
        index: index,
        blocks: blocks,
        pages: pages,
        enginePlain: enginePlain,
        engineChars: engineChars,
        highlights: value,
        isPlaceholder: isPlaceholder,
      );
}

class _ContinuousPage {
  const _ContinuousPage({
    required this.section,
    required this.page,
    required this.sectionPageIndex,
  });

  final _ReaderSection section;
  final _ReaderPage page;
  final int sectionPageIndex;
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
