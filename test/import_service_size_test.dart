import 'package:codar/src/library/import_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts observed file size when provider size matches', () {
    expect(validateImportFileSize(128, expectedSize: 128), 128);
  });

  test('accepts unknown provider size after bounded streaming', () {
    expect(validateImportFileSize(128, expectedSize: -1), 128);
    expect(validateImportFileSize(128, expectedSize: 0), 128);
    expect(validateImportFileSize(128), 128);
  });

  test('accepts files at the exact import limit', () {
    expect(
      validateImportFileSize(maxImportBytes, expectedSize: maxImportBytes),
      maxImportBytes,
    );
  });

  test('rejects empty, oversized, and changed sources', () {
    expect(
      () => validateImportFileSize(0, expectedSize: 0),
      throwsA(isA<ImportException>().having((e) => e.code, 'code', 'bad-size')),
    );
    expect(
      () => validateImportFileSize(maxImportBytes + 1),
      throwsA(isA<ImportException>().having((e) => e.code, 'code', 'bad-size')),
    );
    expect(
      () => validateImportFileSize(128, expectedSize: 127),
      throwsA(
        isA<ImportException>().having((e) => e.code, 'code', 'source-changed'),
      ),
    );
  });
}
