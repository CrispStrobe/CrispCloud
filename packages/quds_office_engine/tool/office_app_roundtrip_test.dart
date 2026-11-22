// Run with dart test from packages/quds_office_engine. This verifies saved
// files produced by installed office apps, never synthetic converter output.
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../test/support/zotero_converter_fixtures.dart';

void main() {
  final outputRoot = Platform.environment['CRISP_OFFICE_ORACLE_OUTPUT'];
  if (outputRoot == null || outputRoot.isEmpty) {
    throw StateError(
      'Set CRISP_OFFICE_ORACLE_OUTPUT to the native app output directory.',
    );
  }
  final directory = '$outputRoot/fresh-converter';
  for (final ext in ['docx', 'odt']) {
    for (final cycle in [1, 2]) {
      for (final kind in ['body', 'cell', 'footnote']) {
        test('installed LibreOffice $ext cycle $cycle $kind', () async {
          final path = '$directory/$ext-cycle-$cycle/$kind.$ext';
          final bytes = File(path).readAsBytesSync();
          final document = ext == 'odt'
              ? await OdtDocumentReader.readBytes(bytes)
              : WordDeserializer().readBytes(bytes);
          expectConverterSnapshot(document, kind);
          final reopened = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expectConverterSnapshot(reopened, kind);
        });
      }
    }
  }
  for (final kind in ['body', 'cell', 'footnote']) {
    test(
      'installed Word save retains active editable Zotero fields in $kind',
      () {
        final input = File('$zoteroConverterFixtureRoot/original/$kind.docx');
        final output = File(
          '$outputRoot/word-citation-stories/$kind-word.docx',
        );
        final original = WordDeserializer().readBytes(input.readAsBytesSync());
        final saved = WordDeserializer().readBytes(output.readAsBytesSync());
        List<Object?> fields(WmlDocument doc) => WordZotero.fields(doc)
            .map(
              (f) => {
                'metadata': jsonDecode(jsonEncode(f.citation!.toJson())),
                'cachedText': f.cachedText,
                'editable': f.canEdit,
                'owner': converterStory(doc, kind).contains(f.paragraph),
              },
            )
            .toList();
        expect(fields(original), hasLength(2));
        expect(fields(saved), fields(original));
        expect(WordFieldSpans.unbalanced(saved), isEmpty);
      },
    );
  }
}
