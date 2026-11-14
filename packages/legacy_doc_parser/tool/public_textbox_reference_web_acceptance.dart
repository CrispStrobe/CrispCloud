// SPDX-License-Identifier: MPL-2.0

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/public_textbox_reference_fixture.dart';

const publicTextboxHiddenValidCases = ['single', 'chain'];
const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _v = 'urn:schemas-microsoft-com:vml';

Map<String, Object> verifyPublicTextboxReferenceWebAcceptance() {
  var visible = 0, auxiliary = 0, inert = 0, rejected = 0;
  for (final hidden in [false, true]) {
    final mutations = hidden
        ? publicTextboxHiddenValidCases
        : publicTextboxValidCases;
    for (final mutation in mutations) {
      final document = publicTextboxReferenceDocument(mutation, hidden: hidden);
      final before = jsonEncode(publicTextboxSourceMetadata(document));
      final result = convertLegacyWordDocument(document);
      final archive = ZipDecoder().decodeBytes(result.bytes);
      final part = publicTextboxOutputPart(mutation);
      final xml = _xml(archive, part);
      final rects = xml.findAllElements('rect', namespace: _v).toList();
      final boxes = xml.findAllElements('txbxContent', namespace: _w).toList();
      final unplaced = hidden || mutation == 'unresolved-chain';
      _requireNoTextboxesOutside(archive, unplaced ? null : part, mutation);
      if (unplaced) {
        _require(
          (result.preservedCounts['textboxes'] ?? 0) == 0 &&
              result.limitations.contains(
                LegacyWordConversionLimitation.embeddedObjects,
              ),
          'Unplaced textbox reported as active: $mutation, hidden=$hidden',
        );
        _verifyInert(archive, document.textboxReferences.single, mutation);
        inert++;
      } else {
        final expectedCount = mutation.startsWith('single') ? 1 : 2;
        _require(
          rects.length == expectedCount &&
              boxes.length == expectedCount &&
              rects.every((rect) => rect.getAttribute('id') != null) &&
              rects.map((rect) => rect.getAttribute('id')).toSet().length ==
                  expectedCount &&
              result.preservedCounts['textboxes'] == expectedCount,
          'Textbox identity, ownership, or count changed: $mutation',
        );
        final words = boxes.map(_text).toList();
        if (mutation.startsWith('two-stories')) {
          _require(
            jsonEncode(words) == jsonEncode(['One', 'Two']) &&
                rects.every((rect) => !_hasNext(rect)),
            'Independent textbox stories became a chain: $mutation',
          );
        } else if (expectedCount == 2) {
          _require(
            jsonEncode(words) == jsonEncode(['One', '']) &&
                rects.first.getAttribute('id') == '_legacyTextboxShape42' &&
                rects.last.getAttribute('id') == '_legacyTextboxShape43' &&
                rects.first
                    .getAttribute('style')!
                    .contains('mso-next-textbox:#_legacyTextboxShape43') &&
                !_hasNext(rects.last),
            'Textbox chain order, text, or linkage changed: $mutation',
          );
        } else {
          _require(
            words.single == 'One' && !_hasNext(rects.single),
            'Singleton textbox text or linkage changed: $mutation',
          );
        }
        visible++;
        if (part != 'word/document.xml') auxiliary++;
      }
      _require(
        before == jsonEncode(publicTextboxSourceMetadata(document)),
        'Textbox conversion mutated the public model: $mutation, hidden=$hidden',
      );
    }
  }
  for (final mutation in publicTextboxInvalidCases) {
    _reject(mutation, hidden: false);
    rejected++;
  }
  for (final mutation in publicTextboxHiddenInvalidCases) {
    _reject(mutation, hidden: true);
    rejected++;
  }
  return {
    'visibleCases': visible,
    'headerOwnerCases': auxiliary,
    'inertEvidenceCases': inert,
    'malformedInputsRejected': rejected,
    'convertedPackages': visible + inert,
    'sourceMetadataUnchanged': true,
  };
}

Map<String, Object?> publicTextboxSourceMetadata(LegacyWordDocument document) =>
    {
      'references': [
        for (final reference in document.textboxReferences)
          {
            'id': reference.id,
            'storyId': reference.storyId,
            'inHeaderFooter': reference.inHeaderFooter,
            'anchorCp': reference.anchorCp,
            'shapeId': reference.shapeId,
            'nextTextboxId': reference.nextTextboxId,
            'chainLength': reference.chainLength,
            'declaredChainLength': reference.declaredChainLength,
            'placementUnresolved': reference.placementUnresolved,
            'anchors': reference.anchors.map(_anchor).toList(),
            'headerAliases': reference.headerAliases.map(_anchor).toList(),
            'replicaAnchors': reference.replicaAnchors.map(_anchor).toList(),
          },
      ],
      'drawings': [
        for (final drawing in document.media.drawings)
          {
            'shapeId': drawing.shapeId,
            'anchorCp': drawing.anchorCp,
            'headerStory': drawing.headerStory,
            'textboxId': drawing.textboxId,
            'nextTextboxShapeId': drawing.nextTextboxShapeId,
          },
      ],
      'stories': [
        for (final story in document.stories)
          {
            'id': story.id,
            'kind': story.kind.name,
            'startCp': story.startCp,
            'endCp': story.endCp,
            'plainText': story.plainText,
          },
      ],
    };

Map<String, Object?> _anchor(LegacyWordTextboxAnchor anchor) => {
  'shapeId': anchor.shapeId,
  'anchorCp': anchor.anchorCp,
  'chainIndex': anchor.chainIndex,
  'nextShapeId': anchor.nextShapeId,
};

void _verifyInert(
  Archive archive,
  LegacyWordTextboxReference reference,
  String mutation,
) {
  final evidence = archive.files
      .where(
        (file) =>
            file.name.startsWith('word/textboxEvidence') &&
            file.name.endsWith('.xml'),
      )
      .toList();
  _require(evidence.length == 1, 'Missing or duplicated textbox evidence');
  _require(
    _text(XmlDocument.parse(utf8.decode(evidence.single.content))) == 'One',
    'Unplaced textbox text changed: $mutation',
  );
  final manifest = archive.findFile('word/evidence/manifest.json');
  _require(manifest != null, 'Missing textbox evidence manifest');
  final records =
      (jsonDecode(utf8.decode(manifest!.content))['records'] as List)
          .cast<Map>()
          .where((record) => record['kind'] == 'textbox')
          .toList();
  _require(records.length == 1, 'Ambiguous textbox evidence record');
  final record = records.single;
  _require(
    record['id'] == reference.id &&
        record['part'] == evidence.single.name &&
        record['story'] == reference.storyId &&
        record['shapeId'] == reference.shapeId &&
        record['nextTextboxId'] == reference.nextTextboxId &&
        record['chainLength'] == reference.chainLength &&
        record['declaredChainLength'] == reference.declaredChainLength &&
        record['placementUnresolved'] == reference.placementUnresolved &&
        jsonEncode(record['anchors'] ?? []) ==
            jsonEncode(reference.anchors.map(_anchor).toList()),
    'Unplaced textbox reference metadata changed: $mutation',
  );
}

void _requireNoTextboxesOutside(
  Archive archive,
  String? owner,
  String mutation,
) {
  final activePart = RegExp(
    r'^word/(document|header\d+|footer\d+|footnotes|endnotes|comments)\.xml$',
  );
  for (final file in archive.files) {
    if (file.name == owner || !activePart.hasMatch(file.name)) continue;
    final xml = XmlDocument.parse(utf8.decode(file.content));
    _require(
      xml.findAllElements('txbxContent', namespace: _w).isEmpty &&
          xml.findAllElements('rect', namespace: _v).isEmpty,
      'Textbox leaked into ${file.name}: $mutation',
    );
  }
}

bool _hasNext(XmlElement rect) =>
    (rect.getAttribute('style') ?? '').contains('mso-next-textbox');

String _text(XmlNode node) => node
    .findAllElements('t', namespace: _w)
    .map((text) => text.innerText)
    .join();

XmlDocument _xml(Archive archive, String path) {
  final file = archive.findFile(path);
  _require(file != null, 'Missing textbox output part: $path');
  return XmlDocument.parse(utf8.decode(file!.content));
}

void _reject(String mutation, {required bool hidden}) {
  try {
    convertLegacyWordDocument(
      publicTextboxReferenceDocument(mutation, hidden: hidden),
    );
  } on FormatException {
    return;
  } on LegacyWordConversionException {
    return;
  }
  throw StateError('Malformed textbox accepted: $mutation, hidden=$hidden');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
