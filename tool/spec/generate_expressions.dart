#!/usr/bin/env fvm dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:collection/collection.dart';
import 'package:gpu_vector_tile_renderer/src/spec/expression/annotation.dart';
import 'package:gpu_vector_tile_renderer/src/spec/expression/expression_dependency.dart';

extension IsNullableExtension on DartType {
  bool get isNullable => nullabilitySuffix == NullabilitySuffix.question;
}

String _toKebabCase(String str) {
  return str.replaceAllMapped(RegExp(r'[A-Z]'), (match) => '-${match.group(0)!.toLowerCase()}');
}

ExpressionAnnotation _getExpressionAnnotation(Declaration expr) {
  final expressionAnnotation = expr.declaredElement!.metadata.firstWhereOrNull((v) => v.element is ConstructorElement);
  final value = expressionAnnotation!.computeConstantValue()!;

  dynamic ownDependencies;

  final $ownDependencies = value.getField('ownDependencies');
  final ownDependenciesType = $ownDependencies?.type;
  if (ownDependenciesType?.getDisplayString() == 'ExpressionDependency') {
    final index = $ownDependencies!.getField('index')!.toIntValue()!;
    ownDependencies = {ExpressionDependency.values[index]};
  } else if (ownDependenciesType?.getDisplayString() == 'Set<ExpressionDependency>') {
    final values = $ownDependencies!.toSetValue()!.map((e) => ExpressionDependency.values[e.toIntValue()!]).toSet();
    ownDependencies = values;
  } else if (ownDependenciesType?.getDisplayString() == 'String') {
    ownDependencies = $ownDependencies!.toStringValue();
  } else {
    ownDependencies = null;
  }

  return ExpressionAnnotation(
    value.getField('name')!.toStringValue()!,
    rawName: value.getField('rawName')!.toStringValue()!,
    ownDependencies: ownDependencies,
  );
}

String? _getExpressionCustomFromJson(Declaration expr) {
  final expressionAnnotation = expr.declaredElement!.metadata.firstWhereOrNull((v) => v.element is ConstructorElement);
  final value = expressionAnnotation!.computeConstantValue()!;

  return value.getField('customFromJson')?.toFunctionValue()?.name;
}

List<ParameterElement> _getExpressionParameters(FunctionDeclaration decl) {
  final expr = decl.functionExpression;
  final parameters = <ParameterElement>[];

  for (final parameter in expr.parameters!.parameterElements) {
    final type = parameter!.type;
    if (type.toString() == 'EvaluationContext') continue;

    parameters.add(parameter);
  }

  return parameters;
}

List<ParameterElement> _getExpressionChildren(FunctionDeclaration decl) {
  final parameters = _getExpressionParameters(decl);
  final result = <ParameterElement>[];

  for (final param in parameters) {
    final type = param.type;

    if (type.getDisplayString().startsWith('Expression')) {
      result.add(param);
    }
  }

  return result;
}

List<String> _generateExpressionConstructorCode(FunctionDeclaration decl) {
  final code = <String>[];
  final annotation = _getExpressionAnnotation(decl);
  final parameters = _getExpressionParameters(decl);
  final returnType = decl.returnType!.type!.toString();

  final childrenExpressions = _getExpressionChildren(decl);

  if (parameters.isNotEmpty || returnType == 'dynamic') {
    code.add('  ${annotation.name}({');

    for (final parameter in _getExpressionParameters(decl)) {
      final type = parameter.type;
      final isNullable = type.isNullable;

      if (isNullable) {
        code.add('    this.${parameter.name},');
      } else {
        code.add('    required this.${parameter.name},');
      }
    }

    code.add('    super.type,');
    code.add('  })');
  } else {
    code.add('  const ${annotation.name}()');
  }

  code.add('      : super(');

  if (childrenExpressions.isNotEmpty) {
    code.add('        childrenExpressions: [');

    for (final child in childrenExpressions) {
      if (child.type.isNullable) {
        code.add('          if (${child.name} != null) ${child.name},');
      } else {
        code.add('          ${child.name},');
      }
    }

    code.add('        ],');
  }

  if (annotation.ownDependencies != null) {
    if (annotation.ownDependencies is ExpressionDependency) {
      code.add('        ownDependencies: const {${annotation.ownDependencies}},');
    } else if (annotation.ownDependencies is Set<ExpressionDependency>) {
      code.add('        ownDependencies: const ${annotation.ownDependencies},');
    } else {
      code.add('        ownDependencies: ${annotation.ownDependencies},');
    }
  }

  code.add('      );');

  return code;
}

List<String> _generateExpressionFieldsCode(FunctionDeclaration decl) {
  final code = <String>[];

  for (final parameter in _getExpressionParameters(decl)) {
    final type = parameter.type;
    code.add('  final ${type.toString()} ${parameter.name};');
  }

  return code;
}

const _typesWithFromJson = ['InterpolationOptions'];

String _generateFromJsonTypeCast(DartType type, String accessor, [String Function(int index)? indexedAccessor]) {
  if (type.getDisplayString().startsWith('Expression')) {
    final expressionType = (type as ParameterizedType).typeArguments.first;
    final cast = 'Expression<$expressionType>.fromJson($accessor)';

    if (type.isNullable) {
      return '$accessor != null ? $cast : null';
    } else {
      return cast;
    }
  } else if (type.isDartCoreList) {
    final subtype = (type as ParameterizedType).typeArguments.first;
    return '$accessor.map((e) => ${_generateFromJsonTypeCast(subtype, 'e')}).toList() as ${subtype.getDisplayString()}';
  } else if (type.isDartCoreMap) {
    final valueType = (type as ParameterizedType).typeArguments.last;
    return '$accessor.map((k, v) => MapEntry(k, ${_generateFromJsonTypeCast(valueType, 'v')})';
  } else if (type is RecordType) {
    final isNamedRecord = type.positionalFields.isEmpty;

    if (isNamedRecord) {
      final fields = type.namedFields;

      var code = '(';

      for (final field in fields) {
        final fieldType = field.type;
        final kebabCaseFieldName = _toKebabCase(field.name);

        code += '${field.name}: ${_generateFromJsonTypeCast(fieldType, '$accessor[\'$kebabCaseFieldName\']')},';
      }

      code += ')';

      return code;
    } else {
      final fields = type.positionalFields;

      var code = '(';

      for (var i = 0; i < fields.length; i++) {
        final field = fields.elementAt(i);
        final fieldType = field.type;

        code += '${_generateFromJsonTypeCast(fieldType, indexedAccessor!(i))},';
      }

      code += ')';

      return code;
    }
  } else {
    if (_typesWithFromJson.contains(type.getDisplayString())) {
      return '${type.getDisplayString()}.fromJson($accessor as dynamic)';
    }

    return '$accessor as ${type.getDisplayString()}';
  }
}

List<String> _generateExpressionFromJsonCode(FunctionDeclaration decl) {
  final code = <String>[];
  final annotation = _getExpressionAnnotation(decl);
  final parameters = _getExpressionParameters(decl);
  final customFromJson = _getExpressionCustomFromJson(decl);

  code.add('  factory ${annotation.name}.fromJson(List<dynamic> args, {Type? type}) {');

  if (customFromJson != null) {
    code.add('    return $customFromJson(args, type: type);');
    code.add('  }');
    return code;
  }

  code.add(
    '    assert(args[0] == \'${annotation.rawName}\', \'Invalid expression type: \${args[0]}, expected [${annotation.rawName}]\');',
  );
  code.add('');

  if (parameters.isEmpty) {
    code.add('    return ${annotation.name}();');
  } else {
    code.add('    var i = 1;');
    code.add('');

    for (var i = 0; i < parameters.length; i++) {
      final parameter = parameters[i];
      final varName = 'arg$i';

      code.add('    // Parse $varName');
      code.add('    ${parameter.type.toString()} $varName;');
      code.add('');

      if (parameter.type.isDartCoreList) {
        code.add('    $varName = [];');

        final subtype = (parameter.type as ParameterizedType).typeArguments.first;
        final trailingNonNullParameters = parameters.skip(i + 1).where((e) => !e.type.isNullable).length;
        final isSubtypeRecord = subtype is RecordType;
        final elementsPerRow = isSubtypeRecord ? subtype.positionalFields.length : 1;

        code.add('    for (; i < args.length - $trailingNonNullParameters; i += $elementsPerRow) {');

        code.add(
          '      $varName.add(${_generateFromJsonTypeCast(subtype, 'args[i]', (index) => 'args[i + $index]')});',
        );

        code.add('    }');
      } else if (parameter.type.isNullable) {
        final cast = _generateFromJsonTypeCast(parameter.type, 'args[i]');

        code.add('    if (args.length > ${i + 1}) {');
        code.add('      $varName = $cast;');
        code.add('      i++;');
        code.add('    }');
      } else {
        final cast = _generateFromJsonTypeCast(parameter.type, 'args[i]');
        code.add('    $varName = $cast;');
        code.add('    i++;');
      }

      code.add('');
    }

    code.add('    return ${annotation.name}(');

    for (final parameter in parameters) {
      code.add('      ${parameter.name}: arg${parameters.indexOf(parameter)},');
    }

    code.add('      type: type,');

    code.add('    );');
  }

  code.add('  }');

  return code;
}

List<String> _generateExpressionEvaluateCode(FunctionDeclaration decl) {
  final code = <String>[];
  final parameters = _getExpressionParameters(decl);

  final implFunctionName = decl.name.toString();

  code.add('  @override');
  code.add('  ${decl.returnType!.type!.toString()} evaluate(EvaluationContext context) {');

  code.add('    return $implFunctionName(');
  code.add('      context,');

  for (final parameter in parameters) {
    code.add('      ${parameter.name},');
  }

  code.add('    );');
  code.add('  }');

  return code;
}

List<String> _generateExpressionEquatableCode(FunctionDeclaration decl) {
  final code = <String>[];
  final parameters = _getExpressionParameters(decl);

  code.add('  @override');
  code.add('  List<Object?> get props => [');

  for (final parameter in parameters) {
    code.add('    ${parameter.name},');
  }

  code.add('  ];');

  return code;
}

List<String> _generateExpressionCode(Map<String, dynamic> referenceExpressions, FunctionDeclaration decl) {
  final annotation = _getExpressionAnnotation(decl);
  final expr = decl.functionExpression;

  final code = <String>[];
  final returnType = decl.returnType!.type!.toString();

  final typeParametersSource = expr.typeParameters?.toSource();

  final referenceDoc = referenceExpressions[annotation.rawName]?['doc'] as String?;

  if (referenceDoc != null) {
    for (final line in referenceDoc.split('\n')) {
      code.add('/// $line');
    }
  }

  if (typeParametersSource != null) {
    code.add('class ${annotation.name}$typeParametersSource extends Expression<$returnType> {');
  } else {
    code.add('class ${annotation.name} extends Expression<$returnType> {');
  }

  code.addAll(_generateExpressionConstructorCode(decl));
  code.add('');
  code.add('/// Creates a new instance of [${annotation.name}] by parsing the given [args] as a JSON list.');
  code.addAll(_generateExpressionFromJsonCode(decl));
  code.add('');
  code.addAll(_generateExpressionFieldsCode(decl));
  code.add('');
  code.addAll(_generateExpressionEvaluateCode(decl));
  code.add('');
  code.addAll(_generateExpressionEquatableCode(decl));
  code.add('}');

  return code;
}

Future<void> main() async {
  final scriptPath = Platform.script.path;
  final rootDirectory = File(scriptPath).parent.parent.parent;
  final expressionsDirectory = Directory('${rootDirectory.path}/lib/src/spec/expression/definitions');
  final outputFile = File('${rootDirectory.path}/lib/src/spec/gen/expressions.gen.dart');
  final referenceFile = File('${rootDirectory.path}/lib/src/spec/reference/v8.json');

  final collection = AnalysisContextCollection(
    includedPaths: [expressionsDirectory.absolute.path],
    resourceProvider: PhysicalResourceProvider.INSTANCE,
  );

  final code = <String>[];

  code.add('// GENERATED CODE - DO NOT MODIFY BY HAND');
  code.add('// Generated by tool/style/generate_style_code.js');

  code.add('');
  code.add('import \'package:gpu_vector_tile_renderer/_spec.dart\';');
  code.add('import \'package:gpu_vector_tile_renderer/src/spec/expression/definitions/_definitions.dart\';');
  code.add('');

  final generatedExpressions = <({String rawName, String name, bool hasGeneric})>{};

  final referenceExpressions =
      jsonDecode(referenceFile.readAsStringSync())['expression_name']['values'] as Map<String, dynamic>;

  for (final context in collection.contexts) {
    for (final file in context.contextRoot.analyzedFiles()) {
      if (!file.endsWith('.dart')) continue;

      final resolvedUnit = await context.currentSession.getResolvedUnit(file);

      if (resolvedUnit is ResolvedUnitResult) {
        final unit = resolvedUnit.unit;

        for (final declaration in unit.declarations) {
          if (declaration is FunctionDeclaration) {
            final isExpression = declaration.metadata.any((e) => e.name.name == 'ExpressionAnnotation');

            if (isExpression) {
              final annotation = _getExpressionAnnotation(declaration);
              final generatedCode = _generateExpressionCode(referenceExpressions, declaration);
              final typeParameters = declaration.functionExpression.typeParameters;

              code.addAll(generatedCode);
              code.add('');

              generatedExpressions.add((
                rawName: annotation.rawName,
                name: annotation.name,
                hasGeneric: typeParameters != null && typeParameters.length > 0,
              ));
            }
          }
        }
      }
    }
  }

  code.add('');
  code.add('Expression<T> expressionFromJson<T>(List<dynamic> args) {');
  code.add('  return switch (args[0] as String) {');

  for (final expression in generatedExpressions) {
    var _code = '    \'${expression.rawName}\' => ';

    if (expression.hasGeneric) {
      _code += '${expression.name}<T>.fromJson(args),';
    } else {
      _code += '${expression.name}.fromJson(args),';
    }

    code.add(_code);
  }

  code.add('    _ => throw Exception(\'Unknown expression type: \${args[0]}\'),');
  code.add('  } as Expression<T>;');
  code.add('}');

  code.add('');

  await outputFile.writeAsString(code.join('\n'));

  print('Generated expressions: ${generatedExpressions.length}');

  final generatedExpressionsNameSet = generatedExpressions.map((e) => e.rawName).toSet();
  final referenceExpressionsNameSet = referenceExpressions.keys.toSet();

  final extraExpressions = generatedExpressionsNameSet.difference(referenceExpressionsNameSet);
  final missingExpressions = referenceExpressionsNameSet.difference(generatedExpressionsNameSet);

  if (extraExpressions.isNotEmpty) {
    print('[WARN] Extra expressions: $extraExpressions');

    for (final extraExpression in extraExpressions) {
      print(' - $extraExpression');
    }
  }

  if (missingExpressions.isNotEmpty) {
    print('[WARN] Missing expressions: $missingExpressions');

    for (final missingExpression in missingExpressions) {
      print(' - $missingExpression');
    }
  }

  // Run dart format
  final process = await Process.start('dart', ['format', outputFile.absolute.path, '--line-length=120']);
  await stdout.addStream(process.stdout);
}
