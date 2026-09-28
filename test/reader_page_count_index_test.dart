import 'package:codar/src/reader/page_count_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('book page numbers stay stable as sections are materialized lazily', () {
    final counts = ReaderPageCountIndex([48, 52, 96, 188]);
    var loadedPageCount = 1;

    expect(counts.totalPages, 384);
    expect(counts.pageIndexFor(0, 0), 0);
    expect(counts.pageIndexFor(1, 0), 48);
    expect(counts.pageIndexFor(2, 0), 100);
    expect(counts.pageIndexFor(3, 187), 383);

    loadedPageCount = 8;
    expect(loadedPageCount, lessThan(counts.totalPages));
    expect(counts.totalPages, 384);
    expect(counts.pageIndexFor(2, 50), 150);
  });

  test('local page indexes are bounded by their section pagination', () {
    final counts = ReaderPageCountIndex([2, 3]);

    expect(counts.pageIndexFor(0, 20), 1);
    expect(counts.pageIndexFor(1, -4), 2);
    expect(counts.totalPages, 5);
  });

  test('empty EPUB spine sections do not add reader pages', () {
    final counts = ReaderPageCountIndex([0, 2, 0, 3]);

    expect(counts.totalPages, 5);
    expect(counts.pageIndexFor(0, 0), 0);
    expect(counts.pageIndexFor(1, 0), 0);
    expect(counts.pageIndexFor(2, 0), 2);
    expect(counts.pageIndexFor(3, 2), 4);
  });
}
