import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:gpu_vector_tile_renderer/src/renderer/layers/symbol/layout_engine.dart';

/// Base class for symbol baselines.
abstract class SymbolBaseline {
  const SymbolBaseline();

  List<SymbolLayoutData> applyTo(SymbolLayoutData layout);
}

/// A symbol baseline that is placed horizontally (screen-space) at an anchor point.
class PointSymbolBaseline extends SymbolBaseline {
  const PointSymbolBaseline(this.anchor);

  final ui.Offset anchor;

  @override
  List<SymbolLayoutData> applyTo(SymbolLayoutData layout) {
    return [layout.copyShifted(anchor)];
  }
}

abstract class _Spline {
  _Spline({required this.points});

  factory _Spline.create(List<ui.Offset> points) {
    if (points.length == 2) {
      return _LinearSpline(points: points);
    } else if (points.length == 3) {
      return _QuadraticBezierSpline(points: points);
    } else if (points.length > 3) {
      return _CatmullRomSpline(points: points);
    } else {
      throw ArgumentError('Invalid number of control points: ${points.length}');
    }
  }

  final List<ui.Offset> points;
  late final double length;

  ui.Offset transform(double t);
}

class _LinearSpline extends _Spline {
  _LinearSpline({required super.points}) {
    length = (points[1] - points[0]).distance;
  }

  @override
  ui.Offset transform(double t) {
    return ui.Offset(
      points[0].dx + (points[1].dx - points[0].dx) * t,
      points[0].dy + (points[1].dy - points[0].dy) * t,
    );
  }
}

class _QuadraticBezierSpline extends _Spline {
  _QuadraticBezierSpline({required super.points}) {
    length = _computeLength();
  }

  double _computeLength() {
    // TODO: placeholder
    return (points[2] - points[0]).distance;
  }

  @override
  ui.Offset transform(double t) {
    final tSq = t * t;
    final invT = 1 - t;
    final invTSq = invT * invT;

    return points[0] * invTSq + points[1] * 2 * invT * t + points[2] * tSq;
  }
}

class _CatmullRomSpline extends _Spline {
  _CatmullRomSpline({required super.points}) {
    _internalSpline = CatmullRomSpline(points);
    _computeLength();
  }

  late final CatmullRomSpline _internalSpline;

  /// Computes the approximate total length of the spline.
  void _computeLength() {
    // Compute the length of the spline by sampling it at discrete intervals.
    final samples = _internalSpline.generateSamples();
    var length = 0.0;

    final iterator = samples.iterator;
    if (!iterator.moveNext()) {
      this.length = 0.0;
      return;
    }

    var last = iterator.current;
    while (iterator.moveNext()) {
      final current = iterator.current;
      length += (current.value - last.value).distance;
      last = current;
    }

    this.length = length;
  }

  @override
  ui.Offset transform(double t) => _internalSpline.transform(t);
}

/// A symbol baseline that is placed along a spline.
///
/// Internally uses [CatmullRomSpline].
class SplineSymbolBaseline extends SymbolBaseline {
  SplineSymbolBaseline(List<ui.Offset> controlPoints) : _spline = _Spline.create(controlPoints);

  final _Spline _spline;
  double get _length => _spline.length;

  @override
  List<SymbolLayoutData> applyTo(SymbolLayoutData layout) {
    if (layout.width > _length) {
      // Placement is too wide to fit on the spline.
      return [];
    }

    final placements = <SymbolLayoutData>[];
    var x = 0.0;

    while (true) {
      if (x > _length) {
        // No more space on the spline.
        break;
      }

      final placementGlyphs = <GlyphLayoutData>[];
      var isEnd = false;

      final anchor = _spline.transform(x / _length);

      for (final glyph in layout.glyphs) {
        x += glyph.advance;

        // Glyph is laid out at x.
        if (x + glyph.width > _length) {
          isEnd = true;
          break;
        }

        // Compute the position on the spline at x.
        final position = _spline.transform(x / _length);
        final glyphX = position.dx - anchor.dx;
        final glyphY = position.dy - anchor.dy;

        placementGlyphs.add(glyph.copyWith(x: glyphX, y: glyphY));
        // TODO: rotation
      }

      if (isEnd) break;
      if (placementGlyphs.isNotEmpty) {
        placements.add(
          SymbolLayoutData(
            anchor: anchor,
            glyphs: placementGlyphs,
            width: layout.width,
            height: layout.height,
          ),
        );
      }

      x += 300.0;
    }

    return placements;
  }
}

/// A symbol baseline that places the text at the center of a spline.
class CenterSplineSymbolBaseline extends SplineSymbolBaseline {
  CenterSplineSymbolBaseline(super.controlPoints);

  @override
  List<SymbolLayoutData> applyTo(SymbolLayoutData layout) {
    if (layout.width > _length) {
      // Placement is too wide to fit on the spline.
      return [];
    }

    final anchor = _spline.transform(0.5);
    return [layout.copyShifted(anchor)];
  }
}
