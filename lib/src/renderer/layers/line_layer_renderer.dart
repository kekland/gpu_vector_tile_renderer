import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_gpu/gpu.dart' as gpu;
import 'package:gpu_vector_tile_renderer/_renderer.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/_utils.dart';
import 'package:gpu_vector_tile_renderer/_vector_tile.dart' as vt;
import 'package:gpu_vector_tile_renderer/src/shaders/bindings/shader_bindings.dart';
import 'package:vector_math/vector_math_64.dart';

const _kLineCapRoundSegments = 16;

abstract class $LineLayerRenderer extends SingleTileLayerRenderer<spec.LayerLine> {
  $LineLayerRenderer({
    required super.orchestrator,
    required super.coordinates,
    required super.container,
    required super.specLayer,
    required super.vtLayer,
  });

  RenderPipelineBindings get pipeline;

  int setFeatureVertices(
    spec.EvaluationContext eval,
    vt.LineStringFeature feature,
    int index,
    List<(Vector2 position, Vector2 normal, double lineLength)> vertexData,
  );

  @override
  void prepare(PrepareContext context) {
    final features = filterFeatures<vt.LineStringFeature>(
      vtLayer,
      specLayer,
      context.eval,
      sortKey: specLayer.layout.lineSortKey,
    );

    if (features.isEmpty) return;

    // TODO: this has to be evaluated per-feature.
    final lineCap = specLayer.layout.lineCap.evaluate(context.eval);

    // TODO:
    // final lineJoin = specLayer.layout.lineJoin.evaluate(context.eval);
    // final miterLimit = specLayer.layout.lineMiterLimit.evaluate(context.eval);
    // final roundLimit = specLayer.layout.lineRoundLimit.evaluate(context.eval);

    // Contains the list of (position, normal, lineLength) for each vertex, grouped by feature.
    final vertexData = <List<(Vector2 position, Vector2 normal, double lineLength)>>[];
    final indices = <int>[];
    var vertexCount = 0;
    var currentLength = 0.0;

    void _addRelativeIndices(List<int> idx) {
      indices.addAll(idx.map((i) => i + vertexCount));
    }

    // Add cap going from a to b.
    void _addCap(Vector2 a, Vector2 b) {
      if (lineCap == spec.LayoutLine$LineCap.butt) return;

      final t = (b - a)..normalize();
      final n = Vector2(t.y, -t.x);

      if (lineCap == spec.LayoutLine$LineCap.square) {
        _addRelativeIndices([0, 1, 2, 1, 2, 3]);

        vertexData.last.add((a, n, currentLength));
        vertexData.last.add((a, -n, currentLength));

        vertexData.last.add((a, t + n, currentLength));
        vertexData.last.add((a, t - n, currentLength));

        vertexCount += 4;
      } else if (lineCap == spec.LayoutLine$LineCap.round) {
        final center = a;
        final startAngle = math.atan2(-n.y, -n.x);

        vertexData.last.add((center, Vector2.zero(), currentLength));
        final centerIndex = vertexCount;

        for (var i = 0; i <= _kLineCapRoundSegments; i++) {
          final angle = startAngle + i / _kLineCapRoundSegments * math.pi;
          final vec = Vector2(math.cos(angle), math.sin(angle));

          vertexData.last.add((center, vec, currentLength));
        }

        for (var i = 0; i < _kLineCapRoundSegments; i++) {
          indices.addAll([centerIndex, centerIndex + i + 1, centerIndex + i + 2]);
        }

        vertexCount += _kLineCapRoundSegments + 2;
      }
    }

    // Add single line segment from a to b.
    void _addSegment(Vector2 a, Vector2 b) {
      final t = b - a;
      final n = Vector2(t.y, -t.x)..normalize();

      _addRelativeIndices([0, 1, 2, 1, 2, 3]);

      vertexData.last.add((a, n, currentLength));
      vertexData.last.add((a, -n, currentLength));

      currentLength += t.length;

      vertexData.last.add((b, n, currentLength));
      vertexData.last.add((b, -n, currentLength));

      vertexCount += 4;
    }

    // Add join at c, from a to b.
    void _addJoin(Vector2 c, Vector2 a, Vector2 b) {
      final ac = c - a;
      final cb = b - c;

      var na = Vector2(ac.y, -ac.x)..normalize();
      var nb = Vector2(cb.y, -cb.x)..normalize();

      // check direction
      final cross = ac.x * cb.y - ac.y * cb.x;
      final direction = cross < 0 ? -1.0 : 1.0;

      na *= direction;
      nb *= direction;

      // TODO: Miter, round joins
      _addRelativeIndices([0, 1, 2]);

      vertexData.last.add((c, Vector2.zero(), currentLength));
      vertexData.last.add((c, na, currentLength));
      vertexData.last.add((c, nb, currentLength));

      vertexCount += 3;
    }

    for (final feature in features) {
      vertexData.add([]);

      // Line consists of:
      // Cap - Segment - Join - Segment - Join - ... - Segment - Cap
      for (final line in feature.lines) {
        if (line.points.length < 2) continue;

        _addCap(line.points[0].vec2, line.points[1].vec2);

        for (var i = 0; i < line.points.length - 1; i++) {
          _addSegment(line.points[i].vec2, line.points[i + 1].vec2);

          if (i != 0) {
            _addJoin(line.points[i].vec2, line.points[i - 1].vec2, line.points[i + 1].vec2);
          }
        }

        _addCap(line.points[line.points.length - 1].vec2, line.points[line.points.length - 2].vec2);

        currentLength = 0.0;
      }
    }

    pipeline.vertex.allocateVertices(gpu.gpuContext, vertexCount);
    pipeline.vertex.allocateIndices(gpu.gpuContext, indices);

    var vertexIndex = 0;
    for (var i = 0; i < vertexData.length; i++) {
      final feature = features[i];
      final featureEval = context.eval.forFeature(feature);

      setFeatureVertices(featureEval, feature, vertexIndex, vertexData[i]);
      vertexIndex += vertexData[i].length;
    }

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

  gpu.Texture? dasharrayTexture;

  @override
  void draw(RenderContext context) {
    if (!pipeline.isReady) return;

    final tileSize = context.getScaledTileSize(coordinates);
    final extent = vtLayer.extent.toDouble();
    final tileLocalToWorld = Matrix4.identity()
      ..translate(coordinates.x * tileSize, coordinates.y * tileSize)
      ..scale(tileSize / extent);

    // Dasharray evaluation
    if (specLayer.paint.lineDasharray != null) {
      final dasharray = specLayer.paint.lineDasharray!.evaluate(context.eval).map((v) => v * 1).toList();
      final dasharrayLength = dasharray.fold(0.0, (acc, v) => acc + v);
      final textureWidth = dasharrayLength.ceil();

      if (dasharrayTexture?.width != textureWidth) {
        dasharrayTexture = gpu.gpuContext.createTexture(
          gpu.StorageMode.hostVisible,
          textureWidth,
          1,
          format: gpu.PixelFormat.r8UNormInt,
          coordinateSystem: gpu.TextureCoordinateSystem.uploadFromHost,
        );
      }

      final data = Uint8List(textureWidth);
      var isGap = false;
      var offset = 0;

      for (final v in dasharray) {
        final length = v.round();
        final value = isGap ? 0 : 255;

        for (var i = offset; i < offset + length; i++) {
          data[i] = value;
        }

        offset += length;
        isGap = !isGap;
      }

      dasharrayTexture!.overwrite(data.buffer.asByteData());
    }

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
