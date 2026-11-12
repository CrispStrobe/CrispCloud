// SPDX-License-Identifier: MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/media_word_fixture.dart';
import '../../test/support/metafile_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

Uint8List _emr(int type, List<int> values) =>
    emfRecord(type, [for (final value in values) ...wordU32(value)]);
Uint8List _meta(int type, List<int> values) =>
    wmfRecord(type, [for (final value in values) ...wordU16(value)]);

/// Fixed source ellipse with a magenta reference frame, red outline and black
/// fill. Off-ellipse radials are intentional: sampling checks their projection.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/metafile_arcs_probe.dart NEW_DIRECTORY',
    );
  }
  final directory = Directory(arguments.single);
  if (directory.existsSync()) throw ArgumentError('Output already exists.');
  directory.createSync(recursive: true);
  for (final format in ['emf', 'wmf']) {
    for (final (kind, emfType, wmfType) in [
      ('arc', 45, 0x0817),
      ('chord', 46, 0x0830),
      ('pie', 47, 0x081a),
      ('arcto', 55, 0),
    ]) {
      if (kind == 'arcto' && format == 'wmf') continue;
      for (final variant in [
        'counterclockwise',
        if (format == 'emf') 'clockwise',
        if (kind == 'arc' || kind == 'chord') 'full',
      ]) {
        final full = variant == 'full';
        final records = format == 'emf'
            ? [
                _emr(38, [1, 0, 1, 0, 0xff00ff]),
                _emr(38, [2, 0, 8, 0, 0xff]),
                if (kind == 'arcto') _emr(38, [3, 0, 2, 0, 0xff0000]),
                _emr(37, [1]),
                _emr(37, [0x80000005]),
                _emr(43, [10, 5, 190, 95]),
                _emr(37, [2]),
                _emr(37, [0x80000004]),
                _emr(57, [variant == 'clockwise' ? 2 : 1]),
                if (kind == 'arcto') _emr(27, [150, 95]),
                _emr(emfType, [
                  20,
                  10,
                  180,
                  90,
                  420,
                  50,
                  full ? 420 : 100,
                  full ? 50 : -110,
                ]),
                if (kind == 'arcto') ...[
                  _emr(37, [3]),
                  _emr(54, [20, 80]),
                ],
              ]
            : [
                wmfRecord(0x02fa, [
                  ...wordU16(0),
                  ...wordU16(1),
                  ...wordU16(0),
                  ...wordU32(0xff00ff),
                ]),
                wmfRecord(0x02fa, [
                  ...wordU16(0),
                  ...wordU16(8),
                  ...wordU16(0),
                  ...wordU32(0xff),
                ]),
                wmfRecord(0x02fc, [
                  ...wordU16(1),
                  ...wordU32(0),
                  ...wordU16(0),
                ]),
                wmfRecord(0x02fc, [
                  ...wordU16(0),
                  ...wordU32(0),
                  ...wordU16(0),
                ]),
                _meta(0x012d, [0]),
                _meta(0x012d, [2]),
                _meta(0x041b, [95, 190, 5, 10]),
                _meta(0x012d, [1]),
                _meta(0x012d, [3]),
                _meta(wmfType, [
                  full ? 50 : -110,
                  full ? 420 : 100,
                  50,
                  420,
                  90,
                  180,
                  10,
                  20,
                ]),
              ];
        final emf = format == 'emf';
        final payload = emf
            ? emfFixture(records: records)
            : wmfFixture(records: records, placeable: true);
        final source = inlinePictureWordFixture(
          picture: inlinePictureData(blip: metafileBlip(payload, emf: emf)),
        );
        final document = parseLegacyWordDocument(source);
        final preview = document.media.assets.single.metafile!.previewSvg;
        if (preview == null) throw StateError('Arc preview is unavailable.');
        final base = '${directory.path}/$format-$kind-$variant';
        File('$base.$format').writeAsBytesSync(payload);
        File('$base.doc').writeAsBytesSync(source);
        File('$base.svg').writeAsStringSync(preview);
        File(
          '$base.docx',
        ).writeAsBytesSync(convertLegacyWordDocument(document).bytes);
      }
    }
  }
}
