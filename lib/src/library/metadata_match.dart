/// Conservative title/author matching for correcting machine-derived names.
/// This does not perform network access and can be tested independently.
bool isConfidentBookMetadataMatch({
  required String queryTitle,
  required String resultTitle,
  required String queryAuthor,
  required String resultAuthor,
  required bool isbnMatched,
}) {
  if (isbnMatched) return true;
  final titleForMatching = _removeTrailingAuthor(queryTitle, queryAuthor);
  final titleScore = bookMetadataTextSimilarity(titleForMatching, resultTitle);
  if (titleScore < 0.90) return false;

  if (queryAuthor.trim().isEmpty) return titleScore >= 0.97;
  final authorScore = bookMetadataTextSimilarity(queryAuthor, resultAuthor);
  return authorScore >= 0.64 && (titleScore * 0.7 + authorScore * 0.3) >= 0.83;
}

double bookMetadataTextSimilarity(String left, String right) {
  final leftText = _normalize(left);
  final rightText = _normalize(right);
  if (leftText.isEmpty || rightText.isEmpty) return 0;
  if (leftText == rightText) return 1;

  final leftTokens = leftText.split(' ');
  final rightTokens = rightText.split(' ');
  final leftCoverage = _tokenCoverage(leftTokens, rightTokens);
  final rightCoverage = _tokenCoverage(rightTokens, leftTokens);
  final tokenCoverage = leftCoverage + rightCoverage == 0
      ? 0.0
      : 2 * leftCoverage * rightCoverage / (leftCoverage + rightCoverage);
  final wholeText = _editSimilarity(leftText, rightText);
  return tokenCoverage > wholeText ? tokenCoverage : wholeText;
}

double _tokenCoverage(List<String> sourceTokens, List<String> targetTokens) {
  var coverage = 0.0;
  for (final token in targetTokens) {
    var best = 0.0;
    for (final candidate in sourceTokens) {
      final similarity = _editSimilarity(candidate, token);
      if (similarity > best) best = similarity;
    }
    coverage += best;
  }
  return coverage / targetTokens.length;
}

String _removeTrailingAuthor(String title, String author) {
  final titleTokens = _normalize(title).split(' ');
  final authorText = _normalize(author);
  if (authorText.isEmpty) return title;
  final authorTokens = authorText.split(' ');
  if (titleTokens.length <= authorTokens.length) return title;
  final authorStart = titleTokens.length - authorTokens.length;
  if (titleTokens.skip(authorStart).join(' ') != authorText) return title;
  return titleTokens.take(authorStart).join(' ');
}

String normalizeBookMetadataText(String value) => _normalize(value);

String _normalize(String value) {
  var text = value.toLowerCase();
  const substitutions = {
    'ı': 'i',
    'İ': 'i',
    'ç': 'c',
    'ğ': 'g',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ñ': 'n',
  };
  substitutions.forEach((from, to) => text = text.replaceAll(from, to));
  text = text.replaceFirst(RegExp(r'\.[a-z0-9]{2,5}$'), '');
  text = text.replaceAll(
    RegExp(r'\s*(?:\(\s*\d+\s*\)|copy|kopya)\s*$', caseSensitive: false),
    '',
  );
  return text
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');
}

double _editSimilarity(String a, String b) {
  final left = a.runes.toList(growable: false);
  final right = b.runes.toList(growable: false);
  if (left.isEmpty || right.isEmpty) return 0;
  var previous = List<int>.generate(right.length + 1, (index) => index);
  for (var i = 1; i <= left.length; i++) {
    final current = List<int>.filled(right.length + 1, 0)..[0] = i;
    for (var j = 1; j <= right.length; j++) {
      final substitutionCost = left[i - 1] == right[j - 1] ? 0 : 1;
      current[j] = [
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + substitutionCost,
      ].reduce((a, b) => a < b ? a : b);
    }
    previous = current;
  }
  final distance = previous.last;
  final length = left.length > right.length ? left.length : right.length;
  return 1 - distance / length;
}
