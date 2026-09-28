import 'package:codar/src/db/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reader brightness survives settings serialization', () {
    final settings = ReaderSettingsData.fromMap({
      'font_family': 'Literata',
      'font_size_px': 19,
      'line_height': 1.6,
      'margin_px': 42,
      'alignment': 'end',
      'theme': 'sepia',
      'brightness': .37,
    });

    expect(settings.brightness, .37);
    expect(settings.toMap()['brightness'], .37);
  });

  test('quote model preserves long text without an application cap', () {
    final text = List.filled(240, 'Uzun alıntı').join(' ');
    final quote = QuoteRecord.fromMap({
      'id': 4,
      'book_id': 'book',
      'section_index': 2,
      'char_offset': 12,
      'cfi': 'cfi',
      'quoted_text': text,
      'created_at': 50,
    });

    expect(quote.quotedText, text);
    expect(quote.quotedText.length, greaterThan(1000));
  });
}
