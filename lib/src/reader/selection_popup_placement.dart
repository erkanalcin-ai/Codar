import 'dart:math' as math;

import 'package:flutter/painting.dart';

Rect placeSelectionPopup({
  required Size viewportSize,
  required Rect safeBounds,
  required List<Rect> selectionRects,
  required Offset fallbackAnchor,
  required Size popupSize,
  double edgePadding = 12,
  double gap = 14,
}) {
  final minLeft = safeBounds.left + edgePadding;
  final minTop = safeBounds.top + edgePadding;
  final maxLeft = math.max(
    minLeft,
    math.min(viewportSize.width, safeBounds.right) -
        popupSize.width -
        edgePadding,
  );
  final maxTop = math.max(
    minTop,
    math.min(viewportSize.height, safeBounds.bottom) -
        popupSize.height -
        edgePadding,
  );
  Rect? selectionBounds;
  for (final rect in selectionRects) {
    selectionBounds = selectionBounds == null
        ? rect
        : selectionBounds.expandToInclude(rect);
  }
  final origins = <Offset>[];
  final bounds = selectionBounds;
  if (bounds != null) {
    origins.addAll([
      Offset(
        bounds.center.dx - popupSize.width / 2,
        bounds.top - popupSize.height - gap,
      ),
      Offset(bounds.center.dx - popupSize.width / 2, bounds.bottom + gap),
      Offset(
        bounds.left - popupSize.width - gap,
        bounds.center.dy - popupSize.height / 2,
      ),
      Offset(bounds.right + gap, bounds.center.dy - popupSize.height / 2),
    ]);
  }
  origins.addAll([
    Offset(
      fallbackAnchor.dx - popupSize.width / 2,
      fallbackAnchor.dy - popupSize.height - gap,
    ),
    Offset(fallbackAnchor.dx - popupSize.width / 2, fallbackAnchor.dy + gap),
  ]);
  final farHandle = selectionRects.isEmpty
      ? fallbackAnchor
      : (() {
          final lastLine = selectionRects.reduce(
            (a, b) => a.bottom >= b.bottom ? a : b,
          );
          return Offset(lastLine.center.dx, lastLine.bottom);
        })();
  Rect? best;
  var bestOverlap = double.infinity;
  var bestDistance = -1.0;
  for (final origin in origins) {
    final left = origin.dx.clamp(minLeft, maxLeft).toDouble();
    final top = origin.dy.clamp(minTop, maxTop).toDouble();
    final candidate = Rect.fromLTWH(
      left,
      top,
      popupSize.width,
      popupSize.height,
    );
    final overlap = selectionRects.fold<double>(0, (total, selected) {
      final intersection = candidate.intersect(selected);
      return total +
          (intersection.isEmpty ? 0 : intersection.width * intersection.height);
    });
    final distance = (candidate.center - farHandle).distanceSquared;
    if (overlap < bestOverlap ||
        (overlap == bestOverlap && distance > bestDistance)) {
      best = candidate;
      bestOverlap = overlap;
      bestDistance = distance;
    }
  }
  return best ??
      Rect.fromLTWH(
        fallbackAnchor.dx.clamp(minLeft, maxLeft).toDouble(),
        fallbackAnchor.dy.clamp(minTop, maxTop).toDouble(),
        popupSize.width,
        popupSize.height,
      );
}
