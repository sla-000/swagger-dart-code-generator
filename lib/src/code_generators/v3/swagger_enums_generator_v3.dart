import 'dart:convert';
import 'package:recase/recase.dart';
import 'package:swagger_dart_code_generator/src/code_generators/swagger_enums_generator.dart';
import 'package:swagger_dart_code_generator/src/code_generators/v3/swagger_models_generator_v3.dart';
import 'package:swagger_dart_code_generator/src/exception_words.dart';
import 'package:swagger_dart_code_generator/src/extensions/string_extension.dart';
import 'package:swagger_dart_code_generator/src/swagger_models/v3/swagger_root.dart';
import 'package:meta/meta.dart';

class SwaggerEnumsGeneratorV3 implements SwaggerEnumsGenerator {
  static const String defaultEnumFieldName = 'VALUE_';
  static const String defaultEnumValueName = 'swaggerGeneratedUnknown';

  @override
  String generate(String dartCode, String fileName) {
    final dynamic map = jsonDecode(dartCode);

    final enumsFromRequests = generateEnumsInRequests(dartCode, fileName);

    final components = map['components'] as Map<String, dynamic>;
    final schemas = components == null
        ? null
        : components['schemas'] as Map<String, dynamic>;

    if (schemas == null) {
      return '';
    }

    final enumsFromClasses = schemas.keys.map((String className) {
      return generateModelClassContent(
        className.pascalCase,
        schemas[className] as Map<String, dynamic>,
      );
    }).join('\n');

    if (enumsFromClasses.isEmpty && enumsFromRequests.isEmpty) {
      return '';
    }

    return '''
import 'package:json_annotation/json_annotation.dart';
$enumsFromClasses\n$enumsFromRequests''';
  }

  @visibleForTesting
  String generateEnumsInRequests(String swagger, String fileName) {
    final enumNames = <String>[];
    final result = StringBuffer();
    final map = jsonDecode(swagger) as Map<String, dynamic>;
    final swaggerRoot = SwaggerRoot.fromJson(map);

    for (var i = 0; i < swaggerRoot.paths.length; i++) {
      final swaggerPath = swaggerRoot.paths[i];

      for (var j = 0; j < swaggerPath.requests.length; j++) {
        final swaggerRequest = swaggerPath.requests[j];

        if (swaggerRequest.parameters == null) {
          continue;
        }

        for (var p = 0; p < swaggerRequest.parameters.length; p++) {
          final swaggerRequestParameter = swaggerRequest.parameters[p];

          var name = SwaggerModelsGeneratorV3.generateRequestEnumName(
              swaggerPath.path,
              swaggerRequest.type,
              swaggerRequestParameter.name);

          if (enumNames.contains(name)) {
            continue;
          }

          final enumValues = swaggerRequestParameter.schema?.enumValues ??
              swaggerRequestParameter.items?.enumValues;

          if (enumValues != null) {
            final enumContent = generateEnumContent(name, enumValues,
                swaggerRequestParameter.inParameter == 'body');

            result.writeln(enumContent);
            enumNames.add(swaggerRequestParameter.name);
          }
        }
      }
    }

    return result.toString();
  }

  @visibleForTesting
  List<String> getEnumNames(String swagger) {
    final enumNames = <String>[];
    final map = jsonDecode(swagger) as Map<String, dynamic>;
    final swaggerRoot = SwaggerRoot.fromJson(map);

    for (var i = 0; i < swaggerRoot.paths.length; i++) {
      final swaggerPath = swaggerRoot.paths[i];

      for (var j = 0; j < swaggerPath.requests.length; j++) {
        final swaggerRequest = swaggerPath.requests[j];

        if (swaggerRequest.parameters == null) {
          continue;
        }

        for (var p = 0; p < swaggerRequest.parameters.length; p++) {
          final swaggerRequestParameter = swaggerRequest.parameters[p];

          var name = SwaggerModelsGeneratorV3.generateRequestEnumName(
              swaggerPath.path,
              swaggerRequest.type,
              swaggerRequestParameter.name);

          if (enumNames.contains(name)) {
            continue;
          }

          final enumValues = swaggerRequestParameter.schema?.enumValues ??
              swaggerRequestParameter.items?.enumValues;

          if (enumValues != null) {
            enumNames.add(swaggerRequestParameter.name);
          }
        }
      }
    }

    return enumNames;
  }

  @visibleForTesting
  String generateEnumContent(
      String enumName, List<String> enumValues, bool isBody) {
    final enumValuesContent = getEnumValuesContent(enumValues);

    var enumMap = '';

    if (isBody) {
      enumMap = '''
\n\tconst _\$${enumName}Map = {
\t${getEnumValuesMapContent(enumName, enumValues)}
      };
      ''';
    }

    final result = """
enum $enumName{
\t@JsonValue('swaggerGeneratedUnknown')
\tswaggerGeneratedUnknown,
$enumValuesContent
}
$enumMap
 """;

    return result;
  }

  @visibleForTesting
  String getEnumValuesMapContent(String enumName, List<String> enumValues) {
    final result = enumValues
        .map((String enumFieldName) =>
            '\t$enumName.${getValidatedEnumFieldName(enumFieldName)}: \'$enumFieldName\'')
        .join(',\n');

    return result;
  }

  @visibleForTesting
  String getEnumValuesContent(List<String> enumValues) {
    final result = enumValues
        .map((String enumFieldName) =>
            "\t@JsonValue('${enumFieldName.replaceAll("\$", "\\\$")}')\n\t${getValidatedEnumFieldName(enumFieldName)}")
        .join(',\n');

    return result;
  }

  String getValidatedEnumFieldName(String name) {
    if (name.startsWith(RegExp('[0-9]+'))) {
      name = defaultEnumFieldName + name;
    }

    var result = name
        .replaceAll(RegExp(r'[^\w|\_|)]'), '_')
        .split('_')
        .where((element) => element.isNotEmpty)
        .map((String word) => word.toLowerCase().capitalize)
        .join();

    if (exceptionWords.contains(result.toLowerCase())) {
      return '\$' + result.lower;
    }

    return result.lower;
  }

  @visibleForTesting
  String generateEnumContentIfPossible(
      Map<String, dynamic> map, String enumName) {
    if (map['enum'] != null) {
      return """
enum ${enumName.capitalize} {
\t@JsonValue('$defaultEnumValueName')\n  $defaultEnumValueName,
${generateEnumValuesContent(map['enum'] as List<dynamic>)}
}
""";
    } else if (map['items'] != null) {
      return generateEnumContentIfPossible(
          map['items'] as Map<String, dynamic>, enumName);
    } else {
      return '';
    }
  }

  @visibleForTesting
  String generateEnumValuesContent(List<dynamic> values) {
    return values
        .map((dynamic e) =>
            "\t@JsonValue('${e.replaceAll("\$", "\\\$")}')\n  ${getValidatedEnumFieldName(e?.toString())}")
        .join(',\n');
  }

  @visibleForTesting
  String generateModelClassContent(String className, Map<String, dynamic> map) {
    if (map['enum'] != null) {
      return generateEnumContentIfPossible(map, className);
    }

    final properties = map['properties'] as Map<String, dynamic>;

    if (properties == null) {
      return null;
    }

    return generateEnumsContent(properties, className);
  }

  @visibleForTesting
  String generateEnumsContent(Map<String, dynamic> map, String className) {
    if (map == null) {
      return '';
    }

    final gemeratedEnumsContent = map.keys
        .map((String key) {
          final enumValuesMap = map[key] as Map<String, dynamic>;

          if (enumValuesMap.containsKey('type')) {
            return generateEnumContentIfPossible(
                enumValuesMap, generateEnumName(className, key));
          }

          return '';
        })
        .where((String generatedEnum) => generatedEnum.isNotEmpty)
        .join('\n');

    return gemeratedEnumsContent;
  }

  String generateEnumName(String className, String enumName) {
    return '${className.capitalize}${enumName.capitalize}';
  }
}
