import 'dart:io';

/// Stable content identity for imported books.
///
/// Dart's [Object.hashCode] is not a persistence contract. This compact
/// two-lane FNV-1a token is deterministic across processes and platforms and
/// needs no additional dependency.
String stableBookId(Iterable<int> bytes) {
  var first = 0x811c9dc5;
  var second = 0x9e3779b9;
  var length = 0;

  for (final value in bytes) {
    final byte = value & 0xff;
    first = ((first ^ byte) * 0x01000193) & 0xffffffff;
    second = ((second ^ (byte ^ 0xa5)) * 0x01000193) & 0xffffffff;
    length++;
  }

  if (length == 0) {
    throw ArgumentError.value(bytes, 'bytes', 'must not be empty');
  }
  final left = first.toRadixString(16).padLeft(8, '0');
  final right = second.toRadixString(16).padLeft(8, '0');
  return 'b_$left${right}_${length.toRadixString(16)}';
}

/// Computes the same stable identity without keeping a large book in memory.
Future<String> stableBookIdFromFile(File file) async {
  var first = 0x811c9dc5;
  var second = 0x9e3779b9;
  var length = 0;

  await for (final chunk in file.openRead()) {
    for (final value in chunk) {
      final byte = value & 0xff;
      first = ((first ^ byte) * 0x01000193) & 0xffffffff;
      second = ((second ^ (byte ^ 0xa5)) * 0x01000193) & 0xffffffff;
      length++;
    }
  }

  if (length == 0) throw ArgumentError.value(file, 'file', 'must not be empty');
  final left = first.toRadixString(16).padLeft(8, '0');
  final right = second.toRadixString(16).padLeft(8, '0');
  return 'b_$left${right}_${length.toRadixString(16)}';
}
