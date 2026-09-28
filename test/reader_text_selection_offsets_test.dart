import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:codar/src/reader/reader_pagination.dart';
import 'package:codar/src/reader/text_selection_offsets.dart';
import 'package:flutter_test/flutter_test.dart';

List<TextBlock> _aligned(String html, String rustPlainText) =>
    ReaderTextSelectionOffsets.alignBlocks(
          parseSectionHtml(html),
          rustPlainText,
          sourceHtml: html,
        )
        .whereType<TextBlock>()
        .toList();

void main() {
  test('maps repeated blocks in document order without searching text', () {
    final blocks = _aligned(
      '<p>Echo world</p><p>Echo world</p>',
      'Echo world Echo world',
    );

    expect(ReaderTextSelectionOffsets.sourceRangeFor(blocks[0], 0, 4), (0, 4));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(blocks[1], 0, 4), (11, 15));
  });

  test('maps Flutter UTF-16 ranges to Rust scalar offsets', () {
    final block = _aligned('<p>A😀 café</p>', 'A😀 café').single;

    // The emoji occupies two Dart code units but one Rust scalar.
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 1, 3), (1, 2));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 4, 8), (3, 7));
  });

  test('resolves an unclassified legacy UTF-16 highlight after an emoji', () {
    const source = 'A😀 bc';
    final blocks = _aligned('<p>A😀 bc</p>', source);

    expect(
      ReaderTextSelectionOffsets.resolveStoredHighlightRange(
        source,
        blocks,
        start: 4,
        end: 6,
        quotedText: 'bc',
        offsetUnit: 'unknown',
      ),
      (3, 5),
    );
  });

  test('resolves an unclassified Rust scalar highlight after an emoji', () {
    const source = 'A😀 bc';
    final blocks = _aligned('<p>A😀 bc</p>', source);

    expect(
      ReaderTextSelectionOffsets.resolveStoredHighlightRange(
        source,
        blocks,
        start: 3,
        end: 5,
        quotedText: 'bc',
        offsetUnit: 'unknown',
      ),
      (3, 5),
    );
  });

  test('does not guess when both stored coordinate units fit repeated text', () {
    const source = '😀 aaa';
    final blocks = _aligned('<p>😀 aaa</p>', source);

    // Scalar [3, 5) and UTF-16 [2, 4) both select "aa" here.
    expect(
      ReaderTextSelectionOffsets.resolveStoredHighlightRange(
        source,
        blocks,
        start: 3,
        end: 5,
        quotedText: 'aa',
        offsetUnit: 'unknown',
      ),
      isNull,
    );
  });

  test('converts explicitly marked legacy UTF-16 highlight coordinates', () {
    const source = 'A😀 bc';
    final blocks = _aligned('<p>A😀 bc</p>', source);

    expect(
      ReaderTextSelectionOffsets.resolveStoredHighlightRange(
        source,
        blocks,
        start: 4,
        end: 6,
        quotedText: 'bc',
        offsetUnit: 'utf16',
      ),
      (3, 5),
    );
  });

  test('maps a named entity to its full Rust plain_text scalar span', () {
    const html = '<p>Copyright &copy; 2012</p>';
    const rustText = 'Copyright &copy; 2012';
    final block = _aligned(html, rustText).single;

    expect(block.plainText, 'Copyright © 2012');
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 10, 11), (10, 16));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 12, 16), (17, 21));
    expect(
      ReaderTextSelectionOffsets.renderedTextForRange(
        [block],
        10,
        16,
      ),
      '©',
    );
  });

  test('maps nbsp, decimal and hexadecimal entities independently', () {
    const html = '<p>&copy;&nbsp;&#169;&#xA9;</p>';
    const rustText = '&copy;&nbsp;&#169;&#xA9;';
    final block = _aligned(html, rustText).single;

    expect(block.plainText, '© ©©');
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 0, 1), (0, 6));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 1, 2), (6, 12));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 2, 3), (12, 18));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 3, 4), (18, 24));
    expect(
      ReaderTextSelectionOffsets.renderedTextForRange([block], 6, 12),
      ' ',
    );
  });

  test('maps a numeric astral entity to one Rust scalar and two UTF-16 units', () {
    final block = _aligned('<p>A&#x1F600;B</p>', 'A&#x1F600;B').single;

    expect(block.plainText, 'A😀B');
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 1, 3), (1, 10));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 3, 4), (10, 11));
  });

  test('maps inline tag separators without changing visible quote text', () {
    const html = '<p>foo<em>bar</em>baz</p>';
    final block = _aligned(html, 'foo bar baz').single;

    expect(block.plainText, 'foobarbaz');
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 0, 9), (0, 11));
    expect(
      ReaderTextSelectionOffsets.renderedTextForRange([block], 0, 11),
      'foobarbaz',
    );
  });

  test('maps nested strong, span and anchor tags in source order', () {
    const html =
        '<p>first<strong>bold<span> nested</span></strong>'
        '<a href="book.xhtml#note"> link</a>end</p>';
    final block = _aligned(html, 'first bold nested link end').single;

    expect(block.plainText, 'firstbold nested linkend');
    expect(
      ReaderTextSelectionOffsets.renderedTextForRange(
        [block],
        0,
        'first bold nested link end'.runes.length,
      ),
      'firstbold nested linkend',
    );
    expect(
      ReaderTextSelectionOffsets.sourceRangeFor(block, 0, block.plainText.length),
      (0, 'first bold nested link end'.runes.length),
    );
  });

  test('uses Rust collapsed Unicode whitespace for several rendered spaces', () {
    const html = '<p>one\u2003\u00a0two</p>';
    final block = _aligned(html, 'one two').single;

    expect(block.plainText, 'one\u2003\u00a0two');
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 3, 5), (3, 4));
    expect(
      ReaderTextSelectionOffsets.renderedTextForRange([block], 3, 4),
      '\u2003\u00a0',
    );
  });

  test('maps br and literal boundary whitespace to Rust scalar spans', () {
    final block = _aligned('<p>foo<br/> bar</p>', 'foo bar').single;

    expect(block.plainText, 'foo\n bar');
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 3, 5), (3, 4));
  });

  test('leaves Rust-trimmed leading and trailing block whitespace unmapped', () {
    final block = _aligned('<p>  alpha  </p>', 'alpha').single;

    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 0, 1), isNull);
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 1, 6), (0, 5));
    expect(ReaderTextSelectionOffsets.sourceRangeFor(block, 0, 7), (0, 5));
  });

  test('rejects a plain_text projection mismatch instead of guessing', () {
    expect(
      () => _aligned('<p>Copyright &copy; 2012</p>', 'Copyright © 2012'),
      throwsFormatException,
    );
  });

  test('selection ranges survive three lazy page slices without gaps', () {
    final source = List.generate(
      260,
      (index) => 'word${index % 19}',
    ).join(' ');
    final blocks = _aligned('<p>$source</p>', source);
    final pages = ReaderPagination.paginate(
      blocks,
      ReaderSettingsData(
        fontFamily: 'System',
        fontSizePx: 18,
        lineHeight: 1.5,
        marginPx: 48,
        alignment: 'start',
        theme: 'light',
      ),
      viewportWidth: 176,
      viewportHeight: 260,
      engineChars: source.runes.length,
    );
    expect(pages.length, greaterThanOrEqualTo(3));

    final selectedRanges = [
      for (final page in pages)
        for (final block in page.blocks.whereType<TextBlock>())
          ReaderTextSelectionOffsets.sourceRangeFor(
            block,
            0,
            block.plainText.length,
          )!,
    ];
    expect(selectedRanges.first.$1, 0);
    expect(selectedRanges.last.$2, source.runes.length);
    for (var index = 1; index < selectedRanges.length; index++) {
      expect(
        selectedRanges[index].$1,
        lessThanOrEqualTo(selectedRanges[index - 1].$2 + 1),
        reason: 'pagination must not skip source characters',
      );
    }
    expect(
      (selectedRanges.first.$1, selectedRanges.last.$2),
      (0, source.runes.length),
    );
  });

  test('full selection covers varied paragraphs and their boundaries', () {
    const second = 'A much longer paragraph with several distinct words '
        'and a final phrase.';
    final rustText = 'Short line. $second End.';
    final blocks = _aligned(
      '<p>Short line.</p><p>$second</p><p>End.</p>',
      rustText,
    );

    final ranges = [
      for (final block in blocks)
        ReaderTextSelectionOffsets.sourceRangeFor(
          block,
          0,
          block.plainText.length,
        )!,
    ];
    expect(ranges.first, (0, 11));
    expect(ranges[1], (12, 12 + second.runes.length));
    expect(ranges.last, (13 + second.runes.length, rustText.runes.length));
    expect(
      ReaderTextSelectionOffsets.renderedTextForRange(
        blocks,
        0,
        rustText.runes.length,
      ),
      'Short line.\n$second\nEnd.',
    );
  });
}
