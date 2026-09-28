/// Stable book-wide page numbering from each section's actual paginated size.
///
/// This is deliberately independent of the reader's lazy page list: a section
/// can contribute its known page count while none of its page widgets exist.
class ReaderPageCountIndex {
  factory ReaderPageCountIndex(Iterable<int> sectionPageCounts) {
    final counts = List<int>.unmodifiable(sectionPageCounts);
    if (counts.isEmpty || counts.any((count) => count < 0)) {
      throw ArgumentError.value(
        counts,
        'sectionPageCounts',
        'Section page counts cannot be negative.',
      );
    }
    final starts = _buildSectionStarts(counts);
    if (starts.last + counts.last < 1) {
      throw ArgumentError.value(
        counts,
        'sectionPageCounts',
        'The book must contain at least one reader page.',
      );
    }
    return ReaderPageCountIndex._(counts, starts);
  }

  const ReaderPageCountIndex._(
    this.sectionPageCounts,
    this._sectionStartPageIndexes,
  );

  final List<int> sectionPageCounts;
  final List<int> _sectionStartPageIndexes;

  static List<int> _buildSectionStarts(Iterable<int> sectionPageCounts) {
    final starts = <int>[];
    var total = 0;
    for (final count in sectionPageCounts) {
      starts.add(total);
      total += count;
    }
    return List<int>.unmodifiable(starts);
  }

  int get totalPages =>
      sectionPageCounts.fold<int>(0, (total, count) => total + count);

  /// Returns a zero-based book page index for a section and its local page.
  int pageIndexFor(int sectionIndex, int sectionPageIndex) {
    RangeError.checkValueInInterval(
      sectionIndex,
      0,
      sectionPageCounts.length - 1,
      'sectionIndex',
    );
    final sectionPageCount = sectionPageCounts[sectionIndex];
    if (sectionPageCount == 0) {
      return _sectionStartPageIndexes[sectionIndex]
          .clamp(0, totalPages - 1)
          .toInt();
    }
    final localPageIndex = sectionPageIndex
        .clamp(0, sectionPageCount - 1)
        .toInt();
    return _sectionStartPageIndexes[sectionIndex] + localPageIndex;
  }
}
