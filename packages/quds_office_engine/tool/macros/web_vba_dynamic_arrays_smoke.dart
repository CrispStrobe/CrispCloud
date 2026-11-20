import 'dart:convert';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

OfficeMacro _compile(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-excel',
    format: OfficeMacroFormat.xlsx,
    moduleName: 'PortableDynamicArrays',
    source: source,
  ),
);

String _body(String source) => 'Sub Main()\n$source\nEnd Sub';

String _depthProgram() {
  final source = StringBuffer('Option Explicit\nOption Base 1\n');
  final unary = List<String>.filled(63, '+ ').join();
  for (var frame = 0; frame < 32; frame++) {
    final name = frame == 0 ? 'Main' : 'Helper$frame';
    source.writeln('Sub $name()');
    source.writeln('Dim data() As Long');
    for (var block = 0; block < 32; block++) {
      source.writeln('Dim item$block As Variant');
    }
    source.writeln('ReDim data(1)');
    for (var block = 0; block < 32; block++) {
      source.writeln('For Each item$block In data');
    }
    source.writeln(
      frame == 31
          ? 'Worksheets(1).Range("A1").Value2 = ${unary}42'
          : 'Call Helper${frame + 1}()',
    );
    source.writeln('Exit Sub');
    for (var block = 31; block >= 0; block--) {
      source.writeln('Next item$block');
    }
    source.writeln('End Sub');
  }
  return source.toString();
}

/// Actual assertions run on both the Dart VM and compiled JavaScript.
Future<void> main() async {
  final checks = <String>[];
  void check(bool condition, String name) {
    if (!condition) throw StateError(name);
    checks.add(name);
  }

  void reject(String source, String code, String name) {
    try {
      _compile(source);
      throw StateError('$name unexpectedly compiled');
    } on OfficeVbaCompileException catch (error) {
      check(error.code == code && error.line > 0 && error.column > 0, name);
    }
  }

  final depth = _compile(_depthProgram());
  check(
    depth.steps.length == 1 && depth.steps.single.arguments['value'] == 42,
    'dynamic arrays at 32 calls by 32 blocks by 64 expression depth',
  );

  final plan = _compile('''
Option Explicit
Option Base 1
Sub Main()
  Dim amounts() As Long, amount As Variant, row As Long, total As Long
  ReDim amounts(2)
  amounts(1) = 75
  amounts(2) = 125
  ReDim Preserve amounts(4)
  amounts(3) = 250
  amounts(4) = 400
  row = 1
  For Each amount In amounts
    Worksheets("Summary").Cells(row, 1).Value2 = amount
    total = total + amount
    row = row + 1
  Next amount
  With Worksheets("Summary")
    .Range("B1").Value2 = total
    .Range("B2").Formula = "=SUM(A1:A4)"
    ReDim Preserve amounts(2)
    ReDim Preserve amounts(4)
    .Range("C1").Value2 = amounts(3)
    .Range("C2").Value2 = amounts(2)
    Erase amounts
    ReDim Preserve amounts(-2147483648 To -2147483647)
    .Range("C3").Value2 = LBound(amounts)
    .Range("C4").Value2 = UBound(amounts)
    Erase amounts
    ReDim amounts(1)
    .Range("D1").Value2 = amounts(1)
  End With
End Sub
''');
  check(plan.steps.length == 11, 'bounded native operation count');
  final saved = OfficeMacro.parse(plan.encode());
  check(
    jsonEncode(saved.toJson()) == jsonEncode(plan.toJson()),
    'native plan round trip',
  );
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Summary').addRow(<Object?>['original']);
  final session = OfficeMacroSession(
    builder.build(),
    format: OfficeMacroFormat.xlsx,
  );
  final original = base64Encode(session.bytes);
  await session.validate(saved);
  check(
    session.revision == 0 && base64Encode(session.bytes) == original,
    'validation does not publish',
  );
  await session.run(saved);
  final sheet = SheetDeserializer().readBytes(session.bytes).sheets.single;
  const expected = <String, Object>{
    'A1': 75,
    'A2': 125,
    'A3': 250,
    'A4': 400,
    'B1': 850,
    'B2': 850,
    'C1': 0,
    'C2': 125,
    'C3': -2147483648,
    'C4': -2147483647,
    'D1': 0,
  };
  for (final entry in expected.entries) {
    check(sheet.cellA1(entry.key).value == entry.value, 'cell ${entry.key}');
  }
  check(session.revision == 1, 'complete run publishes one revision');

  final fixed = _compile(
    _body('''
Dim data(-2 To -1) As String
data(-2) = "discard"
Erase data
Worksheets(1).Range("A1").Value2 = data(-2)
Worksheets(1).Range("A2").Value2 = LBound(data)
'''),
  );
  check(
    fixed.steps[0].arguments['value'] == '' &&
        fixed.steps[1].arguments['value'] == -2,
    'fixed-array Erase resets values and retains bounds',
  );

  for (final action in <String>[
    'ReDim data(1)',
    'ReDim Preserve data(1)',
    'Erase data',
  ]) {
    reject(
      _body('''
Dim data() As Long, item As Variant
ReDim data(0)
For Each item In data
  $action
Next item
'''),
      'vba_array_locked',
      'enumeration lock: $action',
    );
  }
  reject(
    _body('''
Dim data() As Long
ReDim data(0)
Erase data
Worksheets(1).Range("A1").Value2 = UBound(data)
'''),
    'vba_subscript_out_of_range',
    'erased dynamic array has no bounds',
  );
  reject(
    _body('''
Dim data() As Long
ReDim data(1 To 2)
ReDim Preserve data(0 To 2)
'''),
    'vba_subscript_out_of_range',
    'Preserve retains the lower bound',
  );
  reject(
    _body('''
Dim data() As Long
ReDim data(4096)
'''),
    'vba_limit_exceeded',
    '4097 elements refused',
  );
  reject(
    _body('''
Dim a() As Long, b() As Long, c() As Long, d() As Long, extra() As Long
ReDim a(4095), b(4095), c(4095), d(4095), extra(0)
'''),
    'vba_limit_exceeded',
    'aggregate slot quota',
  );
  reject(
    _body('''
Dim data() As Long, index As Long
For index = 1 To 30
  ReDim data(4095)
  Erase data
Next index
'''),
    'vba_limit_exceeded',
    'released storage does not reset work quota',
  );

  final failed = _compile('''
Option Base 1
Sub Main()
  Dim names() As String, name As Variant
  ReDim names(1)
  names(1) = "Summary"
  ReDim Preserve names(2)
  names(2) = "Missing"
  For Each name In names
    Worksheets(name).Range("A1").Value2 = "not published"
  Next name
End Sub
''');
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.run(failed);
    throw StateError('Missing worksheet unexpectedly succeeded');
  } on OfficeMacroException catch (error) {
    check(
      error.code == 'operation_failed' && error.stepIndex == 1,
      'late dynamic-array target failure',
    );
  }
  check(
    session.revision == 1 && base64Encode(session.bytes) == beforeFailure,
    'late failure preserves bytes and revision',
  );
  print(
    jsonEncode(<String, Object?>{
      'suite': 'vba-dynamic-arrays',
      'passed': checks.length,
      'checks': checks,
      'cells': expected,
      'nativeSteps': plan.steps.length,
    }),
  );
}
