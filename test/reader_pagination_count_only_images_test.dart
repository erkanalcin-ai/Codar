import 'dart:typed_data';

import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/reader_pagination.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('count-only image descriptors preserve render pagination', () {
    final renderedContent = _content(
      html: '<p>Before image</p><img src="chapter/figure.jpg"><p>After</p>',
      images: [
        SectionImage(
          source: 'chapter/figure.jpg',
          mimeType: 'image/jpeg',
          data: Uint8List.fromList([1, 2, 3, 4]),
          pixelWidth: 0,
          pixelHeight: 0,
          dataFormat: 'encoded',
          left: 0,
          top: 0,
          displayWidth: 0,
          displayHeight: 0,
          pageWidth: 0,
          pageHeight: 0,
          rotationDegrees: 0,
        ),
      ],
    );
    final countContent = _content(
      html: renderedContent.html,
      images: [
        SectionImage(
          source: 'chapter/figure.jpg',
          mimeType: 'image/jpeg',
          data: Uint8List(0),
          pixelWidth: 0,
          pixelHeight: 0,
          dataFormat: 'encoded',
          left: 0,
          top: 0,
          displayWidth: 0,
          displayHeight: 0,
          pageWidth: 0,
          pageHeight: 0,
          rotationDegrees: 0,
        ),
      ],
    );

    final renderedBlocks = ReaderPagination.parseSectionContent(
      renderedContent,
    );
    final countBlocks = ReaderPagination.parseSectionContent(
      countContent,
      countOnlyImages: true,
    );
    expect(renderedBlocks.whereType<ImageBlock>(), hasLength(1));
    expect(countBlocks.whereType<ImageBlock>(), hasLength(1));
    expect(
      ReaderPagination.countPages(
        countBlocks,
        _settings,
        viewportWidth: 360,
        viewportHeight: 640,
        engineChars: renderedContent.charCount.toInt(),
      ),
      ReaderPagination.countPages(
        renderedBlocks,
        _settings,
        viewportWidth: 360,
        viewportHeight: 640,
        engineChars: renderedContent.charCount.toInt(),
      ),
    );
  });

  test('count-only parsing keeps embedded data images as image blocks', () {
    const html =
        '<p>Before</p><img src="data:image/png;base64,AA=="><p>After</p>';
    final rendered = parseSectionHtml(html);
    final countOnly = parseSectionHtml(html, countOnlyImages: true);

    expect(rendered.whereType<ImageBlock>(), hasLength(1));
    expect(countOnly.whereType<ImageBlock>(), hasLength(1));
  });
}

final _settings = ReaderSettingsData(
  fontFamily: 'System',
  fontSizePx: 18,
  lineHeight: 1.5,
  marginPx: 48,
  alignment: 'start',
  theme: 'light',
);

SectionContent _content({
  required String html,
  required List<SectionImage> images,
}) => SectionContent(
  index: BigInt.zero,
  idref: 'section',
  href: 'chapter.xhtml',
  html: html,
  plainText: 'Before imageAfter',
  charCount: BigInt.from('Before imageAfter'.length),
  images: images,
);
