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

List<String> _noteMarkerPositions(Uint8List bytes) {
  final document = xml.XmlDocument.parse(
    utf8.decode(_parts(bytes)['word/footnotes.xml']!),
  );
  final positions = <String>[];
  for (final note in document.findAllElements(
    'footnote',
    namespace: 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
  )) {
    final id = note.attributes.firstWhere((a) => a.name.local == 'id').value;
    var paragraphIndex = 0;
    for (final paragraph in note.findAllElements(
      'p',
      namespace: 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    )) {
      var offset = 0;
      for (final element in paragraph.descendants.whereType<xml.XmlElement>()) {
        if (element.name.local == 't') offset += element.innerText.length;
        if (element.name.local == 'tab' || element.name.local == 'br') offset++;
        if (element.name.local == 'footnoteRef') {
          final properties = (element.parent as xml.XmlElement).findElements(
            'rPr',
            namespace:
                'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
          );
          final alignment = properties.expand(
            (p) => p.findElements(
              'vertAlign',
              namespace: 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
            ),
          );
          final value = alignment.isEmpty
              ? ''
              : alignment.single.attributes
                    .firstWhere((a) => a.name.local == 'val')
                    .value;
          positions.add('$id:$paragraphIndex:$offset:$value');
        }
      }
      paragraphIndex++;
    }
  }
  return positions;
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
    // This authored fixture deliberately has no automatic marks inside the
    // note stories. Preserve that absence instead of inventing one on save.
    expect(_noteMarkerPositions(original), isEmpty);
    expect(_noteMarkerPositions(saved), _noteMarkerPositions(original));
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

  test('host preserves source note marker position and formatting through three saves', () {
    final package = OpcPackage.openBytes(
      File('test/fixtures/footnote.docx').readAsBytesSync(),
    );
    final part = package.getPart('/word/footnotes.xml')!;
    part.writeText(
      part.readText().replaceFirst(
        '<w:p><w:r><w:t>First footnote text.</w:t></w:r></w:p>',
        '<w:p><w:r><w:t xml:space="preserve">Before </w:t></w:r>'
            '<w:r><w:rPr><w:vertAlign w:val="superscript"/></w:rPr><w:footnoteRef/></w:r>'
            '<w:r><w:t>First footnote text.</w:t></w:r></w:p>',
      ),
    );
    var bytes = package.save();
    final expected = _noteMarkerPositions(bytes);
    expect(expected, ['1:0:7:superscript']);
    for (var cycle = 0; cycle < 3; cycle++) {
      final controller = WordEditorController.fromBytes(bytes);
      addTearDown(controller.dispose);
      controller.insertText('X');
      bytes = controller.saveBytes();
      expect(_noteMarkerPositions(bytes), expected);
      expect(_footnoteTexts(bytes), [
        'Before First footnote text.',
        'Second footnote text.',
      ]);
      final note = controller.documentLaidOut.pages
          .expand((page) => page.notes)
          .first;
      expect(note.text, 'Before 1First footnote text.');
    }
  });
}
