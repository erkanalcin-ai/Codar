import 'dart:math' as math;

import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/page_count_index.dart';
import 'package:codar/src/reader/reader_service.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart'
    as reader_dto;
import 'package:flutter/material.dart';

Future<int> countReaderTotalPageCount({
  required CodarReaderService reader,
  required String path,
  required ReaderSettingsData settings,
  required Size viewport,
}) async {
  await reader.init();
  return reader.withBook(path, (session) async {
    final info = await reader.getDocumentInfo(session);
    final sectionCount = info.sectionCount.toInt();
    if (sectionCount <= 0) return 0;

    final format = info.format.toLowerCase();
    if (format == 'pdf' || format == 'cbz') return sectionCount;

    final sectionPageCounts = List<int>.filled(sectionCount, 0);
    for (var index = 0; index < sectionCount; index++) {
      final content = await reader.getContent(session, index);
      final blocks = ReaderPagination.parseSectionContent(content);
      if (blocks.isEmpty) continue;
      sectionPageCounts[index] = ReaderPagination.countPages(
        blocks,
        settings,
        viewportWidth: viewport.width,
        viewportHeight: ReaderPagination.paginationViewportHeight(
          viewport.height,
        ),
        engineChars: content.charCount.toInt(),
      );
    }
    return ReaderPageCountIndex(sectionPageCounts).totalPages;
  });
}

/// The reader's single pagination implementation for both rendered pages and
/// count-only passes. Count-only callers retain no page/block lists.
class ReaderPagination {
  const ReaderPagination._();

  static const pageTopPadding = 88.0;
  static const pageBottomPadding = 88.0;

  static double paginationViewportHeight(double height) =>
      height - pageTopPadding - pageBottomPadding + 42.0;

  static List<ReaderBlock> parseSectionContent(
    reader_dto.SectionContent content, {
    bool preserveEmptyTextBlocks = false,
  }) {
    final images = [
      for (final image in content.images)
        ReaderImage(
          source: image.source,
          mimeType: image.mimeType,
          data: image.data,
          pixelWidth: image.pixelWidth,
          pixelHeight: image.pixelHeight,
          dataFormat: image.dataFormat,
          left: image.left,
          top: image.top,
          displayWidth: image.displayWidth,
          displayHeight: image.displayHeight,
          pageWidth: image.pageWidth,
          pageHeight: image.pageHeight,
          rotationDegrees: image.rotationDegrees,
        ),
    ];
    return parseSectionHtml(
      content.html,
      images: images,
      preserveEmptyTextBlocks: preserveEmptyTextBlocks,
    );
  }

  static List<ReaderPage> paginate(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
  }) => _paginate(
    blocks,
    settings,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    engineChars: engineChars,
    retainPages: true,
  ).pages;

  static int countPages(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
  }) => _paginate(
    blocks,
    settings,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    engineChars: engineChars,
    retainPages: false,
  ).pageCount;

  /// Runs the same pagination algorithm as [countPages], yielding between
  /// bounded groups of measured page pieces so a loading indicator can paint.
  static Future<int> countPagesCooperatively(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
    required Future<void> Function() yieldFrame,
  }) async => (await _paginateCooperatively(
    blocks,
    settings,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    engineChars: engineChars,
    retainPages: false,
    yieldFrame: yieldFrame,
  )).pageCount;

  static Future<List<ReaderPage>> paginateCooperatively(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
    required Future<void> Function() yieldFrame,
  }) async => (await _paginateCooperatively(
    blocks,
    settings,
    viewportWidth: viewportWidth,
    viewportHeight: viewportHeight,
    engineChars: engineChars,
    retainPages: true,
    yieldFrame: yieldFrame,
  )).pages;

  static Future<_PaginationResult> _paginateCooperatively(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
    required bool retainPages,
    required Future<void> Function() yieldFrame,
  }) async {
    final run = _ReaderPaginationRun(
      blocks,
      settings,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      engineChars: engineChars,
      retainPages: retainPages,
    );
    var workUnits = 0;
    final frameBudget = Stopwatch()..start();
    for (final block in blocks) {
      workUnits = await run.addBlockCooperatively(
        block,
        workUnits: workUnits,
        frameBudget: frameBudget,
        yieldFrame: yieldFrame,
      );
    }
    return run.finish();
  }

  static TextStyle styleForBlock(
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
      // Text.rich inherits Material 3 bodyMedium's letter spacing and even
      // leading distribution when a Reader span leaves them unset. Keep both
      // explicit so TextPainter measures the same rendered paragraph.
      letterSpacing: 0.25,
      leadingDistribution: TextLeadingDistribution.even,
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

  static _PaginationResult _paginate(
    List<ReaderBlock> blocks,
    ReaderSettingsData settings, {
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
    required bool retainPages,
  }) {
    final run = _ReaderPaginationRun(
      blocks,
      settings,
      viewportWidth: viewportWidth,
      viewportHeight: viewportHeight,
      engineChars: engineChars,
      retainPages: retainPages,
    );
    run.addAll(blocks);
    return run.finish();
  }

  static int _fitEnd(
    TextBlock block,
    int start,
    double width,
    double available,
    ReaderSettingsData settings,
    TextAlign align,
  ) {
    final text = block.plainText;
    var step = math.min(128, text.length - start);
    var best = start;
    var high = text.length;
    while (true) {
      final end = _runeBoundaryAtOrAfter(
        text,
        math.min(start + step, text.length),
      );
      final candidate = text.substring(start, end);
      if (_measureText(
            block,
            candidate,
            width,
            settings,
            align,
            startOffset: start,
          ) <=
          available) {
        best = end;
        if (end == text.length) return text.length;
        step = math.min(step * 2, text.length - start);
      } else {
        high = end;
        break;
      }
    }
    var low = best + 1;
    while (low <= high) {
      final end = _runeBoundaryAtOrAfter(text, (low + high) ~/ 2);
      final candidate = text.substring(start, end);
      if (_measureText(
            block,
            candidate,
            width,
            settings,
            align,
            startOffset: start,
          ) <=
          available) {
        best = end;
        low = end + 1;
      } else {
        high = math.max(start, _previousRuneBoundary(text, end));
      }
    }
    if (best <= start) return start;
    var boundary = best;
    while (boundary > start && !RegExp(r'\s').hasMatch(text[boundary - 1])) {
      boundary--;
    }
    return boundary > start ? boundary : best;
  }

  static int _runeBoundaryAtOrAfter(String text, int offset) {
    if (offset <= 0 || offset >= text.length) return offset;
    final before = text.codeUnitAt(offset - 1);
    final after = text.codeUnitAt(offset);
    return before >= 0xd800 && before <= 0xdbff &&
            after >= 0xdc00 && after <= 0xdfff
        ? offset + 1
        : offset;
  }

  static int _previousRuneBoundary(String text, int offset) {
    if (offset <= 0) return 0;
    if (offset >= 2) {
      final before = text.codeUnitAt(offset - 2);
      final after = text.codeUnitAt(offset - 1);
      if (before >= 0xd800 && before <= 0xdbff &&
          after >= 0xdc00 && after <= 0xdfff) {
        return offset - 2;
      }
    }
    return offset - 1;
  }

  static double _measureBlock(
    TextBlock block,
    double width,
    ReaderSettingsData settings,
    TextAlign align,
  ) => _measureText(block, block.plainText, width, settings, align);

  static double _measureText(
    TextBlock block,
    String text,
    double width,
    ReaderSettingsData settings,
    TextAlign align, {
    int startOffset = 0,
  }) {
    final style = styleForBlock(block, settings, const Color(0xFF111111));
    final bulletWidth = block.kind == 'li'
        ? _measureInlineText('•', style)
        : 0.0;
    final painter =
        TextPainter(
          text: _styledSpanForRange(
            block,
            startOffset,
            startOffset + text.length,
            style,
          ),
          textAlign: align,
          textDirection: TextDirection.ltr,
        )..layout(
          maxWidth: math.max(
            1.0,
            width - bulletWidth - (block.kind == 'li' ? 8.0 : 0.0),
          ),
        );
    return painter.height;
  }

  static TextSpan _styledSpanForRange(
    TextBlock block,
    int start,
    int end,
    TextStyle baseStyle,
  ) {
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final part in block.parts) {
      final partEnd = cursor + part.text.length;
      final from = math.max(start, cursor);
      final to = math.min(end, partEnd);
      if (to > from) {
        children.add(
          TextSpan(
            text: part.text.substring(from - cursor, to - cursor),
            style: baseStyle.copyWith(
              fontWeight: part.bold ? FontWeight.bold : null,
              fontStyle: part.italic ? FontStyle.italic : null,
            ),
          ),
        );
      }
      cursor = partEnd;
      if (cursor >= end) break;
    }
    if (children.isEmpty && end > start) {
      final text = block.plainText.substring(start, end);
      return TextSpan(text: text, style: baseStyle);
    }
    return TextSpan(style: baseStyle, children: children);
  }

  static double _measureInlineText(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.width;
  }

  static TextBlock _sliceBlock(TextBlock block, int start, int end) {
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
    return TextBlock(
      kind: block.kind,
      parts: parts,
      sourceStartOffsets:
          block.sourceStartOffsets.length == block.plainText.length
          ? block.sourceStartOffsets.sublist(start, end)
          : const [],
      sourceEndOffsets: block.sourceEndOffsets.length == block.plainText.length
          ? block.sourceEndOffsets.sublist(start, end)
          : const [],
    );
  }

  static String? _fontFamily(String name) => switch (name) {
    'Serif' => 'serif',
    'Monospace' => 'monospace',
    'Literata' => 'Literata',
    'Lora' => 'Lora',
    'Atkinson Hyperlegible' => 'AtkinsonHyperlegible',
    _ => null,
  };
}

class _ReaderPaginationRun {
  _ReaderPaginationRun(
    this.blocks,
    this.settings, {
    required double viewportWidth,
    required double viewportHeight,
    required this.engineChars,
    required this.retainPages,
  }) : width = math
           .max(
             120.0,
             viewportWidth -
                 settings.marginPx.toDouble().clamp(8.0, 96.0).toDouble() * 2,
           )
           .toDouble(),
       height = math.max(220.0, viewportHeight - 42.0).toDouble(),
       align = switch (settings.alignment) {
         'end' => TextAlign.end,
         'center' => TextAlign.center,
         'justify' => TextAlign.justify,
         _ => TextAlign.start,
       },
       parsedLength = blocks.fold<int>(
         0,
         (total, block) => total + block.plainText.length,
       );

  final List<ReaderBlock> blocks;
  final ReaderSettingsData settings;
  final int engineChars;
  final bool retainPages;
  final double width;
  final double height;
  final TextAlign align;
  final int parsedLength;
  final List<_RawReaderPage> _rawPages = [];
  final List<ReaderBlock> _current = [];
  int _currentBlockCount = 0;
  int _pageCount = 0;
  double _used = 0;
  int _currentStart = 0;
  int _parsedCursor = 0;

  void addAll(Iterable<ReaderBlock> items) {
    for (final block in items) {
      addBlock(block);
    }
  }

  void addBlock(ReaderBlock block) {
    if (block is ImageBlock) {
      _addImageBlock(block);
      return;
    }
    final textBlock = block as TextBlock;
    final text = textBlock.plainText;
    if (text.isEmpty) return;
    var cursor = 0;
    while (cursor < text.length) {
      cursor = _addTextPiece(textBlock, cursor);
    }
    _parsedCursor += text.length;
  }

  Future<int> addBlockCooperatively(
    ReaderBlock block, {
    required int workUnits,
    required Stopwatch frameBudget,
    required Future<void> Function() yieldFrame,
  }) async {
    if (block is ImageBlock) {
      _addImageBlock(block);
      return workUnits + 1;
    }
    final textBlock = block as TextBlock;
    final text = textBlock.plainText;
    if (text.isEmpty) return workUnits;
    var cursor = 0;
    while (cursor < text.length) {
      cursor = _addTextPiece(textBlock, cursor);
      workUnits++;
      if (workUnits >= 8 || frameBudget.elapsedMicroseconds >= 6000) {
        await yieldFrame();
        workUnits = 0;
        frameBudget.reset();
      }
    }
    _parsedCursor += text.length;
    return workUnits;
  }

  void _addImageBlock(ImageBlock block) {
    _flush();
    if (block.images.isEmpty) return;
    _pageCount++;
    if (retainPages) _rawPages.add(_RawReaderPage([block], _parsedCursor));
  }

  int _addTextPiece(TextBlock block, int cursor) {
    final text = block.plainText;
    final spacing = _currentBlockCount == 0 ? 0.0 : 12.0;
    final available = height - _used - spacing;
    final end = ReaderPagination._fitEnd(
      block,
      cursor,
      width,
      math.max(1.0, available).toDouble(),
      settings,
      align,
    );
    if (end <= cursor) {
      if (_currentBlockCount > 0) {
        _flush();
        return cursor;
      }
      // Keep progress moving when one glyph exceeds the available height.
      _currentStart = _parsedCursor + cursor;
      final forcedEnd = ReaderPagination._runeBoundaryAtOrAfter(
        text,
        math.min(cursor + 1, text.length),
      );
      final piece = ReaderPagination._sliceBlock(block, cursor, forcedEnd);
      if (retainPages) _current.add(piece);
      _currentBlockCount++;
      _used = ReaderPagination._measureBlock(piece, width, settings, align);
      if (forcedEnd < text.length) _flush();
      return forcedEnd;
    }
    if (_currentBlockCount == 0) _currentStart = _parsedCursor + cursor;
    final piece = ReaderPagination._sliceBlock(block, cursor, end);
    if (retainPages) _current.add(piece);
    _currentBlockCount++;
    _used +=
        spacing + ReaderPagination._measureBlock(piece, width, settings, align);
    if (end < text.length) _flush();
    return end;
  }

  void _flush() {
    if (_currentBlockCount == 0) return;
    _pageCount++;
    if (retainPages) {
      _rawPages.add(_RawReaderPage(List.of(_current), _currentStart));
    }
    _current.clear();
    _currentBlockCount = 0;
    _used = 0;
  }

  _PaginationResult finish() {
    _flush();
    if (_pageCount == 0) {
      return const _PaginationResult(
        pages: [ReaderPage(blocks: [], startOffset: 0)],
        pageCount: 1,
      );
    }
    if (!retainPages) {
      return _PaginationResult(pages: const [], pageCount: _pageCount);
    }
    return _PaginationResult(
      pages: [
        for (final page in _rawPages)
          ReaderPage(
            blocks: page.blocks,
            startOffset: parsedLength == 0
                ? 0
                : ((page.start / parsedLength) * engineChars)
                      .round()
                      .clamp(0, engineChars)
                      .toInt(),
          ),
      ],
      pageCount: _pageCount,
    );
  }
}

class ReaderPage {
  const ReaderPage({required this.blocks, required this.startOffset});

  final List<ReaderBlock> blocks;
  final int startOffset;
}

class _RawReaderPage {
  _RawReaderPage(this.blocks, this.start);

  final List<ReaderBlock> blocks;
  final int start;
}

class _PaginationResult {
  const _PaginationResult({required this.pages, required this.pageCount});

  final List<ReaderPage> pages;
  final int pageCount;
}
