// SPDX-License-Identifier: MPL-2.0
// Inspect one externally authored DOC in an isolated, timeout-bounded process.
// The Python corpus harness treats each stage result separately; a caught
// parser/converter error is evidence, never a successful acceptance result.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:legacy_doc_parser/legacy_doc_parser.dart';

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln('Usage: external_document_probe INPUT.doc NEW_OUTPUT_DIR');
    exitCode = 64;
    return;
  }
  final source = File(arguments[0]);
  final output = Directory(arguments[1]);
  if (output.existsSync()) {
    stderr.writeln('The output directory must be new.');
    exitCode = 73;
    return;
  }
  if (source.lengthSync() > 16 * 1024 * 1024) {
    stderr.writeln('The external corpus input exceeds 16 MiB.');
    exitCode = 65;
    return;
  }
  output.createSync(recursive: true);
  final bytes = source.readAsBytesSync();
  final original = Uint8List.fromList(bytes);
  final result = <String, Object?>{
    'version': 1,
    'source': source.absolute.path,
    'sourceBytes': bytes.length,
    'stages': <String, Object?>{},
  };
  final stages = result['stages']! as Map<String, Object?>;

  void save() {
    result['sourceBytesUnchanged'] =
        bytes.length == original.length &&
        Iterable<int>.generate(
          bytes.length,
        ).every((i) => bytes[i] == original[i]);
    File('${output.path}/result.json').writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(result)}\n',
    );
  }

  void stage(String name, Map<String, Object?> Function() action) {
    final watch = Stopwatch()..start();
    try {
      stages[name] = <String, Object?>{'status': 'ok', ...action()};
    } catch (error, trace) {
      stages[name] = <String, Object?>{
        'status': 'error',
        'errorType': error.runtimeType.toString(),
        'error': error.toString(),
        'stack': trace.toString(),
      };
    }
    (stages[name]! as Map<String, Object?>)['elapsedMicroseconds'] =
        watch.elapsedMicroseconds;
    save();
  }

  stage('textOnly', () {
    final text = extractLegacyWordText(bytes);
    File('${output.path}/text-only.txt').writeAsStringSync(text);
    return {'utf16Length': text.length, 'textFile': 'text-only.txt'};
  });

  LegacyWordDocument? document;
  stage('structured', () {
    final parsed = parseLegacyWordDocument(bytes);
    document = parsed;
    File('${output.path}/main-model.txt').writeAsStringSync(parsed.plainText);
    File('${output.path}/preview.html').writeAsStringSync(parsed.safeHtml);
    final stories = <Map<String, Object?>>[];
    for (var i = 0; i < parsed.stories.length; i++) {
      final story = parsed.stories[i];
      final path = 'story-$i.txt';
      File('${output.path}/$path').writeAsStringSync(story.plainText);
      stories.add({
        'id': story.id,
        'kind': story.kind.name,
        'startCp': story.startCp,
        'endCp': story.endCp,
        'utf16Length': story.plainText.length,
        'textFile': path,
      });
    }
    return {
      'utf16Length': parsed.plainText.length,
      'textFile': 'main-model.txt',
      'warnings': parsed.warnings.map((warning) => warning.name).toList(),
      'sections': parsed.sections.length,
      'bookmarks': parsed.bookmarks.length,
      'fields': parsed.fields.length,
      'notes': parsed.noteReferences.length,
      'comments': parsed.commentReferences.length,
      'textboxes': parsed.textboxReferences.length,
      'stories': stories,
    };
  });
  final parsed = document;
  if (parsed != null) {
    for (final mode in LegacyWordFieldMode.values) {
      stage('convert-${mode.name}', () {
        final converted = convertLegacyWordDocument(parsed, fieldMode: mode);
        final name = '${mode.name}.docx';
        File('${output.path}/$name').writeAsBytesSync(converted.bytes);
        final repeated = convertLegacyWordDocument(parsed, fieldMode: mode);
        final equal =
            converted.bytes.length == repeated.bytes.length &&
            Iterable<int>.generate(
              converted.bytes.length,
            ).every((i) => converted.bytes[i] == repeated.bytes[i]);
        return {
          'output': name,
          'bytes': converted.bytes.length,
          'deterministicRepeat': equal,
          'preservedCounts': converted.preservedCounts,
          'limitations': converted.limitations
              .map((limitation) => limitation.name)
              .toList(),
        };
      });
    }
  }
  save();
  stdout.writeln(jsonEncode(result));
}
