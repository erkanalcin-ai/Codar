import 'package:codar/src/reader/page_count_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('partial section counts never produce an estimated total', () {
    final counts = ReaderPageCountAccumulator(4);

    counts.record(2, 96);
    expect(counts.isComplete, isFalse);
    expect(counts.exactIndex, isNull);

    counts.record(0, 48);
    counts.record(1, 52);
    expect(counts.exactIndex, isNull);

    counts.record(3, 188);
    expect(counts.isComplete, isTrue);
    expect(counts.exactIndex!.totalPages, 384);
    expect(counts.exactIndex!.pageIndexFor(2, 50), 150);
  });

  test('an exact empty-section count is distinct from an unknown count', () {
    final counts = ReaderPageCountAccumulator(3);
    counts.record(0, 0);
    counts.record(1, 2);

    expect(counts.countFor(0), 0);
    expect(counts.countFor(2), isNull);
    expect(counts.exactIndex, isNull);

    counts.record(2, 3);
    expect(counts.exactIndex!.totalPages, 5);
  });

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
