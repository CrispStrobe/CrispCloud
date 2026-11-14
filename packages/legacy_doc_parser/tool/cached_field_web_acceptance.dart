// SPDX-License-Identifier: MPL-2.0
// Stored-result output is checked against authored fixtures and every original
// field identity, not against text reconstructed from the converted package.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/field_visibility_fixture.dart';
import '../test/support/generated_field_tree_fixture.dart';
import 'public_field_web_acceptance.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool value, String message) {
  if (!value) throw StateError(message);
}

LegacyWordStructuredConversion verifyCachedFieldSource(
  Uint8List source,
  String expected, {
  LegacyWordOutputFormat format = LegacyWordOutputFormat.docx,
}) {
  final before = source.toList();
  final model = parseLegacyWordDocument(source);
  final converted = convertLegacyWordDocument(
    model,
    format: format,
    fieldMode: LegacyWordFieldMode.cachedResults,
  );
  _check(
    converted.fieldMode == LegacyWordFieldMode.cachedResults,
    'mode missing',
  );
  _check(converted.format == format, 'output format changed');
  _check(
    converted.preservedCounts['cachedResultFields'] == model.fields.length &&
        (converted.preservedCounts['fields'] ?? 0) == 0,
    'cached fields counted as editable fields',
  );
  _check(
    converted.limitations.contains(LegacyWordConversionLimitation.fieldsLists),
    'field editing limitation missing',
  );
  final zip = ZipDecoder().decodeBytes(converted.bytes);
  final document = XmlDocument.parse(
    utf8.decode(zip.findFile('word/document.xml')!.content),
  );
  for (final part in zip) {
    if (!part.name.startsWith('word/') || !part.name.endsWith('.xml')) continue;
    final xml = XmlDocument.parse(utf8.decode(part.content));
    for (final name in ['fldChar', 'fldSimple', 'instrText']) {
      _check(
        xml.findAllElements(name, namespace: _w).isEmpty,
        'active $name escaped',
      );
    }
  }
  final visible = StringBuffer();
  for (final run in document.findAllElements('r', namespace: _w)) {
    final vanish = run
        .getElement('rPr', namespace: _w)
        ?.getElement('vanish', namespace: _w);
    if (vanish != null &&
        !const [
          '0',
          'false',
          'off',
        ].contains(vanish.getAttribute('val', namespace: _w))) {
      continue;
    }
    for (final element in run.childElements) {
      if (element.name.namespaceUri != _w) continue;
      switch (element.name.local) {
        case 't':
          visible.write(element.innerText);
        case 'tab':
          visible.write('\t');
        case 'br':
          visible.write(switch (element.getAttribute('type', namespace: _w)) {
            'page' => '\f',
            'column' => '\x0e',
            _ => '\n',
          });
      }
    }
  }
  _check(visible.toString() == expected, 'cached result display changed');
  final evidence =
      jsonDecode(
            utf8.decode(zip.findFile('word/evidence/manifest.json')!.content),
          )
          as Map;
  final records = (evidence['records'] as List)
      .cast<Map>()
      .where((r) => r['kind'] == 'cachedField')
      .toList();
  _check(records.length == model.fields.length, 'cached field evidence count');
  for (final field in model.fields) {
    final sameId = records.where((r) => r['id'] == field.id).toList();
    _check(sameId.length == 1, 'duplicate or missing cached field identity');
    final record = sameId.single;
    _check(
      record['parentId'] == field.parentId &&
          record['story'] == field.storyId &&
          record['startCp'] == field.startCp &&
          record['separatorCp'] == field.separatorCp &&
          record['endCp'] == field.endCp &&
          record['type'] == field.type &&
          record['instruction'] == field.instruction &&
          record['storedResult'] == field.storedResult &&
          record['privateResult'] == field.privateResult &&
          record['locked'] == field.locked &&
          record['dirty'] == field.dirty &&
          record['beginHidden'] == field.beginHidden &&
          record['separatorHidden'] == field.separatorHidden &&
          record['endHidden'] == field.endHidden &&
          jsonEncode(record['instructionHiddenRanges']) ==
              jsonEncode([
                for (final (start, end) in field.instructionHiddenRanges)
                  [start, end],
              ]) &&
          record['automaticRecalculation'] == false,
      'cached field metadata changed',
    );
  }
  _check(source.length == before.length, 'source resized');
  for (var i = 0; i < source.length; i++) {
    _check(source[i] == before[i], 'source changed');
  }
  return converted;
}

Map<String, Object?> verifyCachedFieldWebAcceptance() {
  var generated = 0, fields = 0;
  for (final name in fieldVisibilityCases) {
    verifyCachedFieldSource(
      fieldVisibilityFixture(name),
      fieldVisibilityExpectedText[name]!,
    );
  }
  for (var seed = 1; seed <= 96; seed++) {
    final fixture = GeneratedFieldTreeCase(seed);
    final single = verifyCachedFieldSource(fixture.bytes(), fixture.expected);
    final split = verifyCachedFieldSource(
      fixture.bytes(splitPieces: true),
      fixture.expected,
    );
    _check(
      single.bytes.length == split.bytes.length,
      'piece layout changed package size',
    );
    for (var i = 0; i < single.bytes.length; i++) {
      _check(
        single.bytes[i] == split.bytes[i],
        'piece layout changed cached package',
      );
    }
    generated++;
    fields += fixture.fields.length;
  }
  verifyCachedFieldSource(
    fieldVisibilityFixture('formula'),
    'A999Z',
    format: LegacyWordOutputFormat.docm,
  );
  final malformed = verifyPublicFieldWebAcceptance(
    fieldMode: LegacyWordFieldMode.cachedResults,
  );
  return {
    'fixtures': fieldVisibilityCases.length,
    'generatedCases': generated,
    'generatedLayouts': generated * 2,
    'fieldsPerLayout': fields,
    'docmControl': true,
    'malformedOwnershipRejected':
        (malformed['malformedRangesRejected'] as List).length,
    'activeFields': 0,
    'sourceUnchanged': true,
    'fieldEvidenceExact': true,
  };
}
