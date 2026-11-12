// SPDX-License-Identifier: MPL-2.0
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/media_word_fixture.dart';
import '../../test/support/metafile_fixture.dart';
import '../../test/support/structured_word_fixture.dart';

/// Two nested rectangles with the same orientation distinguish alternate
/// and winding compound fill. Black brush, null pen, no external resources.
void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/metafile_probe.dart NEW_DIRECTORY',
    );
  }
  final directory = Directory(arguments.single);
  if (directory.existsSync()) throw ArgumentError('Output already exists.');
  directory.createSync(recursive: true);
  const points = [
    (20, 10),
    (180, 10),
    (180, 90),
    (20, 90),
    (70, 30),
    (130, 30),
    (130, 70),
    (70, 70),
  ];
  for (final format in ['emf32', 'emf16', 'wmf']) {
    for (final mode in [1, 2]) {
      final name = '$format-${mode == 1 ? 'alternate' : 'winding'}';
      final Uint8List payload;
      if (format == 'wmf') {
        payload = wmfFixture(
          placeable: true,
          records: [
            wmfRecord(0x02fc, [...wordU16(0), ...wordU32(0), ...wordU16(0)]),
            wmfRecord(0x02fa, [
              ...wordU16(5),
              ...wordU16(0),
              ...wordU16(0),
              ...wordU32(0),
            ]),
            wmfRecord(0x012d, wordU16(0)),
            wmfRecord(0x012d, wordU16(1)),
            wmfRecord(0x0106, wordU16(mode)),
            wmfRecord(0x0538, [
              ...wordU16(2),
              ...wordU16(4),
              ...wordU16(4),
              for (final (x, y) in points) ...[...wordU16(x), ...wordU16(y)],
            ]),
          ],
        );
      } else {
        payload = emfFixture(
          records: [
            emfRecord(37, wordU32(0x80000004)),
            emfRecord(37, wordU32(0x80000008)),
            emfRecord(19, wordU32(mode)),
            emfRecord(format == 'emf16' ? 91 : 8, [
              for (final value in [20, 10, 180, 90, 2, 8, 4, 4])
                ...wordU32(value),
              for (final (x, y) in points)
                if (format == 'emf16') ...[
                  ...wordU16(x),
                  ...wordU16(y),
                ] else ...[
                  ...wordU32(x),
                  ...wordU32(y),
                ],
            ]),
          ],
        );
      }
      final emf = format != 'wmf';
      final source = inlinePictureWordFixture(
        picture: inlinePictureData(blip: metafileBlip(payload, emf: emf)),
      );
      final document = parseLegacyWordDocument(source);
      final asset = document.media.assets.single;
      if (!asset.metafile!.hasCompletePreview) {
        throw StateError('Authored compound polygon preview is unavailable.');
      }
      File(
        '${directory.path}/$name.${emf ? 'emf' : 'wmf'}',
      ).writeAsBytesSync(payload);
      File('${directory.path}/$name.doc').writeAsBytesSync(source);
      File(
        '${directory.path}/$name.svg',
      ).writeAsStringSync(asset.metafile!.previewSvg!);
      File(
        '${directory.path}/$name.docx',
      ).writeAsBytesSync(convertLegacyWordDocument(document).bytes);
    }
  }
}
