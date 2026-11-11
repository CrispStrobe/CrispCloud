import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

List<String> _footnoteTexts(Uint8List bytes) {
  final Map<String, Uint8List> parts = _parts(bytes);
  final String xmlText = utf8.decode(parts['word/footnotes.xml']!);
  final xml.XmlDocument doc = xml.XmlDocument.parse(xmlText);
  return doc.descendants
      .whereType<xml.XmlElement>()
      .where((xml.XmlElement e) => e.name.local == 'footnote')
      .where(
        (xml.XmlElement e) =>
            !e.attributes.any((xml.XmlAttribute a) => a.name.local == 'type'),
      )
      .map(
        (xml.XmlElement e) => e.descendants
            .whereType<xml.XmlElement>()
            .where((xml.XmlElement t) => t.name.local == 't')
            .map((xml.XmlElement t) => t.innerText)
            .join(),
      )
      .where((String text) => text.isNotEmpty)
      .toList();
}

List<int> _footnoteIdsByType(Uint8List bytes, String type) {
  final xmlText = utf8.decode(_parts(bytes)['word/footnotes.xml']!);
  final doc = xml.XmlDocument.parse(xmlText);
  return doc.descendants
      .whereType<xml.XmlElement>()
      .where(
        (e) =>
            e.name.local == 'footnote' &&
            e.attributes.any((a) => a.name.local == 'type' && a.value == type),
      )
      .map(
        (e) =>
            int.tryParse(
              e.attributes.firstWhere((a) => a.name.local == 'id').value,
            ) ??
            0,
      )
      .toList();
}

Map<String, Uint8List> _parts(Uint8List bytes) {
  final Archive archive = ZipDecoder().decodeBytes(bytes);
  return <String, Uint8List>{
    for (final ArchiveFile file in archive.files)
      if (file.isFile) file.name: Uint8List.fromList(file.content),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Quds preserves footnotes across an unedited save', () {
    final Uint8List original = File('test/fixtures/footnote.docx')
        .readAsBytesSync();
    final WordEditorController controller = WordEditorController.fromBytes(
      original,
    );
    addTearDown(controller.dispose);

    final Uint8List saved = controller.saveBytes();
    final Map<String, Uint8List> after = _parts(saved);

    expect(after.containsKey('word/footnotes.xml'), isTrue);
    expect(_footnoteTexts(saved), <String>[
      'First footnote text.',
      'Second footnote text.',
    ]);
    expect(_footnoteTexts(original), _footnoteTexts(saved));
    expect(_footnoteIdsByType(saved, 'separator'), contains(-1));
    expect(_footnoteIdsByType(saved, 'continuationSeparator'), contains(0));
    final footnotesXml = utf8.decode(_parts(saved)['word/footnotes.xml']!);
    final notes = xml.XmlDocument.parse(footnotesXml)
        .findAllElements(
          'footnote',
          namespace:
              'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        )
        .where(
          (note) => !note.attributes.any(
            (attribute) => attribute.name.local == 'type',
          ),
        );
    for (final note in notes) {
      expect(
        note.findAllElements(
          'footnoteRef',
          namespace:
              'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        ),
        hasLength(1),
      );
    }
    // Compare the untrimmed text above: an imported note must not acquire an
    // invented separator run or lose authored leading/trailing whitespace.

    final WordEditorController reopened = WordEditorController.fromBytes(saved);
    addTearDown(reopened.dispose);
    expect(reopened.document.footnotes.length, 2);
    expect(reopened.document.footnotes.first.text, 'First footnote text.');
  });

  test('Quds preserves footnotes across a minimal edit', () {
    final Uint8List original = File('test/fixtures/footnote.docx')
        .readAsBytesSync();
    final WordEditorController controller = WordEditorController.fromBytes(
      original,
    );
    addTearDown(controller.dispose);

    controller.insertText('X');
    final Uint8List saved = controller.saveBytes();
    expect(_footnoteTexts(original), _footnoteTexts(saved));

    final WordEditorController reopened = WordEditorController.fromBytes(saved);
    addTearDown(reopened.dispose);
    expect(reopened.document.footnotes.length, 2);
    expect(reopened.document.paragraphs.first.text, startsWith('X'));
  });
}
