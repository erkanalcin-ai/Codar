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

  testWidgets('cooperative pagination yields and keeps the exact page count', (
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
    final paragraph = List.filled(18, 'Several words for layout. ').join();
    final blocks = [
      for (var i = 0; i < 64; i++)
        TextBlock(kind: 'p', parts: [SpanPart('Section block $i. $paragraph')]),
    ];
    var yields = 0;
    Future<void> yieldFrame() async {
      yields++;
    }

    final viewportHeight = ReaderPagination.paginationViewportHeight(
      viewport.height,
    );
    final synchronous = ReaderPagination.countPages(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: viewportHeight,
      engineChars: 0,
    );
    final cooperative = await ReaderPagination.countPagesCooperatively(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: viewportHeight,
      engineChars: 0,
      yieldFrame: yieldFrame,
    );
    final pages = await ReaderPagination.paginateCooperatively(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: viewportHeight,
      engineChars: 0,
      yieldFrame: yieldFrame,
    );

    expect(yields, greaterThan(0));
    expect(cooperative, synchronous);
    expect(pages.length, synchronous);
  });

  test('cooperative pagination yields within a single long paragraph', () async {
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
      300,
      'Long paragraphs should keep loading frames responsive. ',
    ).join();
    final blocks = [TextBlock(kind: 'p', parts: [SpanPart(text)])];
    var yields = 0;
    Future<void> yieldFrame() async => yields++;
    final height = ReaderPagination.paginationViewportHeight(viewport.height);
    final synchronous = ReaderPagination.paginate(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: height,
      engineChars: text.length,
    );
    final cooperative = await ReaderPagination.paginateCooperatively(
      blocks,
      settings,
      viewportWidth: viewport.width,
      viewportHeight: height,
      engineChars: text.length,
      yieldFrame: yieldFrame,
    );

    expect(yields, greaterThan(0));
    expect(cooperative.length, synchronous.length);
    expect(
      [for (final page in cooperative) page.startOffset],
      [for (final page in synchronous) page.startOffset],
    );
    expect(
      [
        for (final page in cooperative)
          for (final block in page.blocks)
            if (block is TextBlock) block.plainText,
      ].join(),
      text,
    );
  });

  testWidgets(
    'margin range changes text pagination without changing its model',
    (tester) async {
      final narrowMargins = ReaderSettingsData(
        fontFamily: 'System',
        fontSizePx: 18,
        lineHeight: 1.5,
        marginPx: 8,
        alignment: 'start',
        theme: 'light',
      );
      final wideMargins = ReaderSettingsData(
        fontFamily: 'System',
        fontSizePx: 18,
        lineHeight: 1.5,
        marginPx: 96,
        alignment: 'start',
        theme: 'light',
      );
      const viewport = Size(360, 640);
      final block = TextBlock(
        kind: 'p',
        parts: [
          SpanPart(List.filled(500, 'Margin affects line wrapping. ').join()),
        ],
      );
      final viewportHeight = ReaderPagination.paginationViewportHeight(
        viewport.height,
      );

      final widePageCount = ReaderPagination.countPages(
        [block],
        narrowMargins,
        viewportWidth: viewport.width,
        viewportHeight: viewportHeight,
        engineChars: 0,
      );
      final narrowPageCount = ReaderPagination.countPages(
        [block],
        wideMargins,
        viewportWidth: viewport.width,
        viewportHeight: viewportHeight,
        engineChars: 0,
      );

      expect(narrowPageCount, greaterThan(widePageCount));
    },
  );

  test('font size endpoints produce matching page layouts', () {
    ReaderSettingsData settings(int fontSizePx) => ReaderSettingsData(
      fontFamily: 'System',
      fontSizePx: fontSizePx,
      lineHeight: 1.5,
      marginPx: 48,
      alignment: 'start',
      theme: 'light',
    );

    const viewport = Size(360, 720);
    final blocks = [
      for (var i = 0; i < 24; i++)
        TextBlock(
          kind: 'p',
          parts: [
            SpanPart(
              List.filled(48, 'Font size changes every measured line. ').join(),
            ),
          ],
        ),
    ];
    final usableHeight =
        ReaderPagination.paginationViewportHeight(viewport.height) - 42;
    final smallPages = ReaderPagination.paginate(
      blocks,
      settings(12),
      viewportWidth: viewport.width,
      viewportHeight: ReaderPagination.paginationViewportHeight(
        viewport.height,
      ),
      engineChars: 0,
    );
    final largePages = ReaderPagination.paginate(
      blocks,
      settings(32),
      viewportWidth: viewport.width,
      viewportHeight: ReaderPagination.paginationViewportHeight(
        viewport.height,
      ),
      engineChars: 0,
    );

    expect(largePages.length, greaterThan(smallPages.length));

    for (final page in largePages) {
      var usedHeight = 0.0;
      for (var i = 0; i < page.blocks.length; i++) {
        if (i > 0) usedHeight += 12;
        final block = page.blocks[i] as TextBlock;
        final painter = TextPainter(
          text: TextSpan(
            text: block.plainText,
            style: ReaderPagination.styleForBlock(
              block,
              settings(32),
              const Color(0xFF111111),
            ),
          ),
          textAlign: TextAlign.start,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: viewport.width - 96);
        usedHeight += painter.height;
      }
      expect(usedHeight, lessThanOrEqualTo(usableHeight + 0.1));
    }
  });

  testWidgets('maximum font pages fit the actual rich text page layout', (
    tester,
  ) async {
    ReaderSettingsData settings(int fontSizePx) => ReaderSettingsData(
      fontFamily: 'System',
      fontSizePx: fontSizePx,
      lineHeight: 1.5,
      marginPx: 48,
      alignment: 'start',
      theme: 'light',
    );

    const viewport = Size(360, 720);
    final baseTheme = ThemeData(
      platform: TargetPlatform.android,
      useMaterial3: true,
    );
    final readerTheme = baseTheme.copyWith(
      textTheme: baseTheme.textTheme.copyWith(
        bodyMedium: baseTheme.textTheme.bodyMedium?.copyWith(height: 1.35),
      ),
    );
    TextStyle? inheritedReaderStyle;
    final blocks = [
      TextBlock(kind: 'h1', parts: [SpanPart('Büyük Punto Başlığı')]),
      TextBlock(
        kind: 'p',
        parts: [
          SpanPart(
            List.filled(90, 'Normal metin uzun satır düzenini sınar. ').join(),
          ),
          SpanPart('Kalın metin satır ölçümünü etkiler. ', bold: true),
          SpanPart(
            List.filled(
              90,
              'Devam eden paragraf sayfa sınırlarını aşar. ',
            ).join(),
          ),
          SpanPart('Eğik metin de ölçüme katılır. ', italic: true),
        ],
      ),
      TextBlock(
        kind: 'li',
        parts: [
          SpanPart(
            List.filled(80, 'Uzun liste öğesi de doğru sarmalanmalı. ').join(),
          ),
        ],
      ),
    ];
    final maximumPages = ReaderPagination.paginate(
      blocks,
      settings(32),
      viewportWidth: viewport.width,
      viewportHeight: ReaderPagination.paginationViewportHeight(
        viewport.height,
      ),
      engineChars: 0,
    );

    expect(maximumPages.length, greaterThan(1));
    final readerStyle = ReaderPagination.styleForBlock(
      blocks[1],
      settings(32),
      const Color(0xFF111111),
    );
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final page in maximumPages) {
      await tester.pumpWidget(
        MaterialApp(
          theme: readerTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                inheritedReaderStyle = DefaultTextStyle.of(context).style;
                return SizedBox(
                  width: viewport.width,
                  height: viewport.height,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(48, 88, 48, 88),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < page.blocks.length; i++)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: i == page.blocks.length - 1 ? 0 : 12,
                            ),
                            child: _renderReaderTextBlock(
                              page.blocks[i] as TextBlock,
                              settings(32),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      expect(readerStyle.letterSpacing, inheritedReaderStyle?.letterSpacing);
      expect(
        readerStyle.leadingDistribution,
        inheritedReaderStyle?.leadingDistribution,
      );
      expect(tester.takeException(), isNull);
    }
  });
}

Widget _renderReaderTextBlock(TextBlock block, ReaderSettingsData settings) {
  final style = ReaderPagination.styleForBlock(
    block,
    settings,
    const Color(0xFF111111),
  );
  final text = Text.rich(
    TextSpan(
      children: [
        for (final part in block.parts)
          TextSpan(
            text: part.text,
            style: style.copyWith(
              fontWeight: part.bold ? FontWeight.bold : null,
              fontStyle: part.italic ? FontStyle.italic : null,
            ),
          ),
      ],
    ),
    textAlign: TextAlign.start,
  );
  if (block.kind != 'li') return text;
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('•', style: style),
      const SizedBox(width: 8),
      Expanded(child: text),
    ],
  );
}
