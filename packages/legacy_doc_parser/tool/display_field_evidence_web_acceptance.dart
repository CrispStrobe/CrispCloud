// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/display_field_evidence_fixture.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

LegacyWordStructuredConversion verifyDisplayFieldEvidenceCase(
  String name, {
  required bool sourceRecord,
  required LegacyWordFieldMode mode,
}) {
  final model = displayFieldEvidenceDocument(name, sourceRecord: sourceRecord);
  final field = model.fields.singleWhere((f) => f.displayRevision != null);
  final change = field.displayRevision!;
  final originalRecord = change.sourceRecord?.toList();
  final converted = convertLegacyWordDocument(model, fieldMode: mode);
  final archive = ZipDecoder().decodeBytes(converted.bytes);
  final manifest = archive.findFile('word/evidence/manifest.json');
  _check(manifest != null, '$name: display history has no evidence manifest');
  final records =
      ((jsonDecode(utf8.decode(manifest!.content)) as Map)['records'] as List)
          .cast<Map>();
  final evidence = records
      .where(
        (record) =>
            const [
              'displayFieldRevision',
              'displayFieldRevisionRecord',
            ].contains(record['kind']) &&
            record['fieldId'] == field.id,
      )
      .toList();
  _check(evidence.length == 1, '$name: missing or duplicate display history');
  final record = evidence.single;
  final detail = record['displayRevision'];
  _check(detail is Map, '$name: original display revision metadata lost');
  final metadata = detail as Map;
  final revision = metadata['revision'];
  _check(revision is Map, '$name: revision provenance lost');
  final provenance = revision as Map;
  _check(
    metadata['original'] == change.original &&
        metadata['hidden'] == change.hidden &&
        provenance['author'] == change.revision.author &&
        provenance['time'] == change.revision.time?.toIso8601String() &&
        provenance['authorIndex'] == change.revision.authorIndex &&
        provenance['rawDate'] == change.revision.rawDate &&
        provenance['saveId'] == change.revision.saveId &&
        provenance['reason'] == change.revision.reason,
    '$name: display revision metadata changed',
  );
  _check(
    record['story'] == field.storyId && record['startCp'] == field.startCp,
    '$name: revision owner changed',
  );
  final native = displayFieldNativeHistoryExpected(name, mode);
  _check(
    record['nativeHistoryAvailable'] == native,
    '$name: wrong native history claim',
  );
  _check(
    converted.limitations.contains(LegacyWordConversionLimitation.revisions) ==
        (!native || name == 'sparse-metadata'),
    '$name: missing or invented revision limitation',
  );
  final xml = XmlDocument.parse(
    utf8.decode(archive.findFile('word/document.xml')!.content),
  );
  final originals = xml
      .findAllElements('numberingChange', namespace: _w)
      .map((element) => element.getAttribute('original', namespace: _w))
      .whereType<String>()
      .toList();
  _check(
    native
        ? originals.length == 1 && originals.single == change.original
        : originals.isEmpty,
    '$name: inactive original leaked into editable revision markup',
  );
  if (mode == LegacyWordFieldMode.cachedResults) {
    final cached = records.singleWhere(
      (r) => r['kind'] == 'cachedField' && r['id'] == field.id,
    );
    _check(
      jsonEncode(cached['displayRevision']) == jsonEncode(metadata),
      '$name: cached field omitted history',
    );
    _check(
      xml.findAllElements('fldChar', namespace: _w).isEmpty,
      '$name: cached field became active',
    );
  } else {
    for (final inert in records.where(
      (r) => r['kind'] == 'field' && r['startCp'] == field.startCp,
    )) {
      _check(
        jsonEncode(inert['displayRevision']) == jsonEncode(metadata),
        '$name: inert field omitted history',
      );
    }
  }
  if (sourceRecord) {
    final part = record['part'];
    _check(part is String, '$name: original binary record part missing');
    final bytes = archive.findFile(part as String)?.content;
    _check(
      bytes != null && jsonEncode(bytes) == jsonEncode(originalRecord),
      '$name: original record bytes changed',
    );
    _check(
      jsonEncode(change.sourceRecord) == jsonEncode(originalRecord),
      '$name: caller record mutated',
    );
  } else {
    _check(record['part'] == null, '$name: invented source record');
  }
  return converted;
}

Map<String, Object> verifyDisplayFieldEvidenceWebAcceptance() {
  var cases = 0, native = 0;
  for (final name in displayFieldEvidenceCases) {
    for (final sourceRecord in [false, true]) {
      for (final mode in LegacyWordFieldMode.values) {
        verifyDisplayFieldEvidenceCase(
          name,
          sourceRecord: sourceRecord,
          mode: mode,
        );
        cases++;
        if (displayFieldNativeHistoryExpected(name, mode)) native++;
      }
    }
  }
  for (final mode in LegacyWordFieldMode.values) {
    final output = convertLegacyWordDocument(
      displayFieldEvidenceDocument(
        'active',
        sourceRecord: false,
        includeRevision: false,
      ),
      fieldMode: mode,
    );
    _check(
      !output.limitations.contains(LegacyWordConversionLimitation.revisions),
      'absent revision invented a limitation',
    );
  }
  return {
    'cases': cases,
    'nativeHistoryCases': native,
    'inertHistoryCases': cases - native,
    'noHistoryControls': 2,
    'completeMetadata': true,
    'originalRecordsExact': true,
  };
}

void main() => print(jsonEncode(verifyDisplayFieldEvidenceWebAcceptance()));
