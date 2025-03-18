import 'dart:math';

import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:gpu_vector_tile_renderer/src/renderer/atlas/atlas.dart';

/// [SymbolLayoutData] stores the computed layout data for symbols, without regard for the symbol placement.
class SymbolLayoutData {
  SymbolLayoutData({
    required this.glyphs,
    required this.width,
    required this.height,
  });

  final List<GlyphLayoutData> glyphs;
  final double width;
  final double height;
}

/// [GlyphLayoutData] stores the computed layout data for a glyph.
class GlyphLayoutData {
  GlyphLayoutData({
    required this.rune,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.uv,
  });

  final int rune;

  final double x;
  final double y;
  final double width;
  final double height;

  final AtlasUv uv;
}

class SymbolLayoutEngine {
  static Future<SymbolLayoutData?> performLayout(
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
    if (textField.isEmpty) return null;

    return performLayoutText(orchestrator, textField, feature, layout, eval);
  }

  static Future<SymbolLayoutData> performLayoutText(
    VectorTileLayerRenderOrchestrator orchestrator,
    spec.Formatted text,
    vt.Feature feature,
    spec.LayoutSymbol layout,
    spec.EvaluationContext eval,
  ) async {
    final font = layout.textFont.evaluate(eval);
    final size = layout.textSize.evaluate(eval);
    final maxWidth = layout.textMaxWidth.evaluate(eval);
    final lineHeight = layout.textLineHeight.evaluate(eval);
    final letterSpacing = layout.textLetterSpacing.evaluate(eval);
    final justify = layout.textJustify.evaluate(eval);
    final radialOffset = layout.textRadialOffset.evaluate(eval);
    final variableAnchor = layout.textVariableAnchor?.evaluate(eval);
    final variableAnchorOffset = layout.textVariableAnchorOffset?.evaluate(eval);
    final anchor = layout.textAnchor.evaluate(eval);
    final maxAngle = layout.textMaxAngle.evaluate(eval);
    final writingMode = layout.textWritingMode?.evaluate(eval);
    final rotate = layout.textRotate.evaluate(eval);
    final padding = layout.textPadding.evaluate(eval);
    final keepUpright = layout.textKeepUpright.evaluate(eval);
    final transform = layout.textTransform.evaluate(eval);
    final offset = layout.textOffset.evaluate(eval);
    final allowOverlap = layout.textAllowOverlap.evaluate(eval);
    final overlap = layout.textOverlap?.evaluate(eval);
    final ignorePlacement = layout.textIgnorePlacement.evaluate(eval);
    final optional = layout.textOptional.evaluate(eval);

    final loadedGlyphs = await orchestrator.loadGlyphs(text, font.join(','));

    final layoutGlyphs = <GlyphLayoutData>[];
    var width = 0.0;
    var height = 0.0;

    var x = 0.0;
    var y = 0.0;

    var i = 0;
    for (final section in text.sections) {
      if (section.text == null) continue;

      for (final rune in section.text!.runes) {
        final glyph = loadedGlyphs[i].$1;
        final uv = loadedGlyphs[i].$2;
        i++;

        layoutGlyphs.add(
          GlyphLayoutData(
            rune: rune,
            x: x + glyph.left,
            y: y - glyph.top,
            width: glyph.width.toDouble(),
            height: glyph.height.toDouble(),
            uv: uv,
          ),
        );

        x += glyph.advance;
        width += glyph.advance;
        height = max(height, glyph.height.toDouble());
      }
    }

    return SymbolLayoutData(
      glyphs: layoutGlyphs,
      width: width,
      height: height,
    );
  }
}
