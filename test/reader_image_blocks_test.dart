import 'dart:convert';
import 'dart:typed_data';

import 'package:codar/src/reader/html_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pixel =
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADUlEQVR4nGP4z8AAAAMBAQDJ/pLvAAAAAElFTkSuQmCC';

  test('keeps safe inline image data in its original text order', () {
    final blocks = parseSectionHtml(
      '<p>before<img src="data:image/png;base64,$pixel"/>after</p>',
    );

    expect(blocks, hasLength(3));
    expect((blocks[0] as TextBlock).plainText, 'before');
    expect(blocks[1], isA<ImageBlock>());
    expect(
      (blocks[1] as ImageBlock).images.single.data,
      orderedEquals(base64.decode(pixel)),
    );
    expect((blocks[2] as TextBlock).plainText, 'after');
  });

  test('keeps an image-only section as renderable content', () {
    final blocks = parseSectionHtml(
      '<img src="data:image/png;base64,$pixel"/>',
    );

    expect(blocks, hasLength(1));
    expect(blocks.single, isA<ImageBlock>());
  });

  test('resolves local archive images supplied as typed section data', () {
    final image = ReaderImage(
      source: 'OEBPS/images/pixel.png',
      mimeType: 'image/png',
      data: Uint8List.fromList([1, 2, 3]),
    );

    final blocks = parseSectionHtml(
      '<img src="OEBPS/images/pixel.png"/>',
      images: [image],
    );

    expect(blocks, hasLength(1));
    expect((blocks.single as ImageBlock).images.single, same(image));
  });

  test('groups positioned PDF bitmaps into one page block', () {
    final images = [
      ReaderImage(
        source: 'pdf-image-0-0',
        mimeType: 'image/jpeg',
        data: Uint8List.fromList([1]),
        pageWidth: 612,
        pageHeight: 792,
        left: 20,
        top: 30,
        displayWidth: 200,
        displayHeight: 300,
      ),
      ReaderImage(
        source: 'pdf-image-0-1',
        mimeType: 'image/jpeg',
        data: Uint8List.fromList([2]),
        pageWidth: 612,
        pageHeight: 792,
        left: 40,
        top: 50,
        displayWidth: 100,
        displayHeight: 100,
      ),
    ];

    final blocks = parseSectionHtml('<div></div>', images: images);

    expect(blocks, hasLength(1));
    final page = blocks.single as ImageBlock;
    expect(page.isPdfPage, isTrue);
    expect(page.images, hasLength(2));
  });

  test('does not fetch external, malformed, or unsupported image sources', () {
    final blocks = parseSectionHtml(
      '<p>readable</p>'
      '<img src="https://example.test/remote.png"/>'
      '<img src="data:image/svg+xml;base64,PHN2Zy8+"/>'
      '<img src="data:image/png;base64,%%%"/>',
    );

    expect(blocks, hasLength(1));
    expect((blocks.single as TextBlock).plainText, 'readable');
  });

  test('does not render unsupported typed vector resources as bitmaps', () {
    final image = ReaderImage(
      source: 'images/diagram.svg',
      mimeType: 'image/svg+xml',
      data: Uint8List.fromList([1, 2, 3]),
    );

    expect(
      parseSectionHtml('<img src="images/diagram.svg"/>', images: [image]),
      isEmpty,
    );
  });
}
