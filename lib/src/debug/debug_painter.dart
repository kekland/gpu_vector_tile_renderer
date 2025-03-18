import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:gpu_vector_tile_renderer/_controller.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_utils.dart';
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:gpu_vector_tile_renderer/src/utils/flutter_map/tile_scale_calculator.dart';

void debugPaint(
  Canvas canvas,
  Size size, {
  required VectorTileLayerController controller,
  required MapCamera camera,
  required double tileSize,
}) {
  final debugAttachment = controller.debugAttachment;

  final tileScaleCalculator = TileScaleCalculator(crs: camera.crs, tileSize: tileSize);
  tileScaleCalculator.clearCacheUnlessZoomMatches(camera.zoom);

  final eval = spec.EvaluationContext.empty().copyWithZoom(camera.zoom);

  for (final tile in controller.tiles) {
    if (tile.isLoaded) {
      final vt = tile.vectorTiles.values.first;
      final tileSize = tileScaleCalculator.scaledTileSize(camera.zoom, tile.coordinates.z);
      final origin = Offset(
        tile.coordinates.x * tileSize - camera.pixelOrigin.x,
        tile.coordinates.y * tileSize - camera.pixelOrigin.y,
      );

      final transform = Matrix4.identity()
        ..translate(origin.dx, origin.dy)
        ..scale(tileSize / vt.layers.first.extent, tileSize / vt.layers.first.extent);

      // canvas.drawRect(
      //   Rect.fromLTWH(origin.dx, origin.dy, tileSize, tileSize),
      //   Paint()
      //     ..color = Colors.black.withValues(alpha: 0.2)
      //     ..style = PaintingStyle.stroke,
      // );

      canvas.save();
      canvas.transform(transform.storage);
      canvas.clipRect(Rect.fromLTWH(0, 0, vt.layers.first.extent.toDouble(), vt.layers.first.extent.toDouble()));
      debugPaintTile(canvas, size, vt, controller.style, eval, layerIds: debugAttachment.debugPaintLayers);
      canvas.restore();
    }
  }
}

void _drawPointFeature(Canvas canvas, Size size, vt.PointFeature feature, Color color) {
  for (final point in feature.points) {
    canvas.drawCircle(point, 16.0, Paint()..color = color);
  }
}

void _drawLines(Canvas canvas, Size size, List<Offset> points, Color color, {double strokeWidth = 1.0}) {
  canvas.drawPoints(
    PointMode.polygon,
    points,
    Paint()
      ..color = color
      ..strokeWidth = strokeWidth,
  );
}

void _drawLineStringFeature(Canvas canvas, Size size, vt.LineStringFeature feature, Color color) {
  for (final line in feature.lines) {
    _drawLines(canvas, size, line.points, color);
  }
}

void _drawPolygonFeature(Canvas canvas, Size size, vt.PolygonFeature feature, Color color) {
  for (final polygon in feature.polygons) {
    _drawLines(canvas, size, polygon.exterior.points, color, strokeWidth: 2);

    for (final interior in polygon.interiors) {
      _drawLines(canvas, size, interior.points, color.withValues(alpha: 0.25));
    }
  }
}

void debugPaintLayer(
  Canvas canvas,
  Size size,
  vt.Layer layer,
  spec.Layer? specLayer,
  spec.EvaluationContext eval,
  Color color,
) {
  for (final feature in layer.features) {
    final _feature = feature;
    if (specLayer?.filter?.evaluate(eval.forFeature(feature)) == false) continue;

    if (_feature is vt.PointFeature) {
      _drawPointFeature(canvas, size, _feature, color);
    } else if (_feature is vt.LineStringFeature) {
      _drawLineStringFeature(canvas, size, _feature, color);
    } else if (_feature is vt.PolygonFeature) {
      _drawPolygonFeature(canvas, size, _feature, color);
    }
  }
}

void debugPaintTile(
  Canvas canvas,
  Size size,
  vt.Tile tile,
  spec.Style style,
  spec.EvaluationContext eval, {
  List<String>? layerIds,
}) {
  for (final specLayer in style.layers) {
    if (specLayer.sourceLayer == null) continue;
    if (layerIds != null && !layerIds.contains(specLayer.id)) continue;

    final vtLayer = tile.layers.firstWhereOrNull((l) => l.name == specLayer.sourceLayer);
    if (vtLayer == null) continue;

    debugPaintLayer(canvas, size, vtLayer, specLayer, eval, Colors.red);
  }
}
