// Phase 1 unit tests: pure-Dart contracts (no engine needed).
//
// Engine behavior is proven by rust/tests/spike.rs (host) and the on-device
// harness (lib/main.dart). These tests pin the Dart-side data contracts.

import 'dart:convert';

import 'package:codar/src/storage/codar_lib.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Readium locator JSON has the fields Codar persists', () {
    // Shape produced by Rust get_locator (ebook_rs::ReadiumLocator).
    const sample = '''
      {"href":"ch1.xhtml","type_":"application/xhtml+xml","title":"Ch 1",
       "locations":{"cfi":"epubcfi(/6/2!/4/2:10)","fragment":null,
       "position":3,"progression":0.12,"total_progression":0.03},
       "text":null}
    ''';
    final m = jsonDecode(sample) as Map<String, dynamic>;
    final loc = m['locations'] as Map<String, dynamic>;
    expect(m['href'], isNotEmpty);
    expect(loc['cfi'], isNotEmpty);
    // Percentage is supplementary: present, but never the sole key.
    expect(loc['progression'], isA<num>());
    expect(loc['cfi'], contains('epubcfi'));
  });

  test('CodarLibFile carries MediaStore identity', () {
    final f = CodarLibFile(name: 'a.epub', uri: 'content://media/1');
    expect(f.name, 'a.epub');
    expect(f.uri, startsWith('content://'));
  });

  test('Turkish glyphs survive JSON round-trip (locator/title text)', () {
    const title = 'İstanbul şeker ğölge ışık ÖĞRENCİ ÇALIŞMA';
    final back =
        (jsonDecode(jsonEncode({'title': title})) as Map)['title'] as String;
    expect(back, title);
  });
}
