import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import 'web_vba_word_page_setup_smoke.dart' as fixture;

// Supply the complete committed BAS on both the VM and JavaScript hosts.
const _example = String.fromEnvironment('WORD_TEXT_COLUMNS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:word-text-columns-example';
const _first = 'ActiveDocument.Sections(1).PageSetup.TextColumns';
const _second = 'ActiveDocument.Sections(2).PageSetup.TextColumns';

OfficeMacro wordTextColumnsSource(String source) =>
    OfficeMacroLanguages().compile(
      OfficeMacroSource(
        language: 'vba-word',
        format: OfficeMacroFormat.docx,
        moduleName: 'WordTextColumnsExample',
        source: source,
      ),
    );

OfficeMacro wordTextColumnsPlan(String body) =>
    wordTextColumnsSource('Sub Main()\n$body\nEnd Sub');

/// An imported DOCM with an aliased native group, foreign same-name metadata,
/// and a third, untouched section with custom unequal columns.
Uint8List wordTextColumnsInput() {
  final package = OpcPackage.openBytes(fixture.wordPageSetupInput());
  final part = package.getPart('/word/document.xml')!;
  part.writeText(
    part
        .readText()
        .replaceFirst(
          '<w:cols w:num="2" w:space="360" w:sep="1"/>',
          '<c:cols xmlns:c="$_w" xmlns:w="$_extension" '
              'c:num="1" c:space="240" c:sep="0" '
              'w:num="foreign-count" w:space="foreign-gap" '
              'w:sep="foreign-separator">'
              '<w:columnMetadata w:token="preserve"/></c:cols>',
        )
        .replaceFirst(
          '<w:cols w:num="1" w:space="480"/>',
          '<w:cols w:num="2" w:space="480" w:equalWidth="0" '
              'x:token="untouched-columns">'
              '<w:col w:w="4000" w:space="480"/>'
              '<w:col w:w="7220"/></w:cols>',
        ),
  );
  return package.save();
}

XmlElement wordTextColumnsElement(Uint8List bytes, int section) => fixture
    .wordPageSetupSection(bytes, section)
    .firstChild('cols', namespaceUri: _w)!;

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// The expected outcome is authored independently of the compiler and native
/// dispatch: two uniform columns at 18pt, three at 18pt, and no other changes.
void assertWordTextColumnsExample(Uint8List bytes) {
  final original = fixture.wordPageSetupState(wordTextColumnsInput());
  final expected = <Map<String, Object?>>[
    {...original[0], 'columnCount': 2, 'columnSpace': 18, 'columnSep': true},
    {...original[1], 'columnCount': 3, 'columnSpace': 18, 'columnSep': false},
    original[2],
  ];
  final actual = fixture.wordPageSetupState(bytes);
  _check(
    jsonEncode(actual) == jsonEncode(expected),
    'TextColumns changed the wrong section, page geometry, or text: $actual',
  );
  final first = wordTextColumnsElement(bytes, 0);
  final second = wordTextColumnsElement(bytes, 1);
  final third = wordTextColumnsElement(bytes, 2);
  _check(
    first.getAttribute('num', namespaceUri: _w) == '2' &&
        first.getAttribute('space', namespaceUri: _w) == '360' &&
        first.getAttribute('sep', namespaceUri: _w) == '1' &&
        first.getAttribute('num', namespaceUri: _extension) ==
            'foreign-count' &&
        first.getAttribute('space', namespaceUri: _extension) ==
            'foreign-gap' &&
        first.getAttribute('sep', namespaceUri: _extension) ==
            'foreign-separator' &&
        first
                .firstChild('columnMetadata', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'preserve' &&
        second.getAttribute('num', namespaceUri: _w) == '3' &&
        second.getAttribute('space', namespaceUri: _w) == '360' &&
        second.getAttribute('sep', namespaceUri: _w) == '0' &&
        third.getAttribute('equalWidth', namespaceUri: _w) == '0' &&
        third.getAttribute(
              'token',
              namespaceUri: 'urn:word-page-setup-example',
            ) ==
            'untouched-columns' &&
        third
                .childrenNamed('col', namespaceUri: _w)
                .map((column) => column.getAttribute('w', namespaceUri: _w))
                .join(',') ==
            '4000,7220',
    'TextColumns damaged native, foreign, or untouched custom-column XML',
  );
  final section = fixture.wordPageSetupSection(bytes, 0);
  _check(
    section
                .firstChild('pgNumType', namespaceUri: _w)!
                .getAttribute('start', namespaceUri: _w) ==
            '7' &&
        section
                .firstChild('pgSz', namespaceUri: _w)!
                .getAttribute('code', namespaceUri: _w) ==
            '9' &&
        section
                .firstChild(
                  'sectionTag',
                  namespaceUri: 'urn:word-page-setup-example',
                )!
                .getAttribute(
                  'token',
                  namespaceUri: 'urn:word-page-setup-example',
                ) ==
            'preserve-first',
    'TextColumns changed unrelated section metadata',
  );
  fixture.assertWordPageSetupPackage(bytes);
}

Future<Map<String, Object?>> runWordTextColumnsExample(String source) async {
  final input = wordTextColumnsInput();
  final before = base64Encode(input);
  final plan = wordTextColumnsSource(source);
  const expected = <Map<String, Object?>>[
    {'section': 0, 'count': 2},
    {'section': 0, 'spacing': 18},
    {'section': 0, 'lineBetween': true},
    {'section': 1, 'count': 3},
    {'section': 1, 'spacing': 18},
    {'section': 1, 'lineBetween': false},
  ];
  _check(plan.steps.length == expected.length, 'Wrong example step count');
  for (var index = 0; index < expected.length; index++) {
    final step = plan.steps[index];
    final arguments = expected[index];
    _check(
      step.tool == 'docx.textColumns' &&
          step.arguments.length == arguments.length &&
          arguments.entries.every(
            (entry) => step.arguments[entry.key] == entry.value,
          ),
      'TextColumns example step $index differs from its contract',
    );
  }
  final guard = (await WordPackagePreservation.capture(input, 'columns.docm'))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == expected.length &&
        session.revision == 0 &&
        base64Encode(session.bytes) == before,
    'TextColumns validation published an edit',
  );
  final run = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    !run.validatedOnly &&
        run.completedSteps == expected.length &&
        run.revision == 1 &&
        base64Encode(input) == before,
    'TextColumns did not publish exactly one detached transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordTextColumnsExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordTextColumnsExample(session.bytes);
  await guard.validateSaved(session.bytes);
  _check(session.revision == 2, 'Repeating TextColumns lost its transaction');
  return {
    'operations': expected.length,
    'firstRunRevision': run.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
    'sections': fixture.wordPageSetupState(saved),
  };
}

Future<Map<String, Object?>> runWordTextColumnsRollback() async {
  final input = wordTextColumnsInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Columns rollback');
  final plan = wordTextColumnsPlan('''
$_first.SetCount 2
ActiveDocument.Sections(99).PageSetup.TextColumns.LineBetween = True
''');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Missing section unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      _check(
        error.code == 'operation_failed' &&
            error.stepIndex == 1 &&
            error.tool == 'docx.textColumns',
        'TextColumns failure lost its native operation attribution',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed TextColumns playback published a prefix edit',
    );
  }
  _check(session.stopRecording().steps.isEmpty, 'Failed playback was recorded');
  return {'failedStep': 1, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordTextColumnsRecording() async {
  final input = wordTextColumnsInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Uniform text columns');
  await session.callTool('docx.textColumns', {'section': 0, 'count': 2});
  await session.callTool('docx.textColumns', {'section': 0, 'spacing': 18});
  await session.callTool('docx.textColumns', {
    'section': 1,
    'lineBetween': true,
  });
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.callTool('docx.textColumns', {'section': 99, 'count': 2});
    throw StateError('Missing section unexpectedly succeeded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recording = session.stopRecording();
  _check(
    recording.steps.length == 3 &&
        recording.steps.every((step) => step.tool == 'docx.textColumns') &&
        recording.steps.map((step) => step.arguments['section']).join(',') ==
            '0,0,1' &&
        session.revision == 3 &&
        base64Encode(session.bytes) == beforeFailure,
    'Recording retained a failed call or changed its section selectors',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  final expected = fixture.wordPageSetupState(input);
  expected[0] = {...expected[0], 'columnCount': 2, 'columnSpace': 18};
  expected[1] = {...expected[1], 'columnSep': true};
  _check(
    replay.revision == 1 &&
        jsonEncode(fixture.wordPageSetupState(replay.bytes)) ==
            jsonEncode(expected) &&
        jsonEncode(fixture.wordPageSetupState(session.bytes)) ==
            jsonEncode(expected),
    'Recorded TextColumns changed meaning on replay',
  );
  fixture.assertWordPageSetupPackage(replay.bytes);
  return {'recordedSteps': 3, 'failedCallExcluded': true, 'replayRevision': 1};
}

Future<Map<String, Object?>> runWordTextColumnsPolicy() async {
  final input = wordTextColumnsInput();
  final plan = wordTextColumnsPlan('''
$_first.SetCount 2
$_first.Spacing = 18
$_second.LineBetween = True
''');
  var denied = 0;
  for (final (policy, code) in <(OfficeMacroPolicy, String)>[
    (OfficeMacroPolicy(allowMutation: false), 'permission_denied'),
    (OfficeMacroPolicy(allowedTools: {'docx.pageSetup'}), 'permission_denied'),
    (OfficeMacroPolicy(maxSteps: 2), 'limit_exceeded'),
  ]) {
    final session = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: policy,
    );
    for (final action in [session.validate, session.run]) {
      try {
        await action(plan);
        throw StateError('Restricted TextColumns unexpectedly succeeded');
      } on OfficeMacroException catch (error) {
        _check(error.code == code, 'Wrong TextColumns policy failure');
      }
      _check(
        session.revision == 0 &&
            base64Encode(session.bytes) == base64Encode(input),
        'Policy rejection published part of a TextColumns plan',
      );
      denied++;
    }
  }
  final allowed = OfficeMacroSession(
    input,
    format: OfficeMacroFormat.docx,
    policy: OfficeMacroPolicy(allowedTools: {'docx.textColumns'}, maxSteps: 3),
  );
  final result = await allowed.run(plan);
  _check(
    result.completedSteps == 3 && allowed.revision == 1,
    'An explicitly allowed TextColumns plan did not run',
  );
  return {'atomicDenials': denied, 'allowedSteps': result.completedSteps};
}

Future<void> main() async {
  _check(
    _example.isNotEmpty,
    'Supply the committed BAS in WORD_TEXT_COLUMNS_BAS_BASE64',
  );
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordTextColumnsExample(source),
      'rollback': await runWordTextColumnsRollback(),
      'recording': await runWordTextColumnsRecording(),
      'policy': await runWordTextColumnsPolicy(),
    }),
  );
}
