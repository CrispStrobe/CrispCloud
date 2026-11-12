// SPDX-License-Identifier: MPL-2.0

// The full media path under the VM and dart2js/Node. No dart:io, Flutter,
// browser API, native GDI, or downloaded dependency is imported.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:legacy_doc_parser/legacy_doc_parser.dart';
import 'package:xml/xml.dart';

import '../test/support/media_word_fixture.dart';
import '../test/support/metafile_fixture.dart';
import '../test/support/officeart_shape_fixture.dart';
import 'fidelity/metafile_records.dart';

void main() => print(
  'Media JavaScript/VM acceptance passed: '
  '${jsonEncode(verifyMediaWebAcceptance())}',
);

Map<String, Object> verifyMediaWebAcceptance() {
  var checks = 0;
  void check(bool condition, String description) {
    if (!condition) throw StateError(description);
    checks++;
  }

  void rejects(Uint8List source, String description) {
    try {
      parseLegacyWordDocument(source);
    } on FormatException {
      checks++;
      return;
    }
    throw StateError(description);
  }

  final recordCounts = <String, int>{};
  for (final (format, raw) in [
    (LegacyWordImageFormat.emf, authoredEmfVectors()),
    (LegacyWordImageFormat.wmf, authoredWmfVectors()),
  ]) {
    final info = parseLegacyWordMetafile(raw, format: format);
    check(
      info.hasCompletePreview && info.nativeEmbeddingAllowed,
      '${format.name} preview and native eligibility',
    );
    recordCounts[format.name] = info.recordCount;
    final svg = XmlDocument.parse(info.previewSvg!);
    check(
      svg.findAllElements('rect').length == 2 &&
          svg.findAllElements('ellipse').length == 1,
      '${format.name} independent geometric controls',
    );
    check(
      !info.previewSvg!.contains('href=') &&
          info.previewSvg!.contains('#99CCDD'),
      '${format.name} generated fixed-color markup',
    );
    for (final compressed in [false, true]) {
      for (final twoUids in [false, true]) {
        final payload = format == LegacyWordImageFormat.wmf && twoUids
            ? Uint8List.sublistView(raw, 22)
            : raw;
        final source = inlinePictureWordFixture(
          picture: inlinePictureData(
            blip: metafileBlip(
              payload,
              emf: format == LegacyWordImageFormat.emf,
              compressed: compressed,
              twoUids: twoUids,
              mutateHeader: (header) {
                // Real producers use physical extents here, not GDI pixels.
                header.setInt32(12, 15876, Endian.little);
                header.setInt32(16, 9526, Endian.little);
                header.setInt32(20, 5486400, Endian.little);
                header.setInt32(24, 3291840, Endian.little);
              },
            ),
          ),
        );
        final original = Uint8List.fromList(source);
        final document = parseLegacyWordDocument(source);
        final asset = document.media.assets.single;
        check(
          _equal(asset.bytes, payload) &&
              asset.metafile!.hasCompletePreview &&
              asset.metafile!.bounds.width == 600 &&
              asset.metafile!.bounds.height == 360 &&
              asset.metafile!.officeArtBounds!.width == 15876,
          '${format.name} bounded decoding and replay',
        );
        final package = ZipDecoder().decodeBytes(
          convertLegacyWordDocument(document).bytes,
        );
        final image = package.findFile('word/media/image1.${format.name}');
        check(
          image != null && _equal(image.content, payload),
          '${format.name} exact native DOCX image payload',
        );
        check(_equal(source, original), 'source compound document mutated');
      }
    }
  }

  Uint8List doc(Uint8List blip) =>
      inlinePictureWordFixture(picture: inlinePictureData(blip: blip));
  final raw = authoredEmfVectors();
  for (final mutate in <Uint8List Function(Uint8List)>[
    (bytes) => Uint8List.fromList(bytes)..[bytes.length - 1] ^= 1,
    (bytes) => Uint8List.sublistView(bytes, 0, bytes.length - 1),
    (bytes) => Uint8List.fromList([
      ...bytes.sublist(0, bytes.length - 4),
      0,
      ...bytes.sublist(bytes.length - 4),
    ]),
    (bytes) => Uint8List.fromList(bytes)..[2] &= 0xfe,
  ]) {
    rejects(
      doc(metafileBlip(raw, mutateCompressed: mutate)),
      'malformed zlib was accepted',
    );
  }
  rejects(
    doc(
      metafileBlip(
        Uint8List(100000)..fillRange(0, 100000, 65),
        mutateHeader: (header) => header.setUint32(0, 8, Endian.little),
      ),
    ),
    'inflate output exhaustion was accepted',
  );
  final escaped = parseLegacyWordMetafile(
    emfFixture(
      records: [
        emfRecord(105, [0, 0, 0, 0]),
      ],
    ),
    format: LegacyWordImageFormat.emf,
  );
  check(
    !escaped.nativeEmbeddingAllowed && escaped.previewSvg == null,
    'escape record was activated',
  );
  final ambiguous = parseLegacyWordDocument(
    doc(metafileBlip(wmfFixture(), emf: false)),
  ).media.assets.single.metafile!;
  check(
    ambiguous.nativeEmbeddingAllowed && ambiguous.previewSvg == null,
    'unknown WMF coordinate context was invented',
  );

  // Packed POINT support has a separate validation increment. This checkpoint
  // tests the already supported full-width custom geometry path under JS.
  final vertices = shapeVertices([
    (-10, 0),
    (100, 0),
    (150, 40),
    (100, 100),
    (0, 100),
  ]);
  final source = officeArtShapeWordFixture(
    type: 0,
    values: {4: -15 * 65536},
    rawPropertyRecord: shapePropertyRecord(
      values: {
        4: -15 * 65536,
        0x03bf: 0x80000000,
        0x0183: 0x08000001,
        0x01c2: 0x08000002,
      },
      complex: {
        0x145: vertices,
        0x146: shapeSegments([
          0x4000,
          0xb300,
          0x0001,
          0x2001,
          0xb300,
          0x6001,
          0x8000,
        ]),
      },
      complexLengths: {0x145: vertices.length - 6},
    ),
  );
  final document = parseLegacyWordDocument(source);
  final shape = document.media.drawings.single.shape!;
  check(
    shape.geometry!.path.first.points.single.x == -10 &&
        shape.unsupportedProperties.isEmpty,
    'full-width geometry and signed coordinates',
  );
  check(
    shape.groupShapeBooleanProperties == 0x80000000 &&
        shape.layoutInCell == false &&
        shape.geometry!.editingHints.length == 2 &&
        shape.geometry!.editingHints.last.vertexIndex == 4,
    'unsigned high use bit, inactive paint colors and bounded editing hints',
  );
  final converted = convertLegacyWordDocument(document);
  final zip = ZipDecoder().decodeBytes(converted.bytes);
  final xml = XmlDocument.parse(
    utf8.decode(zip.findFile('word/document.xml')!.content),
  );
  final vml = xml
      .findAllElements('shape', namespace: 'urn:schemas-microsoft-com:vml')
      .single;
  check(
    vml.getAttribute('path') == 'm-10,0l100,0c150,40,100,100,0,100xe' &&
        RegExp(
          r'(?:^|;)rotation:-15(?:\.0)?(?:;|$)',
        ).hasMatch(vml.getAttribute('style')!) &&
        vml
            .getAttribute('style')!
            .contains('mso-position-horizontal-relative:page;'),
    'native custom geometry and rotation serialization',
  );
  check(
    converted.preservedCounts['editableShapes'] == 1,
    'editable shape preservation report',
  );
  check(
    vml.getAttribute(
          'allowincell',
          namespace: 'urn:schemas-microsoft-com:office:office',
        ) ==
        'f',
    'explicit false cell-layout use bit survives VML export',
  );
  final inheritedHidden = parseLegacyWordDocument(
    officeArtShapeWordFixture(
      defaults: {0x03bf: 0x00020002},
      values: {0x03bf: 0x80000000},
    ),
  );
  check(
    inheritedHidden.media.drawings.single.shape!.groupShapeBooleanProperties ==
            0x80020002 &&
        inheritedHidden.media.drawings.single.shape!.unsupportedProperties
            .contains(0x03bf) &&
        convertLegacyWordDocument(
              inheritedHidden,
            ).preservedCounts['editableShapes'] ==
            null,
    'layout use-bit merge cannot erase inherited hidden semantics',
  );
  final imageResult = convertLegacyWord(
    floatingPictureWordFixture(
      anchorBounds: (-120, 240, 600, 1680),
      shapeFlags: 0x0ac0,
      imageProperties: {
        4: -90 * 65536,
        0x0390: 1,
        0x0392: 1,
        0x03bf: 0x80000000,
        0x01ff: 0x80008,
        0x01c0: 0x332211,
        0x01cb: 25400,
        0x01ce: 2,
        0x023f: 0x20002,
        0x0201: 0x665544,
        0x0204: 49152,
        0x0205: -12700,
        0x0206: 0,
      },
    ),
  );
  final imageXml = XmlDocument.parse(
    utf8.decode(
      ZipDecoder()
          .decodeBytes(imageResult.bytes)
          .findFile('word/document.xml')!
          .content,
    ),
  );
  final imageTransform = imageXml.findAllElements('a:xfrm').single;
  check(
    imageXml.findAllElements('wp:anchor').single.getAttribute('layoutInCell') ==
        '0',
    'DrawingML honors the high-bit explicit false cell-layout flag',
  );
  check(
    imageTransform.getAttribute('rot') == '16200000' &&
        imageTransform.getAttribute('flipH') == '1' &&
        imageTransform.getAttribute('flipV') == '1',
    'signed picture-frame quarter turn and independent FSP flips',
  );
  check(
    imageTransform.findElements('a:ext').single.getAttribute('cx') ==
            '914400' &&
        imageXml.findAllElements('wp:positionH').single.innerText == '-304800',
    'quarter-turn source center and pre-rotation extent under JavaScript',
  );
  check(
    imageXml.findAllElements('a:ln').single.getAttribute('w') == '25400' &&
        imageXml.findAllElements('a:prstDash').single.getAttribute('val') ==
            'sysDot',
    'direct DrawingML image outline',
  );
  final shadow = imageXml.findAllElements('a:outerShdw').single;
  check(
    shadow.getAttribute('dist') == '12700' &&
        shadow.getAttribute('dir') == '10800000' &&
        shadow.findAllElements('a:alpha').single.getAttribute('val') == '75000',
    'signed image shadow distance, direction and opacity',
  );
  return {
    'checks': checks,
    'recordCounts': recordCounts,
    'emfBytes': raw.length,
    'wmfBytes': authoredWmfVectors().length,
  };
}

bool _equal(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
