import 'package:codar/src/reader/reader_progress_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stored progress display modes round trip with a safe default', () {
    for (final mode in ReaderProgressDisplayMode.values) {
      expect(ReaderProgressDisplayMode.fromStored(mode.storageValue), mode);
    }
    expect(
      ReaderProgressDisplayMode.fromStored(null),
      ReaderProgressDisplayMode.pageAndPercent,
    );
    expect(
      ReaderProgressDisplayMode.fromStored('unknown'),
      ReaderProgressDisplayMode.pageAndPercent,
    );
  });

  test('progress modes select only the requested display fields', () {
    expect(ReaderProgressDisplayMode.pageAndPercent.showsPage, isTrue);
    expect(ReaderProgressDisplayMode.pageAndPercent.showsPercent, isTrue);
    expect(ReaderProgressDisplayMode.pageOnly.showsPercent, isFalse);
    expect(ReaderProgressDisplayMode.percentOnly.showsPage, isFalse);
    expect(ReaderProgressDisplayMode.hidden.showsPage, isFalse);
    expect(ReaderProgressDisplayMode.hidden.showsPercent, isFalse);
  });
}
