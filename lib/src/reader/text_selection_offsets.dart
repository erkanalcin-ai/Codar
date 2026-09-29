import 'html_blocks.dart';

/// Maps the reader's rendered UTF-16 positions to the Unicode-scalar positions
/// produced by ebook-rs' `extract_plain_text` implementation.
///
/// The projection follows the extractor's tag-space and whitespace rules and
/// keeps a source index for each emitted scalar. Rendered text is then walked
/// in document order. It is never searched in the section text, so repeated
/// phrases cannot select a later occurrence accidentally.
class ReaderTextSelectionOffsets {
  const ReaderTextSelectionOffsets._();

  static List<ReaderBlock> alignBlocks(
    List<ReaderBlock> blocks,
    String sourceText, {
    required String sourceHtml,
  }) {
    final source = _extractRustPlainText(sourceHtml);
    if (source.text != sourceText) {
      throw FormatException(
        'Rendered source projection does not match Rust plain_text',
        sourceHtml,
      );
    }

    var cursor = 0;
    final result = <ReaderBlock>[];
    for (final block in blocks) {
      if (block is! TextBlock) {
        result.add(block);
        continue;
      }

      final text = block.plainText;
      final starts = List<int>.filled(text.length, -1);
      final ends = List<int>.filled(text.length, -1);
      final runes = text.runes.toList(growable: false);
      var leadingWhitespace = 0;
      while (leadingWhitespace < runes.length &&
          _isUnicodeWhitespace(runes[leadingWhitespace])) {
        leadingWhitespace++;
      }
      var trailingWhitespace = runes.length;
      while (trailingWhitespace > leadingWhitespace &&
          _isUnicodeWhitespace(runes[trailingWhitespace - 1])) {
        trailingWhitespace--;
      }

      var utf16Offset = 0;
      var previousRenderedWhitespace = false;
      _SourceMatch? collapsedWhitespaceMatch;
      for (var runeIndex = 0; runeIndex < runes.length; runeIndex++) {
        final rune = runes[runeIndex];
        final width = rune > 0xffff ? 2 : 1;
        final isWhitespace = _isUnicodeWhitespace(rune);
        final reuseCollapsedWhitespace =
            isWhitespace &&
            previousRenderedWhitespace &&
            collapsedWhitespaceMatch != null;
        final match = reuseCollapsedWhitespace
            ? collapsedWhitespaceMatch
            : _matchRune(source.units, cursor, rune);
        if (match == null) {
          final isRustTrimmedWhitespace =
              _isUnicodeWhitespace(rune) &&
              (runeIndex < leadingWhitespace || runeIndex >= trailingWhitespace);
          if (isRustTrimmedWhitespace) {
            utf16Offset += width;
            continue;
          }
          throw FormatException(
            'Rendered reader block could not be mapped to Rust plain_text',
            '$text at UTF-16 offset $utf16Offset',
          );
        }

        for (var codeUnit = utf16Offset; codeUnit < utf16Offset + width; codeUnit++) {
          starts[codeUnit] = match.start;
          ends[codeUnit] = match.end;
        }
        if (!reuseCollapsedWhitespace) cursor = match.nextCursor;
        previousRenderedWhitespace = isWhitespace;
        collapsedWhitespaceMatch =
            isWhitespace && match.collapsedWhitespace ? match : null;
        utf16Offset += width;
      }

      // Empty/whitespace-only HTML blocks are kept through alignment so their
      // source spans advance the cursor, then omitted from rendered output.
      if (!block.isEmpty) result.add(block.withSourceOffsets(starts, ends));
    }
    return result;
  }

  /// Returns a half-open Rust scalar range for a local Flutter selection.
  static (int, int)? sourceRangeFor(
    TextBlock block,
    int localStart,
    int localEnd,
  ) {
    if (block.sourceStartOffsets.isEmpty ||
        block.sourceEndOffsets.length != block.sourceStartOffsets.length) {
      return null;
    }
    final start = localStart.clamp(0, block.sourceStartOffsets.length);
    final end = localEnd.clamp(start, block.sourceStartOffsets.length);
    if (start == end) return null;

    var sourceStart = 0x7fffffff;
    var sourceEnd = 0;
    for (var i = start; i < end; i++) {
      final unitStart = block.sourceStartOffsets[i];
      final unitEnd = block.sourceEndOffsets[i];
      if (unitStart < 0 || unitEnd <= unitStart) continue;
      if (unitStart < sourceStart) sourceStart = unitStart;
      if (unitEnd > sourceEnd) sourceEnd = unitEnd;
    }
    return sourceStart < sourceEnd ? (sourceStart, sourceEnd) : null;
  }

  /// Rebuilds visible rendered text from a Rust source range. Synthetic spaces
  /// introduced by HTML tag boundaries are not shown to the user.
  static String renderedTextForRange(
    List<ReaderBlock> blocks,
    int sourceStart,
    int sourceEnd,
  ) {
    if (sourceStart >= sourceEnd) return '';
    final output = StringBuffer();
    var wroteBlock = false;
    for (final block in blocks) {
      if (block is! TextBlock ||
          block.sourceStartOffsets.length != block.plainText.length ||
          block.sourceEndOffsets.length != block.plainText.length) {
        continue;
      }
      final selected = StringBuffer();
      var hasSelectedRune = false;
      var utf16Offset = 0;
      for (final rune in block.plainText.runes) {
        final width = rune > 0xffff ? 2 : 1;
        var included = false;
        for (var i = utf16Offset; i < utf16Offset + width; i++) {
          if (block.sourceStartOffsets[i] >= 0 &&
              block.sourceStartOffsets[i] < sourceEnd &&
              block.sourceEndOffsets[i] > sourceStart) {
            included = true;
            break;
          }
        }
        if (included) {
          selected.writeCharCode(rune);
          hasSelectedRune = true;
        }
        utf16Offset += width;
      }
      if (!hasSelectedRune) continue;
      if (wroteBlock) output.write('\n');
      output.write(selected);
      wroteBlock = true;
    }
    return output.toString();
  }

  static String substringByScalars(String text, int start, int end) {
    final runes = text.runes.toList(growable: false);
    final from = start.clamp(0, runes.length);
    final to = end.clamp(from, runes.length);
    return String.fromCharCodes(runes.sublist(from, to));
  }

  /// Converts persisted Dart UTF-16 offsets into Rust Unicode-scalar offsets.
  /// A start inside a surrogate pair rounds down; an end rounds up so the
  /// whole character remains included.
  static int scalarOffsetFromUtf16(
    String text,
    int utf16Offset, {
    bool roundUp = false,
  }) {
    final target = utf16Offset.clamp(0, text.length);
    var scalarOffset = 0;
    var cursor = 0;
    for (final rune in text.runes) {
      final width = rune > 0xffff ? 2 : 1;
      if (cursor + width > target) {
        return roundUp ? scalarOffset + 1 : scalarOffset;
      }
      cursor += width;
      scalarOffset++;
      if (cursor == target) return scalarOffset;
    }
    return scalarOffset;
  }

  /// Converts a Rust Unicode-scalar offset to the legacy persisted UTF-16
  /// coordinate, for records created before offset units were stored.
  static int utf16OffsetFromScalar(String text, int scalarOffset) {
    final target = scalarOffset.clamp(0, text.runes.length);
    var result = 0;
    var seen = 0;
    for (final rune in text.runes) {
      if (seen >= target) break;
      result += rune > 0xffff ? 2 : 1;
      seen++;
    }
    return result;
  }

  /// Resolves an unclassified stored highlight only when its saved text
  /// uniquely identifies scalar or legacy UTF-16 coordinates.
  static (int, int)? resolveStoredHighlightRange(
    String sourceText,
    List<ReaderBlock> blocks, {
    required int start,
    required int end,
    required String quotedText,
    required String offsetUnit,
  }) {
    final scalarLength = sourceText.runes.length;
    if (offsetUnit == 'rust_scalar') {
      return _validRange(start, end, scalarLength) ? (start, end) : null;
    }
    if (offsetUnit == 'utf16') {
      final legacy = (
        scalarOffsetFromUtf16(sourceText, start),
        scalarOffsetFromUtf16(sourceText, end, roundUp: true),
      );
      return _validRange(legacy.$1, legacy.$2, scalarLength) ? legacy : null;
    }

    final scalar = (start, end);
    final legacy = (
      scalarOffsetFromUtf16(sourceText, start),
      scalarOffsetFromUtf16(sourceText, end, roundUp: true),
    );
    if (scalar == legacy) {
      return _validRange(scalar.$1, scalar.$2, scalarLength) ? scalar : null;
    }
    if (quotedText.isEmpty) return null;

    final scalarMatches = _rangeMatchesText(
      sourceText,
      blocks,
      scalar,
      quotedText,
    );
    final legacyMatches = _rangeMatchesText(
      sourceText,
      blocks,
      legacy,
      quotedText,
    );
    if (scalarMatches == legacyMatches) return null;
    return scalarMatches ? scalar : legacy;
  }

  static bool _rangeMatchesText(
    String sourceText,
    List<ReaderBlock> blocks,
    (int, int) range,
    String quotedText,
  ) {
    if (!_validRange(range.$1, range.$2, sourceText.runes.length)) return false;
    return substringByScalars(sourceText, range.$1, range.$2) == quotedText ||
        renderedTextForRange(blocks, range.$1, range.$2) == quotedText;
  }

  static bool _validRange(int start, int end, int length) =>
      start >= 0 && start < end && end <= length;

  static _SourceMatch? _matchRune(
    List<_SourceUnit> source,
    int from,
    int renderedRune,
  ) {
    var cursor = from;
    while (cursor < source.length) {
      if (!_isUnicodeWhitespace(renderedRune)) {
        final skippedWhitespaceEntity = _skipWhitespaceEntity(source, cursor);
        if (skippedWhitespaceEntity != null) {
          cursor = skippedWhitespaceEntity;
          continue;
        }
      }
      final unit = source[cursor];

      // <br> is rendered as a line break, while ebook-rs contributes one
      // synthetic space for the tag's opening '<'.
      if (renderedRune == 0x0a && unit.lineBreak) {
        return _SourceMatch(
          unit.start,
          unit.end,
          cursor + 1,
          collapsedWhitespace: unit.visibleWhitespace,
        );
      }

      if (_isUnicodeWhitespace(renderedRune) && unit.visibleWhitespace) {
        return _SourceMatch(
          unit.start,
          unit.end,
          cursor + 1,
          collapsedWhitespace: true,
        );
      }

      final entity = _matchEntity(source, cursor, renderedRune);
      if (entity != null) return entity;

      if (unit.visible && unit.rune == renderedRune) {
        return _SourceMatch(unit.start, unit.end, cursor + 1);
      }

      // Rust's extractor emits a space for every tag opener. Those separators
      // have no corresponding rendered character except for <br> above.
      // Text in head/noscript/template is likewise absent from Flutter output.
      if (unit.tagSeparator || !unit.visible) {
        cursor++;
        continue;
      }

      // No visible source character may be skipped to make a later match.
      return null;
    }
    return null;
  }

  static _SourceMatch? _matchEntity(
    List<_SourceUnit> source,
    int from,
    int renderedRune,
  ) {
    if (from >= source.length ||
        !source[from].visible ||
        source[from].rune != 0x26) {
      return null;
    }

    final encoded = StringBuffer();
    var lastSourceIndex = from;
    for (var i = from; i < source.length && i - from < 64; i++) {
      final unit = source[i];
      if (unit.tagSeparator) {
        lastSourceIndex = i;
        continue;
      }
      if (!unit.visible || unit.visibleWhitespace) return null;
      encoded.writeCharCode(unit.rune);
      lastSourceIndex = i;
      if (unit.rune != 0x3b) continue;

      final decoded = decodeReaderEntities(encoded.toString());
      final decodedRunes = decoded.runes;
      if (decoded != encoded.toString() &&
          decodedRunes.length == 1 &&
          decodedRunes.first == renderedRune) {
        return _SourceMatch(
          source[from].start,
          source[lastSourceIndex].end,
          lastSourceIndex + 1,
        );
      }
    }
    return null;
  }

  /// Consumes an entity that represents whitespace only when no rendered
  /// whitespace is being matched at this position. This covers source
  /// whitespace omitted with an unrendered HTML block without allowing a
  /// visible character to be skipped.
  static int? _skipWhitespaceEntity(List<_SourceUnit> source, int from) {
    if (from >= source.length ||
        !source[from].visible ||
        source[from].rune != 0x26) {
      return null;
    }

    final encoded = StringBuffer();
    var lastSourceIndex = from;
    for (var i = from; i < source.length && i - from < 64; i++) {
      final unit = source[i];
      if (unit.tagSeparator) {
        lastSourceIndex = i;
        continue;
      }
      if (!unit.visible || unit.visibleWhitespace) return null;
      encoded.writeCharCode(unit.rune);
      lastSourceIndex = i;
      if (unit.rune != 0x3b) continue;

      final value = decodeReaderEntities(encoded.toString());
      final runes = value.runes;
      if (value != encoded.toString() &&
          runes.length == 1 &&
          _isUnicodeWhitespace(runes.first)) {
        return lastSourceIndex + 1;
      }
    }
    return null;
  }

  static _RustProjection _extractRustPlainText(String html) {
    final collapsed = <_SourceDraft>[];
    var pendingWhitespaceVisible = false;
    var pendingBreak = false;
    var hasPendingWhitespace = false;

    void flushWhitespace() {
      if (!hasPendingWhitespace) return;
      collapsed.add(
        _SourceDraft(
          0x20,
          visible: false,
          tagSeparator: !pendingWhitespaceVisible,
          visibleWhitespace: pendingWhitespaceVisible,
          lineBreak: pendingBreak,
        ),
      );
      hasPendingWhitespace = false;
      pendingWhitespaceVisible = false;
      pendingBreak = false;
    }

    void push(_SourceDraft unit) {
      if (_isUnicodeWhitespace(unit.rune)) {
        hasPendingWhitespace = true;
        pendingWhitespaceVisible |= unit.visible;
        pendingBreak |= unit.lineBreak;
      } else {
        flushWhitespace();
        collapsed.add(unit);
      }
    }

    var inTag = false;
    var quote = 0;
    var tagStart = 0;
    var skippingTag = '';
    var rendererDropDepth = 0;
    for (var i = 0; i < html.length;) {
      final codeUnit = html.codeUnitAt(i);
      if (!inTag && codeUnit == 0x3c) {
        inTag = true;
        quote = 0;
        tagStart = i;
        final tagName = _tagNameAt(html, i);
        final lowerOpen = skippingTag.isEmpty;
        if (lowerOpen) {
          if (_startsAtIgnoreCase(html, i, '<style')) {
            skippingTag = 'style';
          } else if (_startsAtIgnoreCase(html, i, '<script')) {
            skippingTag = 'script';
          }
        } else {
          final closeTag = skippingTag == 'style' ? '</style' : '</script';
          if (_startsAtIgnoreCase(html, i, closeTag)) {
            skippingTag = '';
          } else if (!_containsIgnoreCase(html, i, closeTag) &&
              _isRustRecoveryTag(html, i)) {
            skippingTag = '';
          }
        }
        push(
          _SourceDraft(
            0x20,
            visible: false,
            tagSeparator: true,
            lineBreak: tagName == 'br',
          ),
        );
        i++;
        continue;
      }

      if (inTag) {
        if (quote != 0) {
          if (codeUnit == quote) quote = 0;
        } else if (codeUnit == 0x22 || codeUnit == 0x27) {
          quote = codeUnit;
        } else if (codeUnit == 0x3e) {
          inTag = false;
          final name = _tagName(html.substring(tagStart, i + 1));
          if (_dropEntirely.contains(name)) {
            final token = html.substring(tagStart, i + 1).trimLeft();
            final closing = token.startsWith('</');
            if (closing) {
              if (rendererDropDepth > 0) rendererDropDepth--;
            } else {
              rendererDropDepth++;
            }
          }
        }
        i++;
        continue;
      }

      final rune = _runeAt(html, i);
      final width = rune > 0xffff ? 2 : 1;
      if (skippingTag.isEmpty) {
        push(
          _SourceDraft(
            rune,
            visible: rendererDropDepth == 0,
          ),
        );
      }
      i += width;
    }
    flushWhitespace();

    while (collapsed.isNotEmpty && collapsed.first.rune == 0x20) {
      collapsed.removeAt(0);
    }
    while (collapsed.isNotEmpty && collapsed.last.rune == 0x20) {
      collapsed.removeLast();
    }

    final units = [
      for (var i = 0; i < collapsed.length; i++)
        _SourceUnit(
          collapsed[i].rune,
          i,
          i + 1,
          visible: collapsed[i].visible,
          tagSeparator: collapsed[i].tagSeparator,
          visibleWhitespace: collapsed[i].visibleWhitespace,
          lineBreak: collapsed[i].lineBreak,
        ),
    ];
    return _RustProjection(
      units,
      String.fromCharCodes(units.map((unit) => unit.rune)),
    );
  }

  static int _runeAt(String text, int offset) {
    final first = text.codeUnitAt(offset);
    if (first >= 0xd800 && first <= 0xdbff && offset + 1 < text.length) {
      final second = text.codeUnitAt(offset + 1);
      if (second >= 0xdc00 && second <= 0xdfff) {
        return 0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00);
      }
    }
    return first;
  }

  static bool _startsAtIgnoreCase(String text, int offset, String prefix) {
    if (offset + prefix.length > text.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      var actual = text.codeUnitAt(offset + i);
      var expected = prefix.codeUnitAt(i);
      if (actual >= 0x41 && actual <= 0x5a) actual += 0x20;
      if (expected >= 0x41 && expected <= 0x5a) expected += 0x20;
      if (actual != expected) return false;
    }
    return true;
  }

  static bool _containsIgnoreCase(String text, int offset, String value) {
    for (var i = offset; i + value.length <= text.length; i++) {
      if (_startsAtIgnoreCase(text, i, value)) return true;
    }
    return false;
  }

  static bool _isRustRecoveryTag(String html, int offset) =>
      _startsAtIgnoreCase(html, offset, '<p') ||
      _startsAtIgnoreCase(html, offset, '<div') ||
      _startsAtIgnoreCase(html, offset, '<body') ||
      _startsAtIgnoreCase(html, offset, '<h') ||
      _startsAtIgnoreCase(html, offset, '<section');

  static String _tagNameAt(String html, int offset) {
    final end = _findTagEnd(html, offset);
    if (end == -1) return '';
    return _tagName(html.substring(offset, end + 1));
  }

  static int _findTagEnd(String html, int start) {
    var quote = 0;
    for (var i = start; i < html.length; i++) {
      final unit = html.codeUnitAt(i);
      if (quote != 0) {
        if (unit == quote) quote = 0;
      } else if (unit == 0x22 || unit == 0x27) {
        quote = unit;
      } else if (unit == 0x3e) {
        return i;
      }
    }
    return -1;
  }

  static String _tagName(String tag) {
    if (tag.startsWith('<!--') || tag.length < 3) return '';
    final inner = tag.substring(1, tag.length - 1).trim();
    final name = (inner.startsWith('/') ? inner.substring(1) : inner)
        .split(RegExp(r'[\s/>]'))
        .first;
    return name.toLowerCase();
  }

  static bool _isUnicodeWhitespace(int rune) =>
      (rune >= 0x09 && rune <= 0x0d) ||
      rune == 0x20 ||
      rune == 0x85 ||
      rune == 0xa0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200a) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202f ||
      rune == 0x205f ||
      rune == 0x3000;
}

const _dropEntirely = {'script', 'style', 'head', 'noscript', 'template'};

class _RawSourceUnit {
  const _RawSourceUnit(
    this.rune, {
    this.visible = false,
    this.tagSeparator = false,
    this.visibleWhitespace = false,
    this.lineBreak = false,
  });

  final int rune;
  final bool visible;
  final bool tagSeparator;
  final bool visibleWhitespace;
  final bool lineBreak;
}

class _SourceDraft extends _RawSourceUnit {
  const _SourceDraft(
    super.rune, {
    super.visible,
    super.tagSeparator,
    super.visibleWhitespace,
    super.lineBreak,
  });
}

class _SourceUnit extends _RawSourceUnit {
  const _SourceUnit(
    super.rune,
    this.start,
    this.end, {
    super.visible,
    super.tagSeparator,
    super.visibleWhitespace,
    super.lineBreak,
  });

  final int start;
  final int end;
}

class _RustProjection {
  const _RustProjection(this.units, this.text);
  final List<_SourceUnit> units;
  final String text;
}

class _SourceMatch {
  const _SourceMatch(
    this.start,
    this.end,
    this.nextCursor, {
    this.collapsedWhitespace = false,
  });
  final int start;
  final int end;
  final int nextCursor;
  final bool collapsedWhitespace;
}
