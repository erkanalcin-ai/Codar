import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/reader_pagination.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('font reflow preserves exact content and source ranges', (
    tester,
  ) async {
    final text = List.filled(90, 'Türkçe 😀 metin sayfa sınırını aşar. ').join();
    final starts = <int>[];
    final ends = <int>[];
    var scalar = 0;
    for (final rune in text.runes) {
      final width = rune > 0xffff ? 2 : 1;
      for (var i = 0; i < width; i++) {
        starts.add(scalar);
        ends.add(scalar + 1);
      }
      scalar++;
    }
    final sourceBlock = TextBlock(
      kind: 'p',
      parts: [SpanPart(text)],
      sourceStartOffsets: starts,
      sourceEndOffsets: ends,
    );
    const viewport = Size(360, 640);
    final viewportHeight = ReaderPagination.paginationViewportHeight(
      viewport.height,
    );

    for (final fontSize in [12, 18, 32]) {
      final settings = ReaderSettingsData(
        fontFamily: 'System',
        fontSizePx: fontSize,
        lineHeight: 1.5,
        marginPx: 48,
        alignment: 'start',
        theme: 'light',
      );
      final pages = await ReaderPagination.paginateCooperatively(
        [sourceBlock],
        settings,
        viewportWidth: viewport.width,
        viewportHeight: viewportHeight,
        engineChars: scalar,
        yieldFrame: () async {},
      );
      final synchronousPages = ReaderPagination.paginate(
        [sourceBlock],
        settings,
        viewportWidth: viewport.width,
        viewportHeight: viewportHeight,
        engineChars: scalar,
      );
      final count = ReaderPagination.countPages(
        [sourceBlock],
        settings,
        viewportWidth: viewport.width,
        viewportHeight: viewportHeight,
        engineChars: scalar,
      );
      final pageBlocks = [
        for (final page in pages)
          for (final block in page.blocks)
            if (block is TextBlock) block,
      ];

      expect(pages.length, count);
      expect(
        pages.map((page) => page.startOffset),
        synchronousPages.map((page) => page.startOffset),
      );
      expect(
        [
          for (final page in pages)
            [
              for (final block in page.blocks)
                if (block is TextBlock) block.plainText,
            ],
        ],
        [
          for (final page in synchronousPages)
            [
              for (final block in page.blocks)
                if (block is TextBlock) block.plainText,
            ],
        ],
      );
      expect(
        [
          for (final page in pages)
            [
              for (final block in page.blocks)
                if (block is TextBlock) block.sourceStartOffsets,
            ],
        ],
        [
          for (final page in synchronousPages)
            [
              for (final block in page.blocks)
                if (block is TextBlock) block.sourceStartOffsets,
            ],
        ],
      );
      expect(pageBlocks.map((block) => block.plainText).join(), text);
      expect(
        pageBlocks.expand((block) => block.sourceStartOffsets).toList(),
        starts,
      );
      expect(
        pageBlocks.expand((block) => block.sourceEndOffsets).toList(),
        ends,
      );
      expect(
        pages.map((page) => page.startOffset),
        orderedEquals(pages.map((page) => page.startOffset).toList()..sort()),
      );
    }
  });
}
