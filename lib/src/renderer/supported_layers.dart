import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;

/// List of layer types that can be rendered by the renderer.
const supportedLayerTypes = {
  spec.Layer$Type.background,
  spec.Layer$Type.fill,
  spec.Layer$Type.line,
  spec.Layer$Type.symbol,
};

/// Returns whether the given layer is supported by the renderer.
bool isLayerSupported(spec.Layer layer) => supportedLayerTypes.contains(layer.type);
