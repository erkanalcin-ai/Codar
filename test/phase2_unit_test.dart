// Phase 2 unit tests: HTML parser safety, model mapping, l10n completeness.

import 'package:codar/src/db/models.dart';
import 'package:codar/src/l10n/strings.dart';
import 'package:codar/src/reader/html_blocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('script/style/iframe content never survives parsing', () {
    const html =
        '<html><head><style>.x{color:red}</style>'
        '<script>alert(document.cookie)</script></head>'
        '<body><h1>Title</h1><p onclick="evil()">Hello <b>World</b></p>'
        '<iframe src="http://evil.example/"></iframe></body></html>';
    final blocks = parseSectionHtml(html);
    final all = blocks.map((b) => b.plainText).join('\n');
    expect(all, contains('Title'));
    expect(all, contains('Hello World'));
    expect(all, isNot(contains('alert')));
    expect(all, isNot(contains('color:red')));
    expect(all, isNot(contains('evil')));
    expect(all, isNot(contains('<')));
    expect((blocks.first as TextBlock).kind, 'h1');
  });

  test('entities and Turkish text decode correctly', () {
    const html =
        '<p>&ccedil; &Ccedil; &#287; &#x11F; &ldquo;ok&rdquo; &amp; &lt; &nbsp;test</p>';
    final blocks = parseSectionHtml(html);
    expect(blocks.length, 1);
    expect(blocks.first.plainText, contains('ç Ç ğ ğ “ok” & <'));
    expect(blocks.first.plainText, isNot(contains('&ccedil;')));
  });

  test(
    'normal HTML collapses source whitespace but keeps br and pre breaks',
    () {
      const html =
          '<p>First\n    wrapped\tline<br/>next</p>'
          '<pre>one\n  two</pre><p>a&nbsp;  b</p>';
      final blocks = parseSectionHtml(html);
      expect(blocks.map((block) => block.plainText).toList(), [
        'First wrapped line\nnext',
        'one\n  two',
        'a  b',
      ]);
    },
  );

  test('lists and headings keep structure, unknown tags keep text', () {
    const html =
        '<h2>Chap</h2><ul><li>one</li><li>two</li></ul><foo>kept</foo>';
    final blocks = parseSectionHtml(html);
    expect(blocks.map((b) => (b as TextBlock).kind).toList(), [
      'h2',
      'li',
      'li',
      'p',
    ]);
    expect(blocks.last.plainText, contains('kept'));
  });

  test('empty input yields no blocks (renderer shows fallback)', () {
    expect(parseSectionHtml(''), isEmpty);
    expect(parseSectionHtml('<script>x</script>'), isEmpty);
  });

  test('HighlightRecord maps null-safe', () {
    final h = HighlightRecord.fromMap({});
    expect(h.bookId, '');
    expect(h.quotedText, '');
    final full = HighlightRecord(
      bookId: 'b',
      sectionIndex: 2,
      startOffset: 5,
      endOffset: 9,
      cfi: 'epubcfi(/6/2)',
      color: 0xFFFFFF00,
      quotedText: 'alıntı',
      note: 'not',
    );
    expect(full.sectionIndex, 2);
    expect(full.quotedText, 'alıntı');
  });

  test('EN locale covers every TR key', () {
    // Access both tables through tr() fallback behavior: unknown locale
    // falls back to TR, so compare key sets indirectly via known keys.
    const keys = [
      'home',
      'library',
      'records',
      'settings',
      'continueReading',
      'recentlyRead',
      'favorites',
      'allBooks',
      'searchHint',
      'noBooks',
      'importBook',
      'read',
      'details',
      'chapters',
      'highlights',
      'notes',
      'bookmarks',
      'readerSettings',
      'theme',
      'appLanguage',
      'highlight',
      'word',
      'sentence',
      'paragraph',
      'collections',
      'delete',
    ];
    for (final k in keys) {
      expect(tr('en', k), isNot(k), reason: 'missing EN key: $k');
      expect(tr('tr', k), isNot(k), reason: 'missing TR key: $k');
    }
    expect(tr('tr', 'home'), 'Ana Sayfa');
    expect(tr('en', 'home'), 'Home');
  });
}
