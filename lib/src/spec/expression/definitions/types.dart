import 'package:gpu_vector_tile_renderer/src/spec/utils/type_utils.dart';
import 'package:intl/intl.dart' as intl;

import 'package:gpu_vector_tile_renderer/src/spec/expression/_definition_imports.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart';

@ExpressionAnnotation('LiteralExpression', rawName: 'literal', customFromJson: literalExpressionFromJsonImpl)
T literalExpressionImpl<T>(EvaluationContext context, T value) => value;

LiteralExpression<T> literalExpressionFromJsonImpl<T>(List<dynamic> args, {Type? type}) {
  assert(args[0] == 'literal');

  if (args.length != 2) {
    throw Exception('Expected 2 arguments, got ${args.length}');
  }

  if (isTypeEnum<T>()) {
    return LiteralExpression<T>(value: parseEnumJson<T>(args[1]));
  }

  if (isTypeEnumList<T>()) {
    return LiteralExpression<T>(value: parseEnumListJson<T>(args[1]));
  }

  // TODO: Make this better :/
  if ((T == List<num>) && args[1] is List && isListWithElementType<num>(args[1])) {
    return LiteralExpression<T>(value: args[1].cast<num>() as T);
  } else if ((T == List<String>) && args[1] is List && isListWithElementType<String>(args[1])) {
    return LiteralExpression<T>(value: args[1].cast<String>() as T);
  }

  return LiteralExpression<T>(value: args[1] as T, type: type);
}

@ExpressionAnnotation('CollatorExpressionExpression', rawName: 'collator')
Collator collatorExpressionImpl(
  EvaluationContext context,
  ({Expression<bool>? caseSensitive, Expression<bool>? diacriticSensitive, Expression<String>? locale}) object,
) {
  final _locale = object.locale?.evaluate(context);

  return Collator(
    caseSensitive: object.caseSensitive?.evaluate(context) ?? false,
    diacriticSensitive: object.diacriticSensitive?.evaluate(context) ?? false,
    locale: _locale != null ? Locale(languageCode: _locale) : null,
  );
}

@ExpressionAnnotation('FormatExpression', rawName: 'format')
Formatted formatExpressionImpl(EvaluationContext context) {
  // TODO
  return Formatted.empty();
}

@ExpressionAnnotation('ImageExpressionExpression', rawName: 'image')
ResolvedImage imageExpressionImpl(EvaluationContext context, Expression<String> value) {
  final _value = value(context);
  return ResolvedImage(_value);
}

@ExpressionAnnotation('NumberFormatExpression', rawName: 'number-format')
String numberFormatExpressionImpl(
  EvaluationContext context,
  Expression<num> number,
  ({
    Expression<String>? locale,
    Expression<String>? currency,
    Expression<int>? minFractionDigits,
    Expression<int>? maxFractionDigits,
  })
  options,
) {
  final _number = number(context);

  final _locale = options.locale?.evaluate(context);
  final _currency = options.currency?.evaluate(context);
  final _minFractionDigits = options.minFractionDigits?.evaluate(context);
  final _maxFractionDigits = options.maxFractionDigits?.evaluate(context);

  final format = intl.NumberFormat(null, _locale);

  if (_currency != null) format.currencyName = _currency;
  if (_minFractionDigits != null) format.minimumFractionDigits = _minFractionDigits;
  if (_maxFractionDigits != null) format.maximumFractionDigits = _maxFractionDigits;

  return format.format(_number);
}

// ------------------------------------
// Assertions
// ------------------------------------

@ExpressionAnnotation('ArrayAssertionExpression', rawName: 'array')
List arrayAssertionExpressionImpl(
  EvaluationContext context,
  Expression<dynamic> value,
  Type? childType,
  int? childCount,
) {
  final _value = value(context);

  if (_value is! List) {
    throw Exception('Expected an array, got ${_value.runtimeType}');
  }

  if (childType != null) {
    for (final item in _value) {
      if (item.runtimeType != childType) {
        throw Exception('Expected an array of $childType, got ${item.runtimeType} instead.');
      }
    }
  }

  if (childCount != null) {
    if (_value.length != childCount) {
      throw Exception('Expected an array of length $childCount, got ${_value.length}');
    }
  }

  return _value;
}

T _assertionExpressionImpl<T>(EvaluationContext context, List<Expression<dynamic>> args) {
  for (var i = 0; i < args.length; i++) {
    final value = args[i](context);

    if (value.runtimeType == T) {
      return value;
    }

    if (i == args.length - 1) {
      throw Exception('Expected value to be of type $T, but found ${value.runtimeType} instead.');
    }
  }

  throw Exception('Assertion failed.');
}

@ExpressionAnnotation('BooleanAssertionExpression', rawName: 'boolean')
bool booleanAssertionExpressionImpl(EvaluationContext context, List<Expression<dynamic>> args) {
  return _assertionExpressionImpl<bool>(context, args);
}

@ExpressionAnnotation('NumberAssertionExpression', rawName: 'number')
num numberAssertionExpressionImpl(EvaluationContext context, List<Expression<dynamic>> args) {
  return _assertionExpressionImpl<num>(context, args);
}

@ExpressionAnnotation('StringAssertionExpression', rawName: 'string')
String stringAssertionExpressionImpl(EvaluationContext context, List<Expression<dynamic>> args) {
  return _assertionExpressionImpl<String>(context, args);
}

@ExpressionAnnotation('ObjectAssertionExpression', rawName: 'object')
Map<String, dynamic> objectAssertionExpressionImpl(EvaluationContext context, List<Expression<dynamic>> args) {
  return _assertionExpressionImpl<Map<String, dynamic>>(context, args);
}

String _typeOf(dynamic value) {
  if (value == null) return 'null';
  if (value is num) return 'number';
  if (value is String) return 'string';
  if (value is bool) return 'boolean';
  if (value is Map<String, dynamic>) return 'object';
  if (value is List) {
    if (value.isEmpty) return 'array';

    final childTypes = value.map(_typeOf).toSet();
    final childType = childTypes.length == 1 ? childTypes.first : 'value';

    return 'array<$childType, ${value.length}>';
  }

  throw 'Unsupported type: ${value.runtimeType}';
}

@ExpressionAnnotation('TypeOfExpression', rawName: 'typeof')
String typeOfExpressionImpl(EvaluationContext context, Expression<dynamic> value) {
  return _typeOf(value(context));
}

// ------------------------------------
// Coercion
// ------------------------------------

@ExpressionAnnotation('ToStringExpression', rawName: 'to-string')
String toStringExpressionImpl(EvaluationContext context, Expression<dynamic> value) {
  final _value = value(context);

  if (_value == null) return '';
  if (_value is bool) {
    return _value ? 'true' : 'false';
  }
  if (_value is num) {
    return _value.toString();
  }
  if (_value is Color) {
    final _r = (_value.r * 255).round();
    final _g = (_value.g * 255).round();
    final _b = (_value.b * 255).round();
    final _a = _value.a;

    return 'rgba($_r, $_g, $_b, $_a)';
  }

  return _value.toString();
}

@ExpressionAnnotation('ToNumberExpression', rawName: 'to-number')
num toNumberExpressionImpl(EvaluationContext context, List<Expression<dynamic>> values) {
  for (final value in values) {
    final _value = value(context);

    if (_value is num) return _value;
    if (_value is bool) return _value ? 1 : 0;
    if (_value is String) {
      final _number = num.tryParse(_value);

      if (_number != null) return _number;
    }
  }

  throw Exception('Could not convert any of the values to a number.');
}

@ExpressionAnnotation('ToBooleanExpression', rawName: 'to-boolean')
bool toBooleanExpressionImpl(EvaluationContext context, Expression<dynamic> value) {
  final _value = value(context);

  if (_value == '' || _value == 0 || _value == false || _value == null || (_value is num && _value.isNaN)) {
    return false;
  }

  return true;
}

@ExpressionAnnotation('ToColorExpression', rawName: 'to-color')
Color toColorExpressionImpl(EvaluationContext context, List<Expression<dynamic>> values) {
  for (final value in values) {
    final _value = value(context);

    if (_value is Color) return _value;
    if (_value is List) {
      return Color.fromList(_value.cast<num>());
    }
    if (_value is String) {
      return Color.fromJson(_value);
    }
  }

  throw Exception('Could not convert any of the values to a color.');
}
