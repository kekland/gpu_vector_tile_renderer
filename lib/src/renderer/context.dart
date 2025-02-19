import 'package:flutter/widgets.dart';
import 'package:flutter_gpu/gpu.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart';
import 'package:gpu_vector_tile_renderer/src/utils/flutter_map/tile_scale_calculator.dart';

class PrepareContext {
  const PrepareContext({required this.eval});

  final EvaluationContext eval;
}

class RenderContext {
  const RenderContext({
    required this.pass,
    required this.size,
    required this.pixelRatio,
    required this.camera,
    required this.unscaledTileSize,
    required this.tileScaleCalculator,
    required this.eval,
  });

  final RenderPass pass;
  final Size size;
  final double pixelRatio;
  final MapCamera camera;
  final double unscaledTileSize;
  final EvaluationContext eval;
  final TileScaleCalculator tileScaleCalculator;

  double getScaledTileSize(TileCoordinates coordinates) =>
      tileScaleCalculator.scaledTileSize(camera.zoom, coordinates.z);

  Size get scaledSize => size * pixelRatio;

  Matrix4 get worldToGl {
    final worldToGl = Matrix4.identity();

    worldToGl.translate(-1.0, 1.0);
    worldToGl.scale(pixelRatio);
    worldToGl.scale(2.0 / scaledSize.width, -2.0 / scaledSize.height);
    worldToGl.translate(-camera.pixelOrigin.x, -camera.pixelOrigin.y);

    return worldToGl;
  }

  void setTileScissor(RenderPass pass, TileCoordinates coordinates) {
    final scaledTileSize = getScaledTileSize(coordinates);

    final origin = Offset(
      coordinates.x * scaledTileSize - camera.pixelOrigin.x,
      coordinates.y * scaledTileSize - camera.pixelOrigin.y,
    );

    var _x = (origin.dx * pixelRatio).ceil();
    var _y = (origin.dy * pixelRatio).ceil();
    var _width = (scaledTileSize * pixelRatio).ceil();
    var _height = (scaledTileSize * pixelRatio).ceil();

    if (_x < 0) {
      _width += _x;
      _width = _width.clamp(0, size.width * pixelRatio).ceil();
      _x = 0;
    }

    if (_y < 0) {
      _height += _y;
      _height = _height.clamp(0, size.height * pixelRatio).ceil();
      _y = 0;
    }

    pass.setScissor(Scissor(x: _x, y: _y, width: _width, height: _height));
  }
}
