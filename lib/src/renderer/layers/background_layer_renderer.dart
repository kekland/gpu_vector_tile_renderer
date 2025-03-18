import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/src/shaders/bindings/shader_bindings.dart';
import 'package:vector_math/vector_math_64.dart';

abstract class $BackgroundLayerRenderer extends SingleTileLayerRenderer<spec.LayerBackground> {
  $BackgroundLayerRenderer({
    required super.orchestrator,
    required super.coordinates,
    required super.container,
    required super.specLayer,
    required super.vtLayer,
  });

  RenderPipelineBindings get pipeline;

  void setVertices();

  @override
  void prepare(PrepareContext context) {
    pipeline.vertex.allocateVertices(gpu.gpuContext, 4);
    pipeline.vertex.allocateIndices(gpu.gpuContext, [0, 1, 2, 0, 2, 3]);
    setVertices();
    pipeline.upload(gpu.gpuContext);
  }

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
  void draw(RenderContext context) {
    if (!pipeline.isReady) return;

    final tileSize = context.getScaledTileSize(coordinates);
    final extent = vtLayer.extent.toDouble();
    final tileLocalToWorld =
        Matrix4.identity()
          ..translate(coordinates.x * tileSize, coordinates.y * tileSize)
          ..scale(tileSize);

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
    pipeline.bind(gpu.gpuContext, context.pass);

    context.pass.draw();
    context.pass.clearBindings();
  }
}
