import 'dart:convert';

import 'package:gpu_vector_tile_renderer/_spec.dart' as spec;
import 'package:gpu_vector_tile_renderer/src/renderer/layers/_generator.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/gen/shader_templates.gen.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/serializer/parsed_shader.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/serializer/shader_reader.dart';
import 'package:gpu_vector_tile_renderer/src/shaders/serializer/shader_writer.dart';
import 'package:gpu_vector_tile_renderer/src/style_precompiler_2/shader_bindings_generator.dart';
import 'package:gpu_vector_tile_renderer/src/utils/string_utils.dart';

(List<ParsedShader> shaders, String shaderBindingsCode, String layerRenderersCode, String shaderBundle) precompileStyle(
  spec.Style style,
) {
  final vertexShaders = <ParsedShaderVertex>[];
  final fragmentShaders = <ParsedShaderFragment>[];
  final supportedLayerNames = <String>{};
  final shaderBindings = <String>[];
  final layerRenderers = <String>[];

  // temporary!
  vertexShaders.add(
    readShader(vertexShaderTemplates['background']!, name: 'background', type: ShaderType.vertex) as ParsedShaderVertex,
  );

  fragmentShaders.add(
    readShader(fragmentShaderTemplates['background']!, name: 'background', type: ShaderType.fragment)
        as ParsedShaderFragment,
  );

  shaderBindings.add(generateShaderBindings(vertexShaders.first, fragmentShaders.first));

  // For each layer, precompile the shaders
  for (final layer in style.layers) {
    final result = switch (layer.type) {
      spec.Layer$Type.fill => _precompileFillLayer(layer as spec.LayerFill),
      spec.Layer$Type.line => _precompileLineLayer(layer as spec.LayerLine),
      _ => null,
    };

    if (result != null) {
      final (vertexShader, fragmentShader, shaderBindingsCode, layerRendererCode) = result;

      vertexShaders.add(vertexShader);
      fragmentShaders.add(fragmentShader);
      shaderBindings.add(shaderBindingsCode);
      layerRenderers.add(layerRendererCode);
      supportedLayerNames.add(layer.id);
    }
  }

  shaderBindings.insert(0, generateCommonShaderUboBindings([...vertexShaders, ...fragmentShaders]));
  shaderBindings.insert(0, generateShaderBindingsHeader());

  layerRenderers.insertAll(0, [
    '// GENERATED FILE - DO NOT MODIFY',
    '// Generated by lib/src/style_precompiler_2/style_precompiler.dart',
    '',
    '// ignore_for_file: unused_local_variable, non_constant_identifier_names',
    '',
    'import \'package:gpu_vector_tile_renderer/_controller.dart\';',
    'import \'package:gpu_vector_tile_renderer/_renderer.dart\';',
    'import \'package:gpu_vector_tile_renderer/_utils.dart\';',
    'import \'package:gpu_vector_tile_renderer/_spec.dart\' as spec;',
    'import \'package:gpu_vector_tile_renderer/_vector_tile.dart\' as vt;',
    'import \'package:flutter_gpu/gpu.dart\' as gpu;',
    'import \'package:vector_math/vector_math_64.dart\';',
    'import \'package:flutter_map/flutter_map.dart\';',
    '',
    'import \'./shader_bindings.gen.dart\';',
    '',
    'const shaderBundleName = \'${style.name}.shaderbundle\';',
    '',
    'SingleTileLayerRenderer? createSingleTileLayerRenderer('
        '  gpu.ShaderLibrary shaderLibrary,'
        '  TileCoordinates coordinates,'
        '  TileContainer container,'
        '  spec.Layer specLayer,'
        '  vt.Layer vtLayer,'
        ') {',
    '  return switch(specLayer.id) {',
    for (final layerName in supportedLayerNames) ...[
      '    \'$layerName\' => ${nameToDartClassName(toSnakeCase(layerName))}LayerRenderer(',
      '      shaderLibrary: shaderLibrary,',
      '      coordinates: coordinates,',
      '      container: container,',
      '      specLayer: specLayer as dynamic,',
      '      vtLayer: vtLayer,',
      '    ),',
    ],
    '    _ => null,',
    '  };',
    '}',
  ]);

  final shaderBundle = <String, dynamic>{};
  for (final shader in [...vertexShaders, ...fragmentShaders]) {
    shaderBundle['${shader.name}_${shader.type == ShaderType.vertex ? 'vert' : 'frag'}'] = {
      'type': shader.type == ShaderType.vertex ? 'vertex' : 'fragment',
      // TODO: Set path here
      'file': 'lib/compiled_style/shaders/${shader.name}.${shader.type == ShaderType.vertex ? 'vert' : 'frag'}',
    };
  }

  return (
    [...vertexShaders, ...fragmentShaders],
    shaderBindings.join('\n'),
    layerRenderers.join('\n'),
    jsonEncode(shaderBundle),
  );
}

_PrecompileLayerResult _precompileFillLayer(spec.LayerFill layer) {
  final paint = layer.paint;

  return _precompileLayer(
    layer,
    shaderTemplateName: 'fill',
    abstractLayerRendererClassName: 'FillLayerRenderer',
    setFeatureVerticesGenerator: fillLayerRendererSetFeatureVerticesGenerator,
    setUniformsGenerator: setUniformsGenerator,
    jointPropertiesMap: {
      'antialias': (paint.fillAntialias, 'fillAntialias', 'antialias'),
      'opacity': (paint.fillOpacity, 'fillOpacity', 'opacity'),
      'color': (paint.fillColor, 'fillColor', 'color'),
      'translate': (paint.fillTranslate, 'fillTranslate', 'translate'),
    },
  );
}

_PrecompileLayerResult _precompileLineLayer(spec.LayerLine layer) {
  final paint = layer.paint;

  return _precompileLayer(
    layer,
    shaderTemplateName: 'line',
    abstractLayerRendererClassName: 'LineLayerRenderer',
    setFeatureVerticesGenerator: lineLayerRendererSetFeatureVerticesGenerator,
    setUniformsGenerator: setUniformsGenerator,
    jointPropertiesMap: {
      'color': (paint.lineColor, 'lineColor', 'color'),
      'opacity': (paint.lineOpacity, 'lineOpacity', 'opacity'),
      'width': (paint.lineWidth, 'lineWidth', 'width'),
    },
  );
}

typedef _PrecompileLayerResult =
    (ParsedShaderVertex vertexShader, ParsedShaderFragment fragmentShader, String shaderBindings, String layerRenderer);

/// Precompiles the:
///
/// - Vertex shader
/// - Fragment shader
/// - Shader bindings code
/// - Layer renderer code
///
/// for a given layer.
_PrecompileLayerResult _precompileLayer(
  spec.Layer layer, {
  required String abstractLayerRendererClassName,
  required List<String> Function(List<String>, List<String>) setFeatureVerticesGenerator,
  required List<String> Function(List<String>, List<String>) setUniformsGenerator,
  required String shaderTemplateName,
  required Map<String, (spec.Property property, String dartName, String glslName)> jointPropertiesMap,
}) {
  // Setup mappings
  final keys = jointPropertiesMap.keys.toSet();
  final propertiesMap = <String, spec.Property>{};
  final dartNameMap = <String, String>{};
  final glslNameMap = <String, String>{};
  final analysisResultsMap = <String, _PropertyAnalysis>{};

  for (final entry in jointPropertiesMap.entries) {
    propertiesMap[entry.key] = entry.value.$1;
    dartNameMap[entry.key] = entry.value.$2;
    glslNameMap[entry.key] = entry.value.$3;
    analysisResultsMap[entry.key] = _analyzeProperty(entry.value.$1);
  }

  // Shader name is snake-case of the layer id.
  //
  // E.g. if layer name is "Forest Green", then the shader name will be "forest_green".
  final shaderName = toSnakeCase(layer.id);

  // Class-like name for the shader.
  //
  // E.g. "Forest green" -> "ForestGreen"
  final shaderClassName = nameToDartClassName(shaderName);

  // Read the template shaders
  var vertexShader =
      readShader(vertexShaderTemplates[shaderTemplateName]!, name: shaderName, type: ShaderType.vertex)
          as ParsedShaderVertex;

  var fragmentShader =
      readShader(fragmentShaderTemplates[shaderTemplateName]!, name: shaderName, type: ShaderType.fragment)
          as ParsedShaderFragment;

  /// Returns the property declaration pragma for the given property name.
  ///
  /// Makes sure that the prop declaration exists (and is the same) in the vertex and fragment shaders.
  PropDeclarationShaderPragma _getPropDeclarationPragma(String propName) {
    final vertexPragma = vertexShader.pragmas.whereType<PropDeclarationShaderPragma>().firstWhere(
      (p) => p.variable.name == propName,
    );

    final fragmentPragma = fragmentShader.pragmas.whereType<PropDeclarationShaderPragma>().firstWhere(
      (p) => p.variable.name == propName,
    );

    assert(vertexPragma == fragmentPragma);
    return vertexPragma;
  }

  /// Replaces the pragma in the shader with the given values.
  void _replacePragma(ParsedShader shader, ShaderPragma pragma, List<Object?> values) {
    final index = shader.content.indexOf(pragma);
    assert(index != -1);

    shader.content.removeAt(index);
    shader.content.insertAll(index, values.nonNulls);
  }

  // Property resolution map for shaders.
  //
  // This determines how the property will be resolved in the shader's `main()` block, and will be used to replace the
  // pragmas in the shader templates.
  final vertexPropResolutions = <String, List<Object>>{};
  final fragmentPropResolutions = <String, List<Object>>{};

  // This will be the code that's used in the layer renderer to evaluate the property values before setting them in
  // either the vertex attributes or the uniforms.
  final rendererPropertyVertexEval = <String>[];
  final rendererPropertyUniformEval = <String>[];

  // This will be the code that's used in the layer renderer to set the vertex attributes.
  final rendererVertexAttributeSetters = <String>[];

  // This will be the code that's used in the layer renderer to set the uniform values.
  final rendererUboSetters = <String>[];

  // The shader UBO that will contain the property values set as uniform.
  final propertiesUboName = '${shaderClassName}Ubo';
  final propertiesUboInstance = '${shaderName}_ubo';
  final propertiesUbo = ShaderUbo(name: propertiesUboName, instanceName: propertiesUboInstance, variables: []);

  // First pass does:
  // - Replace the declaration pragmas in the shader templates with the property declaration code
  // - Generate the code that sets the vertex attributes in the layer renderer
  // - Generate the code that sets the uniform values in the layer renderer
  // - Generate the code to resolve the property in the shader's `main()` block (prop resolutions)
  for (final key in keys) {
    final analysis = analysisResultsMap[key]!;
    final propertyDartName = dartNameMap[key];
    final dartProperty = propertiesMap[key];
    final pragma = _getPropDeclarationPragma(key);

    // A string that can be applied at the end of a Dart property to convert it to the correct type for the shader
    // bindings.
    String propertyConversion = switch (pragma.variable.typeGlsl) {
      ShaderGlslType.float => '.toDouble()',
      ShaderGlslType.int_ => '.toInt()',
      ShaderGlslType.vec4 when dartProperty is spec.Property<spec.Color> => '.vec',
      _ => '',
    };

    //
    // Property is a constant. It will be baked into the shader.
    // - Vertex declaration: constant
    // - Vertex resolution: none
    // - Fragment declaration: constant
    // - Fragment resolution: none
    // - Renderer vertex attribute setter: none
    // - Renderer uniform setter: none
    //
    if (analysis.type == _PropertyShaderType.constant) {
      final constVariable = pragma.variable.copyWith(
        qualifier: ShaderVariableQualifier.const_,
        value: analysis.constantValue,
      );

      _replacePragma(vertexShader, pragma, [constVariable]);
      _replacePragma(fragmentShader, pragma, [constVariable]);

      continue;
    }

    // Variables that will be added to the UBO
    List<ShaderVariable>? uboVariables;

    // Variables that will be added to either the UBO or vertex attributes
    final List<ShaderVariable> flexibleVariables;

    // Function that will be used to resolve the property in the vertex shader's `main()` block.
    final List<Object> Function(String Function(String name) variableAccessor)? vertexResolutionFn;

    // Function that will be used to compute the property values before the setter runs.
    //
    // This function is specific to the UBO setter.
    List<String> Function()? dartUboPropertyEvalFn;

    // Function that will be used to compute the property values before the setter runs.
    // For uniforms, there's no need to do that since the property is computed once anyway, but for the sake of
    // consistency, this will be used for both uniforms and attributes.
    // For attributes, this will be used to compute the property values once per feature, without recomputing them
    // for every vertex.
    //
    // This function can be applied to both the UBO and the vertex attributes.
    final List<String> Function() dartPropertyEvalFn;

    // Function that will be used to apply the properties in the UBO.
    //
    // This function is specific to the UBO setter.
    List<String> Function()? dartUboSetterFn;

    // Function that will be used to apply the property.
    final List<String> Function(String Function(String name) getShaderBindingKey) dartSetterFn;

    // Property now can be only passed as a uniform or an attribute, and can potentially have interpolation.
    // Prepare the interpolation-required values, as those will be used for both uniforms or attributes.
    if (analysis.interpolation != null) {
      //
      // Property is cross-faded. This means that the shader will accept two values for two zoom levels.
      //
      if (analysis.interpolation == _PropertyInterpolation.crossfade) {
        final startValueName = '${pragma.variable.name}_start_value';
        final endValueName = '${pragma.variable.name}_end_value';

        flexibleVariables = [
          pragma.variable.copyWith(name: startValueName),
          pragma.variable.copyWith(name: endValueName),
        ];

        vertexResolutionFn = (accessor) {
          final _startValue = accessor(startValueName);
          final _endValue = accessor(endValueName);

          return [pragma.variable.copyWith(value: 'data_crossfade($_startValue, $_endValue)')];
        };

        dartPropertyEvalFn = () {
          return [
            'final $startValueName = paint.$propertyDartName.evaluate(eval.copyWithZoom(eval.zoom.floor()))$propertyConversion;',
            'final $endValueName = paint.$propertyDartName.evaluate(eval.copyWithZoom(eval.zoom.floor() + 1))$propertyConversion;',
          ];
        };

        dartSetterFn = (getShaderBindingKey) {
          final _startValueKey = getShaderBindingKey(startValueName);
          final _endValueKey = getShaderBindingKey(endValueName);

          return ['$_startValueKey: $startValueName', '$_endValueKey: $endValueName'];
        };
      }
      //
      // Property is interpolated or stepped. This means that the shader will accept:
      // - Value start/end for two closest stops (depends if the property is data-driven)
      // - Two closest stops (in the uniform)
      //
      else {
        final startValueName = '${pragma.variable.name}_start_value';
        final endValueName = '${pragma.variable.name}_end_value';
        final startStopName = '${pragma.variable.name}_start_stop';
        final endStopName = '${pragma.variable.name}_end_stop';

        flexibleVariables = [
          pragma.variable.copyWith(name: startValueName),
          pragma.variable.copyWith(name: endValueName),
        ];

        uboVariables = [
          ShaderVariable(typeGlsl: ShaderGlslType.float, name: startStopName),
          ShaderVariable(typeGlsl: ShaderGlslType.float, name: endStopName),
        ];

        vertexResolutionFn = (accessor) {
          final _startValue = accessor(startValueName);
          final _endValue = accessor(endValueName);
          final _startStop = '$propertiesUboInstance.$startStopName';
          final _endStop = '$propertiesUboInstance.$endStopName';
          final _params = '$_startValue, $_endValue, $_startStop, $_endStop';

          if (analysis.interpolation == _PropertyInterpolation.step) {
            return [pragma.variable.copyWith(value: 'data_step($_params)')];
          } else if (analysis.interpolation == _PropertyInterpolation.interpolate) {
            return [pragma.variable.copyWith(value: 'data_interpolate($_params)')];
          } else {
            throw UnimplementedError('Interpolation type not supported: ${analysis.interpolation}');
          }
        };

        dartUboPropertyEvalFn = () {
          final stopsArray = '[${analysis.interpolationStops!.join(', ')}]';

          return [
            'final $startStopName = getNearestFloorValue(eval.zoom, $stopsArray);',
            'final $endStopName = getNearestCeilValue(eval.zoom, $stopsArray);',
          ];
        };

        dartPropertyEvalFn = () {
          final stopsArray = '[${analysis.interpolationStops!.join(', ')}]';

          return [
            'final $startValueName = paint.$propertyDartName.evaluate(eval.copyWithZoom(getNearestFloorValue(eval.zoom, $stopsArray)))$propertyConversion;',
            'final $endValueName = paint.$propertyDartName.evaluate(eval.copyWithZoom(getNearestCeilValue(eval.zoom, $stopsArray)))$propertyConversion;',
          ];
        };

        dartUboSetterFn = () {
          final _startStopKey = nameToDartFieldName('${propertiesUboName}_$startStopName');
          final _endStopKey = nameToDartFieldName('${propertiesUboName}_$endStopName');

          return ['$_startStopKey: $startStopName', '$_endStopKey: $endStopName'];
        };

        dartSetterFn = (getShaderBindingKey) {
          final _startValueKey = getShaderBindingKey(startValueName);
          final _endValueKey = getShaderBindingKey(endValueName);

          return ['$_startValueKey: $startValueName', '$_endValueKey: $endValueName'];
        };
      }
    }
    //
    // Property is non-interpolated, so it'll be passed as it is.
    //
    else {
      flexibleVariables = [pragma.variable];
      vertexResolutionFn = null;

      dartPropertyEvalFn = () {
        return ['final ${pragma.variable.name} = paint.$propertyDartName.evaluate(eval)$propertyConversion;'];
      };

      dartSetterFn = (getShaderBindingKey) {
        final key = getShaderBindingKey(pragma.variable.name);
        return ['$key: ${pragma.variable.name}'];
      };
    }

    // Add any ubo variables if needed
    if (uboVariables != null) propertiesUbo.variables.addAll(uboVariables);
    if (dartUboPropertyEvalFn != null) rendererPropertyUniformEval.addAll(dartUboPropertyEvalFn());
    if (dartUboSetterFn != null) rendererUboSetters.addAll(dartUboSetterFn());

    //
    // Property is passed in an uniform.
    // - Vertex declaration: uniform, output
    // - Vertex resolution: yes
    // - Fragment declaration: input
    // - Fragment resolution: yes
    // - Renderer vertex attribute setter: none
    // - Renderer uniform setter: yes
    //
    if (analysis.type == _PropertyShaderType.uniform) {
      // Add variables to the UBO.
      propertiesUbo.variables.addAll(flexibleVariables);

      // Add an output variable to the vertex shader.
      _replacePragma(vertexShader, pragma, [
        pragma.variable.copyWith(qualifier: ShaderVariableQualifier.out_, name: 'v_${pragma.variable.name}'),
      ]);

      // Add an input variable to the fragment shader.
      _replacePragma(fragmentShader, pragma, [
        pragma.variable.copyWith(qualifier: ShaderVariableQualifier.in_, name: 'v_${pragma.variable.name}'),
      ]);

      // Add the Dart-side code.
      rendererPropertyUniformEval.addAll(dartPropertyEvalFn());
      rendererUboSetters.addAll(dartSetterFn((name) => nameToDartFieldName('${propertiesUboName}_$name')));
    }
    //
    // Property is passed as an attribute.
    // - Vertex declaration: input, output
    // - Vertex resolution: yes
    // - Fragment declaration: input
    // - Fragment resolution: yes
    // - Renderer vertex attribute setter: yes
    // - Renderer uniform setter: none
    //
    else if (analysis.type == _PropertyShaderType.attribute) {
      // Add input variables and one output variable to the vertex shader.
      _replacePragma(vertexShader, pragma, [
        ...flexibleVariables.map((v) => v.copyWith(qualifier: ShaderVariableQualifier.in_)),
        pragma.variable.copyWith(qualifier: ShaderVariableQualifier.out_, name: 'v_${pragma.variable.name}'),
      ]);

      // Add an input variable to the fragment shader.
      _replacePragma(fragmentShader, pragma, [
        pragma.variable.copyWith(qualifier: ShaderVariableQualifier.in_, name: 'v_${pragma.variable.name}'),
      ]);

      // Add the Dart side code.
      rendererPropertyVertexEval.addAll(dartPropertyEvalFn());
      rendererVertexAttributeSetters.addAll(dartSetterFn((name) => nameToDartFieldName(name)));
    }
    //
    // Property type is unknown.
    //
    else {
      throw UnimplementedError('Property type not supported: $analysis');
    }

    vertexPropResolutions[key] = [
      // Add the vertex resolution if it's applicable
      if (vertexResolutionFn != null) ...vertexResolutionFn((name) => name),

      // Pass the property to the output
      'v_${pragma.variable.name} = ${pragma.variable.name};',
    ];

    // Add the fragment resolution
    fragmentPropResolutions[key] = [
      // Retrieve the property from the input
      pragma.variable.copyWith(value: 'v_${pragma.variable.name}'),
    ];
  }

  // Second pass does:
  // - Replace the property resolution pragmas in the shader templates with the property resolution code
  void _applyPropertyResolutionPragma(
    ParsedShader shader,
    PropResolutionShaderPragma pragma,
    Map<String, List<Object>> resolutions,
  ) {
    final index = shader.content.indexOf(pragma);
    assert(index != -1);

    shader.content.removeAt(index);

    if (pragma.resolutions.length == 1 && pragma.resolutions.single == '...') {
      // Apply all resolutions
      shader.content.insertAll(index, resolutions.values.expand((r) => r).toList());
    } else {
      // Apply only specified resolutions
      final keys = pragma.resolutions;
      shader.content.insertAll(index, keys.expand((key) => resolutions[key]!).toList());
    }
  }

  void _recursivelyApplyPropertyResolutionPragmas(ParsedShader shader, Map<String, List<Object>> resolutions) {
    while (true) {
      final index = shader.content.indexWhere((e) => e is PropResolutionShaderPragma);
      if (index == -1) break;

      final pragma = shader.content[index] as PropResolutionShaderPragma;
      _applyPropertyResolutionPragma(shader, pragma, resolutions);
    }
  }

  // Apply the property resolutions
  _recursivelyApplyPropertyResolutionPragmas(vertexShader, vertexPropResolutions);
  _recursivelyApplyPropertyResolutionPragmas(fragmentShader, fragmentPropResolutions);

  // Expand prelude pragmas in the shaders
  void _recursivelyApplyPreludePragmas(ParsedShader shader) {
    while (true) {
      final index = shader.content.indexWhere((e) => e is PreludeShaderPragma);
      if (index == -1) break;

      final pragma = shader.content[index] as PreludeShaderPragma;
      shader.content.removeAt(index);
      shader.content.insert(index, preludeShaders[pragma.name]!);
    }
  }

  _recursivelyApplyPreludePragmas(vertexShader);
  _recursivelyApplyPreludePragmas(fragmentShader);

  // Add the ubo if necessary
  void _addUboToShader(ParsedShader shader, ShaderUbo ubo) {
    var index = shader.content.lastIndexOf((e) => e is PropDeclarationShaderPragma);
    if (index == -1) {
      index = 2;
    }

    shader.content.insert(index, ubo);
  }

  if (propertiesUbo.variables.isNotEmpty) {
    _addUboToShader(vertexShader, propertiesUbo);
    _addUboToShader(fragmentShader, propertiesUbo);
  }

  void _reparseShader(ParsedShader shader) => readShader(writeShader(shader), name: shader.name, type: shader.type);

  // Re-parse the vertex and fragment shader
  vertexShader = _reparseShader(vertexShader) as ParsedShaderVertex;
  fragmentShader = _reparseShader(fragmentShader) as ParsedShaderFragment;

  // Generate the shader bindings for the vertex and fragment shader
  final shaderBindings = generateShaderBindings(vertexShader, fragmentShader);

  // Generate the code for the layer renderer
  final layerRendererName = '${shaderClassName}LayerRenderer';
  final layerRendererO = StringBuffer();

  layerRendererO.writeln('class $layerRendererName extends $abstractLayerRendererClassName {');
  layerRendererO.writeln('  $layerRendererName({');
  layerRendererO.writeln('    required gpu.ShaderLibrary shaderLibrary,');
  layerRendererO.writeln('    required super.coordinates,');
  layerRendererO.writeln('    required super.container,');
  layerRendererO.writeln('    required super.specLayer,');
  layerRendererO.writeln('    required super.vtLayer,');
  layerRendererO.writeln('  }) : pipeline = ${shaderClassName}RenderPipelineBindings(shaderLibrary);');
  layerRendererO.writeln();
  layerRendererO.writeln('  @override');
  layerRendererO.writeln('  final ${shaderClassName}RenderPipelineBindings pipeline;');
  layerRendererO.writeln();
  layerRendererO.writeln('  @override');
  layerRendererO.writeln(
    setFeatureVerticesGenerator(
      rendererPropertyVertexEval,
      rendererVertexAttributeSetters,
    ).map((v) => '  $v').join('\n'),
  );
  layerRendererO.writeln();
  layerRendererO.writeln('  @override');
  layerRendererO.writeln(
    setUniformsGenerator(rendererPropertyUniformEval, rendererUboSetters).map((v) => '  $v').join('\n'),
  );
  layerRendererO.writeln('}');

  final layerRenderer = layerRendererO.toString();

  // Do assertions and checks
  assert(vertexShader.pragmas.isEmpty);
  assert(fragmentShader.pragmas.isEmpty);

  return (vertexShader, fragmentShader, shaderBindings, layerRenderer);
}

/// How the property is passed to the shader.
enum _PropertyShaderType { uniform, attribute, constant }

/// How the property is interpolated.
enum _PropertyInterpolation { crossfade, interpolate, step }

/// Results of property analysis.
///
/// Property analysis checks what dependencies a property's expression has, and determines what kind of data
/// should be passed to the shader.
///
/// It'll also try to optimize the data passed. For example, if the property is data-driven, but it only depends on the
/// camera zoom, then instead of passing the data as vertex attributes, it'll be passed as a uniform.
class _PropertyAnalysis {
  _PropertyAnalysis({required this.type, this.interpolation, this.constantValue, this.interpolationStops});

  /// Type of how the property is passed to the shader: uniform, attribute, or constant (baked-in).
  final _PropertyShaderType type;

  /// Whether the property is interpolated, and if so, how.
  final _PropertyInterpolation? interpolation;

  /// If the property has interpolation, the interpolation stops.
  final List<double>? interpolationStops;

  /// If the property is constant, the constant value.
  final Object? constantValue;
}

/// An empty evaluation context to use for constant property evaluation.
const _emptyEvaluationContext = spec.EvaluationContext.empty();

/// Analyzes a given property.
///
/// See [_PropertyAnalysis] on what the analysis results mean.
_PropertyAnalysis _analyzeProperty(spec.Property prop) {
  final hasExpression = prop.expression != null;

  final dependencies = hasExpression ? prop.expression!.dependencies : const <spec.ExpressionDependency>{};

  final hasDependencies = dependencies.isNotEmpty;
  final hasDataDependency = hasExpression && dependencies.contains(spec.ExpressionDependency.data);
  final hasCameraDependency = hasExpression && dependencies.contains(spec.ExpressionDependency.camera);

  // Property value is always constant, no matter the evaluation context.
  // Shader receives the value baked into the shader.
  //
  // This can happen if the property is declared as a [spec.ConstantProperty], or if property has no expression, or if
  // the expression has no dependencies.
  if (prop is spec.ConstantProperty || !hasExpression || !hasDependencies) {
    final value = prop.evaluate(_emptyEvaluationContext);
    return _PropertyAnalysis(type: _PropertyShaderType.constant, constantValue: value);
  }
  //
  // Property value is the same for all features.
  // Shader receives the value as a uniform.
  //
  // This can happen if the property is declared as a [spec.DataConstantProperty].
  //
  else if (prop is spec.DataConstantProperty) {
    assert(!prop.expression!.dependencies.contains(spec.ExpressionDependency.data));
    return _PropertyAnalysis(type: _PropertyShaderType.uniform);
  }
  //
  // Property value is the same for all features.
  // Output is cross-faded between two values based on a zoom-dependent interpolation.
  // Shader receives two values to cross-fade between as a uniform.
  //
  // This can happen if the property is declared as a [spec.CrossFadedProperty], or if the property has no data
  // dependencies.
  //
  else if (prop is spec.CrossFadedProperty || (prop is spec.CrossFadedDataDrivenProperty && !hasDataDependency)) {
    return _PropertyAnalysis(type: _PropertyShaderType.uniform, interpolation: _PropertyInterpolation.crossfade);
  }
  //
  // Property value is different between features.
  // Output is cross-faded between two values based on a zoom-dependent interpolation.
  // Shader receives two values to cross-fade between as a vertex attribute.
  //
  else if (prop is spec.CrossFadedDataDrivenProperty) {
    assert(prop.expression!.dependencies.contains(spec.ExpressionDependency.data));
    return _PropertyAnalysis(type: _PropertyShaderType.attribute, interpolation: _PropertyInterpolation.crossfade);
  }
  //
  // Property value is different between features.
  //
  // Depending on the expression type, the following will happen:
  // 1. Zoom is used (subsequently as an input to a step/interpolation):
  //    - Shader will receive the interpolation values for the two nearest zoom levels as vertex attributes
  //    - Shader will have the interpolation code baked in
  //    - Result is interpolated between the two values based on the zoom level
  // 2. Zoom is not used:
  //    - Shader will receive the value as a vertex attribute
  //
  else if (prop is spec.DataDrivenProperty) {
    if (hasCameraDependency) {
      if (prop.expression! is spec.StepExpression) {
        final stepExpr = prop.expression! as spec.StepExpression;

        return _PropertyAnalysis(
          type: _PropertyShaderType.attribute,
          interpolation: _PropertyInterpolation.step,
          interpolationStops: stepExpr.stops.map((stop) => stop.$1.toDouble()).toList(),
        );
      } else if (prop.expression! is spec.InterpolateExpression) {
        final interpolateExpr = prop.expression! as spec.InterpolateExpression;

        // TODO: Interpolation settings

        return _PropertyAnalysis(
          type: _PropertyShaderType.attribute,
          interpolation: _PropertyInterpolation.interpolate,
          interpolationStops: interpolateExpr.stops.map((stop) => stop.$1.toDouble()).toList(),
        );
      } else {
        throw UnimplementedError('Expression type not supported: ${prop.expression!.runtimeType}');
      }
    } else {
      return _PropertyAnalysis(type: _PropertyShaderType.attribute);
    }
  } else {
    throw UnimplementedError('Property type not supported: $prop');
  }
}
