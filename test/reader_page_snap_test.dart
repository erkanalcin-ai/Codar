import 'package:codar/src/reader/reader_page_snap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snaps to the nearest full page after a vertical fling', () {
    expect(
      readerPageSnapTarget(
        pixels: 2.4 * 800,
        pageExtent: 800,
        minScrollExtent: 0,
        maxScrollExtent: 7 * 800,
      ),
      2 * 800,
    );
    expect(
      readerPageSnapTarget(
        pixels: 2.6 * 800,
        pageExtent: 800,
        minScrollExtent: 0,
        maxScrollExtent: 7 * 800,
      ),
      3 * 800,
    );
  });

  test('clamps the last page and rejects invalid scroll metrics', () {
    expect(
      readerPageSnapTarget(
        pixels: 7.8 * 800,
        pageExtent: 800,
        minScrollExtent: 0,
        maxScrollExtent: 7.5 * 800,
      ),
      7.5 * 800,
    );
    expect(
      readerPageSnapTarget(
        pixels: 0,
        pageExtent: 0,
        minScrollExtent: 0,
        maxScrollExtent: 100,
      ),
      isNull,
    );
  });
}
