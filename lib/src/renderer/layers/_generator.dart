/// A template method used by `style_precompiler.dart` for generating the `setUniforms` code.
List<String> setUniformsGenerator(List<String> uniformEval, List<String> uniformSetters) {
  return [
    'void setUniforms(',
    '  RenderContext context,',
    '  Matrix4 cameraWorldToGl,',
    '  double cameraZoom,',
    '  double pixelRatio,',
    '  Matrix4 tileLocalToGl,',
    '  double tileSize,',
    '  double tileExtent,',
    '  double tileOpacity,',
    ') {',
    '  final eval = context.eval;',
    '  final paint = specLayer.paint;',
    '',
    ...uniformEval.map((v) => '  $v'),
    '',
    '  pipeline.setUniforms(',
    '    cameraWorldToGl: cameraWorldToGl,',
    '    cameraZoom: cameraZoom,',
    '    cameraPixelRatio: pixelRatio,',
    '    tileLocalToGl: tileLocalToGl,',
    '    tileSize: tileSize,',
    '    tileExtent: tileExtent,',
    '    tileOpacity: tileOpacity,',
    ...uniformSetters.map((v) => '        $v,'),
    '  );',
    '}',
  ];
}

/// A template method used by `style_precompiler.dart` for generating the [setVertices] code for a
/// [BackgroundLayerRenderer].
List<String> backgroundLayerRendererSetVerticesGenerator(List<String> vertexEval, List<String> vertexSetters) {
  return [
    'void setVertices() {',
    '  final paint = specLayer.paint;',
    ...vertexEval.map((v) => '      $v'),
    '',
    '  pipeline.vertex.setVertex(0, position: Vector2(-1, -1));',
    '  pipeline.vertex.setVertex(1, position: Vector2(1, -1));',
    '  pipeline.vertex.setVertex(2, position: Vector2(1, 1));',
    '  pipeline.vertex.setVertex(3, position: Vector2(-1, 1));',
    '',
    '  pipeline.upload(gpu.gpuContext);',
    '}',
  ];
}

/// A template method used by `style_precompiler.dart` for generating the [setFeatureVertices] code for a
/// [FillLayerRenderer].
List<String> fillLayerRendererSetFeatureVerticesGenerator(List<String> vertexEval, List<String> vertexSetters) {
  return [
    'int setFeatureVertices(spec.EvaluationContext eval, vt.PolygonFeature feature, int index) {',
    '  final paint = specLayer.paint;',
    ...vertexEval.map((v) => '      $v'),
    '',
    '  for (final polygon in feature.polygons) {',
    '    for (final vertex in polygon.vertices) {',
    '      pipeline.vertex.setVertex(',
    '        index,',
    '        position: vertex.vec2,',
    ...vertexSetters.map((v) => '        $v,'),
    '      );',
    '      index += 1;',
    '    }',
    '  }',
    '',
    '  return index;',
    '}',
  ];
}

List<String> lineLayerRendererSetFeatureVerticesGenerator(List<String> vertexEval, List<String> vertexSetters) {
  return [
    'int setFeatureVertices(',
    '  spec.EvaluationContext eval,',
    '  vt.LineStringFeature feature,',
    '  int index,',
    '  List<(Vector2 position, Vector2 normal, double lineLength)> vertexData,',
    ') {',
    '  final paint = specLayer.paint;',
    ...vertexEval.map((v) => '      $v'),
    '',
    '  for (var i = 0; i < vertexData.length; i++) {',
    '    final vertex = vertexData[i];',
    '    pipeline.vertex.setVertex(',
    '      index + i,',
    '      position: vertex.\$1,',
    '      normal: vertex.\$2,',
    ...vertexSetters.map((v) => '      $v,'),
    '    );',
    '  }',
    '',
    '  return index + vertexData.length;',
    '}',
  ];
}

List<String> lineDashedLayerRendererSetFeatureVerticesGenerator(List<String> vertexEval, List<String> vertexSetters) {
  return [
    'int setFeatureVertices(',
    '  spec.EvaluationContext eval,',
    '  vt.LineStringFeature feature,',
    '  int index,',
    '  List<(Vector2 position, Vector2 normal, double lineLength)> vertexData,',
    ') {',
    '  final paint = specLayer.paint;',
    ...vertexEval.map((v) => '      $v'),
    '',
    '  for (var i = 0; i < vertexData.length; i++) {',
    '    final vertex = vertexData[i];',
    '    pipeline.vertex.setVertex(',
    '      index + i,',
    '      position: vertex.\$1,',
    '      normal: vertex.\$2,',
    '      lineLength: vertex.\$3,',
    ...vertexSetters.map((v) => '      $v,'),
    '    );',
    '  }',
    '',
    '  return index + vertexData.length;',
    '}',
  ];
}

List<String> symbolLayerRendererSetFeatureVerticesGenerator(List<String> vertexEval, List<String> vertexSetters) {
  return [
    'int setFeatureVertices(',
    '  spec.EvaluationContext eval,',
    '  vt.PointFeature feature,',
    '  Iterable<Vector2> anchors,',
    '  SymbolLayoutData layoutData,',
    '  int index,',
    ') {',
    '  final paint = specLayer.paint;',
    ...vertexEval.map((v) => '      $v'),
    '',
    '  var vertexIndex = index;',
    '  for (final glyph in layoutData.glyphs) {',
    '    final pos0 = Vector2(glyph.x, glyph.y);',
    '    final pos1 = Vector2(glyph.x + glyph.width, glyph.y);',
    '    final pos2 = Vector2(glyph.x + glyph.width, glyph.y + glyph.height);',
    '    final pos3 = Vector2(glyph.x, glyph.y + glyph.height);',
    '',
    '    final uv0 = glyph.uv.uv0;',
    '    final uv1 = Vector2(glyph.uv.uv1.x, glyph.uv.uv0.y);',
    '    final uv2 = glyph.uv.uv1;',
    '    final uv3 = Vector2(glyph.uv.uv0.x, glyph.uv.uv1.y);',
    '',
    '    for (final anchor in anchors) {',
    for (var i = 0; i < 4; i++) ...[
      '      pipeline.vertex.setVertex(',
      '        vertexIndex + $i,',
      '        position: pos$i,',
      '        uv: uv$i,',
      '        anchor: anchor,',
      ...vertexSetters.map((v) => '        $v,'),
      '      );',
      '',
    ],
    '      vertexIndex += 4;',
    '    }',
    '  }',
    '',
    '  return vertexIndex;',
    '}',
  ];
}
