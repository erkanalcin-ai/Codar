import 'package:codar/src/db/models.dart';

class ReaderBookmarkLocation {
  const ReaderBookmarkLocation(this.sectionIndex, this.charOffset);

  final int sectionIndex;
  final int charOffset;

  @override
  bool operator ==(Object other) =>
      other is ReaderBookmarkLocation &&
      other.sectionIndex == sectionIndex &&
      other.charOffset == charOffset;

  @override
  int get hashCode => Object.hash(sectionIndex, charOffset);
}

class ReaderBookmarkState {
  final Set<ReaderBookmarkLocation> _locations = {};

  bool contains(int sectionIndex, int charOffset) =>
      _locations.contains(ReaderBookmarkLocation(sectionIndex, charOffset));

  void restore(Iterable<BookmarkRecord> bookmarks) {
    _locations
      ..clear()
      ..addAll(
        bookmarks.map(
          (bookmark) => ReaderBookmarkLocation(
            bookmark.sectionIndex,
            bookmark.charOffset,
          ),
        ),
      );
  }

  void add(int sectionIndex, int charOffset) {
    _locations.add(ReaderBookmarkLocation(sectionIndex, charOffset));
  }

  void remove(int sectionIndex, int charOffset) {
    _locations.remove(ReaderBookmarkLocation(sectionIndex, charOffset));
  }
}
