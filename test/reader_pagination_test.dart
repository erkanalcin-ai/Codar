import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/reader_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('count-only pagination matches rendered page count', (
    tester,
  ) async {
    final settings = ReaderSettingsData(
      fontFamily: 'System',
      fontSizePx: 18,
      lineHeight: 1.5,
      marginPx: 48,
      alignment: 'start',
      theme: 'light',
    );
    const viewport = Size(360, 640);
    final text = List.filled(
      800,
      'Reader pagination stays consistent. ',
    ).join();
    final blocks = [
      TextBlock(kind: 'p', parts: [SpanPart(text)]),
    ];
    final viewportHeight = ReaderPagination.paginationViewportHeight(
      viewport.height,
    );

    final renderedPages = ReaderPagination.paginate(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: viewportHeight,
      engineChars: text.length,
    );
    final totalPageCount = ReaderPagination.countPages(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: viewportHeight,
      engineChars: text.length,
    );

    expect(totalPageCount, greaterThan(1));
    expect(totalPageCount, renderedPages.length);
  });
}
