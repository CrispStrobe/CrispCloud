import 'dart:convert';

import '../../test/support/vba_conformance.dart';

const splitWordSink = 'ActiveDocument.Tables(1).Cell(1, 1).Range.Text';

const splitSinks = <String, String>{
  'vba-word': splitWordSink,
  'vba-excel': 'Worksheets(1).Range("A1").Value2',
  'vba-powerpoint':
      'ActivePresentation.Slides(1).Shapes(1).TextFrame.TextRange.Text',
};

/// Uses the same independently authored array oracle for every host adapter.
/// Only the fixed output selector and its native operation mapping differ.
List<VbaConformanceSuite> splitSuites(String source) => [
  for (final dialect in splitSinks.keys) _forDialect(source, dialect),
];

VbaConformanceSuite _forDialect(String source, String dialect) {
  final root = jsonDecode(source) as Map<String, Object?>;
  root['dialect'] = dialect;
  for (final raw in root['cases']! as List<Object?>) {
    final fixture = raw! as Map<String, Object?>;
    fixture['source'] = (fixture['source']! as String).replaceAll(
      splitWordSink,
      splitSinks[dialect]!,
    );
    final expected = fixture['expected']! as Map<String, Object?>;
    final steps = expected['steps'];
    if (steps is! List<Object?>) continue;
    expected['steps'] = [
      for (final rawStep in steps)
        _outputStep(rawStep! as Map<String, Object?>, dialect),
    ];
  }
  return VbaConformanceSuite.parse(jsonEncode(root));
}

Map<String, Object?> _outputStep(Map<String, Object?> step, String dialect) {
  final arguments = step['arguments']! as Map<String, Object?>;
  if (step['tool'] != 'docx.tableCellRangeText' ||
      arguments.length != 4 ||
      arguments['table'] != 0 ||
      arguments['row'] != 0 ||
      arguments['column'] != 0 ||
      arguments['text'] is! String) {
    throw StateError('The Split corpus must use the fixed String output sink.');
  }
  final text = arguments['text'];
  return switch (dialect) {
    'vba-word' => step,
    'vba-excel' => {
      'tool': 'xlsx.cellValue',
      'arguments': {'sheet': 0, 'cell': 'A1', 'value': text},
    },
    'vba-powerpoint' => {
      'tool': 'pptx.shapeText',
      'arguments': {'topLevel': true, 'slide': 0, 'shape': 0, 'text': text},
    },
    _ => throw ArgumentError.value(dialect, 'dialect'),
  };
}

/// Supply the unchanged fixture through -DVBA_CONFORMANCE_BASE64 on VM/dart2js.
void main() {
  const encoded = String.fromEnvironment('VBA_CONFORMANCE_BASE64');
  if (encoded.isEmpty) throw StateError('Supply the canonical Split corpus.');
  final suites = splitSuites(utf8.decode(base64Decode(encoded)));
  print(
    canonicalVbaConformanceJson({
      'schemaVersion': 1,
      'suite': 'vba-split-all-adapters',
      'adapterCount': suites.length,
      'caseCount': suites.fold<int>(
        0,
        (count, suite) => count + suite.cases.length,
      ),
      'adapters': [for (final suite in suites) runVbaConformanceSuite(suite)],
    }),
  );
}
