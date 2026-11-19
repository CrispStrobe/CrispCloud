import 'dart:convert';

import 'office_operations.dart';

/// A stable domain error. [stepIndex], when present, is zero-based.
class OfficeMacroException implements Exception {
  const OfficeMacroException(
    this.code,
    this.message, {
    this.stepIndex,
    this.tool,
  });

  final String code;
  final String message;
  final int? stepIndex;
  final String? tool;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'message': message,
    if (stepIndex != null) 'stepIndex': stepIndex,
    if (tool != null) 'tool': tool,
  };

  @override
  String toString() => 'OfficeMacroException($code): $message';
}

/// Native parameter types. `json` accepts any finite JSON value, including null.
enum OfficeMacroParameterType { string, number, integer, boolean, json }

/// Every declared parameter must be provided; there are no implicit coercions.
class OfficeMacroParameter {
  const OfficeMacroParameter(this.type);

  factory OfficeMacroParameter.fromJson(Map<String, Object?> json) {
    macroFields(json, const <String>{'type'}, 'parameter');
    final type = macroString(json, 'type');
    for (final candidate in OfficeMacroParameterType.values) {
      if (candidate.name == type) return OfficeMacroParameter(candidate);
    }
    throw OfficeMacroException(
      'invalid_macro',
      'Unknown parameter type: $type',
    );
  }

  final OfficeMacroParameterType type;

  bool accepts(Object? value) => switch (type) {
    OfficeMacroParameterType.string => value is String,
    OfficeMacroParameterType.number => value is num && value.isFinite,
    OfficeMacroParameterType.integer => value is int,
    OfficeMacroParameterType.boolean => value is bool,
    OfficeMacroParameterType.json => true,
  };

  Map<String, Object?> toJson() => <String, Object?>{'type': type.name};
}

/// One canonical tool call, with immutable JSON arguments.
class OfficeMacroStep {
  OfficeMacroStep({required this.tool, required Map<String, Object?> arguments})
    : arguments = freezeMacroObject(arguments) {
    if (!RegExp(r'^(docx|xlsx|pptx)\.[A-Za-z][A-Za-z0-9]*$').hasMatch(tool)) {
      throw OfficeMacroException('invalid_macro', 'Invalid Office tool: $tool');
    }
  }

  factory OfficeMacroStep.fromJson(Map<String, Object?> json) {
    macroFields(json, const <String>{'tool', 'arguments'}, 'step');
    return OfficeMacroStep(
      tool: macroString(json, 'tool'),
      arguments: macroObject(json['arguments'], 'arguments'),
    );
  }

  final String tool;
  final Map<String, Object?> arguments;

  Map<String, Object?> toJson() => <String, Object?>{
    'tool': tool,
    'arguments': arguments,
  };
}

/// Version 1 native macro. Loading a macro never executes it.
///
/// Use `{"$parameter":"name"}` to substitute a declared parameter as a
/// JSON value. `{"$literal":value}` escapes parameter-looking objects.
class OfficeMacro {
  OfficeMacro({
    required this.name,
    required this.format,
    required Iterable<OfficeMacroStep> steps,
    Map<String, OfficeMacroParameter> parameters = const {},
    this.version = 1,
  }) : steps = List<OfficeMacroStep>.unmodifiable(steps),
       parameters = Map<String, OfficeMacroParameter>.unmodifiable(parameters) {
    if (version != 1) {
      throw OfficeMacroException(
        'unsupported_version',
        'Unsupported macro version: $version',
      );
    }
    if (name.trim().isEmpty || name.length > 128) {
      throw const OfficeMacroException(
        'invalid_macro',
        'Macro name must contain 1..128 characters.',
      );
    }
    if (this.steps.length > 10000 || this.parameters.length > 256) {
      throw const OfficeMacroException('limit_exceeded', 'Macro is too large.');
    }
    for (final key in this.parameters.keys) {
      if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]{0,63}$').hasMatch(key)) {
        throw OfficeMacroException('invalid_macro', 'Invalid parameter: $key');
      }
    }
    // Programmatic/compiler-produced plans have the same aggregate bound as
    // parsed JSON; repeated references must not produce an enormous encoding.
    freezeMacroObject(toJson());
  }

  factory OfficeMacro.parse(String source) {
    if (utf8.encode(source).length > macroJsonByteLimit) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'Macro JSON is too large.',
      );
    }
    try {
      final Object? decoded = jsonDecode(source);
      return OfficeMacro.fromJson(macroObject(decoded, 'macro'));
    } on FormatException catch (error) {
      throw OfficeMacroException(
        'invalid_macro',
        'Invalid JSON: ${error.message}',
      );
    }
  }

  factory OfficeMacro.fromJson(Map<String, Object?> json) {
    // Bound and freeze before descending, including maps supplied directly by
    // a host rather than by jsonDecode. This also refuses cycles and non-JSON.
    final input = freezeMacroObject(json);
    macroFields(input, const <String>{
      'version',
      'name',
      'format',
      'parameters',
      'steps',
    }, 'macro');
    final version = input['version'];
    if (version is! int) {
      throw const OfficeMacroException(
        'invalid_macro',
        'version must be an integer.',
      );
    }
    final steps = input['steps'];
    if (steps is! List<Object?>) {
      throw const OfficeMacroException(
        'invalid_macro',
        'steps must be an array.',
      );
    }
    final definitions = input.containsKey('parameters')
        ? macroObject(input['parameters'], 'parameters')
        : const <String, Object?>{};
    return OfficeMacro(
      version: version,
      name: macroString(input, 'name'),
      format: macroFormat(macroString(input, 'format')),
      parameters: <String, OfficeMacroParameter>{
        for (final entry in definitions.entries)
          entry.key: OfficeMacroParameter.fromJson(
            macroObject(entry.value, 'parameter ${entry.key}'),
          ),
      },
      steps: <OfficeMacroStep>[
        for (final step in steps)
          OfficeMacroStep.fromJson(macroObject(step, 'step')),
      ],
    );
  }

  final int version;
  final String name;
  final OfficeMacroFormat format;
  final Map<String, OfficeMacroParameter> parameters;
  final List<OfficeMacroStep> steps;

  Map<String, Object?> toJson() => <String, Object?>{
    'version': version,
    'name': name,
    'format': format.name,
    if (parameters.isNotEmpty)
      'parameters': <String, Object?>{
        for (final entry in parameters.entries) entry.key: entry.value.toJson(),
      },
    'steps': <Object?>[for (final step in steps) step.toJson()],
  };

  /// Emits re-importable JSON. Near the byte limit, compact formatting takes
  /// precedence over indentation so [parse] can always read this result.
  String encode({bool pretty = true}) {
    final json = toJson();
    if (pretty) {
      final indented = const JsonEncoder.withIndent('  ').convert(json);
      if (utf8.encode(indented).length <= macroJsonByteLimit) return indented;
    }
    return jsonEncode(json);
  }
}

// Internal JSON helpers are shared by the runtime and language adapters. They
// are deliberately not exported by the public automation entry point.
const int macroJsonByteLimit = 1024 * 1024;

OfficeMacroFormat macroFormat(String value) {
  for (final candidate in OfficeMacroFormat.values) {
    if (candidate.name == value) return candidate;
  }
  throw OfficeMacroException(
    'invalid_macro',
    'Unknown document format: $value',
  );
}

String macroString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw OfficeMacroException('invalid_macro', '$key must be a string.');
  }
  return value;
}

Map<String, Object?> macroObject(Object? value, String label) {
  if (value is! Map<String, Object?>) {
    throw OfficeMacroException('invalid_macro', '$label must be an object.');
  }
  return value;
}

void macroFields(Map<String, Object?> input, Set<String> fields, String label) {
  final unknown = input.keys.where((key) => !fields.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw OfficeMacroException(
      'invalid_macro',
      'Unknown $label fields: ${unknown.join(', ')}',
    );
  }
}

Map<String, Object?> freezeMacroObject(Map<String, Object?> input) {
  var remaining = 100000;
  var encodedBytes = 0;
  void charge(int bytes) {
    encodedBytes += bytes;
    if (encodedBytes > macroJsonByteLimit) {
      throw const OfficeMacroException('limit_exceeded', 'JSON exceeds 1 MiB.');
    }
  }

  Object? copy(Object? value, int depth) {
    if (--remaining < 0 || depth > 32) {
      throw const OfficeMacroException(
        'limit_exceeded',
        'JSON is too large or too deeply nested.',
      );
    }
    if (value == null || value is bool || value is String || value is num) {
      if (value is num && !value.isFinite) {
        throw const OfficeMacroException(
          'invalid_macro',
          'JSON numbers must be finite.',
        );
      }
      if (value is String && value.length > macroJsonByteLimit) {
        throw const OfficeMacroException(
          'limit_exceeded',
          'JSON string is too large.',
        );
      }
      charge(utf8.encode(jsonEncode(value)).length);
      return value;
    }
    if (value is List<Object?>) {
      charge(2 + (value.isEmpty ? 0 : value.length - 1));
      return List<Object?>.unmodifiable(
        value.map((item) => copy(item, depth + 1)),
      );
    }
    if (value is Map<String, Object?>) {
      charge(2 + (value.isEmpty ? 0 : value.length - 1));
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        if (entry.key.length > macroJsonByteLimit) {
          throw const OfficeMacroException(
            'limit_exceeded',
            'JSON key is too large.',
          );
        }
        charge(utf8.encode(jsonEncode(entry.key)).length + 1);
        result[entry.key] = copy(entry.value, depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    }
    throw const OfficeMacroException(
      'invalid_macro',
      'Arguments must contain only JSON values.',
    );
  }

  return copy(input, 0) as Map<String, Object?>;
}
