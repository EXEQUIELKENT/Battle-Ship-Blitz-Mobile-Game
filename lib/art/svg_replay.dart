import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'svg_path.dart';

/// PERF (brief stutter right when a battle screen's legacy cannons/boards
/// first paint — worst right after the app resumes from the background,
/// when Android's GPU-surface recreation forces every currently-mounted
/// painter to repaint at once regardless of any `shouldRepaint` gate):
/// [paintSvgFragment] re-tokenizes and regex-parses its whole markup
/// string from scratch on every call. Every legacy cannon/board's markup
/// is a fixed constant string per skin id (see `legacy_cannon_art.dart`'s
/// `_ringMarkup`/turret consts and `legacy_board_art.dart`'s board
/// consts) — the exact same string is replayed unchanged, call after
/// call, so there's nothing to re-parse.
///
/// [paintSvgFragmentCached] records the fragment into a `ui.Picture` the
/// FIRST time a given [source] string is seen, and replays that recorded
/// picture — a cheap, GPU-ready display list — on every call after. Kept
/// as a separate entry point (rather than caching inside
/// [paintSvgFragment] itself) so the caching only ever applies to markup
/// that is genuinely constant per call site; nothing here changes for a
/// caller building a fresh/dynamic string per call.
final Map<String, ui.Picture> _pictureCache = {};

void paintSvgFragmentCached(Canvas canvas, String source) {
  var picture = _pictureCache[source];
  if (picture == null) {
    final recorder = ui.PictureRecorder();
    paintSvgFragment(Canvas(recorder), source);
    picture = recorder.endRecording();
    _pictureCache[source] = picture;
  }
  canvas.drawPicture(picture);
}

/// Replays a *fragment* of raw design-tool SVG markup — `circle`,
/// `ellipse`, `rect`, `path` and one level of `g` grouping/transform —
/// directly onto [canvas], verbatim in the SVG's own design-space
/// coordinates and stroke widths.
///
/// This exists because hand-transcribing each shape into Dart calls (the
/// approach `legacy_ship_art.dart`/`family_*_art.dart` use for paths) loses
/// fidelity on art with many small layered shapes — stroke colours,
/// literal rivet/highlight positions, opacity layering — exactly the kind
/// of detail that is easy to approximate wrong by hand and hard to notice
/// until it's on screen next to the source. Replaying the markup directly
/// makes the Dart art byte-for-byte faithful to whatever was authored,
/// forever, with no re-transcription risk.
///
/// The caller is expected to have already set up the canvas's transform
/// (translate/scale to map the SVG's own design space onto the target
/// widget) — everything here draws in raw, untransformed source units, so
/// stroke widths and radii scale for free with the canvas's current
/// transform exactly as a real SVG viewer would scale them.
///
/// Deliberately NOT a general XML/SVG parser: it assumes the same small,
/// regular vocabulary every file under `uploads/New Design/` actually
/// uses (confirmed by inspecting every source file) — flat, single-level
/// `<g>` groups (no groups nested inside groups), only `translate(dx,dy)`
/// and `rotate(deg cx cy)` transforms, and `fill`/`stroke`/`stroke-width`/
/// `opacity` as the only inherited attributes. Silently ignores anything
/// outside that vocabulary rather than throwing, since the whole point is
/// to survive being handed a real design file.
void paintSvgFragment(Canvas canvas, String source) {
  final tags = RegExp(r'<[^>]+>').allMatches(source);
  var style = const _Style();
  // ROOT-CAUSE FIX (every legacy cannon's mount collar and its two
  // highlight rivets rendered almost invisibly — the "missing circle
  // detail in the middle of the gun"): `<g>` merged its own attributes
  // into `style` and `</g>` only ever restored the CANVAS, never the
  // style. So a group's `opacity` leaked out of it and multiplied into
  // everything drawn afterwards, for the rest of the fragment.
  //
  // Every legacy cannon's ring markup ends with the rivet-spiral group
  // `<g fill="#1E2A36" opacity="0.55">`, and MK-I alone adds a second
  // `<g fill="white" opacity="0.28">` after it. The mount circle and
  // rivets that follow specify no opacity of their own, so they were
  // inheriting 0.55 — and on MK-I 0.55 × 0.28 = 0.154, i.e. drawn at
  // 15% alpha. Present in the markup, byte-identical to the design
  // source, and all but invisible on screen.
  //
  // A group's style has to be scoped exactly like its transform is, so
  // it gets a stack of its own that unwinds in step with the canvas.
  final styleStack = <_Style>[];

  for (final m in tags) {
    final tag = m.group(0)!;
    if (tag.startsWith('</g')) {
      if (styleStack.isNotEmpty) {
        style = styleStack.removeLast();
        canvas.restore();
      }
      continue;
    }
    if (tag.startsWith('</') || tag.startsWith('<svg') || tag.startsWith('<?')) {
      continue;
    }
    final nameMatch = RegExp(r'^<([\w:-]+)').firstMatch(tag);
    if (nameMatch == null) continue;
    final name = nameMatch.group(1)!;
    final attrs = _attrs(tag);

    if (name == 'g') {
      canvas.save();
      styleStack.add(style);
      final t = attrs['transform'];
      if (t != null) _applyTransform(canvas, t);
      style = style.merge(attrs);
      continue;
    }

    final leafStyle = style.merge(attrs);
    switch (name) {
      case 'circle':
        _drawCircle(canvas, attrs, leafStyle);
      case 'ellipse':
        _drawEllipse(canvas, attrs, leafStyle);
      case 'rect':
        _drawRect(canvas, attrs, leafStyle);
      case 'path':
        _drawPath(canvas, attrs, leafStyle);
      case 'polygon':
        _drawPoly(canvas, attrs, leafStyle, close: true);
      case 'polyline':
        _drawPoly(canvas, attrs, leafStyle, close: false);
    }
  }
  // Unwind any groups a malformed/truncated fragment left open, so a bad
  // embed can't leave the caller's canvas transform stack imbalanced.
  while (styleStack.isNotEmpty) {
    styleStack.removeLast();
    canvas.restore();
  }
}

class _Style {
  final Color? fill;
  final Color? stroke;
  final double strokeWidth;
  final double opacity;

  const _Style({this.fill, this.stroke, this.strokeWidth = 1, this.opacity = 1});

  _Style merge(Map<String, String> a) {
    final fillAttr = a['fill'];
    final strokeAttr = a['stroke'];
    final opAttr = a['opacity'];
    final swAttr = a['stroke-width'];
    return _Style(
      fill: fillAttr == null ? fill : _parseColor(fillAttr),
      stroke: strokeAttr == null ? stroke : _parseColor(strokeAttr),
      strokeWidth: swAttr != null ? double.parse(swAttr) : strokeWidth,
      opacity: opAttr != null ? opacity * double.parse(opAttr) : opacity,
    );
  }
}

Map<String, String> _attrs(String tag) {
  final map = <String, String>{};
  for (final m in RegExp(r'''([\w:-]+)="([^"]*)"''').allMatches(tag)) {
    map[m.group(1)!] = m.group(2)!;
  }
  return map;
}

Color? _parseColor(String v) {
  if (v == 'none') return null;
  if (v == 'white') return Colors.white;
  if (v == 'black') return Colors.black;
  if (v.startsWith('#')) {
    final hex = v.substring(1);
    if (hex.length == 6) return Color(0xFF000000 | int.parse(hex, radix: 16));
    if (hex.length == 8) return Color(int.parse(hex, radix: 16));
  }
  return null;
}

double _op(Map<String, String> a, String key) =>
    a[key] != null ? double.parse(a[key]!) : 1.0;

StrokeCap _cap(String? v) => switch (v) {
      'round' => StrokeCap.round,
      'square' => StrokeCap.square,
      _ => StrokeCap.butt,
    };

StrokeJoin _join(String? v) => switch (v) {
      'round' => StrokeJoin.round,
      'bevel' => StrokeJoin.bevel,
      _ => StrokeJoin.miter,
    };

List<double>? _dash(String? v) {
  if (v == null) return null;
  final parts = v.trim().split(RegExp(r'[\s,]+')).map(double.parse).toList();
  return parts.isEmpty || parts.every((d) => d <= 0) ? null : parts;
}

Path _dashPath(Path source, List<double> dash) {
  final out = Path();
  for (final metric in source.computeMetrics()) {
    var d = 0.0;
    var i = 0;
    var draw = true;
    while (d < metric.length) {
      final segLen = dash[i % dash.length].clamp(0.01, double.infinity);
      final end = (d + segLen).clamp(0.0, metric.length);
      if (draw) out.addPath(metric.extractPath(d, end), Offset.zero);
      d = end;
      i++;
      draw = !draw;
    }
  }
  return out;
}

void _applyTransform(Canvas canvas, String t) {
  final translate = RegExp(r'translate\(\s*([-\d.]+)[,\s]+([-\d.]+)\s*\)').firstMatch(t);
  if (translate != null) {
    canvas.translate(double.parse(translate.group(1)!), double.parse(translate.group(2)!));
    return;
  }
  final rotate = RegExp(r'rotate\(\s*([-\d.]+)[,\s]+([-\d.]+)[,\s]+([-\d.]+)\s*\)').firstMatch(t);
  if (rotate != null) {
    final deg = double.parse(rotate.group(1)!);
    final cx = double.parse(rotate.group(2)!);
    final cy = double.parse(rotate.group(3)!);
    canvas.translate(cx, cy);
    canvas.rotate(deg * math.pi / 180);
    canvas.translate(-cx, -cy);
  }
}

void _fillAndStroke(Canvas canvas, Path path, Map<String, String> a, _Style st) {
  if (st.fill != null) {
    canvas.drawPath(path, Paint()..color = st.fill!.withValues(alpha: st.opacity * _op(a, 'fill-opacity')));
  }
  if (st.stroke != null && st.strokeWidth > 0) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = st.strokeWidth
      ..strokeCap = _cap(a['stroke-linecap'])
      ..strokeJoin = _join(a['stroke-linejoin'])
      ..color = st.stroke!.withValues(alpha: st.opacity * _op(a, 'stroke-opacity'));
    final dash = _dash(a['stroke-dasharray']);
    canvas.drawPath(dash == null ? path : _dashPath(path, dash), paint);
  }
}

void _drawCircle(Canvas canvas, Map<String, String> a, _Style st) {
  final cx = double.parse(a['cx'] ?? '0');
  final cy = double.parse(a['cy'] ?? '0');
  final r = double.parse(a['r'] ?? '0');
  _fillAndStroke(canvas, Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)), a, st);
}

void _drawEllipse(Canvas canvas, Map<String, String> a, _Style st) {
  final cx = double.parse(a['cx'] ?? '0');
  final cy = double.parse(a['cy'] ?? '0');
  final rx = double.parse(a['rx'] ?? '0');
  final ry = double.parse(a['ry'] ?? '0');
  _fillAndStroke(
    canvas,
    Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: rx * 2, height: ry * 2)),
    a,
    st,
  );
}

void _drawRect(Canvas canvas, Map<String, String> a, _Style st) {
  final x = double.parse(a['x'] ?? '0');
  final y = double.parse(a['y'] ?? '0');
  final w = double.parse(a['width'] ?? '0');
  final h = double.parse(a['height'] ?? '0');
  final rxAttr = a['rx'];
  final ryAttr = a['ry'];
  final rx = rxAttr != null ? double.parse(rxAttr) : (ryAttr != null ? double.parse(ryAttr) : 0.0);
  final ry = ryAttr != null ? double.parse(ryAttr) : rx;
  final path = Path()
    ..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.elliptical(rx, ry)));
  _fillAndStroke(canvas, path, a, st);
}

void _drawPath(Canvas canvas, Map<String, String> a, _Style st) {
  final d = a['d'];
  if (d == null) return;
  _fillAndStroke(canvas, parseSvgPath(d), a, st);
}

/// `<polygon>`/`<polyline>` — the design's `Ship Damage/*.svg` files draw
/// most of their crater and shrapnel geometry this way rather than as
/// paths, so replaying those files needs it.
void _drawPoly(Canvas canvas, Map<String, String> a, _Style st,
    {required bool close}) {
  final raw = a['points'];
  if (raw == null) return;
  final nums = raw
      .trim()
      .split(RegExp(r'[\s,]+'))
      .where((s) => s.isNotEmpty)
      .map(double.tryParse)
      .toList();
  if (nums.length < 4 || nums.any((v) => v == null)) return;
  final path = Path()..moveTo(nums[0]!, nums[1]!);
  for (var i = 2; i + 1 < nums.length; i += 2) {
    path.lineTo(nums[i]!, nums[i + 1]!);
  }
  if (close) path.close();
  _fillAndStroke(canvas, path, a, st);
}
