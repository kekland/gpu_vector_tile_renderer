import 'package:flutter_gpu/gpu.dart' as gpu;

/// An atlas stores a collection of images, their corresponding positions, and the metadata needed to layout/render
/// them. The atlas will also manage creating and updating the images in the GPU.
///
/// Current atlas implementations are:
/// - [GlyphAtlas]
/// - [SpriteAtlas]
///
/// Generics:
/// - [TKey] refers to the key type that will be used to query the atlas for a specific image.
/// - [TMetrics] refers to the metrics type that will be returned when querying the atlas for a specific image.
abstract class Atlas<TKey, TMetrics> {
  gpu.Texture get texture;

  bool hasKey(TKey key);

  (int x, int y) getPosition(TKey key);
  TMetrics getMetrics(TKey key);
}
