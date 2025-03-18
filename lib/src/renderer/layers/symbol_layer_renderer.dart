import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart';
import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_shaders.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_utils.dart';
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:vector_math/vector_math_64.dart';

export './symbol/layout_engine.dart';

abstract class $SymbolLayerRenderer extends SingleTileLayerRenderer<spec.LayerSymbol> {
  $SymbolLayerRenderer({
    required super.orchestrator,
    required super.coordinates,
    required super.container,
    required super.specLayer,
    required super.vtLayer,
  });

  RenderPipelineBindings get pipeline;

  Texture get glyphTexture => orchestrator.glyphManager.texture;

  int setFeatureVertices(
    spec.EvaluationContext eval,
    vt.PointFeature feature,
    Iterable<Vector2> anchors,
    SymbolLayoutData layoutData,
    int index,
  );

  void setUniforms(
    RenderContext context,
    Matrix4 cameraWorldToGl,
    double cameraZoom,
    double pixelRatio,
    Matrix4 tileLocalToGl,
    double tileSize,
    double tileExtent,
    double tileOpacity,
  );

  @override
  Future<void> prepare(PrepareContext context) async {
    final layout = specLayer.layout;

    final features = filterFeatures(
      vtLayer,
      specLayer,
      context.eval,
      sortKey: specLayer.layout.symbolSortKey,
    );

    final layoutDataFutures = <Future<SymbolLayoutData?>>[];
    final filteredFeatures = <vt.PointFeature>[];

    for (final feature in features) {
      final eval = context.eval.forFeature(feature);
      final symbolPlacement = layout.symbolPlacement.evaluate(eval);

      // For now, we only support point placement.
      if (symbolPlacement != spec.LayoutSymbol$SymbolPlacement.point) continue;
      if (feature is! vt.PointFeature) continue;

      filteredFeatures.add(feature);
      layoutDataFutures.add(SymbolLayoutEngine.performLayout(orchestrator, feature, layout, eval));
    }

    final layoutDatas = (await layoutDataFutures.wait);
    var vertexCount = 0;

    for (var i = 0; i < layoutDatas.length; i++) {
      final layoutData = layoutDatas[i];
      if (layoutData == null) continue;

      final anchorCount = filteredFeatures[i].points.length;

      // For each anchor, we'll have a [layoutData].
      vertexCount += anchorCount * (layoutData.glyphs.length * 4);
    }

    if (vertexCount == 0) return;
    pipeline.vertex.allocateVertices(gpuContext, vertexCount);

    // For each quad, we'll have 6 indices.
    assert(vertexCount % 4 == 0);
    final indexCount = vertexCount ~/ 4 * 6;
    final indexBuffer = Int32List(indexCount);

    var vertexIndex = 0;
    for (var i = 0; i < layoutDatas.length; i++) {
      final layoutData = layoutDatas[i];
      if (layoutData == null) continue;

      final feature = filteredFeatures[i];
      final anchors = feature.points;

      final featureEval = context.eval.forFeature(feature);
      vertexIndex = setFeatureVertices(
        featureEval,
        feature,
        anchors.map((v) => v.vec2),
        layoutData,
        vertexIndex,
      );
    }

    // Create index buffer. For each quad, it's 6 indices
    for (var i = 0; i < indexCount; i += 6) {
      final b = i ~/ 6 * 4;
      indexBuffer[i + 0] = b + 0;
      indexBuffer[i + 1] = b + 1;
      indexBuffer[i + 2] = b + 2;
      indexBuffer[i + 3] = b + 2;
      indexBuffer[i + 4] = b + 3;
      indexBuffer[i + 5] = b + 0;
    }

    pipeline.vertex.allocateIndicesDirect(gpuContext, indexBuffer);
    pipeline.upload(gpuContext);
  }

  @override
  void draw(RenderContext context) {
    if (!pipeline.isReady) return;

    final tileSize = context.getScaledTileSize(coordinates);
    final extent = vtLayer.extent.toDouble();
    final tileLocalToWorld = Matrix4.identity()
      ..translate(coordinates.x * tileSize, coordinates.y * tileSize)
      ..scale(tileSize / extent);

    setUniforms(
      context,
      context.worldToGl,
      context.camera.zoom,
      context.pixelRatio,
      context.worldToGl * tileLocalToWorld,
      tileSize,
      extent,
      container.opacityAnimation.value,
    );

    context.setTileScissor(context.pass, coordinates);
    pipeline.bind(gpuContext, context.pass);

    context.pass.draw();
    context.pass.clearBindings();
  }
}
