// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';
import '../test/support/field_marker_formatting_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
bool _same(List<(int, int)> a, List<(int, int)> b) =>
    a.length == b.length &&
    List.generate(a.length, (i) => a[i] == b[i]).every((value) => value);

void verifyFieldInstructionVisibilityCase(
  FieldInstructionFormattingCase fixture,
) {
  void check(bool condition, String message) {
    if (!condition) throw StateError('${fixture.name}: $message');
  }

  final source = fixture.bytes(), before = fixture.bytes();
  final model = parseLegacyWordDocument(source);
  for (final field in model.fields) {
    check(
      _same(
        field.instructionHiddenRanges,
        fixture.expectedRangesByStart[field.startCp]!,
      ),
      'captured source ranges at ${field.startCp}',
    );
  }
  if (fixture.scalarFormattingSplit) {
    check(
      model.warnings.contains(LegacyWordWarning.unsupportedFormatting),
      'split scalar style warning',
    );
  }
  final result = convertLegacyWordDocument(model);
  final xml = XmlDocument.parse(
    utf8.decode(
      ZipDecoder()
          .decodeBytes(result.bytes)
          .findFile('word/document.xml')!
          .content,
    ),
  );
  final fields = model.fields.toList()
    ..sort((a, b) => a.startCp.compareTo(b.startCp));
  final stack = <(LegacyWordField, bool)>[];
  final offsets = <int, int>{};
  var next = 0;
  for (final run in xml.findAllElements('r', namespace: _w)) {
    final marker = run
        .getElement('fldChar', namespace: _w)
        ?.getAttribute('fldCharType', namespace: _w);
    if (marker == 'begin') {
      final field = fields[next++];
      if (stack.isNotEmpty && !stack.last.$2) {
        final parent = stack.last.$1;
        offsets[parent.id] = field.endCp - parent.startCp - 1;
      }
      offsets[field.id] = 0;
      stack.add((field, false));
    } else if (marker == 'separate') {
      stack[stack.length - 1] = (stack.last.$1, true);
    } else if (marker == 'end') {
      final field = stack.removeLast().$1;
      check(
        offsets[field.id] == field.instruction.length,
        'complete instruction',
      );
    }
    final instruction = run.getElement('instrText', namespace: _w);
    if (instruction == null) continue;
    final field = stack.last.$1, start = offsets[stack.last.$1.id]!;
    final text = instruction.innerText;
    check(
      field.instruction.substring(start, start + text.length) == text,
      'exact instruction bytes',
    );
    final contextHidden = stack
        .take(stack.length - 1)
        .any((entry) => !entry.$2);
    final actualHidden = run
        .getElement('rPr', namespace: _w)
        ?.getElement('vanish', namespace: _w)
        ?.getAttribute('val', namespace: _w);
    for (var offset = start; offset < start + text.length; offset++) {
      final sourceHidden = field.instructionHiddenRanges.any(
        (range) => offset >= range.$1 && offset < range.$2,
      );
      check(
        actualHidden == (contextHidden || sourceHidden ? '1' : '0'),
        'literal visibility at $offset',
      );
    }
    offsets[field.id] = start + text.length;
  }
  check(stack.isEmpty && next == fields.length, 'all fields balanced');
  check(
    result.preservedCounts['fields'] == fields.length,
    'active fields retained',
  );
  check(
    source.length == before.length &&
        List.generate(
          source.length,
          (i) => source[i] == before[i],
        ).every((v) => v),
    'source unchanged',
  );
}

LegacyWordField _withVisibility(
  LegacyWordField field,
  List<(int, int)> ranges,
) => LegacyWordField(
  id: field.id,
  storyId: field.storyId,
  startCp: field.startCp,
  endCp: field.endCp,
  separatorCp: field.separatorCp,
  parentId: field.parentId,
  instruction: field.instruction,
  storedResult: field.storedResult,
  type: field.type,
  locked: field.locked,
  dirty: field.dirty,
  privateResult: field.privateResult,
  beginHidden: field.beginHidden,
  separatorHidden: field.separatorHidden,
  endHidden: field.endHidden,
  instructionVisibility: LegacyWordFieldInstructionVisibility(ranges),
  displayRevision: field.displayRevision,
);

int verifyPublicFieldInstructionVisibility() {
  var rejections = 0;
  void reject(LegacyWordDocument source, List<LegacyWordField> fields) {
    final model = LegacyWordDocument(
      blocks: source.blocks,
      sections: source.sections,
      plainText: source.plainText,
      safeHtml: source.safeHtml,
      fields: fields,
    );
    for (final mode in LegacyWordFieldMode.values) {
      try {
        convertLegacyWordDocument(model, fieldMode: mode);
      } on FormatException {
        rejections++;
        continue;
      }
      throw StateError(
        'Invalid instruction range was accepted in ${mode.name}',
      );
    }
  }

  final cases = fieldInstructionFormattingCases();
  final model = parseLegacyWordDocument(cases.first.bytes());
  final field = model.fields.single;
  for (final ranges in <List<(int, int)>>[
    [(-1, 1)],
    [(0, 0)],
    [(2, 1)],
    [(0, field.instruction.length + 1)],
    [(0, 4), (2, 5)],
    [(4, 5), (1, 2)],
  ]) {
    reject(model, [_withVisibility(field, ranges)]);
  }
  final scalar = parseLegacyWordDocument(cases[4].bytes());
  final emoji = scalar.fields.single.instruction.indexOf('😀');
  reject(scalar, [
    _withVisibility(scalar.fields.single, [(emoji + 1, emoji + 2)]),
  ]);
  reject(scalar, [
    _withVisibility(scalar.fields.single, [(emoji, emoji + 1)]),
  ]);
  final nested = parseLegacyWordDocument(cases[2].bytes());
  final parent = nested.fields.singleWhere((f) => f.parentId == null);
  reject(nested, [
    for (final f in nested.fields)
      f.id == parent.id ? _withVisibility(f, [(0, f.instruction.length)]) : f,
  ]);
  final raw = [(1, 2)];
  final copied = LegacyWordFieldInstructionVisibility(raw);
  raw[0] = (3, 4);
  if (copied.hiddenRanges.single != (1, 2)) {
    throw StateError('Visibility retains mutable source');
  }
  try {
    copied.hiddenRanges.add((5, 6));
    throw StateError('Visibility is mutable');
  } on UnsupportedError {
    /* Read-only snapshot verified. */
  }
  try {
    LegacyWordFieldInstructionVisibility(List.filled(200001, (0, 1)));
  } on FormatException {
    rejections++;
  }
  if (rejections != 19) {
    throw StateError('Visibility allocation bound was not enforced');
  }
  final instruction = ' QUOTE "${List.filled(100001, 'x ').join()}" ';
  final visibility = LegacyWordFieldInstructionVisibility([
    for (var i = 0; i < 100001; i++) (8 + i * 2, 9 + i * 2),
  ]);
  final span = instruction.length + 2;
  final aggregate = LegacyWordDocument(
    blocks: [
      LegacyWordParagraph(startCp: 0, endCp: span * 2 + 1, runs: const []),
    ],
    sections: const [],
    plainText: '',
    safeHtml: '',
    fields: [
      for (var i = 0; i < 2; i++)
        LegacyWordField(
          id: i,
          storyId: 'main',
          startCp: span * i,
          endCp: span * (i + 1),
          instruction: instruction,
          storedResult: '',
          type: 'QUOTE',
          instructionVisibility: visibility,
        ),
    ],
  );
  for (final mode in LegacyWordFieldMode.values) {
    try {
      convertLegacyWordDocument(aggregate, fieldMode: mode);
    } on LegacyWordConversionException catch (error) {
      if (error.issue != LegacyWordConversionIssue.tooComplex) rethrow;
      rejections++;
      continue;
    }
    throw StateError('Aggregate visibility budget was not enforced');
  }
  return rejections;
}

Map<String, Object> verifyFieldInstructionVisibilityWebAcceptance() {
  final cases = fieldInstructionFormattingCases();
  for (final fixture in cases) {
    verifyFieldInstructionVisibilityCase(fixture);
  }
  return {
    'sourceCases': cases.length,
    'publicRejections': verifyPublicFieldInstructionVisibility(),
    'immutableRanges': true,
    'sourceUnchanged': true,
    'cachedResultsEvaluated': false,
  };
}

void main() =>
    print(jsonEncode(verifyFieldInstructionVisibilityWebAcceptance()));
