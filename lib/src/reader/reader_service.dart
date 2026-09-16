// CodarReaderService — sole Dart entry point to the Rust Reader Core.
//
// Lifecycle contract: every [openBook] must be paired with [closeSession],
// enforced via try/finally at call sites and [dispose] on teardown.

import 'package:codar/src/rust/frb_generated.dart/api/reader.dart' as frb;
import 'package:codar/src/rust/frb_generated.dart/frb_generated.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/locator.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/metadata.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/search.dart';
import 'package:flutter/foundation.dart';

/// Thin typed handle for one open book. Not the book data itself.
class ReaderSession {
  ReaderSession(this.id);
  final BigInt id;
  bool _closed = false;
  bool get isClosed => _closed;
  void markClosed() => _closed = true;
}

class CodarReaderService with ChangeNotifier {
  bool _ready = false;
  bool get isReady => _ready;
  final Set<BigInt> _open = {};

  Future<void> init() async {
    await RustLib.init();
    _ready = true;
    notifyListeners();
  }

  void _requireReady() {
    if (!_ready) throw StateError('CodarReaderService.init() not called');
  }

  Future<ReaderSession> openBook(String path) async {
    _requireReady();
    final res = await frb.openBook(path: path);
    _open.add(res.sessionId);
    return ReaderSession(res.sessionId);
  }

  Future<bool> closeSession(ReaderSession session) async {
    if (session.isClosed) return false;
    session.markClosed();
    _open.remove(session.id);
    return frb.closeBook(sessionId: session.id);
  }

  Future<int> liveSessionCount() async {
    _requireReady();
    final n = await frb.liveSessionCount();
    return n.toInt();
  }

  Future<DocumentInfo> getDocumentInfo(ReaderSession s) =>
      frb.getDocumentInfo(sessionId: s.id);

  Future<frb.CoverImage?> getCover(ReaderSession s) =>
      frb.getCover(sessionId: s.id);

  Future<List<ChapterInfo>> getChapters(ReaderSession s) =>
      frb.getChapters(sessionId: s.id);

  Future<SectionContent> getContent(ReaderSession s, int sectionIndex) =>
      frb.getContent(sessionId: s.id, sectionIndex: BigInt.from(sectionIndex));

  Future<int?> findSection(ReaderSession s, String href) async {
    final v = await frb.findSection(sessionId: s.id, href: href);
    return v?.toInt();
  }

  Future<SectionContent> getPage(ReaderSession s, int pageIndex) =>
      frb.getPage(sessionId: s.id, pageIndex: BigInt.from(pageIndex));

  Future<List<SearchHit>> search(ReaderSession s, String query) =>
      frb.search(sessionId: s.id, query: query);

  Future<String> getLocator(ReaderSession s, int sectionIndex, int charOffset) =>
      frb.getLocator(
        sessionId: s.id,
        sectionIndex: BigInt.from(sectionIndex),
        charOffset: BigInt.from(charOffset),
      );

  Future<RestoredLocation> restoreLocator(ReaderSession s, String locatorJson) =>
      frb.restoreLocator(sessionId: s.id, locatorJson: locatorJson);

  Future<ProgressInfo> getProgress(
          ReaderSession s, int sectionIndex, int charOffset) =>
      frb.getProgress(
        sessionId: s.id,
        sectionIndex: BigInt.from(sectionIndex),
        charOffset: BigInt.from(charOffset),
      );

  Future<PaginationResult> paginateSection(
    ReaderSession s,
    int sectionIndex, {
    int fontSizePx = 18,
    double lineHeight = 1.5,
    int viewportWidthPx = 800,
    int viewportHeightPx = 1280,
    int marginPx = 48,
  }) =>
      frb.paginateSection(
        sessionId: s.id,
        sectionIndex: BigInt.from(sectionIndex),
        fontSizePx: fontSizePx,
        lineHeight: lineHeight,
        viewportWidthPx: viewportWidthPx,
        viewportHeightPx: viewportHeightPx,
        marginPx: marginPx,
      );

  /// Runs [fn] with a session that is always closed afterwards.
  Future<T> withBook<T>(
      String path, Future<T> Function(ReaderSession s) fn) async {
    final s = await openBook(path);
    try {
      return await fn(s);
    } finally {
      await closeSession(s);
    }
  }

  @override
  void dispose() {
    for (final id in _open.toList()) {
      frb.closeBook(sessionId: id).catchError((Object _) => false);
    }
    _open.clear();
    super.dispose();
  }
}
