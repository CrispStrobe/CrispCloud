import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

Uint8List _workbook() {
  final builder = XlsxWorkbookBuilder();
  builder.addSheet('Data').addRow(<Object?>['original', 2]);
  return builder.build();
}

OfficeMacroStep _value(String cell, Object? value) => OfficeMacroStep(
  tool: 'xlsx.cellValue',
  arguments: <String, Object?>{'cell': cell, 'value': value},
);

OfficeMacro _plan(
  Iterable<OfficeMacroStep> steps, {
  Map<String, OfficeMacroParameter> parameters = const {},
}) => OfficeMacro(
  name: 'Test macro',
  format: OfficeMacroFormat.xlsx,
  steps: steps,
  parameters: parameters,
);

Map<String, Object?> _parameter(String name) => <String, Object?>{
  r'$parameter': name,
};

Matcher _error(String code, {int? stepIndex, String? tool}) {
  var matcher = isA<OfficeMacroException>().having(
    (error) => error.code,
    'code',
    code,
  );
  if (stepIndex != null) {
    matcher = matcher.having(
      (error) => error.stepIndex,
      'stepIndex',
      stepIndex,
    );
  }
  if (tool != null) {
    matcher = matcher.having((error) => error.tool, 'tool', tool);
  }
  return matcher;
}

void main() {
  group('macro execution', () {
    test(
      'native macro execution preserves XLSM VBA bytes, type, and relationship',
      () async {
        const workbookType =
            'application/vnd.ms-excel.sheet.macroEnabled.main+xml';
        const vbaType = 'application/vnd.ms-office.vbaProject';
        const relationshipType =
            'http://schemas.microsoft.com/office/2006/relationships/vbaProject';
        final package = OpcPackage.openBytes(
          File('test/fixtures/fidelity/native.xlsx').readAsBytesSync(),
        );
        package.getPart('/xl/workbook.xml')!.contentType = workbookType;
        package.contentTypes.setOverride('/xl/workbook.xml', workbookType);
        final opaque = Uint8List.fromList(<int>[
          0,
          1,
          2,
          127,
          128,
          253,
          254,
          255,
        ]);
        package.createPart('/xl/vbaProject.bin', vbaType, opaque);
        final relationship = package
            .relationshipsFor('/xl/workbook.xml')
            .add(type: relationshipType, target: 'vbaProject.bin');
        final session = OfficeMacroSession(
          package.save(),
          format: OfficeMacroFormat.xlsx,
        );
        await session.run(
          _plan(<OfficeMacroStep>[_value('A1', 'Native macro edit')]),
        );

        final output = OpcPackage.openBytes(session.bytes);
        expect(output.getPart('/xl/vbaProject.bin')!.readBytes(), opaque);
        expect(output.getPart('/xl/vbaProject.bin')!.contentType, vbaType);
        expect(output.getPart('/xl/workbook.xml')!.contentType, workbookType);
        final savedRelationship = output
            .relationshipsFor('/xl/workbook.xml')
            .firstByType(relationshipType)!;
        expect(savedRelationship.id, relationship.id);
        expect(savedRelationship.target, relationship.target);
        expect(savedRelationship.targetMode, relationship.targetMode);
        expect(
          SheetDeserializer().read(output).firstSheet.cellA1('A1').value,
          'Native macro edit',
        );
        expect(session.revision, 1);
      },
    );

    test(
      'asset callback failure rolls back preceding document edits',
      () async {
        final builder = DocxDocumentBuilder()..paragraph('original text');
        final requested = <String>[];
        final session = OfficeMacroSession(
          builder.build(),
          format: OfficeMacroFormat.docx,
          resolveAsset: (key) {
            requested.add(key);
            throw StateError('Host asset is unavailable');
          },
        );
        final before = session.bytes;
        final macro = OfficeMacro(
          name: 'Asset failure',
          format: OfficeMacroFormat.docx,
          steps: <OfficeMacroStep>[
            OfficeMacroStep(
              tool: 'docx.replaceText',
              arguments: <String, Object?>{
                'paragraph': 0,
                'text': 'detached edit',
              },
            ),
            OfficeMacroStep(
              tool: 'docx.imageAdd',
              arguments: <String, Object?>{
                'file': 'host-logo',
                'width': 10,
                'height': 10,
              },
            ),
          ],
        );
        await expectLater(
          session.run(macro),
          throwsA(
            _error('operation_failed', stepIndex: 1, tool: 'docx.imageAdd'),
          ),
        );
        expect(requested, <String>['host-logo']);
        expect(session.bytes, before);
        expect(session.revision, 0);
        session.startRecording('Session recovered');
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test(
      'empty plans still validate input and preserve valid document bytes',
      () async {
        final empty = _plan(const <OfficeMacroStep>[]);
        final malformed = OfficeMacroSession(
          Uint8List.fromList(<int>[1, 2, 3]),
          format: OfficeMacroFormat.xlsx,
        );
        await expectLater(
          malformed.validate(empty),
          throwsA(_error('document_error')),
        );
        await expectLater(
          malformed.run(empty),
          throwsA(_error('document_error')),
        );
        expect(malformed.revision, 0);

        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        final receipt = await session.run(empty);
        final validation = await session.validate(empty);
        expect(receipt.completedSteps, 0);
        expect(validation.completedSteps, 0);
        expect(validation.validatedOnly, isTrue);
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'typed parameters produce real values, formatting, and formulas',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final macro = _plan(
          <OfficeMacroStep>[
            _value('A1', _parameter('title')),
            _value('A2', _parameter('amount')),
            _value('B2', _parameter('flag')),
            _value('C2', _parameter('empty')),
            OfficeMacroStep(
              tool: 'xlsx.cellFormat',
              arguments: <String, Object?>{
                'sheet': _parameter('sheet'),
                'cell': 'A1',
                'bold': _parameter('flag'),
              },
            ),
            OfficeMacroStep(
              tool: 'xlsx.cellFormula',
              arguments: <String, Object?>{'cell': 'D2', 'formula': '=A2*2'},
            ),
          ],
          parameters: const <String, OfficeMacroParameter>{
            'title': OfficeMacroParameter(OfficeMacroParameterType.string),
            'amount': OfficeMacroParameter(OfficeMacroParameterType.number),
            'flag': OfficeMacroParameter(OfficeMacroParameterType.boolean),
            'empty': OfficeMacroParameter(OfficeMacroParameterType.json),
            'sheet': OfficeMacroParameter(OfficeMacroParameterType.integer),
          },
        );

        final receipt = await session.run(
          macro,
          parameters: <String, Object?>{
            'title': 'Revenue',
            'amount': 12.5,
            'flag': true,
            'empty': null,
            'sheet': 0,
          },
        );
        final sheet = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single;
        expect(sheet.cellA1('A1').value, 'Revenue');
        expect(sheet.cellA1('A1').fontBold, isTrue);
        expect(sheet.cellA1('A2').value, 12.5);
        expect(sheet.cellA1('B2').value, true);
        expect(sheet.cellA1('C2').value, isNull);
        expect(sheet.cellA1('D2').formula, 'A2*2');
        expect(sheet.cellA1('D2').value, 25);
        expect(receipt.completedSteps, 6);
        expect(receipt.revision, 1);
        expect(receipt.validatedOnly, isFalse);
        expect(session.revision, 1);
      },
    );

    test(
      'parameters are required, reject extras, and never coerce types',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        final macro = _plan(
          <OfficeMacroStep>[_value('A1', _parameter('count'))],
          parameters: const <String, OfficeMacroParameter>{
            'count': OfficeMacroParameter(OfficeMacroParameterType.integer),
          },
        );
        for (final bindings in <Map<String, Object?>>[
          <String, Object?>{},
          <String, Object?>{'count': '3'},
          <String, Object?>{'count': 3.0},
          <String, Object?>{'count': null},
          <String, Object?>{'count': true},
          <String, Object?>{'count': 3, 'unexpected': 4},
        ]) {
          await expectLater(
            session.run(macro, parameters: bindings),
            throwsA(_error('invalid_parameter')),
          );
          expect(session.bytes, before);
          expect(session.revision, 0);
        }
      },
    );

    test(
      'parameter objects are data and cannot inject another reference',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        final macro = _plan(
          <OfficeMacroStep>[_value('A1', _parameter('payload'))],
          parameters: const <String, OfficeMacroParameter>{
            'payload': OfficeMacroParameter(OfficeMacroParameterType.json),
            'secret': OfficeMacroParameter(OfficeMacroParameterType.string),
          },
        );
        await expectLater(
          session.run(
            macro,
            parameters: <String, Object?>{
              'payload': _parameter('secret'),
              'secret': 'must not be substituted',
            },
          ),
          throwsA(
            _error('operation_failed', stepIndex: 0, tool: 'xlsx.cellValue'),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'undeclared and malformed references fail before publication',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        for (final value in <Object?>[
          _parameter('missing'),
          <String, Object?>{r'$parameter': 3},
          <String, Object?>{r'$parameter': 'missing', 'extra': true},
          <String, Object?>{r'$literal': 3, 'extra': true},
        ]) {
          await expectLater(
            session.run(
              _plan(<OfficeMacroStep>[
                _value('A1', 'must not be published'),
                _value('B1', value),
              ]),
            ),
            throwsA(_error('invalid_parameter')),
          );
        }
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'later semantic failure retains exact original bytes and revision',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        await session.run(_plan(<OfficeMacroStep>[_value('A1', 'committed')]));
        final before = session.bytes;
        final revision = session.revision;
        final macro = _plan(<OfficeMacroStep>[
          _value('A1', 'must roll back'),
          OfficeMacroStep(
            tool: 'xlsx.rowHeight',
            arguments: <String, Object?>{'row': 0, 'height': 1},
          ),
        ]);
        await expectLater(
          session.run(macro),
          throwsA(
            _error('operation_failed', stepIndex: 1, tool: 'xlsx.rowHeight'),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, revision);
        expect(
          SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('A1')
              .value,
          'committed',
        );
        await session.run(_plan(<OfficeMacroStep>[_value('A1', 'recovered')]));
        expect(session.revision, revision + 1);
      },
    );

    test(
      'validation executes semantic checks without publishing or recording',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        session.startRecording('Only published calls');
        final receipt = await session.validate(
          _plan(<OfficeMacroStep>[_value('A1', 'detached edit')]),
        );
        expect(receipt.completedSteps, 1);
        expect(receipt.validatedOnly, isTrue);
        expect(receipt.revision, 0);
        await expectLater(
          session.validate(
            _plan(<OfficeMacroStep>[
              OfficeMacroStep(
                tool: 'xlsx.cellValue',
                arguments: <String, Object?>{
                  'sheet': 99,
                  'cell': 'A1',
                  'value': 1,
                },
              ),
            ]),
          ),
          throwsA(_error('operation_failed', stepIndex: 0)),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test(
      'cancellation between operations rolls back and refuses overlapping work',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        final cancellation = OfficeMacroCancellation();
        final pending = session.run(
          _plan(<OfficeMacroStep>[
            _value('A1', 'first'),
            _value('B1', 'second'),
          ]),
          cancellation: cancellation,
        );
        final overlapping = session.run(
          _plan(<OfficeMacroStep>[_value('C1', 'busy')]),
        );
        expect(
          () => session.startRecording('Busy'),
          throwsA(_error('session_busy')),
        );
        // The first operation's zero-duration event was queued by run() first.
        // This cancellation is observed at the checkpoint for the second step.
        Timer.run(cancellation.cancel);
        await expectLater(overlapping, throwsA(_error('session_busy')));
        await expectLater(
          pending,
          throwsA(_error('cancelled', stepIndex: 1, tool: 'xlsx.cellValue')),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
        await session.run(
          _plan(<OfficeMacroStep>[_value('A1', 'after cancellation')]),
        );
        expect(session.revision, 1);
      },
    );

    test(
      'pre-cancelled requests never publish and do not leave the session busy',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        final token = OfficeMacroCancellation()..cancel();
        await expectLater(
          session.run(
            _plan(<OfficeMacroStep>[_value('A1', 'unused')]),
            cancellation: token,
          ),
          throwsA(_error('cancelled')),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
        session.startRecording('After cancellation');
        expect(session.stopRecording().steps, isEmpty);
      },
    );

    test('session owns its input and returned byte buffers', () {
      final input = _workbook();
      final expected = Uint8List.fromList(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.xlsx);
      input.fillRange(0, input.length, 0);
      session.bytes.fillRange(0, expected.length, 1);
      expect(session.bytes, expected);
      expect(session.inspect()['format'], 'xlsx');
    });
  });

  group('macro authorization and limits', () {
    test(
      'expanded output growth fails before publishing bytes or revision',
      () async {
        final input = _workbook();
        final expanded = ZipReader.fromBytes(input).entries.fold<int>(
          0,
          (total, entry) => total + entry.uncompressedSize,
        );
        final session = OfficeMacroSession(
          input,
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxExpandedBytes: expanded + 64),
        );
        await expectLater(
          session.run(
            _plan(<OfficeMacroStep>[
              _value('A1', List<String>.filled(4096, 'x').join()),
            ]),
          ),
          throwsA(_error('limit_exceeded')),
        );
        expect(session.bytes, input);
        expect(session.revision, 0);
        expect(
          SheetDeserializer()
              .readBytes(session.bytes)
              .sheets
              .single
              .cellA1('A1')
              .value,
          'original',
        );
      },
    );

    test(
      'full-sheet merge exhausts the work budget before allocating cells',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        await expectLater(
          session.run(
            _plan(<OfficeMacroStep>[
              _value('A1', 'unpublished first step'),
              OfficeMacroStep(
                tool: 'xlsx.mergeCells',
                arguments: <String, Object?>{'range': 'A1:XFD1048576'},
              ),
            ]),
          ),
          throwsA(
            _error('limit_exceeded', stepIndex: 1, tool: 'xlsx.mergeCells'),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'cell work is cumulative within a run and resets for the next run',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxCellVisits: 6),
        );
        final before = session.bytes;
        final steps = <OfficeMacroStep>[
          _value('A1', 'unpublished first step'),
          OfficeMacroStep(
            tool: 'xlsx.mergeCells',
            arguments: <String, Object?>{'range': 'A2:B3'},
          ),
          OfficeMacroStep(
            tool: 'xlsx.mergeCells',
            arguments: <String, Object?>{'range': 'D2:E3'},
          ),
        ];
        await expectLater(
          session.run(_plan(steps)),
          throwsA(
            _error('limit_exceeded', stepIndex: 2, tool: 'xlsx.mergeCells'),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
        await session.run(_plan(steps.take(2)));
        final sheet = SheetDeserializer()
            .readBytes(session.bytes)
            .sheets
            .single;
        expect(sheet.merges.map((range) => range.a1), <String>['A2:B3']);
        expect(session.revision, 1);
      },
    );

    test(
      'expanded input and package part limits reject without publication',
      () async {
        final input = _workbook();
        for (final policy in <OfficeMacroPolicy>[
          OfficeMacroPolicy(maxExpandedBytes: 1),
          OfficeMacroPolicy(maxPackageParts: 1),
        ]) {
          final session = OfficeMacroSession(
            input,
            format: OfficeMacroFormat.xlsx,
            policy: policy,
          );
          await expectLater(
            session.run(_plan(<OfficeMacroStep>[_value('A1', 'never opened')])),
            throwsA(_error('limit_exceeded')),
          );
          await expectLater(
            session.validate(_plan(const <OfficeMacroStep>[])),
            throwsA(_error('limit_exceeded')),
          );
          expect(session.bytes, input);
          expect(session.revision, 0);
        }
      },
    );

    test(
      'unknown tools, cross-format calls, and undeclared fields are rejected',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        final before = session.bytes;
        for (final entry in <(OfficeMacro, String)>[
          (
            _plan(<OfficeMacroStep>[
              OfficeMacroStep(tool: 'xlsx.executeCode', arguments: const {}),
            ]),
            'unknown_tool',
          ),
          (
            _plan(<OfficeMacroStep>[
              OfficeMacroStep(
                tool: 'docx.paragraphInsert',
                arguments: const {},
              ),
            ]),
            'format_mismatch',
          ),
          (
            _plan(<OfficeMacroStep>[
              OfficeMacroStep(
                tool: 'xlsx.cellValue',
                arguments: <String, Object?>{
                  'cell': 'A1',
                  'value': 3,
                  'op': 'cellValue',
                },
              ),
            ]),
            'invalid_arguments',
          ),
          (
            OfficeMacro(
              name: 'Wrong format',
              format: OfficeMacroFormat.docx,
              steps: const [],
            ),
            'format_mismatch',
          ),
        ]) {
          await expectLater(session.run(entry.$1), throwsA(_error(entry.$2)));
        }
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'host allowlist is copied and cannot be widened by macro or caller',
      () async {
        final allowed = <String>{'xlsx.cellValue'};
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(allowedTools: allowed),
        );
        final before = session.bytes;
        allowed.add('xlsx.renameSheet');
        await expectLater(
          session.run(
            _plan(<OfficeMacroStep>[
              _value('A1', 'never published'),
              OfficeMacroStep(
                tool: 'xlsx.renameSheet',
                arguments: <String, Object?>{'name': 'Denied'},
              ),
            ]),
          ),
          throwsA(
            _error('permission_denied', stepIndex: 1, tool: 'xlsx.renameSheet'),
          ),
        );
        expect(session.allowedTools, <String>{'xlsx.cellValue'});
        expect(
          () => session.allowedTools.add('xlsx.renameSheet'),
          throwsUnsupportedError,
        );
        expect(session.bytes, before);
        expect(session.revision, 0);
      },
    );

    test(
      'read-only policy permits inspection and denies run, validation, and recording',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(allowMutation: false),
        );
        final macro = _plan(<OfficeMacroStep>[_value('A1', 'denied')]);
        expect(session.inspect()['format'], 'xlsx');
        expect(session.allowedTools, isEmpty);
        expect(
          () => session.startRecording('Denied'),
          throwsA(_error('permission_denied')),
        );
        await expectLater(
          session.run(macro),
          throwsA(_error('permission_denied')),
        );
        await expectLater(
          session.validate(macro),
          throwsA(_error('permission_denied')),
        );
        expect(session.revision, 0);
      },
    );

    test(
      'step and expanded byte limits reject work before publication',
      () async {
        final oneStep = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxSteps: 1),
        );
        final before = oneStep.bytes;
        await expectLater(
          oneStep.run(
            _plan(<OfficeMacroStep>[_value('A1', 1), _value('B1', 2)]),
          ),
          throwsA(_error('limit_exceeded')),
        );
        expect(oneStep.bytes, before);
        final bounded = OfficeMacroSession(
          before,
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxMacroBytes: 400),
        );
        await expectLater(
          bounded.run(
            _plan(
              <OfficeMacroStep>[_value('A1', _parameter('text'))],
              parameters: const <String, OfficeMacroParameter>{
                'text': OfficeMacroParameter(OfficeMacroParameterType.string),
              },
            ),
            parameters: <String, Object?>{
              'text': List<String>.filled(500, 'x').join(),
            },
          ),
          throwsA(_error('limit_exceeded')),
        );
        expect(bounded.bytes, before);
        expect(bounded.revision, 0);
      },
    );

    test('empty or oversized documents and invalid policies are rejected', () {
      expect(
        () => OfficeMacroSession(Uint8List(0), format: OfficeMacroFormat.xlsx),
        throwsA(_error('limit_exceeded')),
      );
      expect(
        () => OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxDocumentBytes: 1),
        ),
        throwsA(_error('limit_exceeded')),
      );
      expect(() => OfficeMacroPolicy(maxSteps: 0), throwsArgumentError);
      expect(
        () => OfficeMacroPolicy(maxDuration: Duration.zero),
        throwsArgumentError,
      );
    });
  });

  group('macro recording', () {
    test(
      'aggregate recording byte limit rejects the next call before publication',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxMacroBytes: 300),
        );
        session.startRecording('Bounded bytes');
        final value = List<String>.filled(100, 'x').join();
        await session.callTool('xlsx.cellValue', <String, Object?>{
          'cell': 'A1',
          'value': value,
        });
        final before = session.bytes;
        await expectLater(
          session.callTool('xlsx.cellValue', <String, Object?>{
            'cell': 'B1',
            'value': value,
          }),
          throwsA(_error('limit_exceeded')),
        );
        expect(session.bytes, before);
        expect(session.revision, 1);
        final recorded = session.stopRecording();
        expect(OfficeMacro.parse(recorded.encode()).steps, hasLength(1));

        final standalone = OfficeMacroRecorder(
          name: 'Bounded bytes',
          format: OfficeMacroFormat.xlsx,
          maxBytes: 300,
        );
        standalone.record('xlsx.cellValue', <String, Object?>{
          'cell': 'A1',
          'value': value,
        });
        expect(
          () => standalone.record('xlsx.cellValue', <String, Object?>{
            'cell': 'B1',
            'value': value,
          }),
          throwsA(_error('limit_exceeded')),
        );
        expect(standalone.length, 1);
      },
    );

    test(
      'only successful direct calls are recorded, with immutable captured arguments',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        session.startRecording('Direct calls');
        final arguments = <String, Object?>{'cell': 'A1', 'value': 'captured'};
        final call = session.callTool('xlsx.cellValue', arguments);
        arguments['value'] = 'changed after invocation';
        await call;
        await expectLater(
          session.callTool('xlsx.cellValue', <String, Object?>{
            'sheet': 99,
            'cell': 'A1',
            'value': 'failed',
          }),
          throwsA(_error('operation_failed')),
        );
        await session.run(_plan(<OfficeMacroStep>[_value('B1', 'playback')]));
        await session.validate(
          _plan(<OfficeMacroStep>[_value('C1', 'validation')]),
        );
        final recording = session.stopRecording();
        expect(recording.name, 'Direct calls');
        expect(recording.steps, hasLength(1));
        expect(recording.steps.single.arguments, <String, Object?>{
          'cell': 'A1',
          'value': 'captured',
        });
        expect(
          () => recording.steps.single.arguments['value'] = 'mutated',
          throwsUnsupportedError,
        );
        expect(session.revision, 2);
        final replay = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
        );
        await replay.run(OfficeMacro.parse(recording.encode()));
        expect(
          SheetDeserializer()
              .readBytes(replay.bytes)
              .sheets
              .single
              .cellA1('A1')
              .value,
          'captured',
        );
        expect(replay.revision, 1);
      },
    );

    test(
      'standalone recorder freezes nested values and escapes reference-looking objects',
      () {
        final recorder = OfficeMacroRecorder(
          name: 'Captured JSON',
          format: OfficeMacroFormat.docx,
        );
        final nested = <String, Object?>{'position': 3, 'alignment': 'center'};
        final tabs = <Object?>[nested];
        final literal = <String, Object?>{r'$parameter': 'literal name'};
        recorder.record('docx.paragraphFormat', <String, Object?>{
          'paragraph': 0,
          'tabs': tabs,
        });
        recorder.record('docx.styleDefinition', <String, Object?>{
          'style': 'Normal',
          'pPr': literal,
        });
        nested['position'] = 9;
        tabs.clear();
        literal[r'$parameter'] = 'changed';
        final snapshot = recorder.toMacro();
        final recordedTabs =
            snapshot.steps.first.arguments['tabs']! as List<Object?>;
        expect(recordedTabs, <Object?>[
          <String, Object?>{'position': 3, 'alignment': 'center'},
        ]);
        expect(() => recordedTabs.add(null), throwsUnsupportedError);
        expect(snapshot.steps.last.arguments['pPr'], <String, Object?>{
          r'$literal': <String, Object?>{r'$parameter': 'literal name'},
        });
        recorder.record('docx.heading', <String, Object?>{
          'paragraph': 0,
          'level': 1,
        });
        expect(snapshot.steps, hasLength(2));
        expect(recorder.toMacro().steps, hasLength(3));
      },
    );

    test(
      'recording capacity fails before a second call can mutate the document',
      () async {
        final session = OfficeMacroSession(
          _workbook(),
          format: OfficeMacroFormat.xlsx,
          policy: OfficeMacroPolicy(maxSteps: 1),
        );
        session.startRecording('Bounded');
        await session.callTool('xlsx.cellValue', <String, Object?>{
          'cell': 'A1',
          'value': 'first',
        });
        final before = session.bytes;
        await expectLater(
          session.callTool('xlsx.cellValue', <String, Object?>{
            'cell': 'A1',
            'value': 'second',
          }),
          throwsA(_error('limit_exceeded')),
        );
        expect(session.bytes, before);
        expect(session.revision, 1);
        expect(session.stopRecording().steps, hasLength(1));
      },
    );
  });
}
