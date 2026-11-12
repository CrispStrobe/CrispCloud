// SPDX-License-Identifier: MPL-2.0
// Machine-readable adapter for the independent Python fidelity harness.
import 'dart:convert';
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/fidelity/convert.dart source.doc new.docx',
    );
    exitCode = 64;
    return;
  }
  final source = File(arguments[0]);
  final output = File(arguments[1]);
  if (source.lengthSync() > 64 * 1024 * 1024) {
    throw const FormatException('Source exceeds the binary DOC size limit.');
  }
  final document = parseLegacyWordDocument(source.readAsBytesSync());
  final result = convertLegacyWordDocument(document);
  output.createSync(exclusive: true);
  output.writeAsBytesSync(result.bytes, flush: true);
  stdout.writeln(
    jsonEncode({
      'counts': result.preservedCounts,
      'warnings': document.warnings.map((value) => value.name).toList(),
      'limitations': result.limitations.map((value) => value.name).toList(),
      'signatureValidityClaimed': result.signatureValidityClaimed,
    }),
  );
}
