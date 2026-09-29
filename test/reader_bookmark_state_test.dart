import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/reader_bookmark_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bookmark location toggles without duplicate page entries', () {
    final state = ReaderBookmarkState();
    final existing = BookmarkRecord(
      id: 1,
      bookId: 'book',
      sectionIndex: 2,
      cfi: 'first',
      charOffset: 90,
      label: 'page',
    );
    final duplicate = BookmarkRecord(
      id: 2,
      bookId: 'book',
      sectionIndex: 2,
      cfi: 'duplicate',
      charOffset: 90,
      label: 'page',
    );

    state.restore([existing, duplicate]);
    expect(state.contains(2, 90), isTrue);
    state.remove(2, 90);
    expect(state.contains(2, 90), isFalse);
    state.add(2, 90);
    state.add(2, 90);
    expect(state.contains(2, 90), isTrue);
    expect(state.contains(2, 91), isFalse);
  });
}
