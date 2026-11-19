import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:test/test.dart';

TypeMatcher<OfficeMacroException> _limitError() => isA<OfficeMacroException>()
    .having((error) => error.code, 'code', 'limit_exceeded');

String _payload() => List<String>.filled(200 * 1024, 'x').join();

OfficeMacroSession _session() => OfficeMacroSession(
  File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
  format: OfficeMacroFormat.xlsx,
);

const _reference = <String, Object?>{r'$parameter': 'payload'};
const _parameters = <String, OfficeMacroParameter>{
  'payload': OfficeMacroParameter(OfficeMacroParameterType.string),
};

/// Reading past six entries would mean the 1 MiB byte budget was already
/// exceeded. This makes the test observe early rejection without a huge probe.
class _TrapAfterBudget extends ListBase<Object?> {
  _TrapAfterBudget(this.payload);

  final String payload;

  @override
  int get length => 10;

  @override
  set length(int value) => throw UnsupportedError('Read-only fixture');

  @override
  Object? operator [](int index) {
    if (index >= 6) throw StateError('Traversal continued beyond byte budget');
    return payload;
  }

  @override
  void operator []=(int index, Object? value) =>
      throw UnsupportedError('Read-only fixture');
}

void main() {
  test(
    'one expanded call cannot multiply a bounded parameter past 1 MiB',
    () async {
      final session = _session();
      final before = session.bytes;
      final macro = OfficeMacro(
        name: 'Nested amplification',
        format: OfficeMacroFormat.xlsx,
        parameters: _parameters,
        steps: <OfficeMacroStep>[
          OfficeMacroStep(
            tool: 'xlsx.cellValue',
            arguments: <String, Object?>{
              'cell': 'A1',
              'value': List<Object?>.filled(10, _reference),
            },
          ),
        ],
      );
      await expectLater(
        session.run(
          macro,
          parameters: <String, Object?>{'payload': _payload()},
        ),
        throwsA(_limitError()),
      );
      expect(session.bytes, before);
      expect(session.revision, 0);
    },
  );

  test(
    'many expanded calls stop at the first cumulative byte overflow',
    () async {
      final session = _session();
      final before = session.bytes;
      final step = OfficeMacroStep(
        tool: 'xlsx.cellValue',
        arguments: const <String, Object?>{'cell': 'A1', 'value': _reference},
      );
      final macro = OfficeMacro(
        name: 'Repeated parameter',
        format: OfficeMacroFormat.xlsx,
        parameters: _parameters,
        steps: List<OfficeMacroStep>.filled(10, step),
      );
      await expectLater(
        session.run(
          macro,
          parameters: <String, Object?>{'payload': _payload()},
        ),
        throwsA(
          _limitError().having(
            (error) => error.stepIndex,
            'first overflowing step',
            5,
          ),
        ),
      );
      expect(session.bytes, before);
      expect(session.revision, 0);
    },
  );

  test('programmatic plans enforce aggregate bytes before encoding', () {
    final step = OfficeMacroStep(
      tool: 'xlsx.cellValue',
      arguments: <String, Object?>{'cell': 'A1', 'value': _payload()},
    );
    expect(
      () => OfficeMacro(
        name: 'Programmatic amplification',
        format: OfficeMacroFormat.xlsx,
        steps: List<OfficeMacroStep>.filled(10, step),
      ),
      throwsA(_limitError()),
    );
  });

  test(
    'argument copying stops before traversing an already oversized tail',
    () {
      expect(
        () => OfficeMacroStep(
          tool: 'xlsx.cellValue',
          arguments: <String, Object?>{
            'cell': 'A1',
            'value': _TrapAfterBudget(_payload()),
          },
        ),
        throwsA(_limitError()),
      );
    },
  );

  test(
    'default serialization round-trips a valid plan near the byte ceiling',
    () {
      final step = OfficeMacroStep(
        tool: 'xlsx.cellValue',
        arguments: <String, Object?>{
          'cell': 'A1',
          'value': List<String>.filled(950, 'x').join(),
        },
      );
      final macro = OfficeMacro(
        name: 'Near limit',
        format: OfficeMacroFormat.xlsx,
        steps: List<OfficeMacroStep>.filled(1000, step),
      );
      expect(
        utf8.encode(macro.encode(pretty: false)).length,
        lessThan(1024 * 1024),
      );
      final serialized = macro.encode();
      expect(utf8.encode(serialized).length, lessThanOrEqualTo(1024 * 1024));
      expect(OfficeMacro.parse(serialized).toJson(), macro.toJson());
    },
  );
}
