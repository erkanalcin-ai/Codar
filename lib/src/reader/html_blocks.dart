// Minimal section-HTML parser for the reader. No WebView, no new packages.
//
// Safety: only a small allowlist of structural/inline tags is honored;
// everything else (script, style, iframe, img, a, form, …) is dropped with
// attributes. Only text nodes survive. Output never contains raw HTML.

class SpanPart {
  SpanPart(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold;
  final bool italic;
}

class TextBlock {
  TextBlock({required this.kind, required this.parts});

  /// 'h1'..'h6', 'p', 'li', 'quote'
  final String kind;
  final List<SpanPart> parts;

  String get plainText => parts.map((p) => p.text).join();
  bool get isHeading => kind.startsWith('h');
  bool get isEmpty => plainText.trim().isEmpty;
}

const _dropEntirely = {'script', 'style', 'head', 'noscript', 'template'};

/// Parse engine section HTML into render blocks.
List<TextBlock> parseSectionHtml(String html) {
  final blocks = <TextBlock>[];
  var parts = <SpanPart>[];
  String? blockKind;
  var bold = 0;
  var italic = 0;
  var dropDepth = 0;
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    final text = _decodeEntities(buf.toString());
    buf.clear();
    if (text.isEmpty) return;
    parts.add(SpanPart(text, bold: bold > 0, italic: italic > 0));
  }

  void flushBlock() {
    flushText();
    final kind = blockKind;
    if (kind != null) {
      final block = TextBlock(kind: kind, parts: parts);
      if (!block.isEmpty) blocks.add(block);
    }
    parts = <SpanPart>[];
    blockKind = null;
  }

  void openBlock(String kind) {
    flushBlock();
    blockKind = kind;
  }

  final tagRe = RegExp(r'<!--.*?-->|<[^>]*>', dotAll: true);
  var pos = 0;
  for (final m in tagRe.allMatches(html)) {
    if (dropDepth == 0) buf.write(html.substring(pos, m.start));
    final token = m.group(0)!;
    pos = m.end;
    if (token.startsWith('<!--')) continue;
    final inner = token.substring(1, token.length - 1).trim();
    final closing = inner.startsWith('/');
    final name = (closing ? inner.substring(1) : inner)
        .split(RegExp(r'[\s/>]'))
        .first
        .toLowerCase();
    if (name.isEmpty) continue;

    if (!closing && _dropEntirely.contains(name)) {
      dropDepth++;
      continue;
    }
    if (closing && _dropEntirely.contains(name)) {
      if (dropDepth > 0) dropDepth--;
      continue;
    }
    if (dropDepth > 0) continue;

    switch (name) {
      case 'p':
      case 'div':
      case 'section':
      case 'article':
        if (!closing) {
          if (blockKind != null) flushBlock();
          blockKind ??= 'p';
        } else {
          flushBlock();
        }
      case 'br':
        flushText();
        parts.add(SpanPart('\n'));
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        if (!closing) {
          openBlock(name);
        } else {
          flushBlock();
        }
      case 'li':
        if (!closing) {
          openBlock('li');
        } else {
          flushBlock();
        }
      case 'ul':
      case 'ol':
        flushBlock();
      case 'blockquote':
        if (!closing) {
          openBlock('quote');
        } else {
          flushBlock();
        }
      case 'b':
      case 'strong':
        if (!closing) {
          bold++;
        } else if (bold > 0) {
          bold--;
        }
      case 'i':
      case 'em':
        if (!closing) {
          italic++;
        } else if (italic > 0) {
          italic--;
        }
      default:
        // Unknown/unsafe tag: drop the tag, keep inner text (already in buf).
        break;
    }
  }
  if (dropDepth == 0) buf.write(html.substring(pos));
  if (blockKind == null && parts.isEmpty && buf.isNotEmpty) {
    blockKind = 'p';
  }
  flushBlock();
  return blocks;
}

String _decodeEntities(String s) {
  // Two passes: engine HTML may double-escape text (e.g. &amp;nbsp;).
  // Output is plain text (never re-parsed as HTML), so this is safe.
  return _decodeOnce(_decodeOnce(s));
}

String _decodeOnce(String s) {
  var out = s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&ldquo;', '\u201c')
      .replaceAll('&rdquo;', '\u201d')
      .replaceAll('&lsquo;', '\u2018')
      .replaceAll('&rsquo;', '\u2019')
      .replaceAll('&mdash;', '\u2014')
      .replaceAll('&ndash;', '\u2013')
      .replaceAll('&hellip;', '\u2026')
      .replaceAll('&ccedil;', 'ç')
      .replaceAll('&Ccedil;', 'Ç')
      .replaceAll('&scaron;', 'š')
      .replaceAll('&Scaron;', 'Š')
      .replaceAll('&gbreve;', 'ğ')
      .replaceAll('&Gbreve;', 'Ğ')
      .replaceAll('&ouml;', 'ö')
      .replaceAll('&Ouml;', 'Ö')
      .replaceAll('&uuml;', 'ü')
      .replaceAll('&Uuml;', 'Ü')
      .replaceAll('&auml;', 'ä')
      .replaceAll('&Auml;', 'Ä')
      .replaceAll('&szlig;', 'ß')
      .replaceAll('&eacute;', 'é')
      .replaceAll('&egrave;', 'è')
      .replaceAll('&euml;', 'ë')
      .replaceAll('&agrave;', 'à')
      .replaceAll('&aacute;', 'á')
      .replaceAll('&oacute;', 'ó')
      .replaceAll('&iacute;', 'í')
      .replaceAll('&uacute;', 'ú')
      .replaceAll('&ntilde;', 'ñ')
      .replaceAll('&Ntilde;', 'Ñ')
      .replaceAll('&copy;', '©')
      .replaceAll('&reg;', '®')
      .replaceAll('&trade;', '™')
      .replaceAll('&middot;', '·')
      .replaceAll('&laquo;', '«')
      .replaceAll('&raquo;', '»')
      .replaceAll('&sect;', '§')
      .replaceAll('&deg;', '°')
      .replaceAll('&plusmn;', '±')
      .replaceAll('&times;', '×')
      .replaceAll('&divide;', '÷');
  out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1)!);
    if (code == null || code <= 0 || code > 0x10FFFF) return '';
    return String.fromCharCode(code);
  });
  out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1)!, radix: 16);
    if (code == null || code <= 0 || code > 0x10FFFF) return '';
    return String.fromCharCode(code);
  });
  return out;
}
