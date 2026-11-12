// SPDX-License-Identifier: MPL-2.0
import 'dart:io';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

/// Inspect a DOC/DOT and optionally write a new DOCX or explicit DOCM copy.
/// dart:io belongs to this command-line example; the package itself is portable.
Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty || arguments.contains('--help')) {
    stdout.writeln(
      'Usage: dart run example/legacy_doc_parser_example.dart '
      'input.doc [new-copy.docx|new-copy.docm]',
    );
    return;
  }
  if (arguments.length > 2) {
    stderr.writeln(
      'Provide an input path and, optionally, one new output path.',
    );
    exitCode = 64;
    return;
  }
  try {
    final input = File(arguments.first);
    if (await input.length() > 64 * 1024 * 1024) {
      throw const FormatException('The input exceeds the 64 MiB file limit.');
    }
    final document = parseLegacyWordDocument(await input.readAsBytes());
    stdout.writeln(
      'Parsed ${document.blocks.length} main blocks, '
      '${document.sections.length} sections, ${document.stories.length} auxiliary stories.',
    );
    stdout.writeln(
      'Main text: ${document.plainText.length} UTF-16 code units; '
      'images: ${document.media.assets.length}; fields: ${document.fields.length}.',
    );
    if (document.warnings.isNotEmpty) {
      stdout.writeln(
        'Parser warnings: ${document.warnings.map((warning) => warning.name).join(', ')}',
      );
    }
    if (arguments.length == 1) {
      stdout.writeln(
        'Add a new .docx or .docm output path to create a converted copy.',
      );
      return;
    }

    final name = arguments[1].toLowerCase();
    final LegacyWordOutputFormat format;
    if (name.endsWith('.docx')) {
      format = LegacyWordOutputFormat.docx;
    } else if (name.endsWith('.docm')) {
      format = LegacyWordOutputFormat.docm;
    } else {
      throw const FormatException(
        'The output path must end in .docx or .docm.',
      );
    }
    final conversion = convertLegacyWordDocument(document, format: format);
    stdout.writeln(
      'Conversion limitations: '
      '${conversion.limitations.map((limitation) => limitation.name).join(', ')}',
    );
    stdout.writeln('Emitted content: ${conversion.preservedCounts}');
    if (format == LegacyWordOutputFormat.docm) {
      stdout.writeln(
        'DOCM may retain a VBA project. Conversion does not execute it.',
      );
    }
    if (conversion.signatureEvidenceParts.isNotEmpty) {
      stdout.writeln(
        'Original signatures are inert evidence; they do not authenticate this copy.',
      );
    }

    // Exclusive creation refuses an existing destination. The example
    // intentionally provides no overwrite/force option.
    final output = File(arguments[1]);
    await output.create(exclusive: true);
    await output.writeAsBytes(conversion.bytes, flush: true);
    stdout.writeln(
      'Created ${output.path}. Review the converted copy in your office application.',
    );
  } on FileSystemException catch (error) {
    stderr.writeln('File operation failed: ${error.message}');
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('Document could not be converted: ${error.message}');
    exitCode = 1;
  } on LegacyWordConversionException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}
