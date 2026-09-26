// Minimal section-HTML parser for the reader. No WebView, no new packages.
//
// Safety: only a small allowlist of structural/inline tags is honored;
// everything else (script, style, iframe, a, form, …) is dropped with
// attributes. Image bytes are passed separately as typed data. Output never
// contains raw HTML.

import 'dart:convert';
import 'dart:typed_data';

class SpanPart {
  SpanPart(this.text, {this.bold = false, this.italic = false});
  final String text;
  final bool bold;
  final bool italic;
}

sealed class ReaderBlock {
  const ReaderBlock();
  String get plainText;
}

class TextBlock extends ReaderBlock {
  TextBlock({required this.kind, required this.parts});

  /// 'h1'..'h6', 'p', 'li', 'quote'
  final String kind;
  final List<SpanPart> parts;

  @override
  String get plainText => parts.map((p) => p.text).join();
  bool get isHeading => kind.startsWith('h');
  bool get isEmpty => plainText.trim().isEmpty;
}

class ReaderImage {
  const ReaderImage({
    required this.source,
    required this.mimeType,
    required this.data,
    this.pixelWidth = 0,
    this.pixelHeight = 0,
    this.dataFormat = 'encoded',
    this.left = 0,
    this.top = 0,
    this.displayWidth = 0,
    this.displayHeight = 0,
    this.pageWidth = 0,
    this.pageHeight = 0,
    this.rotationDegrees = 0,
  });

  final String source;
  final String mimeType;
  final Uint8List data;
  final int pixelWidth;
  final int pixelHeight;
  final String dataFormat;
  final double left;
  final double top;
  final double displayWidth;
  final double displayHeight;
  final double pageWidth;
  final double pageHeight;
  final int rotationDegrees;

  bool get isPdfPlacement => pageWidth > 0 && pageHeight > 0;
  bool get isRenderableRaster =>
      dataFormat == 'rgba8888' || _supportedRasterTypes.contains(mimeType);
}

class ImageBlock extends ReaderBlock {
  const ImageBlock({required this.images});

  /// One HTML image, or all bitmap placements on a textless PDF page.
  final List<ReaderImage> images;

  bool get isPdfPage =>
      images.isNotEmpty && images.every((image) => image.isPdfPlacement);

  @override
  String get plainText => '';
}

const _dropEntirely = {'script', 'style', 'head', 'noscript', 'template'};

/// Parse engine section HTML into render blocks.
List<ReaderBlock> parseSectionHtml(
  String html, {
  List<ReaderImage> images = const [],
}) {
  final blocks = <ReaderBlock>[];
  final imageBySource = {for (final image in images) image.source: image};
  final matchedImageSources = <String>{};
  var parts = <SpanPart>[];
  String? blockKind;
  var bold = 0;
  var italic = 0;
  var dropDepth = 0;
  var preDepth = 0;
  final buf = StringBuffer();

  void flushText() {
    if (buf.isEmpty) return;
    final sourceText = buf.toString();
    buf.clear();
    // In normal HTML flow, source indentation and line wrapping collapse to
    // spaces. Keep explicit <br> breaks (handled separately) and preformatted
    // text intact.
    final normalizedSource = preDepth == 0
        ? sourceText.replaceAll(RegExp(r'[\t\n\f\r ]+'), ' ')
        : sourceText;
    final text = _decodeEntities(normalizedSource);
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
      case 'pre':
        if (!closing) {
          flushBlock();
          blockKind = 'pre';
          preDepth++;
        } else {
          flushBlock();
          if (preDepth > 0) preDepth--;
        }
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
      case 'img':
        if (closing) break;
        final source = _imageSource(inner);
        if (source == null) break;
        final image = imageBySource[source] ?? _decodeDataImage(source);
        if (image == null || !image.isRenderableRaster) break;
        flushText();
        final resumeKind = blockKind;
        flushBlock();
        blocks.add(ImageBlock(images: [image]));
        blockKind = resumeKind;
        matchedImageSources.add(source);
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

  final pdfImages = images
      .where((image) => image.isPdfPlacement && image.isRenderableRaster)
      .toList();
  if (pdfImages.isNotEmpty) {
    blocks.add(ImageBlock(images: pdfImages));
  }
  for (final image in images) {
    if (!image.isPdfPlacement &&
        image.isRenderableRaster &&
        !matchedImageSources.contains(image.source)) {
      blocks.add(ImageBlock(images: [image]));
    }
  }
  return blocks;
}

String? _imageSource(String tag) {
  final source = _attribute(tag, 'src');
  if (source == null) return null;
  final decoded = _decodeEntities(source.trim());
  if (decoded.isEmpty || decoded.startsWith('#')) return null;
  final lower = decoded.toLowerCase();
  if (lower.startsWith('http:') ||
      lower.startsWith('https:') ||
      lower.startsWith('//')) {
    return null;
  }
  return decoded;
}

String? _attribute(String tag, String wanted) {
  final attribute = RegExp(
    r'\b' +
        RegExp.escape(wanted) +
        r'''\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))''',
    caseSensitive: false,
  ).firstMatch(tag);
  return attribute?.group(1) ?? attribute?.group(2) ?? attribute?.group(3);
}

ReaderImage? _decodeDataImage(String source) {
  if (!source.toLowerCase().startsWith('data:image/')) return null;
  final comma = source.indexOf(',');
  if (comma < 0) return null;
  final metadata = source.substring(5, comma).split(';');
  var mimeType = metadata.first.toLowerCase();
  if (mimeType == 'image/jpg') mimeType = 'image/jpeg';
  if (!_supportedRasterTypes.contains(mimeType)) return null;
  try {
    final encoded = source.substring(comma + 1);
    final bytes = metadata.any((part) => part.toLowerCase() == 'base64')
        ? base64.decode(encoded)
        : Uint8List.fromList(utf8.encode(Uri.decodeComponent(encoded)));
    if (bytes.isEmpty) return null;
    return ReaderImage(source: source, mimeType: mimeType, data: bytes);
  } on FormatException {
    return null;
  }
}

const _supportedRasterTypes = {
  'image/jpeg',
  'image/png',
  'image/gif',
  'image/webp',
  'image/bmp',
};

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
