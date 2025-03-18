import 'package:equatable/equatable.dart';
import 'package:gpu_vector_tile_renderer/_spec.dart';
import 'package:gpu_vector_tile_renderer/src/spec/utils/type_utils.dart';

/// A base class for an expression.
///
/// An expression must contain a type, which is the type of the value it evaluates to.
///
/// An expression can be evaluated by calling [evaluate] with an [EvaluationContext].
///
/// The expressions themselves are generated automatically from their definitions in
/// `lib/src/spec/expression/definitions`.
abstract class Expression<T> with EquatableMixin {
  const Expression({Type? type, Set<ExpressionDependency>? ownDependencies, Iterable<Expression>? childrenExpressions})
      : type = type ?? T,
        ownDependencies = ownDependencies ?? const {},
        childrenExpressions = childrenExpressions ?? const [];

  /// Parses an expression from a JSON-like object.
  ///
  /// This is a generic factory constructor that can be used to parse any MapLibre-spec compatible expression type. Any
  /// children expressions are also parsed recursively.
  ///
  /// Throws an exception if parsing an expression fails for any reason.
  factory Expression.fromJson(dynamic args) {
    // TODO: Literal parsing can be moved to Literal class, and by using a custom factory constructor there.

    // [Color] literals
    if (T == Color) {
      if (args is String) {
        return LiteralExpression<Color>(value: Color.fromJson(args)) as Expression<T>;
      } else if (args is List && isListWithElementType<num>(args)) {
        return LiteralExpression<Color>(value: Color.fromList(args as List<num>)) as Expression<T>;
      }
    }

    // [Formatted] literals
    if (T == Formatted) {
      if (args is String) {
        return LiteralExpression<Formatted>(value: Formatted.fromJson(args)) as Expression<T>;
      }

      final expression = expressionFromJson(args);

      if (expression.type == Formatted) {
        return expression as Expression<T>;
      } else {
        return _FormattedStringAdapterExpression(expression) as Expression<T>;
      }
    }

    // [Padding] literals
    if (T == Padding && args is num) {
      return LiteralExpression<Padding>(value: Padding.fromJson([args])) as Expression<T>;
    }

    // [Enum] or [String] literals
    if (args is String) {
      if (isTypeEnum<T>()) {
        return LiteralExpression<T>(value: parseEnumJson<T>(args)) as Expression<T>;
      }

      return LiteralExpression<String>(value: args) as Expression<T>;
    }

    // Other common literals
    if (args == null) return LiteralExpression<Null>(value: null) as Expression<T>;
    if (args is num) return LiteralExpression<num>(value: args) as Expression<T>;
    if (args is bool) return LiteralExpression<bool>(value: args) as Expression<T>;
    if (args is Map<String, dynamic>) return LiteralExpression<Map<String, dynamic>>(value: args) as Expression<T>;

    return expressionFromJson<T>(args);
  }

  /// The type of the value this expression evaluates to.
  final Type type;

  /// The children expressions of this expression.
  ///
  /// This is used to optimize the expression (by precomputing values), or to evaluate the data dependencies of
  /// expressions.
  final Iterable<Expression> childrenExpressions;

  /// The dependencies that this expression has.
  ///
  /// For example, feature data expressions will set this to [ExpressionDependency.data], or camera expressions will
  /// set this to [ExpressionDependency.camera].
  final Set<ExpressionDependency> ownDependencies;

  /// The data dependencies of this expression, including the children expressions.
  Set<ExpressionDependency> get dependencies {
    return childrenExpressions.fold(ownDependencies, (value, e) => value.union(e.dependencies));
  }

  /// Evaluates this expression with the given [context].
  T evaluate(EvaluationContext context);

  /// Same as [evaluate], so that an expression object can be called as a function.
  T call(EvaluationContext context) => evaluate(context);
}

class _FormattedStringAdapterExpression extends Expression<Formatted> {
  _FormattedStringAdapterExpression(this.expression) : super(childrenExpressions: [expression]);

  final Expression expression;

  @override
  Formatted evaluate(EvaluationContext context) => Formatted.fromJson(expression(context));

  @override
  List<Object?> get props => [expression];
}
