import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_utils.dart';
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:gpu_vector_tile_renderer/src/renderer/layers/symbol/layout_engine.dart';

abstract class $SymbolLayerRenderer extends SingleTileLayerRenderer<spec.LayerSymbol> {
  $SymbolLayerRenderer({
    required super.coordinates,
    required super.container,
    required super.specLayer,
    required super.vtLayer,
  });

  @override
  void prepare(PrepareContext context) {
    final layout = specLayer.layout;

    final features = filterFeatures(
      vtLayer,
      specLayer,
      context.eval,
      sortKey: specLayer.layout.symbolSortKey,
    );

    for (final feature in features) {
      final eval = context.eval.forFeature(feature);
      final symbolPlacement = layout.symbolPlacement.evaluate(eval);

      // For now, we only support point placement.
      if (symbolPlacement != spec.LayoutSymbol$SymbolPlacement.point) continue;
      if (feature is! vt.PointFeature) continue;
    }
  }
}
