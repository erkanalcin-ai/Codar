import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;

import 'package:codar/src/db/models.dart';
import 'package:codar/src/rust/frb_generated.dart/reader/content.dart';
import 'package:flutter/painting.dart';

/// Bounded process-local cache for exact per-section page counts.
/// It retains compact fingerprints and counts, never section content.
class ReaderPageCountCache {
  ReaderPageCountCache({this.capacity = 512}) {
    if (capacity < 1) throw ArgumentError.value(capacity, 'capacity');
  }

  final int capacity;
  final LinkedHashMap<String, int> _counts = LinkedHashMap();

  int? get(String key) {
    final count = _counts.remove(key);
    if (count != null) _counts[key] = count;
    return count;
  }

  void put(String key, int pageCount) {
    if (pageCount < 0) throw ArgumentError.value(pageCount, 'pageCount');
    _counts.remove(key);
    _counts[key] = pageCount;
    while (_counts.length > capacity) {
      _counts.remove(_counts.keys.first);
    }
  }

  void clear() => _counts.clear();

  static String keyFor({
    required String bookId,
    required int sectionIndex,
    required SectionContent content,
    required ReaderSettingsData settings,
    required double viewportWidth,
    required double viewportHeight,
    required int engineChars,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final sink = _SectionFingerprintSink();
    final encoder = utf8.encoder.startChunkedConversion(sink);

    void add(String value) {
      encoder.add('${value.length}:');
      var start = 0;
      while (start < value.length) {
        var end = math.min(start + 8192, value.length);
        if (end < value.length) {
          final last = value.codeUnitAt(end - 1);
          if (last >= 0xD800 && last <= 0xDBFF) end--;
        }
        encoder.add(value.substring(start, end));
        start = end;
      }
      encoder.add(';');
    }

    add('reader-page-count-v2');
    add(bookId);
    add('$sectionIndex');
    add(content.index.toString());
    add(content.html);
    add(content.plainText);
    add(content.charCount.toString());
    for (final image in content.images) {
      add('image');
      add(image.source);
      add(image.mimeType);
      add('${image.pixelWidth}');
      add('${image.pixelHeight}');
      add(image.dataFormat);
      add('${image.left}');
      add('${image.top}');
      add('${image.displayWidth}');
      add('${image.displayHeight}');
      add('${image.pageWidth}');
      add('${image.pageHeight}');
      add('${image.rotationDegrees}');
    }
    add(settings.fontFamily);
    add('${settings.fontSizePx}');
    add('${settings.lineHeight}');
    add('${settings.marginPx}');
    add(settings.alignment);
    add('$viewportWidth');
    add('$viewportHeight');
    add('$engineChars');
    _addTextScaler(add, textScaler, settings);
    encoder.close();
    return sink.finish();
  }

  /// Cache identity for an exact page count when the book's stable ID already
  /// identifies its imported bytes. This lets callers reuse the count before
  /// fetching and serializing an unopened section from the Rust session.
  static String layoutKeyFor({
    required String bookId,
    required int sectionIndex,
    required ReaderSettingsData settings,
    required double viewportWidth,
    required double viewportHeight,
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final sink = _SectionFingerprintSink();
    final encoder = utf8.encoder.startChunkedConversion(sink);
    for (final value in [
      'reader-page-count-layout-v2',
      bookId,
      '$sectionIndex',
      settings.fontFamily,
      '${settings.fontSizePx}',
      '${settings.lineHeight}',
      '${settings.marginPx}',
      settings.alignment,
      '$viewportWidth',
      '$viewportHeight',
    ]) {
      encoder.add('${value.length}:$value;');
    }
    final baseSize = settings.fontSizePx
        .toDouble()
        .clamp(12.0, 40.0)
        .toDouble();
    for (final size in [
      baseSize,
      baseSize * 1.2,
      baseSize * 1.35,
      baseSize * 1.5,
    ]) {
      final value = '${textScaler.scale(size)}';
      encoder.add('${value.length}:$value;');
    }
    encoder.close();
    return sink.finish();
  }

  static void _addTextScaler(
    void Function(String) add,
    TextScaler textScaler,
    ReaderSettingsData settings,
  ) {
    final baseSize = settings.fontSizePx
        .toDouble()
        .clamp(12.0, 40.0)
        .toDouble();
    for (final size in [
      baseSize,
      baseSize * 1.2,
      baseSize * 1.35,
      baseSize * 1.5,
    ]) {
      add('${textScaler.scale(size)}');
    }
  }
}

final readerPageCountCache = ReaderPageCountCache();

class _SectionFingerprintSink implements Sink<List<int>> {
  var _first = 0x811c9dc5;
  var _second = 0x9e3779b9;
  var _length = 0;

  @override
  void add(List<int> bytes) {
    for (final value in bytes) {
      final byte = value & 0xff;
      _first = ((_first ^ byte) * 0x01000193) & 0xffffffff;
      _second = ((_second ^ (byte ^ 0xa5)) * 0x01000193) & 0xffffffff;
      _length++;
    }
  }

  @override
  void close() {}

  String finish() =>
      '${_first.toRadixString(16).padLeft(8, '0')}'
      '${_second.toRadixString(16).padLeft(8, '0')}'
      '_${_length.toRadixString(16)}';
}
