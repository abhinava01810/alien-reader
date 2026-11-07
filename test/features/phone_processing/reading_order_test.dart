import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:alien_reader_app/features/phone_processing/data/reading_order.dart';

/// A line box at (x, y) of size w×h, rotated by [deg] about the origin.
LineBox _line(String t, num x, num y, num w, {num h = 20, double deg = 0}) {
  final r = deg * math.pi / 180;
  math.Point<num> p(num px, num py) => math.Point(
    px * math.cos(r) - py * math.sin(r),
    px * math.sin(r) + py * math.cos(r),
  );
  return LineBox(t, [p(x, y), p(x + w, y), p(x + w, y + h), p(x, y + h)]);
}

void main() {
  test('joins a justified line split into two blocks, left to right', () {
    final text = readingOrderText([
      _line('dependency in everyday tasks', 0, 28, 300),
      _line('we are eliminating', 420, 0, 180), // right half of row 1
      _line('At ALIEN INNOVATIONS,', 0, 0, 250), // left half of row 1
    ]);
    expect(
      text,
      'At ALIEN INNOVATIONS, we are eliminating\n'
      'dependency in everyday tasks',
    );
  });

  test('headings stay above their paragraph on a tilted page', () {
    const tilt = 8.0;
    final lines = [
      _line('MISSION', 0, 200, 100, deg: tilt),
      _line('To make the lives', 0, 230, 400, deg: tilt),
      _line('OUR VISION', 0, 0, 120, deg: tilt),
      _line('To empower visually', 0, 30, 400, deg: tilt),
      _line('with technologies', 0, 60, 200, deg: tilt),
      _line('that', 300, 60, 40, deg: tilt),
    ];
    expect(
      readingOrderText(lines),
      'OUR VISION\n'
      'To empower visually\n'
      'with technologies that\n'
      '\n'
      'MISSION\n'
      'To make the lives',
    );
  });

  test('empty input gives empty text', () {
    expect(readingOrderText(const []), '');
  });
}
