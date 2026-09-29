import 'package:codar/src/reader/reader_reflow_coalescer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'layout slider defers work and emits only the latest reflow revision',
    () {
      final coalescer = ReaderReflowCoalescer();
      coalescer.beginInteraction();

      expect(coalescer.request(1), isNull);
      expect(coalescer.request(2), isNull);
      expect(coalescer.request(3), isNull);
      expect(coalescer.endInteraction(), 3);
      expect(coalescer.request(4), 4);
      expect(coalescer.endInteraction(), isNull);
    },
  );
}
