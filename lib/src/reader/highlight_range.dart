class HighlightRange {
  const HighlightRange(this.start, this.end);

  final int start;
  final int end;
}

class HighlightColorRange extends HighlightRange {
  const HighlightColorRange(super.start, super.end, this.color);

  final int color;
}

/// Returns the one color that continuously covers [selection]. Partial or
/// mixed-color ranges return null; gaps are never treated as covered.
int? uniformHighlightColor(
  HighlightRange selection,
  Iterable<HighlightColorRange> highlights,
) {
  if (selection.start >= selection.end) return null;
  final overlaps =
      highlights
          .where(
            (item) => item.start < selection.end && item.end > selection.start,
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  var cursor = selection.start;
  int? color;
  for (final item in overlaps) {
    if (item.start > cursor) return null;
    if (color != null && color != item.color) return null;
    color = item.color;
    if (item.end > cursor) cursor = item.end;
    if (cursor >= selection.end) return color;
  }
  return null;
}

/// Returns the unpainted portions of [highlight] after [selection] is cleared.
List<HighlightRange> subtractHighlightRange(
  HighlightRange highlight,
  HighlightRange selection,
) {
  if (highlight.start >= highlight.end || selection.start >= selection.end) {
    return const [];
  }
  final start = highlight.start > selection.start
      ? highlight.start
      : selection.start;
  final end = highlight.end < selection.end ? highlight.end : selection.end;
  if (start >= end) return [highlight];

  return [
    if (highlight.start < start) HighlightRange(highlight.start, start),
    if (end < highlight.end) HighlightRange(end, highlight.end),
  ];
}
