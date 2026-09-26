import 'dart:io';

import 'package:codar/src/library/book_id.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('streamed file identity matches the in-memory identity', () async {
    final bytes = List<int>.generate(300000, (index) => index % 251);
    final file = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}'
      'codar_book_id_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    try {
      await file.writeAsBytes(bytes, flush: true);
      expect(await stableBookIdFromFile(file), stableBookId(bytes));
    } finally {
      if (await file.exists()) await file.delete();
    }
  });
}
