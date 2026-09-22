// Shared deep-link builder/parser for exact-CFI reader navigation.
//
// A record (highlight/note/bookmark/progress) carries section_index +
// char offset + CFI. The CFI is the stable cross-session anchor; the
// section index is the fast path for content fetching. The reader
// verifies the CFI on arrival via `getLocator` and reports drift
// instead of silently landing on the wrong text.

String readerRouteFor(
  String bookId, {
  int? section,
  int? offset,
  String? cfi,
}) {
  final params = <String, String>{};
  if (section != null) params['section'] = '$section';
  if (offset != null) params['offset'] = '$offset';
  if (cfi != null && cfi.isNotEmpty) params['cfi'] = cfi;
  final qs = params.entries
      .map((e) =>
          '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
      .join('&');
  final path = '/reader/${Uri.encodeComponent(bookId)}';
  return qs.isEmpty ? path : '$path?$qs';
}

/// Parsed `?section=&offset=&cfi=` triple. All fields optional; callers
/// fall back to saved progress when absent.
class ReaderTarget {
  ReaderTarget({this.section, this.offset, this.cfi});
  final int? section;
  final int? offset;
  final String? cfi;

  static ReaderTarget parse(Map<String, String> query) => ReaderTarget(
        section: int.tryParse(query['section'] ?? ''),
        offset: int.tryParse(query['offset'] ?? ''),
        cfi: (query['cfi'] ?? '').isEmpty ? null : query['cfi'],
      );
}

/// Number of grid columns for the current width: phones 3, large
/// tablets/foldables more. Pure function so it is unit-testable.
int libraryGridColumns(double width) {
  if (width >= 1200) return 6;
  if (width >= 900) return 5;
  if (width >= 600) return 4;
  return 3;
}
