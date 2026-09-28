import 'package:codar/src/reader/highlight_range.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('clearing the whole highlighted range leaves no paint', () {
    expect(
      subtractHighlightRange(
        const HighlightRange(10, 20),
        const HighlightRange(10, 20),
      ),
      isEmpty,
    );
  });

  test('clearing part of a highlight preserves the remaining ranges', () {
    expect(
      subtractHighlightRange(
        const HighlightRange(10, 30),
        const HighlightRange(16, 24),
      ).map((range) => (range.start, range.end)),
      [(10, 16), (24, 30)],
    );
    expect(
      subtractHighlightRange(
        const HighlightRange(10, 30),
        const HighlightRange(5, 16),
      ).map((range) => (range.start, range.end)),
      [(16, 30)],
    );
  });

  test('a selection outside a highlight does not alter it', () {
    const highlight = HighlightRange(10, 20);
    expect(
      subtractHighlightRange(
        highlight,
        const HighlightRange(20, 25),
      ).map((range) => (range.start, range.end)),
      [(10, 20)],
    );
  });

  test('same-color selection is active only when coverage is complete', () {
    const yellow = 1;
    const green = 2;
    expect(
      uniformHighlightColor(const HighlightRange(12, 18), const [
        HighlightColorRange(10, 20, yellow),
      ]),
      yellow,
    );
    expect(
      uniformHighlightColor(const HighlightRange(12, 18), const [
        HighlightColorRange(10, 15, yellow),
        HighlightColorRange(15, 20, yellow),
      ]),
      yellow,
    );
    expect(
      uniformHighlightColor(const HighlightRange(12, 18), const [
        HighlightColorRange(10, 15, yellow),
        HighlightColorRange(15, 20, green),
      ]),
      isNull,
    );
    expect(
      uniformHighlightColor(const HighlightRange(12, 18), const [
        HighlightColorRange(12, 15, yellow),
      ]),
      isNull,
    );
  });
}
