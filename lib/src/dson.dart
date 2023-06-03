import '../dson_adapter.dart';

/// Function to transform the value of an object based on its key
typedef ResolverCallback = Object Function(dynamic value, FunctionParam param, String className, String paramName);

/// Convert JSON to Dart Class withless code generate(build_runner)
class DSON {
  /// Common resolvers
  final List<ResolverCallback> resolvers;

  /// Convert JSON to Dart Class withless code generate(build_runner)
  const DSON({
    this.resolvers = const [],
  });

  ///
  /// For complex objects it is necessary to declare the constructor in
  /// the [inner] property and declare the list resolver in the [resolvers]
  /// property.
  ///
  /// The [aliases] parameter can be used to create alias to specify the name
  /// of a field when it is deserialized.
  ///
  /// For example:
  /// ```dart
  /// Home home = dson.fromJson(
  ///   // json Map or List
  ///   jsonMap,
  ///   // Main constructor
  ///   Home.new,
  ///   // external types
  ///   inner: {
  ///     'owner': Person.new,
  ///     'parents': ListParam<Person>(Person.new),
  ///   },
  ///   // Param names Object <-> Param name in API
  ///   aliases: {
  ///     Home: {'owner': 'master'},
  ///     Person: {'id': 'key'}
  ///   }
  /// );
  /// ```

  ///
  /// For more information, see the
  /// [documentation](https://pub.dev/documentation/dson_adapter/latest/).
  T fromJson<T>(
    dynamic map,
    Function mainConstructor, {
    Map<String, dynamic> inner = const {},
    List<ResolverCallback> resolvers = const [],
    Map<Type, Map<String, String>> aliases = const {},
  }) {
    final mainConstructorNamed = mainConstructor.runtimeType.toString();
    final aliasesWithTypeInString = aliases.map((key, value) => MapEntry(key.toString(), value));
    final hasOnlyNamedParams = RegExp(r'\(\{(.+)\}\)').firstMatch(mainConstructorNamed);
    final className = mainConstructorNamed.split(' => ').last;
    if (hasOnlyNamedParams == null) {
      throw ParamsNotAllowed('$className must have named params only!');
    }

    final regExp = _namedParamsRegExMatch(className, mainConstructorNamed);

    final commonResolvers = [...this.resolvers, ...resolvers];

    final params = regExp //
        .group(1)!
        .split(',')
        .map((e) => e.trim())
        .map(FunctionParam.fromString)
        .map(
          (param) {
            dynamic value;

            var paramName = param.name;
            final newParamName = aliasesWithTypeInString[className]?[param.name];

            if (newParamName != null) {
              paramName = newParamName;
            }

            final workflow = map[paramName];

            if (workflow is Map || workflow is List || workflow is Set) {
              final innerParam = inner[param.name];

              if (innerParam is IParam) {
                value = innerParam.call(
                  this,
                  workflow,
                  inner,
                  commonResolvers,
                  aliases,
                );
              } else if (innerParam is Function) {
                value = fromJson(
                  workflow,
                  innerParam,
                  aliases: aliases,
                );
              } else {
                value = workflow;
              }
            } else {
              value = workflow;
            }

            if (value != null && commonResolvers.isEmpty) {
              value = _checkValueType(value, param, className, newParamName ?? param.name);
            } else {
              try {
                value = this.resolvers.fold(
                  value,
                  (previousValue, element) {
                    final result = element(value, param, className, newParamName ?? param.name);

                    return _checkValueType(result, param, className, newParamName ?? param.name);
                  },
                );
              } catch (e) {}

              value = resolvers.fold(
                value,
                (previousValue, element) {
                  final result = element(value, param, className, newParamName ?? param.name);

                  return _checkValueType(result, param, className, newParamName ?? param.name);
                },
              );
            }

            if (value == null) {
              if (param.isRequired) {
                if (param.isNullable) {
                  final entry = MapEntry(
                    Symbol(param.name),
                    null,
                  );
                  return entry;
                } else {
                  throw DSONException(
                    'Param $className.${param.name} '
                    'is required and non-nullable.',
                  );
                }
              } else {
                return null;
              }
            }

            final entry = MapEntry(Symbol(param.name), value);
            return entry;
          },
        )
        .where((entry) => entry != null)
        .cast<MapEntry<Symbol, dynamic>>()
        .toList();

    final namedParams = <Symbol, dynamic>{}..addEntries(params);

    return Function.apply(mainConstructor, [], namedParams);
  }

  dynamic _checkValueType(dynamic value, FunctionParam param, String className, String newParamName) {
    if (value.runtimeType.toString() == param.type) {
      return value;
    } else {
      throw DSONException(
        "Type '${value.runtimeType}' is not a subtype of type '${param.type}' of"
        " '$className({${param.isRequired ? 'required ' : ''}"
        "${param.name}})'${newParamName != param.name ? " with alias '"
            "$newParamName'." : '.'}",
      );
    }
  }

  RegExpMatch _namedParamsRegExMatch(
    String className,
    String mainConstructorNamed,
  ) {
    final result = RegExp(r'\(\{(.+)\}\)').firstMatch(mainConstructorNamed);

    if (result == null) {
      throw ParamsNotAllowed('$className must have named params only!');
    }

    return result;
  }
}

class FunctionParam {
  final String type;
  final String name;
  final bool isRequired;
  final bool isNullable;

  FunctionParam({
    required this.type,
    required this.name,
    required this.isRequired,
    required this.isNullable,
  });

  factory FunctionParam.fromString(String paramText) {
    final elements = paramText.split(' ');

    final name = elements.last;
    elements.removeLast();

    var type = elements.last;

    final lastMarkQuestionIndex = type.lastIndexOf('?');
    final isNullable = lastMarkQuestionIndex == type.length - 1;

    if (isNullable) {
      type = type.replaceFirst('?', '', lastMarkQuestionIndex);
    }

    final isRequired = elements.contains('required');

    return FunctionParam(
      name: name,
      type: type,
      isRequired: isRequired,
      isNullable: isNullable,
    );
  }

  @override
  String toString() => 'Param(type: $type, name: $name)';
}
