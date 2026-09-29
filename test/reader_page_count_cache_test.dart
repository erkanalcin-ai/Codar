import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/page_count_cache.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart';
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
  }) => ReaderPageCountCache.keyFor(
    bookId: 'book-1',
    sectionIndex: 0,
    content: content(text: text),
    settings: readerSettings ?? settings(),
    viewportWidth: width,
    viewportHeight: 600,
    engineChars: text.length,
  );

  test('page count cache key changes with section content and layout', () {
    final base = key();
    expect(key(), base);
    expect(key(text: 'different source text'), isNot(base));
    expect(key(readerSettings: settings(size: 30)), isNot(base));
    expect(key(readerSettings: settings(margin: 80)), isNot(base));
    expect(key(width: 400), isNot(base));
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
}
