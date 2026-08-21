import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Minimal SVG path-data parser plus a drawing helper, so the themed
/// fleet art can be ported from the design source **verbatim**.
///
/// The design (`claude.ai/design` — "Skin system architecture") specifies
/// six families as SVG, and each family is a few dozen shapes. Hand
/// translating every `d` string into `moveTo`/`cubicTo` calls would be
/// both unreadable and impossible to check against the original; keeping
/// the path strings intact means any shape here can be diffed against the
/// design a character at a time.
///
/// Supports the subset the design actually uses: `M m L l H h V v C c
/// Q q Z z`. Anything else is ignored rather than throwing — a missing
/// flourish is a far better failure than a crashed battle screen.
Path parseSvgPath(String d) {
  final path = Path();
  var i = 0;
  final n = d.length;
  double cx = 0, cy = 0; // current point
  double sx = 0, sy = 0; // sub-path start
  var command = '';

  bool isCommand(String c) => 'MmLlHhVvCcQqZzAaSsTt'.contains(c);

  void skipSeparators() {
    while (i < n && (d[i] == ' ' || d[i] == ',' || d[i] == '\n' || d[i] == '\t' || d[i] == '\r')) {
      i++;
    }
  }

  double readNumber() {
    skipSeparators();
    final start = i;
    if (i < n && (d[i] == '-' || d[i] == '+')) i++;
    while (i < n && (_isDigit(d[i]) || d[i] == '.')) {
      i++;
    }
    // Exponent form doesn't appear in the design source, but costs
    // nothing to accept.
    if (i < n && (d[i] == 'e' || d[i] == 'E')) {
      i++;
      if (i < n && (d[i] == '-' || d[i] == '+')) i++;
      while (i < n && _isDigit(d[i])) {
        i++;
      }
    }
    if (start == i) return 0;
    return double.parse(d.substring(start, i));
  }

  while (i < n) {
    skipSeparators();
    if (i >= n) break;
    if (isCommand(d[i])) {
      command = d[i];
      i++;
    } else if (!_isNumberStart(d[i])) {
      // Neither a command nor the start of a coordinate.
      //
      // BUGFIX (infinite loop): the previous `default:` bail only caught
      // an unrecognised value in `command`, but an unrecognised character
      // mid-path never reaches it — the last valid command is still in
      // effect, `readNumber` finds no digits, returns 0 WITHOUT advancing,
      // and the loop spins on the same character forever. A malformed
      // path has to fail as a short path, not as a hung frame.
      break;
    }
    final before = i;
    switch (command) {
      case 'M':
      case 'm':
        {
          final x = readNumber(), y = readNumber();
          cx = command == 'm' ? cx + x : x;
          cy = command == 'm' ? cy + y : y;
          path.moveTo(cx, cy);
          sx = cx;
          sy = cy;
          // A repeated coordinate pair after M is an implicit L.
          command = command == 'm' ? 'l' : 'L';
          break;
        }
      case 'L':
      case 'l':
        {
          final x = readNumber(), y = readNumber();
          cx = command == 'l' ? cx + x : x;
          cy = command == 'l' ? cy + y : y;
          path.lineTo(cx, cy);
          break;
        }
      case 'H':
      case 'h':
        {
          final x = readNumber();
          cx = command == 'h' ? cx + x : x;
          path.lineTo(cx, cy);
          break;
        }
      case 'V':
      case 'v':
        {
          final y = readNumber();
          cy = command == 'v' ? cy + y : y;
          path.lineTo(cx, cy);
          break;
        }
      case 'C':
      case 'c':
        {
          final rel = command == 'c';
          final x1 = readNumber(), y1 = readNumber();
          final x2 = readNumber(), y2 = readNumber();
          final x = readNumber(), y = readNumber();
          final c1x = rel ? cx + x1 : x1, c1y = rel ? cy + y1 : y1;
          final c2x = rel ? cx + x2 : x2, c2y = rel ? cy + y2 : y2;
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          path.cubicTo(c1x, c1y, c2x, c2y, ex, ey);
          cx = ex;
          cy = ey;
          break;
        }
      case 'Q':
      case 'q':
        {
          final rel = command == 'q';
          final x1 = readNumber(), y1 = readNumber();
          final x = readNumber(), y = readNumber();
          final c1x = rel ? cx + x1 : x1, c1y = rel ? cy + y1 : y1;
          final ex = rel ? cx + x : x, ey = rel ? cy + y : y;
          path.quadraticBezierTo(c1x, c1y, ex, ey);
          cx = ex;
          cy = ey;
          break;
        }
      case 'Z':
      case 'z':
        path.close();
        cx = sx;
        cy = sy;
        break;
      default:
        // Unknown command — bail rather than spin forever.
        i = n;
    }
    // Belt and braces: any iteration that consumed nothing would repeat
    // forever. Z is the one command that legitimately reads no numbers,
    // and it has already consumed its own character above.
    if (i == before && command != 'Z' && command != 'z') break;
  }
  return path;
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

bool _isNumberStart(String c) =>
    _isDigit(c) || c == '-' || c == '+' || c == '.';

/// Draws design-space shapes onto a canvas, mapping a viewBox onto the
/// widget's real size.
///
/// Two things it gets right that a plain `canvas.scale()` would not:
///
///  * **Non-uniform viewBoxes.** Ship art is authored in a 300×100 box
///    with `preserveAspectRatio="none"`, so a destroyer and a carrier
///    stretch the same drawing to different aspect ratios. Geometry is
///    transformed, not the canvas.
///  * **Stroke weights that survive being drawn small.** Because the
///    transform is applied to the PATH rather than the canvas, stroke
///    widths here start out in device pixels — the design's literal
///    `vector-effect="non-scaling-stroke"`. That alone is not enough, so
///    they then go through [ink]; see [_inkScaleFor] for why.
class FamilyCanvas {
  final Canvas canvas;
  final Float64List _m;

  /// Average scale, for the few places a length has to be scaled (dash
  /// patterns, glow radii) rather than left in device pixels.
  final double scale;

  /// Multiplier applied to every stroke width — see [_inkScaleFor].
  final double inkScale;

  /// Thinnest ink allowed, in logical pixels. Below roughly this the
  /// outline stops reading as a line and starts flickering in and out
  /// along the shape, which is worse than being slightly heavy.
  static const double _minInk = 0.85;

  /// How the design's stroke weights survive being drawn small.
  ///
  /// The source SVG marks every stroke `vector-effect="non-scaling-stroke"`
  /// and that was reproduced literally: ink stayed a fixed number of
  /// device pixels at any size. Correct to the letter, wrong in effect —
  /// the design *authors* its 2–4px ink against a ship drawn 300 units
  /// wide, and the game draws that same ship at a fraction of the size
  /// inside a grid cell. Fixed ink on a shrinking hull is ink that grows
  /// relative to everything around it, until a destroyer at grid scale is
  /// mostly outline. That is exactly what it looked like on a small
  /// screen.
  ///
  /// So: scale ink with the drawing below the design's own reference
  /// size, and stop scaling at or above it. At full size the result is
  /// pixel-for-pixel what the design specifies; smaller, the proportions
  /// hold instead of the absolute weight. The floor keeps hairlines
  /// visible at the very smallest sizes.
  static double _inkScaleFor(double scale) =>
      scale >= 1 ? 1 : scale.clamp(0.0, 1.0);

  FamilyCanvas._(this.canvas, this._m, this.scale, this.inkScale);

  /// Maps [viewBox] onto [size], stretching if their aspect ratios differ.
  factory FamilyCanvas.stretch(Canvas canvas, Size size, Rect viewBox) {
    final sx = size.width / viewBox.width;
    final sy = size.height / viewBox.height;
    final m = Matrix4.identity()
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-viewBox.left, -viewBox.top, 0, 1);
    // A stretched box gets its ink from the AVERAGE of the two axes: a
    // hull squeezed to a 2-cell destroyer is much shorter than it is
    // thinner, and taking either axis alone would make the outline
    // lurch as ships of different lengths sit side by side.
    final s = (sx + sy) / 2;
    return FamilyCanvas._(canvas, m.storage, s, _inkScaleFor(s));
  }

  /// Maps [viewBox] onto [size] preserving aspect ratio, centred.
  factory FamilyCanvas.fit(Canvas canvas, Size size, Rect viewBox) {
    final s = (size.width / viewBox.width) < (size.height / viewBox.height)
        ? size.width / viewBox.width
        : size.height / viewBox.height;
    final dx = (size.width - viewBox.width * s) / 2;
    final dy = (size.height - viewBox.height * s) / 2;
    final m = Matrix4.identity()
      ..translateByDouble(dx, dy, 0, 1)
      ..scaleByDouble(s, s, 1, 1)
      ..translateByDouble(-viewBox.left, -viewBox.top, 0, 1);
    return FamilyCanvas._(canvas, m.storage, s, _inkScaleFor(s));
  }

  Path _mapped(Path p) => p.transform(_m);

  /// Design-space stroke width → the width to actually paint with.
  double ink(double designWidth) {
    final w = designWidth * inkScale;
    return w < _minInk ? _minInk : w;
  }

  // --------------------------------------------------------------- fills

  void fill(String d, Color color, {double opacity = 1}) {
    canvas.drawPath(
      _mapped(parseSvgPath(d)),
      Paint()..color = opacity == 1 ? color : color.withValues(alpha: opacity),
    );
  }

  void stroke(
    String d,
    Color color,
    double width, {
    double opacity = 1,
    StrokeCap cap = StrokeCap.butt,
    StrokeJoin join = StrokeJoin.round,
  }) {
    canvas.drawPath(
      _mapped(parseSvgPath(d)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink(width)
        ..strokeCap = cap
        ..strokeJoin = join
        ..color = opacity == 1 ? color : color.withValues(alpha: opacity),
    );
  }

  /// Fill then outline — by far the commonest shape in the design.
  void shape(
    String d, {
    Color? fillColor,
    double fillOpacity = 1,
    Color? inkColor,
    double inkWidth = 0,
    double inkOpacity = 1,
    StrokeJoin join = StrokeJoin.round,
  }) {
    final p = _mapped(parseSvgPath(d));
    if (fillColor != null) {
      canvas.drawPath(
        p,
        Paint()
          ..color = fillOpacity == 1
              ? fillColor
              : fillColor.withValues(alpha: fillOpacity),
      );
    }
    if (inkColor != null && inkWidth > 0) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ink(inkWidth)
          ..strokeJoin = join
          ..color = inkOpacity == 1
              ? inkColor
              : inkColor.withValues(alpha: inkOpacity),
      );
    }
  }

  // ------------------------------------------------------------ premades

  void ellipse(
    double cx,
    double cy,
    double rx,
    double ry, {
    Color? fillColor,
    double fillOpacity = 1,
    Color? inkColor,
    double inkWidth = 0,
    double inkOpacity = 1,
    List<double>? dash,
  }) {
    final p = _mapped(
      Path()..addOval(Rect.fromCenter(
          center: Offset(cx, cy), width: rx * 2, height: ry * 2)),
    );
    if (fillColor != null) {
      canvas.drawPath(
        p,
        Paint()
          ..color = fillOpacity == 1
              ? fillColor
              : fillColor.withValues(alpha: fillOpacity),
      );
    }
    if (inkColor != null && inkWidth > 0) {
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink(inkWidth)
        ..color = inkOpacity == 1
            ? inkColor
            : inkColor.withValues(alpha: inkOpacity);
      canvas.drawPath(dash == null ? p : _dashed(p, dash), paint);
    }
  }

  void circle(
    double cx,
    double cy,
    double r, {
    Color? fillColor,
    double fillOpacity = 1,
    Color? inkColor,
    double inkWidth = 0,
    double inkOpacity = 1,
    List<double>? dash,
  }) =>
      ellipse(cx, cy, r, r,
          fillColor: fillColor,
          fillOpacity: fillOpacity,
          inkColor: inkColor,
          inkWidth: inkWidth,
          inkOpacity: inkOpacity,
          dash: dash);

  void rect(
    double x,
    double y,
    double w,
    double h, {
    double r = 0,
    Color? fillColor,
    double fillOpacity = 1,
    Color? inkColor,
    double inkWidth = 0,
    double inkOpacity = 1,
  }) {
    final rr = r > 0
        ? (Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(x, y, w, h), Radius.circular(r))))
        : (Path()..addRect(Rect.fromLTWH(x, y, w, h)));
    final p = _mapped(rr);
    if (fillColor != null) {
      canvas.drawPath(
        p,
        Paint()
          ..color = fillOpacity == 1
              ? fillColor
              : fillColor.withValues(alpha: fillOpacity),
      );
    }
    if (inkColor != null && inkWidth > 0) {
      canvas.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = ink(inkWidth)
          ..strokeJoin = StrokeJoin.round
          ..color = inkOpacity == 1
              ? inkColor
              : inkColor.withValues(alpha: inkOpacity),
      );
    }
  }

  void line(
    double x1,
    double y1,
    double x2,
    double y2,
    Color color,
    double width, {
    double opacity = 1,
    StrokeCap cap = StrokeCap.butt,
    List<double>? dash,
  }) {
    final p = _mapped(Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2));
    canvas.drawPath(
      dash == null ? p : _dashed(p, dash),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink(width)
        ..strokeCap = cap
        ..color = opacity == 1 ? color : color.withValues(alpha: opacity),
    );
  }

  /// Dashed variant of an already-mapped path. Dash lengths are given in
  /// design units and scaled here, since a dash pattern IS a length along
  /// the path rather than an ink weight.
  Path _dashed(Path source, List<double> pattern) {
    final scaled = pattern.map((v) => v * scale).toList();
    final out = Path();
    for (final metric in source.computeMetrics()) {
      var distance = 0.0;
      var index = 0;
      var draw = true;
      while (distance < metric.length) {
        final len = scaled[index % scaled.length];
        if (draw) {
          out.addPath(
            metric.extractPath(distance, (distance + len).clamp(0, metric.length)),
            Offset.zero,
          );
        }
        distance += len;
        index++;
        draw = !draw;
      }
    }
    return out;
  }

  /// Strokes a path with a dash pattern (design units).
  void strokeDashed(
    String d,
    Color color,
    double width,
    List<double> pattern, {
    double opacity = 1,
  }) {
    canvas.drawPath(
      _dashed(_mapped(parseSvgPath(d)), pattern),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink(width)
        ..color = opacity == 1 ? color : color.withValues(alpha: opacity),
    );
  }

  /// Runs [body] with an extra rotation about a design-space point —
  /// the design uses `transform="rotate(a cx cy)"` in a few places.
  void rotated(double degrees, double cx, double cy, VoidCallback body) {
    canvas.save();
    // The transform is baked into paths, not the canvas, so rotate in
    // device space around the mapped centre.
    final mapped = MatrixUtils.transformPoint(
        Matrix4.fromFloat64List(_m), Offset(cx, cy));
    canvas.translate(mapped.dx, mapped.dy);
    canvas.rotate(degrees * 3.1415926535897932 / 180);
    canvas.translate(-mapped.dx, -mapped.dy);
    body();
    canvas.restore();
  }
}
