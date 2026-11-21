import 'dart:convert';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;

import 'web_vba_word_page_setup_smoke.dart' as fixture;

// Both hosts receive the complete, committed BAS rather than an inline copy.
const _example = String.fromEnvironment('WORD_SECTIONS_BAS_BASE64');
const _w = OfficeNamespaces.w;
const _extension = 'urn:word-page-setup-example';

OfficeMacro wordSectionsSource(String source) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'WordSectionsExample',
    source: source,
  ),
);

OfficeMacro wordSectionsPlan(String body) =>
    wordSectionsSource('Sub Main()\n$body\nEnd Sub');

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

/// Assert independently authored dimensions, break kinds, and retained data.
void assertWordSectionsExample(Uint8List bytes) {
  final original = fixture.wordPageSetupState(fixture.wordPageSetupInput());
  final expected = <Map<String, Object?>>[
    {...original[0], 'width': 792, 'height': 612, 'break': 'nextPage'},
    {
      ...original[1],
      'width': 800,
      'height': 600,
      'left': 54,
      'break': 'evenPage',
    },
    original[2],
  ];
  final actual = fixture.wordPageSetupState(bytes);
  _check(
    jsonEncode(actual) == jsonEncode(expected),
    'Wrong section geometry, margins, text, or break kind: $actual',
  );
  final first = fixture.wordPageSetupSection(bytes, 0);
  final second = fixture.wordPageSetupSection(bytes, 1);
  final third = fixture.wordPageSetupSection(bytes, 2);
  final firstSize = first.firstChild('pgSz', namespaceUri: _w)!;
  final secondSize = second.firstChild('pgSz', namespaceUri: _w)!;
  final firstMargins = first.firstChild('pgMar', namespaceUri: _w)!;
  _check(
    firstSize.getAttribute('w', namespaceUri: _w) == '15840' &&
        firstSize.getAttribute('h', namespaceUri: _w) == '12240' &&
        firstSize.getAttribute('orient', namespaceUri: _w) == 'landscape' &&
        firstSize.getAttribute('code', namespaceUri: _w) == '9' &&
        firstSize.getAttribute('w', namespaceUri: _extension) ==
            'foreign-width' &&
        firstSize
                .firstChild('paper', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'paper' &&
        firstMargins.getAttribute('gutter', namespaceUri: _w) == '0' &&
        firstMargins.getAttribute('left', namespaceUri: _extension) ==
            'foreign-left' &&
        first
                .firstChild('type', namespaceUri: _w)!
                .getAttribute('val', namespaceUri: _w) ==
            'nextPage' &&
        first
                .firstChild('pgNumType', namespaceUri: _w)!
                .getAttribute('start', namespaceUri: _w) ==
            '7' &&
        first
                .firstChild('sectionTag', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'preserve-first' &&
        secondSize.getAttribute('w', namespaceUri: _w) == '16000' &&
        secondSize.getAttribute('h', namespaceUri: _w) == '12000' &&
        secondSize.getAttribute('orient', namespaceUri: _w) == 'landscape' &&
        secondSize.getAttribute('code', namespaceUri: _w) == '5' &&
        second
                .firstChild('type', namespaceUri: _w)!
                .getAttribute('val', namespaceUri: _w) ==
            'evenPage' &&
        third
                .firstChild('pgSz', namespaceUri: _w)!
                .getAttribute('code', namespaceUri: _w) ==
            '3' &&
        third
                .firstChild('sectionTag', namespaceUri: _extension)!
                .getAttribute('token', namespaceUri: _extension) ==
            'untouched',
    'Section writes damaged native or extension metadata',
  );
  fixture.assertWordPageSetupPackage(bytes);
}

Future<Map<String, Object?>> runWordSectionsExample(String source) async {
  final input = fixture.wordPageSetupInput();
  final original = base64Encode(input);
  final plan = wordSectionsSource(source);
  // These expected operations are the BAS contract, not compiler dispatch data.
  const expected = <(String, Map<String, Object?>)>[
    ('docx.pageOrientation', {'section': 0, 'orientation': 'landscape'}),
    ('docx.sectionStart', {'section': 0, 'kind': 'nextPage'}),
    ('docx.sectionStart', {'section': 1, 'kind': 'evenPage'}),
    ('docx.pageOrientation', {'section': 1, 'orientation': 'landscape'}),
    ('docx.pageOrientation', {'section': 1, 'orientation': 'toggle'}),
    ('docx.pageOrientation', {'section': 1, 'orientation': 'toggle'}),
    ('docx.pageSetup', {'section': 1, 'property': 'left', 'points': 54}),
  ];
  _check(plan.steps.length == expected.length, 'Wrong example operation count');
  for (var i = 0; i < expected.length; i++) {
    final (tool, arguments) = expected[i];
    final step = plan.steps[i];
    _check(
      step.tool == tool &&
          step.arguments.length == arguments.length &&
          arguments.entries.every(
            (entry) => step.arguments[entry.key] == entry.value,
          ),
      'Section example step $i differs from its declared operation',
    );
  }
  final guard = (await WordPackagePreservation.capture(
    input,
    'sections.docm',
  ))!;
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  final validation = await session.validate(plan);
  _check(
    validation.validatedOnly &&
        validation.completedSteps == expected.length &&
        session.revision == 0 &&
        base64Encode(session.bytes) == original,
    'Section dry-run published an edit',
  );
  final result = await session.run(OfficeMacro.parse(plan.encode()));
  _check(
    result.completedSteps == expected.length &&
        result.revision == 1 &&
        !result.validatedOnly &&
        base64Encode(input) == original,
    'Section example did not publish exactly one detached transaction',
  );
  var saved = session.bytes;
  for (var cycle = 0; cycle < 3; cycle++) {
    assertWordSectionsExample(saved);
    await guard.validateSaved(saved);
    if (cycle < 2) {
      saved = WordSerializer().writeBytes(WordDeserializer().readBytes(saved));
    }
  }
  await session.run(plan);
  assertWordSectionsExample(session.bytes);
  _check(
    session.revision == 2,
    'Repeating section example lost its transaction',
  );
  await guard.validateSaved(session.bytes);
  return {
    'operations': expected.length,
    'firstRunRevision': result.revision,
    'repeatedRevision': session.revision,
    'additionalReopens': 2,
    'opaquePayloadsPreserved': true,
    'sections': fixture.wordPageSetupState(saved),
  };
}

Future<Map<String, Object?>> runWordSectionsRollback() async {
  final input = fixture.wordPageSetupInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Section rollback');
  final plan = wordSectionsPlan('''
ActiveDocument.Sections(1).PageSetup.SectionStart = wdSectionOddPage
ActiveDocument.Sections(99).PageSetup.TogglePortrait
''');
  for (final action in [session.validate, session.run]) {
    try {
      await action(plan);
      throw StateError('Missing section unexpectedly succeeded');
    } on OfficeMacroException catch (error) {
      _check(
        error.code == 'operation_failed' &&
            error.stepIndex == 1 &&
            error.tool == 'docx.pageOrientation',
        'Section failure was not attributed to its native operation',
      );
    }
    _check(
      session.revision == 0 &&
          base64Encode(session.bytes) == base64Encode(input),
      'Failed section operation published a prefix edit',
    );
  }
  _check(session.stopRecording().steps.isEmpty, 'Failed playback was recorded');
  return {'failedStep': 1, 'validateAndRunRollback': true};
}

Future<Map<String, Object?>> runWordSectionsRecording() async {
  final input = fixture.wordPageSetupInput();
  final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  session.startRecording('Section orientations and breaks');
  await session.callTool('docx.pageOrientation', {
    'section': 0,
    'orientation': 'landscape',
  });
  await session.callTool('docx.sectionStart', {
    'section': 1,
    'kind': 'oddPage',
  });
  final beforeFailure = base64Encode(session.bytes);
  try {
    await session.callTool('docx.sectionStart', {
      'section': 99,
      'kind': 'nextPage',
    });
    throw StateError('Missing section unexpectedly succeeded');
  } on OfficeMacroException catch (error) {
    if (error.code != 'operation_failed') rethrow;
  }
  final recording = session.stopRecording();
  _check(
    recording.steps.length == 2 &&
        recording.steps[0].tool == 'docx.pageOrientation' &&
        recording.steps[0].arguments['section'] == 0 &&
        recording.steps[1].tool == 'docx.sectionStart' &&
        recording.steps[1].arguments['section'] == 1 &&
        session.revision == 2 &&
        base64Encode(session.bytes) == beforeFailure,
    'Recording changed selectors or retained a failed native call',
  );
  final replay = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
  await replay.run(OfficeMacro.parse(recording.encode()));
  final expected = fixture.wordPageSetupState(input);
  expected[0] = {...expected[0], 'width': 792, 'height': 612};
  expected[1] = {...expected[1], 'break': 'oddPage'};
  _check(
    replay.revision == 1 &&
        jsonEncode(fixture.wordPageSetupState(replay.bytes)) ==
            jsonEncode(expected) &&
        jsonEncode(fixture.wordPageSetupState(session.bytes)) ==
            jsonEncode(expected),
    'Recorded section edits changed meaning on replay',
  );
  fixture.assertWordPageSetupPackage(replay.bytes);
  return {'recordedSteps': 2, 'failedCallExcluded': true, 'replayRevision': 1};
}

Future<Map<String, Object?>> runWordSectionsPolicy() async {
  final input = fixture.wordPageSetupInput();
  final plan = wordSectionsPlan('''
ActiveDocument.Sections(1).PageSetup.Orientation = wdOrientLandscape
ActiveDocument.Sections(2).PageSetup.SectionStart = wdSectionEvenPage
''');
  for (final tools in [
    {'docx.pageOrientation'},
    {'docx.sectionStart'},
  ]) {
    final session = OfficeMacroSession(
      input,
      format: OfficeMacroFormat.docx,
      policy: OfficeMacroPolicy(allowedTools: tools),
    );
    for (final action in [session.validate, session.run]) {
      try {
        await action(plan);
        throw StateError('A missing tool permission unexpectedly succeeded');
      } on OfficeMacroException catch (error) {
        _check(error.code == 'permission_denied', 'Wrong permission failure');
      }
      _check(
        session.revision == 0 &&
            base64Encode(session.bytes) == base64Encode(input),
        'Permission denial published a partial section edit',
      );
    }
  }
  return {'bothNativeAllowlistsEnforced': true, 'denialsPublishNothing': true};
}

/// Exercise authored fractional geometry before serialization can round it.
Map<String, Object?> runWordSectionsPrecision() {
  num number(double value) =>
      value == value.truncateToDouble() ? value.toInt() : value;
  void orient(WmlDocument document, String value) => native.applyStep(
    document,
    {'op': 'pageOrientation', 'section': 0, 'orientation': value},
  );
  final receipts = <Map<String, Object?>>[];
  for (final (name, dimensions, orientation, width, height)
      in <(String, WmlPageSize?, String, double, double)>[
        ('authored A4 default', null, 'landscape', 841.9, 595.3),
        (
          'fractional dimensions become square',
          const WmlPageSize(width: 600.01, height: 600.02),
          'landscape',
          600,
          600,
        ),
        (
          'near-square exact landscape',
          const WmlPageSize(width: 600.05, height: 600),
          'portrait',
          600,
          600.05,
        ),
      ]) {
    var document = WmlDocument.empty(text: 'Native precision');
    if (dimensions != null) document.sections.single.pageSize = dimensions;
    final margins = document.sections.single.margins;
    orient(document, orientation);
    _check(
      identical(document.sections.single.margins, margins),
      '$name changed the named margins',
    );
    for (var cycle = 0; cycle < 3; cycle++) {
      final section = document.sections.single;
      final size = XmlDocument.parse(
        section.sourceProperties!.xml,
      ).root!.firstChild('pgSz', namespaceUri: _w)!;
      _check(
        section.pageSize.width == width &&
            section.pageSize.height == height &&
            size.getAttribute('orient', namespaceUri: _w) == orientation,
        '$name lost normalized dimensions or explicit orientation',
      );
      orient(document, 'toggle');
      orient(document, 'toggle');
      document = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
    }
    _check(
      document.sections.single.pageSize.width == width &&
          document.sections.single.pageSize.height == height,
      '$name changed after the final reopen',
    );
    receipts.add({
      'case': name,
      'width': number(width),
      'height': number(height),
      'orientation': orientation,
      'roundTrips': 3,
    });
  }
  for (final dimensionRounding in [true, false]) {
    final document = WmlDocument.empty(text: 'Atomic precision failure');
    final section = document.sections.single;
    section
      ..pageSize = WmlPageSize(
        width: dimensionRounding ? 600.01 : 600,
        height: 800,
      )
      ..margins = WmlPageMargins(
        left: dimensionRounding ? 300 : 299.98,
        right: dimensionRounding ? 300 : 299.98,
      );
    final size = section.pageSize;
    final margins = section.margins;
    final source = section.sourceProperties;
    try {
      orient(document, 'portrait');
      throw StateError('Rounded geometry unexpectedly erased the page body');
    } on ArgumentError {
      _check(
        identical(section.pageSize, size) &&
            identical(section.margins, margins) &&
            identical(section.sourceProperties, source) &&
            document.paragraphs.single.text == 'Atomic precision failure',
        'Rejected rounded geometry partially changed the native model',
      );
    }
  }
  return {'cases': receipts, 'atomicRoundedBodyFailures': 2};
}

Future<void> main() async {
  _check(
    _example.isNotEmpty,
    'Supply the exact BAS in WORD_SECTIONS_BAS_BASE64',
  );
  final source = utf8.decode(base64Decode(_example));
  print(
    jsonEncode({
      'example': await runWordSectionsExample(source),
      'rollback': await runWordSectionsRollback(),
      'recording': await runWordSectionsRecording(),
      'policy': await runWordSectionsPolicy(),
      'nativePrecision': runWordSectionsPrecision(),
    }),
  );
}
