import 'package:codar/src/reader/selection_geometry.dart';
import 'package:codar/src/reader/selection_popup_placement.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderMouseRegion;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewport = Size(400, 800);
  const safe = Rect.fromLTRB(16, 24, 384, 776);
  const popup = Size(320, 180);

  testWidgets('selection geometry finds text below a mouse region', (
    tester,
  ) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: MouseRegion(key: key, child: const Text('before Ekrem after')),
        ),
      ),
    );

    final root = key.currentContext!.findRenderObject();
    final rects = globalTextSelectionRects(
      root,
      const TextSelection(baseOffset: 7, extentOffset: 12),
    );

    expect(root, isA<RenderMouseRegion>());
    expect(rects, hasLength(1));
    expect(rects.single.width, greaterThan(0));
  });

  test('short selection places popup outside selected text', () {
    const selected = Rect.fromLTWH(150, 280, 72, 22);
    final placed = placeSelectionPopup(
      viewportSize: viewport,
      safeBounds: safe,
      selectionRects: const [selected],
      fallbackAnchor: selected.center,
      popupSize: popup,
    );

    expect(placed.overlaps(selected), isFalse);
    expect(safe.contains(placed.topLeft), isTrue);
    expect(safe.contains(placed.bottomRight), isTrue);
  });

  test('bottom-edge selection uses an available safe position above', () {
    const selected = Rect.fromLTWH(100, 700, 180, 28);
    final placed = placeSelectionPopup(
      viewportSize: viewport,
      safeBounds: safe,
      selectionRects: const [selected],
      fallbackAnchor: selected.bottomCenter,
      popupSize: popup,
    );

    expect(placed.bottom, lessThanOrEqualTo(selected.top));
    expect(safe.contains(placed.topLeft), isTrue);
    expect(safe.contains(placed.bottomRight), isTrue);
  });

  test('full-page selection keeps popup safe and away from lower handle', () {
    const selected = Rect.fromLTRB(18, 30, 382, 765);
    final placed = placeSelectionPopup(
      viewportSize: viewport,
      safeBounds: safe,
      selectionRects: const [selected],
      fallbackAnchor: const Offset(200, 750),
      popupSize: popup,
    );

    expect(safe.contains(placed.topLeft), isTrue);
    expect(safe.contains(placed.bottomRight), isTrue);
    expect(placed.top, lessThan(safe.center.dy));
  });
}
