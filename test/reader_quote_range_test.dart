import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/quote_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('saved quote resolves at its anchored repeated-text occurrence', () {
    const base = 10;
    final block = _mappedBlock('target / target', base);
    final quote = QuoteRecord.fromMap({
      'id': 5,
      'book_id': 'book',
      'section_index': 0,
      'char_offset': base + 9,
      'cfi': 'epubcfi(test)',
      'quoted_text': 'target',
      'created_at': 1,
    });

    final range = ReaderQuoteRangeResolver.resolve(quote, [block]);

    expect(range?.start, base + 9);
    expect(range?.end, base + 15);
  });

  test(
    'saved quote range handles trimmed whitespace and supplementary text',
    () {
      const base = 20;
      final block = _mappedBlock(' target 😀', base);
      final quote = _quote(start: base, text: 'target 😀');

      final range = ReaderQuoteRangeResolver.resolve(quote, [block]);

      expect(range?.start, base + 1);
      expect(range?.end, base + 9);
    },
  );

  test('quote spanning rendered blocks includes the synthetic line break', () {
    final first = _mappedBlock('one', 40);
    final second = _mappedBlock('two', 43);
    final quote = _quote(start: 40, text: 'one\ntwo');

    final range = ReaderQuoteRangeResolver.resolve(quote, [first, second]);

    expect(range?.start, 40);
    expect(range?.end, 46);
  });

  test('unmatched saved quote is not painted approximately', () {
    final block = _mappedBlock('different text', 0);
    final quote = _quote(start: 0, text: 'not here');

    expect(ReaderQuoteRangeResolver.resolve(quote, [block]), isNull);
  });
  test('saved quote segments resolve in each section without duplication', () {
    final quote = QuoteRecord(
      id: 7,
      bookId: 'book',
      sectionIndex: 2,
      charOffset: 40,
      cfi: 'epubcfi(test)',
      quotedText: 'alpha\nbeta',
      ranges: const [
        QuoteRangeRecord(sectionIndex: 2, startOffset: 40, endOffset: 45),
        QuoteRangeRecord(sectionIndex: 3, startOffset: 0, endOffset: 4),
      ],
    );

    final firstSection = ReaderQuoteRangeResolver.rangesForSection(quote, 2, [
      _mappedBlock('alpha', 40),
    ]);
    expect(firstSection, hasLength(1));
    expect(firstSection.single.start, 40);
    expect(firstSection.single.end, 45);
    final secondSection = ReaderQuoteRangeResolver.rangesForSection(quote, 3, [
      _mappedBlock('beta', 0),
    ]);
    expect(secondSection, hasLength(1));
    expect(secondSection.single.start, 0);
    expect(secondSection.single.end, 4);
    expect(
      ReaderQuoteRangeResolver.rangesForSection(quote, 4, [
        _mappedBlock('alpha', 40),
      ]),
      isEmpty,
    );
  });

  test('legacy quote remains resolvable from its original section anchor', () {
    final quote = _quote(start: 20, text: 'target');
    final blocks = [_mappedBlock('target', 20)];

    final legacy = ReaderQuoteRangeResolver.rangesForSection(quote, 0, blocks);
    expect(legacy, hasLength(1));
    expect(legacy.single.start, 20);
    expect(legacy.single.end, 26);
    expect(
      ReaderQuoteRangeResolver.rangesForSection(quote, 1, blocks),
      isEmpty,
    );
  });
}

QuoteRecord _quote({required int start, required String text}) => QuoteRecord(
  bookId: 'book',
  sectionIndex: 0,
  charOffset: start,
  cfi: 'epubcfi(test)',
  quotedText: text,
);

TextBlock _mappedBlock(String text, int sourceStart) {
  final starts = <int>[];
  final ends = <int>[];
  var scalar = sourceStart;
  for (final rune in text.runes) {
    final width = rune > 0xffff ? 2 : 1;
    for (var i = 0; i < width; i++) {
      starts.add(scalar);
      ends.add(scalar + 1);
    }
    scalar++;
  }
  return TextBlock(
    kind: 'p',
    parts: [SpanPart(text)],
    sourceStartOffsets: starts,
    sourceEndOffsets: ends,
  );
}
