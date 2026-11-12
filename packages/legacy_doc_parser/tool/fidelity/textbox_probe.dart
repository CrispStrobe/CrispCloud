// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

import '../../test/support/linked_textbox_fixture.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    throw ArgumentError(
      'Usage: dart run tool/fidelity/textbox_probe.dart NEW_DIRECTORY',
    );
  }
  final destination = Directory(arguments.single);
  if (destination.existsSync()) throw ArgumentError('Output already exists.');
  destination.createSync(recursive: true);
  for (final (name, height) in [('small', 840), ('large', 1400)]) {
    final result = convertLegacyWordDocument(
      linkedTextboxFixture(firstHeightTwips: height),
    );
    File('${destination.path}/$name.docx').writeAsBytesSync(result.bytes);
  }
}
