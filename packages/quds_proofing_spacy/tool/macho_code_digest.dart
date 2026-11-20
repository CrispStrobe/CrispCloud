// Prints the signature-independent Mach-O code digest (machOCodeSha256) of a
// signed library, the value the runtime compares with qualified builds.
//
//   dart run tool/macho_code_digest.dart path/to/libcrispembed-spacy.dylib
//
// Exits 1 when the file is not a signed thin 64-bit Mach-O.
import 'dart:io';

import 'package:quds_proofing_spacy/quds_proofing_spacy.dart';

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('usage: macho_code_digest.dart <signed Mach-O library>');
    exit(64);
  }
  final digest = machOCodeSha256(File(arguments.single).readAsBytesSync());
  if (digest == null) {
    stderr.writeln('${arguments.single}: not a signed thin 64-bit Mach-O');
    exit(1);
  }
  stdout.writeln(digest);
}
