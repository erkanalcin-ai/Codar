import 'package:flutter/rendering.dart';

/// Returns selected text boxes in global logical coordinates.
/// Selectable text can be wrapped in render objects such as RenderMouseRegion,
/// so find its RenderParagraph below the keyed subtree.
List<Rect> globalTextSelectionRects(
  RenderObject? subtree,
  TextSelection selection,
) {
  final paragraph = _findParagraph(subtree);
  if (paragraph == null) return const [];
  return [
    for (final box in paragraph.getBoxesForSelection(selection))
      Rect.fromPoints(
        paragraph.localToGlobal(box.toRect().topLeft),
        paragraph.localToGlobal(box.toRect().bottomRight),
      ),
  ];
}

RenderParagraph? _findParagraph(RenderObject? object) {
  if (object == null) return null;
  if (object is RenderParagraph) return object;
  RenderParagraph? found;
  object.visitChildren((child) {
    found ??= _findParagraph(child);
  });
  return found;
}
