import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/zotero/footnote_separator_acceptance.dart' as acceptance;

// Untouched outputs from the identified external file converter. These tests
// exercise native reopening/refresh/persistence; they do not run Zotero's UI.
void main() {
  const directory = 'test/fixtures/zotero/separators';
  final manifest =
      jsonDecode(File('$directory/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  for (final entry
      in (manifest['files'] as List).cast<Map<String, dynamic>>()) {
    final name = entry['file'] as String;
    final preset = entry['preset'] as String;
    test(
      'retained $name reopens and refreshes without losing separator or citations',
      () async {
        final bytes = File('$directory/$name').readAsBytesSync();
        expect(sha256.convert(bytes).toString(), entry['sha256']);
        var document = await OdtDocumentReader.readBytes(bytes);
        expect(acceptance.inspect(document, preset)['activeFields'], 2);
        final originalGeometry = document.footnoteSeparator!;
        acceptance.refresh(document);
        expect(document.footnoteSeparator, same(originalGeometry));
        expect(WordZotero.fields(document).map((field) => field.cachedText), [
          '(Refreshed body)',
          '(Refreshed note)',
        ]);
        for (var cycle = 0; cycle < 2; cycle++) {
          document = WordDeserializer().readBytes(
            WordSerializer().writeBytes(document),
          );
          expect(
            acceptance.inspect(
              document,
              preset,
            )['ownershipAndUnknownMetadataPreserved'],
            isTrue,
          );
          document = await OdtDocumentReader.readBytes(
            OdtDocumentWriter.writeEditableZoteroBytes(document),
          );
          expect(
            acceptance.inspect(
              document,
              preset,
            )['ownershipAndUnknownMetadataPreserved'],
            isTrue,
          );
        }
        expect(
          sha256.convert(File('$directory/$name').readAsBytesSync()).toString(),
          entry['sha256'],
        );
      },
    );
  }
}
