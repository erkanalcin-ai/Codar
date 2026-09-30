import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/page_count_cache.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ReaderSettingsData settings({int size = 18, int margin = 48}) =>
      ReaderSettingsData(
        fontFamily: 'System',
        fontSizePx: size,
        lineHeight: 1.5,
        marginPx: margin,
        alignment: 'start',
        theme: 'light',
      );

  SectionContent content({String text = 'reader text'}) => SectionContent(
    index: BigInt.zero,
    idref: 'section-0',
    href: 'text/chapter.xhtml',
    html: '<p>$text</p>',
    plainText: text,
    charCount: BigInt.from(text.length),
    images: const [],
  );

  String key({
    String text = 'reader text',
    ReaderSettingsData? readerSettings,
    double width = 360,
    TextScaler textScaler = TextScaler.noScaling,
  }) => ReaderPageCountCache.keyFor(
    bookId: 'book-1',
    sectionIndex: 0,
    content: content(text: text),
    settings: readerSettings ?? settings(),
    viewportWidth: width,
    viewportHeight: 600,
    engineChars: text.length,
    textScaler: textScaler,
  );

  String layoutKey({
    String bookId = 'book-1',
    int sectionIndex = 0,
    ReaderSettingsData? readerSettings,
    double width = 360,
    double height = 600,
    TextScaler textScaler = TextScaler.noScaling,
  }) => ReaderPageCountCache.layoutKeyFor(
    bookId: bookId,
    sectionIndex: sectionIndex,
    settings: readerSettings ?? settings(),
    viewportWidth: width,
    viewportHeight: height,
    textScaler: textScaler,
  );

  test('page count cache key changes with section content and layout', () {
    final base = key();
    expect(key(), base);
    expect(key(text: 'different source text'), isNot(base));
    expect(key(readerSettings: settings(size: 30)), isNot(base));
    expect(key(readerSettings: settings(margin: 80)), isNot(base));
    expect(key(width: 400), isNot(base));
    expect(key(textScaler: TextScaler.noScaling), base);
    expect(key(textScaler: TextScaler.linear(1.3)), isNot(base));
  });

  test('page count cache is bounded and reuses exact keyed counts', () {
    final cache = ReaderPageCountCache(capacity: 2);
    final first = key();
    final second = key(text: 'second source');
    final third = key(text: 'third source');

    cache.put(first, 17);
    expect(cache.get(first), 17);
    cache.put(second, 9);
    cache.put(third, 12);

    expect(cache.get(first), isNull);
    expect(cache.get(second), 9);
    expect(cache.get(third), 12);
  });

  test(
    'layout key allows exact counts to be reused before section retrieval',
    () {
      final base = layoutKey();
      expect(layoutKey(), base);
      expect(layoutKey(bookId: 'another-book'), isNot(base));
      expect(layoutKey(sectionIndex: 1), isNot(base));
      expect(layoutKey(readerSettings: settings(size: 30)), isNot(base));
      expect(layoutKey(readerSettings: settings(margin: 80)), isNot(base));
      expect(layoutKey(width: 400), isNot(base));
      expect(layoutKey(height: 700), isNot(base));
      expect(layoutKey(textScaler: TextScaler.noScaling), base);
      expect(layoutKey(textScaler: TextScaler.linear(1.3)), isNot(base));

      final cache = ReaderPageCountCache();
      cache.put(base, 384);
      expect(cache.get(layoutKey()), 384);
    },
  );
}
