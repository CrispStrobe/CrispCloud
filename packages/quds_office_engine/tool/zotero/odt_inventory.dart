import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Read-only diagnostic; it neither imports the document nor invokes Zotero.
Future<void> main(List<String> arguments) async {
  const usage =
      'Usage: dart run tool/zotero/odt_inventory.dart document.odt\n'
      'Print native Zotero field locations, cached text, preferences and findings as JSON.\n'
      'This inventory does not enable editable ODT loading.';
  if (arguments.length == 1 && arguments.single == '--help') {
    stdout.writeln(usage);
    return;
  }
  if (arguments.length != 1) {
    stderr.writeln(usage);
    exitCode = 64;
    return;
  }
  try {
    final file = File(arguments.single);
    const limits = OdfZoteroLimits();
    if (await file.length() > limits.maxArchiveBytes) {
      throw const OdfZoteroLimitException('archive bytes');
    }
    final inventory = await OdfZotero.inspect(await file.readAsBytes());
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(inventory.toJson()),
    );
  } on FileSystemException catch (error) {
    stderr.writeln('Unable to read ODT: ${error.message}');
    exitCode = 66;
  } on FormatException catch (error) {
    stderr.writeln('Unable to inventory ODT: ${error.message}');
    exitCode = 65;
  } on ZipException catch (error) {
    stderr.writeln('Unable to inventory ODT: $error');
    exitCode = 65;
  }
}
