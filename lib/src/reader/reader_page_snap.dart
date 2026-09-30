/// Returns the nearest full-page scroll offset, clamped to the scroll range.
double? readerPageSnapTarget({
  required double pixels,
  required double pageExtent,
  required double minScrollExtent,
  required double maxScrollExtent,
}) {
  if (!pixels.isFinite ||
      !pageExtent.isFinite ||
      pageExtent <= 0 ||
      !minScrollExtent.isFinite ||
      !maxScrollExtent.isFinite ||
      maxScrollExtent < minScrollExtent) {
    return null;
  }

  final page = ((pixels - minScrollExtent) / pageExtent).roundToDouble();
  return (minScrollExtent + page * pageExtent)
      .clamp(minScrollExtent, maxScrollExtent)
      .toDouble();
}
