import 'dart:math' as math;

/// One recognised line and its four corners, clockwise from top-left, in
/// image pixels.
class LineBox {
  const LineBox(this.text, this.corners);

  final String text;
  final List<math.Point<num>> corners;
}

/// Puts OCR lines back into reading order.
///
/// ML Kit groups lines into blocks by layout, so a justified line with a wide
/// gap comes back as two blocks and headings can land far from their
/// paragraph. This straightens the page by the lines' median tilt, groups
/// lines that sit on the same row (joining split fragments left to right),
/// orders rows top to bottom, and starts a new paragraph at large gaps.
String readingOrderText(List<LineBox> lines) {
  final usable = lines
      .where((l) => l.text.trim().isNotEmpty && l.corners.length == 4)
      .toList();
  if (usable.isEmpty) return '';

  // Page tilt: median angle of each line's top edge.
  final angles = [
    for (final l in usable)
      math.atan2(
        (l.corners[1].y - l.corners[0].y).toDouble(),
        (l.corners[1].x - l.corners[0].x).toDouble(),
      ),
  ]..sort();
  final tilt = angles[angles.length ~/ 2];
  final c = math.cos(-tilt), s = math.sin(-tilt);

  final placed = [for (final l in usable) _place(l, c, s)]
    ..sort((a, b) => a.y.compareTo(b.y));

  final heights = [for (final p in placed) p.height]..sort();
  final typical = math.max(heights[heights.length ~/ 2], 1.0);

  // Group into rows: a line joins the current row when its centre is within
  // half a line height of the row's centre.
  final rows = <List<_Placed>>[];
  for (final p in placed) {
    if (rows.isNotEmpty) {
      final row = rows.last;
      final rowY = row.map((r) => r.y).reduce((a, b) => a + b) / row.length;
      if ((p.y - rowY).abs() < typical * 0.5) {
        row.add(p);
        continue;
      }
    }
    rows.add([p]);
  }

  final out = StringBuffer();
  double? lastY;
  for (final row in rows) {
    row.sort((a, b) => a.x.compareTo(b.x));
    final y = row.map((r) => r.y).reduce((a, b) => a + b) / row.length;
    if (lastY != null) {
      out.write(y - lastY > typical * 1.9 ? '\n\n' : '\n');
    }
    out.write(row.map((r) => r.text.trim()).join(' '));
    lastY = y;
  }
  return out.toString();
}

class _Placed {
  _Placed(this.text, this.x, this.y, this.height);
  final String text;
  final double x; // left edge, de-tilted
  final double y; // vertical centre, de-tilted
  final double height;
}

_Placed _place(LineBox l, double c, double s) {
  double rx(math.Point<num> p) => p.x * c - p.y * s;
  double ry(math.Point<num> p) => p.x * s + p.y * c;
  final ys = [for (final p in l.corners) ry(p)];
  final xs = [for (final p in l.corners) rx(p)];
  final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
  return _Placed(l.text, xs.reduce(math.min), (top + bottom) / 2, bottom - top);
}
