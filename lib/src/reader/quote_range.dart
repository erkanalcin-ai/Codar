import 'package:codar/src/db/models.dart';
import 'package:codar/src/reader/html_blocks.dart';

class ReaderQuoteRange {
  const ReaderQuoteRange({required this.start, required this.end});

  final int start;
  final int end;
}

/// Resolves a saved quote against its anchored section without searching for
/// an unrelated repeated occurrence elsewhere in the book.
class ReaderQuoteRangeResolver {
  const ReaderQuoteRangeResolver._();

  static ReaderQuoteRange? resolve(
    QuoteRecord quote,
    List<ReaderBlock> blocks,
  ) {
    final quoteRunes = quote.quotedText.runes.toList(growable: false);
    if (quoteRunes.isEmpty) return null;

    final units = <_QuoteUnit>[];
    var wroteBlock = false;
    for (final block in blocks) {
      if (block is! TextBlock ||
          block.plainText.isEmpty ||
          block.sourceStartOffsets.length != block.plainText.length ||
          block.sourceEndOffsets.length != block.plainText.length) {
        continue;
      }
      if (wroteBlock) units.add(const _QuoteUnit(0x0a));
      var utf16Offset = 0;
      for (final rune in block.plainText.runes) {
        final width = rune > 0xffff ? 2 : 1;
        var sourceStart = 0x7fffffff;
        var sourceEnd = 0;
        for (var i = utf16Offset; i < utf16Offset + width; i++) {
          final start = block.sourceStartOffsets[i];
          final end = block.sourceEndOffsets[i];
          if (start >= 0 && end > start) {
            if (start < sourceStart) sourceStart = start;
            if (end > sourceEnd) sourceEnd = end;
          }
        }
        units.add(
          _QuoteUnit(
            rune,
            sourceStart == 0x7fffffff ? null : sourceStart,
            sourceEnd == 0 ? null : sourceEnd,
          ),
        );
        utf16Offset += width;
      }
      wroteBlock = true;
    }

    var startIndex = 0;
    while (startIndex < units.length) {
      final unit = units[startIndex];
      if (unit.sourceEnd == null || unit.sourceEnd! <= quote.charOffset) {
        startIndex++;
        continue;
      }
      if (_isWhitespace(unit.rune)) {
        startIndex++;
        continue;
      }
      break;
    }
    if (startIndex >= units.length ||
        units[startIndex].rune != quoteRunes.first) {
      return null;
    }

    var sourceStart = units[startIndex].sourceStart;
    var sourceEnd = units[startIndex].sourceEnd;
    var cursor = startIndex;
    for (final rune in quoteRunes) {
      if (cursor >= units.length || units[cursor].rune != rune) return null;
      final unit = units[cursor];
      if (unit.sourceStart != null && unit.sourceEnd != null) {
        sourceStart ??= unit.sourceStart;
        if (sourceEnd == null || unit.sourceEnd! > sourceEnd) {
          sourceEnd = unit.sourceEnd;
        }
      }
      cursor++;
    }
    if (sourceStart == null || sourceEnd == null || sourceEnd <= sourceStart) {
      return null;
    }
    return ReaderQuoteRange(start: sourceStart, end: sourceEnd);
  }

  static bool _isWhitespace(int rune) =>
      String.fromCharCodes([rune]).trim().isEmpty;
}

class _QuoteUnit {
  const _QuoteUnit(this.rune, [this.sourceStart, this.sourceEnd]);

  final int rune;
  final int? sourceStart;
  final int? sourceEnd;
}
