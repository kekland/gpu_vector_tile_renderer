import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:vector_math/vector_math_64.dart';

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

  TMetrics getMetrics(TKey key);
  AtlasUv getUv(TKey key);

  (TMetrics, AtlasUv) get(TKey key);
}

class AtlasUv {
  AtlasUv({required this.uv0, required this.uv1});

  final Vector2 uv0;
  final Vector2 uv1;
}
