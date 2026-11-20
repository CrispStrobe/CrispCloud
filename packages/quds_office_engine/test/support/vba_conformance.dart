import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';

/// Versioned, document-independent fixtures shared by VM and JavaScript tests.
///
/// Expectations contain complete native steps or stable source diagnostics.
/// A passing spec-derived case is not an observation from an Office process.
class VbaConformanceSuite {
  const VbaConformanceSuite._(this.id, this.dialect, this.cases);

  factory VbaConformanceSuite.parse(String json) {
    final Object? decoded = jsonDecode(json);
    final root = _object(decoded, 'suite');
    _fields(root, const {
      'schemaVersion',
      'suite',
      'dialect',
      'cases',
    }, 'suite');
    if (root['schemaVersion'] != 1) {
      _invalid('schemaVersion', 'only version 1 is supported');
    }
    final id = _identifier(root['suite'], 'suite');
    final dialect = _text(root['dialect'], 'dialect');
    if (dialect != 'vba-excel' &&
        dialect != 'vba-word' &&
        dialect != 'vba-powerpoint') {
      _invalid('dialect', 'must be vba-excel, vba-word, or vba-powerpoint');
    }
    final items = root['cases'];
    if (items is! List<Object?> || items.isEmpty) {
      _invalid('cases', 'must be a nonempty array');
    }
    final identifiers = <String>{};
    final cases = <VbaConformanceCase>[];
    for (var index = 0; index < items.length; index++) {
      final path = 'cases[$index]';
      final item = _object(items[index], path);
      _fields(item, const {
        'id',
        'feature',
        'source',
        'expected',
        'provenance',
      }, path);
      final caseId = _identifier(item['id'], '$path.id');
      if (!identifiers.add(caseId)) {
        _invalid('$path.id', 'duplicate identifier $caseId');
      }
      final source = _text(item['source'], '$path.source');
      cases.add(
        VbaConformanceCase._(
          caseId,
          _text(item['feature'], '$path.feature'),
          source,
          dialect,
          _expectation(item['expected'], source, '$path.expected', dialect),
          _provenance(item['provenance'], '$path.provenance'),
        ),
      );
    }
    return VbaConformanceSuite._(id, dialect, List.unmodifiable(cases));
  }

  final String id;
  final String dialect;
  final List<VbaConformanceCase> cases;
}

class VbaConformanceCase {
  const VbaConformanceCase._(
    this.id,
    this.feature,
    this.source,
    this.dialect,
    this.expected,
    this.provenance,
  );

  final String id;
  final String feature;
  final String source;
  final String dialect;
  final Map<String, Object?> expected;
  final Map<String, Object?> provenance;
}

/// Executes the public compiler and refuses any mismatched expectation.
Map<String, Object?> runVbaConformanceCase(VbaConformanceCase fixture) {
  final actual = _compileOutcome(fixture);
  if (canonicalVbaConformanceJson(actual) !=
      canonicalVbaConformanceJson(fixture.expected)) {
    throw StateError(
      '${fixture.id}: expected ${canonicalVbaConformanceJson(fixture.expected)}; '
      'received ${canonicalVbaConformanceJson(actual)}',
    );
  }
  return <String, Object?>{
    'id': fixture.id,
    'feature': fixture.feature,
    'provenance': fixture.provenance['kind'],
    'actual': actual,
    if (actual.containsKey('steps')) 'nativePlanRoundTrip': true,
  };
}

Map<String, Object?> _compileOutcome(VbaConformanceCase fixture) {
  try {
    final macro = OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: fixture.dialect,
        format: switch (fixture.dialect) {
          'vba-word' => OfficeMacroFormat.docx,
          'vba-powerpoint' => OfficeMacroFormat.pptx,
          _ => OfficeMacroFormat.xlsx,
        },
        moduleName: 'Conformance',
        source: fixture.source,
      ),
    );
    final restored = OfficeMacro.parse(macro.encode());
    if (canonicalVbaConformanceJson(restored.toJson()) !=
        canonicalVbaConformanceJson(macro.toJson())) {
      throw StateError(
        '${fixture.id}: native plan JSON round trip changed data',
      );
    }
    return <String, Object?>{
      'steps': <Object?>[for (final step in macro.steps) step.toJson()],
    };
  } on OfficeVbaCompileException catch (error) {
    return <String, Object?>{
      'diagnostic': <String, Object?>{
        'code': error.code,
        'line': error.line,
        'column': error.column,
      },
    };
  }
}

Map<String, Object?> runVbaConformanceSuite(VbaConformanceSuite suite) =>
    <String, Object?>{
      'schemaVersion': 1,
      'suite': suite.id,
      'dialect': suite.dialect,
      'caseCount': suite.cases.length,
      'cases': <Object?>[
        for (final fixture in suite.cases) runVbaConformanceCase(fixture),
      ],
    };

/// Sorts object keys and normalizes integral JSON numbers for portable receipts.
String canonicalVbaConformanceJson(Object? value) =>
    jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonical(value[key]),
    };
  }
  if (value is List<Object?>) {
    return <Object?>[for (final item in value) _canonical(item)];
  }
  if (value is num &&
      value.isFinite &&
      value.abs() <= 9007199254740991 &&
      value == value.truncateToDouble()) {
    return value.toInt();
  }
  return value;
}

Map<String, Object?> _expectation(
  Object? value,
  String source,
  String path,
  String dialect,
) {
  final input = _object(value, path);
  if (input.length != 1 ||
      (!input.containsKey('steps') && !input.containsKey('diagnostic'))) {
    _invalid(path, 'must contain exactly one of steps or diagnostic');
  }
  if (input.containsKey('steps')) {
    final steps = input['steps'];
    if (steps is! List<Object?>) _invalid('$path.steps', 'must be an array');
    final parsed = <Object?>[];
    for (var index = 0; index < steps.length; index++) {
      final stepPath = '$path.steps[$index]';
      final step = _object(steps[index], stepPath);
      _fields(step, const {'tool', 'arguments'}, stepPath);
      try {
        final native = OfficeMacroStep.fromJson(step);
        final prefix = switch (dialect) {
          'vba-word' => 'docx.',
          'vba-powerpoint' => 'pptx.',
          _ => 'xlsx.',
        };
        if (!native.tool.startsWith(prefix)) {
          _invalid(stepPath, '$dialect expectations must target $prefix');
        }
        parsed.add(Map<String, Object?>.unmodifiable(native.toJson()));
      } on OfficeMacroException catch (error) {
        _invalid(stepPath, error.message);
      }
    }
    return Map.unmodifiable(<String, Object?>{
      'steps': List<Object?>.unmodifiable(parsed),
    });
  }
  final diagnostic = _object(input['diagnostic'], '$path.diagnostic');
  _fields(diagnostic, const {'code', 'line', 'column'}, '$path.diagnostic');
  final code = _text(diagnostic['code'], '$path.diagnostic.code');
  if (!RegExp(r'^vba_[a-z_]+$').hasMatch(code)) {
    _invalid('$path.diagnostic.code', 'must be a stable vba_ diagnostic code');
  }
  final line = _position(diagnostic['line'], '$path.diagnostic.line');
  final column = _position(diagnostic['column'], '$path.diagnostic.column');
  final lines = source.split(RegExp(r'\r\n?|\n'));
  if (line > lines.length || column > lines[line - 1].length + 1) {
    _invalid(
      '$path.diagnostic',
      'position is outside the supplied UTF-16 source',
    );
  }
  return Map.unmodifiable(<String, Object?>{
    'diagnostic': Map<String, Object?>.unmodifiable(<String, Object?>{
      'code': code,
      'line': line,
      'column': column,
    }),
  });
}

Map<String, Object?> _provenance(Object? value, String path) {
  final input = _object(value, path);
  final kind = input['kind'];
  const baseFields = {'kind', 'references', 'note'};
  if (kind == 'office-host') {
    _fields(input, {...baseFields, 'host'}, path);
    final host = _object(input['host'], '$path.host');
    _fields(host, const {
      'application',
      'version',
      'platform',
      'observedAt',
      'evidence',
    }, '$path.host');
    for (final key in const ['application', 'version', 'platform']) {
      _text(host[key], '$path.host.$key');
    }
    _timestamp(host['observedAt'], '$path.host.observedAt');
    _link(host['evidence'], '$path.host.evidence');
  } else if (kind == 'spec-derived' || kind == 'dialect-contract') {
    _fields(input, baseFields, path);
  } else {
    _invalid(
      '$path.kind',
      'must be spec-derived, dialect-contract, or office-host',
    );
  }
  _text(input['note'], '$path.note');
  final references = input['references'];
  if (references is! List<Object?> || references.isEmpty) {
    _invalid(
      '$path.references',
      'must be a nonempty array of HTTPS references',
    );
  }
  for (var index = 0; index < references.length; index++) {
    _link(references[index], '$path.references[$index]');
  }
  return Map.unmodifiable(<String, Object?>{
    'kind': kind,
    'references': List<Object?>.unmodifiable(references),
    'note': input['note'],
    if (input.containsKey('host'))
      'host': Map<String, Object?>.unmodifiable(
        _object(input['host'], '$path.host'),
      ),
  });
}

void _timestamp(Object? value, String path) {
  final text = _text(value, path);
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(?:\.\d+)?(?:Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$',
  ).firstMatch(text);
  if (match == null) _invalid(path, 'must be an ISO timestamp with timezone');
  final year = int.parse(match[1]!);
  final month = int.parse(match[2]!);
  final day = int.parse(match[3]!);
  final date = DateTime.utc(year, month, day);
  if (date.year != year || date.month != month || date.day != day) {
    _invalid(path, 'must contain a valid calendar date');
  }
}

Never _invalid(String path, String message) =>
    throw FormatException('$path: $message');

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, Object?>) _invalid(path, 'must be an object');
  return value;
}

void _fields(Map<String, Object?> value, Set<String> fields, String path) {
  if (value.length != fields.length || !fields.containsAll(value.keys)) {
    _invalid(
      path,
      'required fields are ${fields.join(', ')}; unknown fields are refused',
    );
  }
}

String _text(Object? value, String path) {
  if (value is! String || value.trim().isEmpty) {
    _invalid(path, 'must be nonempty text');
  }
  return value;
}

String _identifier(Object? value, String path) {
  final text = _text(value, path);
  if (!RegExp(r'^[a-z0-9][a-z0-9._-]{0,95}$').hasMatch(text)) {
    _invalid(
      path,
      'must be a portable lowercase identifier of at most 96 characters',
    );
  }
  return text;
}

int _position(Object? value, String path) {
  if (value is! num ||
      !value.isFinite ||
      value < 1 ||
      value != value.truncateToDouble()) {
    _invalid(path, 'must be a positive integer');
  }
  return value.toInt();
}

void _link(Object? value, String path) {
  final text = _text(value, path);
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    _invalid(path, 'must be an absolute HTTPS URL without credentials');
  }
}
