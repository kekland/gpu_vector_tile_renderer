import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:gpu_vector_tile_renderer/_glyphs.dart' as glyphs;
import 'package:gpu_vector_tile_renderer/src/renderer/atlas/atlas.dart';
import 'package:gpu_vector_tile_renderer/src/renderer/atlas/glyph_manager.dart';
import 'package:gpu_vector_tile_renderer/src/renderer/layers/symbol/symbol_baseline.dart';
import 'package:gpu_vector_tile_renderer/src/spec/spec.dart';

/// [SymbolLayoutData] stores the computed layout data for a single symbol placement.
class SymbolLayoutData {
  SymbolLayoutData({
    required this.glyphs,
    required this.anchor,
    required this.width,
    required this.height,
  });

  final List<GlyphLayoutData> glyphs;
  final Offset anchor;
  final double width;
  final double height;

  SymbolLayoutData copyShifted(Offset offset) {
    final newGlyphs = glyphs.map((glyph) {
      return glyph.copyWith();
    }).toList();

    return SymbolLayoutData(
      glyphs: newGlyphs,
      anchor: anchor + offset,
      width: width,
      height: height,
    );
  }
}

/// [GlyphLayoutData] stores the computed layout data for a single glyph.
class GlyphLayoutData {
  GlyphLayoutData({
    required this.rune,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.advance,
    required this.angleRad,
    required this.uv,
  });

  final int rune;

  double x;
  double y;
  double width;
  double height;
  double advance;
  double angleRad;

  final AtlasUv uv;

  GlyphLayoutData copyWith({
    double? x,
    double? y,
    double? width,
    double? height,
    double? advance,
    double? angleRad,
  }) {
    return GlyphLayoutData(
      rune: rune,
      x: x ?? this.x,
      y: y ?? this.y,
      width: width ?? this.width,
      height: height ?? this.height,
      advance: advance ?? this.advance,
      angleRad: angleRad ?? this.angleRad,
      uv: uv,
    );
  }
}

class SymbolLayoutEngine {
  static Future<List<SymbolLayoutData>> performLayout(
    VectorTileLayerRenderOrchestrator orchestrator,
    vt.Feature feature,
    spec.LayoutSymbol layout,
    spec.EvaluationContext eval,
  ) async {
    // No icons for now.
    // if (layout.iconImage != null) {
    //   performIconLayout(feature, layout, eval);
    // }

    final textField = layout.textField.evaluate(eval);
    if (textField.isEmpty) return [];

    return performLayoutText(orchestrator, textField, feature, layout, eval);
  }

  static List<SymbolBaseline> _getBaselines(
    spec.EvaluationContext eval,
    spec.LayoutSymbol layout,
    vt.Feature feature,
  ) {
    final placement = layout.symbolPlacement.evaluate(eval);

    if (placement == spec.LayoutSymbol$SymbolPlacement.point) {
      final points = switch (feature) {
        vt.PointFeature f => f.points,
        vt.LineStringFeature f => f.lines.map((v) => v.points).expand((v) => v),
        vt.PolygonFeature f => f.polygons.map((v) => v.exterior.points).expand((v) => v),
        _ => throw UnimplementedError(),
      };

      return points.map(PointSymbolBaseline.new).toList();
    } else if (placement == spec.LayoutSymbol$SymbolPlacement.line) {
      final lines = switch (feature) {
        vt.LineStringFeature f => f.lines.map((v) => v.points),
        vt.PolygonFeature f => f.polygons.map((v) => v.exterior.points),
        _ => throw UnimplementedError(),
      };

      return lines.map(SplineSymbolBaseline.new).toList();
    } else if (placement == spec.LayoutSymbol$SymbolPlacement.lineCenter) {
      final lines = switch (feature) {
        vt.LineStringFeature f => f.lines.map((v) => v.points),
        vt.PolygonFeature f => f.polygons.map((v) => v.exterior.points),
        _ => throw UnimplementedError(),
      };

      return lines.map(CenterSplineSymbolBaseline.new).toList();
    }

    throw UnimplementedError();
  }

  static spec.Formatted _transformText(
    VectorTileLayerRenderOrchestrator orchestrator,
    spec.EvaluationContext eval,
    spec.LayoutSymbol layout,
    spec.Formatted text,
  ) {
    final transform = layout.textTransform.evaluate(eval);
    final transformedSections = <spec.FormattedSection>[];
    final operation = switch (transform) {
      spec.LayoutSymbol$TextTransform.uppercase => (String text) => text.toUpperCase(),
      spec.LayoutSymbol$TextTransform.lowercase => (String text) => text.toLowerCase(),
      spec.LayoutSymbol$TextTransform.none => (String text) => text,
    };

    for (final section in text.sections) {
      late final spec.FormattedSection transformedSection;

      if (section.text != null) {
        transformedSection = spec.FormattedSection.text(
          text: operation(section.text!),
          scale: section.scale,
          fontStack: section.fontStack,
          textColor: section.textColor,
        );
      } else {
        transformedSection = section;
      }

      transformedSections.add(transformedSection);
    }

    return spec.Formatted(sections: transformedSections);
  }

  static Future<List<GlyphData>> _loadGlyphs(
    VectorTileLayerRenderOrchestrator orchestrator,
    spec.EvaluationContext eval,
    spec.LayoutSymbol layout,
    spec.Formatted text,
  ) async {
    final font = layout.textFont.evaluate(eval);
    return orchestrator.loadGlyphs(text, font.join(','));
  }

  static SymbolLayoutData _layoutSinglePlacement(
    VectorTileLayerRenderOrchestrator orchestrator,
    spec.EvaluationContext eval,
    spec.LayoutSymbol layout,
    spec.Formatted transformedText,
    List<GlyphData> loadedGlyphs, {
    bool multiline = false,
  }) {
    final anchor = layout.textAnchor.evaluate(eval);
    final size = layout.textSize.evaluate(eval);
    final maxWidthEm = layout.textMaxWidth.evaluate(eval);
    final lineHeightEm = layout.textLineHeight.evaluate(eval);
    final letterSpacingEm = layout.textLetterSpacing.evaluate(eval);
    final justify = layout.textJustify.evaluate(eval);
    final maxAngle = layout.textMaxAngle.evaluate(eval);
    final writingMode = layout.textWritingMode?.evaluate(eval);
    final rotate = layout.textRotate.evaluate(eval);
    final padding = layout.textPadding.evaluate(eval);
    final keepUpright = layout.textKeepUpright.evaluate(eval);
    final offset = layout.textOffset.evaluate(eval);

    final lineHeight = (size * lineHeightEm).toDouble();

    final _lines = <List<GlyphLayoutData>>[[]];
    final _lineWidths = <double>[0.0];

    final _maxWidth = maxWidthEm * size;

    const wordBreakRunes = [0x0020];
    const sdfPadding = 3.0;

    var i = 0;
    for (final section in transformedText.sections) {
      if (section.text == null) continue; // TODO: Implement images.
      final _size = size * (section.scale ?? 1);
      final _scale = (_size / 24.0);

      for (final rune in section.text!.runes) {
        final (glyph, uv) = loadedGlyphs[i];
        i++;

        // Check if the rune is a whitespace.
        if (multiline && wordBreakRunes.contains(rune)) {
          if (_lineWidths.last > _maxWidth) {
            _lines.add([]);
            _lineWidths.add(0.0);

            continue;
          }
        }

        final advance = glyph.advance * _scale + (_size * letterSpacingEm);
        final left = glyph.left * _scale;
        final top = glyph.top * _scale;
        final width = glyph.width * _scale;
        final height = glyph.height * _scale;

        _lines.last.add(
          GlyphLayoutData(
            rune: rune,
            uv: uv,
            x: _lineWidths.last + left,
            y: -top,
            width: width,
            height: height,
            advance: advance,
            angleRad: 0.0,
          ),
        );

        _lineWidths.last += advance;
      }
    }

    final width = _lineWidths.reduce(max);
    final height = _lines.length * lineHeight;

    final anchorPosition = switch (anchor) {
      spec.LayoutSymbol$TextAnchor.topLeft => Offset(0.0, 0.0),
      spec.LayoutSymbol$TextAnchor.left => Offset(0.0, -height / 2),
      spec.LayoutSymbol$TextAnchor.bottomLeft => Offset(0.0, -height),
      spec.LayoutSymbol$TextAnchor.top => Offset(-width / 2, 0.0),
      spec.LayoutSymbol$TextAnchor.center => Offset(-width / 2, -height / 2),
      spec.LayoutSymbol$TextAnchor.bottom => Offset(-width / 2, -height),
      spec.LayoutSymbol$TextAnchor.topRight => Offset(-width, 0.0),
      spec.LayoutSymbol$TextAnchor.right => Offset(-width, -height / 2),
      spec.LayoutSymbol$TextAnchor.bottomRight => Offset(-width, -height),
    };

    if (multiline) {
      // Auto justify is dependent on the anchor.
      final _justify = justify == LayoutSymbol$TextJustify.auto
          ? switch (anchor) {
              spec.LayoutSymbol$TextAnchor.center => spec.LayoutSymbol$TextJustify.center,
              spec.LayoutSymbol$TextAnchor.left => spec.LayoutSymbol$TextJustify.left,
              spec.LayoutSymbol$TextAnchor.right => spec.LayoutSymbol$TextJustify.right,
              spec.LayoutSymbol$TextAnchor.top => spec.LayoutSymbol$TextJustify.center,
              spec.LayoutSymbol$TextAnchor.bottom => spec.LayoutSymbol$TextJustify.center,
              spec.LayoutSymbol$TextAnchor.topLeft => spec.LayoutSymbol$TextJustify.left,
              spec.LayoutSymbol$TextAnchor.topRight => spec.LayoutSymbol$TextJustify.right,
              spec.LayoutSymbol$TextAnchor.bottomLeft => spec.LayoutSymbol$TextJustify.left,
              spec.LayoutSymbol$TextAnchor.bottomRight => spec.LayoutSymbol$TextJustify.right,
            }
          : justify;

      // Apply text-justify, anchor offset and line-height to glyphs.
      for (var i = 0; i < _lines.length; i++) {
        final line = _lines[i];
        final lineWidth = _lineWidths[i];

        final justifyOffset = Offset(
          switch (_justify) {
            spec.LayoutSymbol$TextJustify.left => 0.0,
            spec.LayoutSymbol$TextJustify.center => (width - lineWidth) / 2,
            spec.LayoutSymbol$TextJustify.right => width - lineWidth,
            // Auto is handled above.
            _ => throw StateError('Impossible justify: $_justify'),
          },
          i * lineHeight,
        );

        for (final glyph in line) {
          glyph.x += justifyOffset.dx + anchorPosition.dx + offset[0];
          glyph.y += justifyOffset.dy + anchorPosition.dy + offset[1];
        }
      }

      return SymbolLayoutData(
        anchor: Offset.zero,
        glyphs: _lines.expand((v) => v).toList(),
        width: width,
        height: height,
      );
    } else {
      assert(_lines.length == 1);
      assert(_lineWidths.length == 1);

      return SymbolLayoutData(
        anchor: Offset.zero,
        glyphs: _lines[0],
        width: width,
        height: height,
      );
    }
  }

  static Future<List<SymbolLayoutData>> performLayoutText(
    VectorTileLayerRenderOrchestrator orchestrator,
    spec.Formatted text,
    vt.Feature feature,
    spec.LayoutSymbol layout,
    spec.EvaluationContext eval,
  ) async {
    final transformedText = _transformText(orchestrator, eval, layout, text);
    final loadedGlyphs = await _loadGlyphs(orchestrator, eval, layout, transformedText);

    final placement = layout.symbolPlacement.evaluate(eval);
    final multiline = placement == spec.LayoutSymbol$SymbolPlacement.point;

    final singlePlacement = _layoutSinglePlacement(
      orchestrator,
      eval,
      layout,
      transformedText,
      loadedGlyphs,
      multiline: multiline,
    );

    final baselines = _getBaselines(eval, layout, feature);
    return baselines.map((v) => v.applyTo(singlePlacement)).expand((v) => v).toList();
  }
}
