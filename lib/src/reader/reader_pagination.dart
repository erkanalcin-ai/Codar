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
    reader_dto.SectionContent content,
  ) {
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
    return parseSectionHtml(content.html, images: images);
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
    final margin = settings.marginPx.toDouble().clamp(8.0, 96.0).toDouble();
    final width = math.max(120.0, viewportWidth - margin * 2).toDouble();
    final height = math.max(220.0, viewportHeight - 42.0).toDouble();
    final align = switch (settings.alignment) {
      'end' => TextAlign.end,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      _ => TextAlign.start,
    };
    final parsedLength = blocks.fold<int>(
      0,
      (total, block) => total + block.plainText.length,
    );
    final rawPages = <_RawReaderPage>[];
    final current = <ReaderBlock>[];
    var currentBlockCount = 0;
    var pageCount = 0;
    var used = 0.0;
    var currentStart = 0;
    var parsedCursor = 0;

    void flush() {
      if (currentBlockCount == 0) return;
      pageCount++;
      if (retainPages) {
        rawPages.add(_RawReaderPage(List.of(current), currentStart));
      }
      current.clear();
      currentBlockCount = 0;
      used = 0;
    }

    for (final block in blocks) {
      if (block is ImageBlock) {
        flush();
        if (block.images.isNotEmpty) {
          pageCount++;
          if (retainPages) {
            rawPages.add(_RawReaderPage([block], parsedCursor));
          }
        }
        continue;
      }
      final textBlock = block as TextBlock;
      final text = textBlock.plainText;
      if (text.isEmpty) continue;
      var cursor = 0;
      while (cursor < text.length) {
        final spacing = currentBlockCount == 0 ? 0.0 : 12.0;
        final available = height - used - spacing;
        final end = _fitEnd(
          textBlock,
          cursor,
          width,
          math.max(1.0, available).toDouble(),
          settings,
          align,
        );
        if (end <= cursor) {
          if (currentBlockCount > 0) {
            flush();
            continue;
          }
          // Keep progress moving when one glyph exceeds the available height.
          currentStart = parsedCursor + cursor;
          final forcedEnd = math.min(cursor + 1, text.length);
          final piece = _sliceBlock(textBlock, cursor, forcedEnd);
          if (retainPages) current.add(piece);
          currentBlockCount++;
          used = _measureBlock(piece, width, settings, align);
          cursor = forcedEnd;
          if (cursor < text.length) flush();
          continue;
        }
        if (currentBlockCount == 0) currentStart = parsedCursor + cursor;
        final piece = _sliceBlock(textBlock, cursor, end);
        if (retainPages) current.add(piece);
        currentBlockCount++;
        used += spacing + _measureBlock(piece, width, settings, align);
        cursor = end;
        if (cursor < text.length) flush();
      }
      parsedCursor += text.length;
    }
    flush();
    if (pageCount == 0) {
      return const _PaginationResult(
        pages: [ReaderPage(blocks: [], startOffset: 0)],
        pageCount: 1,
      );
    }
    if (!retainPages) {
      return _PaginationResult(pages: const [], pageCount: pageCount);
    }
    return _PaginationResult(
      pages: [
        for (final page in rawPages)
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
      pageCount: pageCount,
    );
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
    TextAlign align,
  ) {
    final style = styleForBlock(block, settings, const Color(0xFF111111));
    final prefix = block.kind == 'li' ? '• ' : '';
    final painter = TextPainter(
      text: TextSpan(text: '$prefix$text', style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: width);
    return painter.height;
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
