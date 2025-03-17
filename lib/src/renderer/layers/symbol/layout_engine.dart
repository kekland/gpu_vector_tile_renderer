import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;

class SymbolLayoutEngine {
  static Future<void> performLayout(
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
    if (textField.isEmpty) return;

    await performLayoutText(orchestrator, textField, feature, layout, eval);
  }

  static Future<void> performLayoutText(
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

    final glyphs = await orchestrator.loadGlyphs(text, font.join(','));

    var i = 0;
    for (final section in text.sections) {
      if (section.text == null) continue;

      for (final rune in section.text!.runes) {
        final glyph = glyphs[i];
        i++;
      }
    }
  }
}
