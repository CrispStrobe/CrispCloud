// Run the app's actual controller dependency through import, commands, history
// and asynchronous export. ZIP/XML assertions are independent of Quds readers.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:xml/xml.dart' as xml;

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _fixture =
    'packages/quds_office_engine/test/fixtures/fidelity/word-compatibility.docx';

Map<String, Uint8List> _parts(Uint8List bytes) => {
  for (final file in ZipDecoder().decodeBytes(bytes).files)
    if (file.isFile) file.name: Uint8List.fromList(file.content),
};

xml.XmlDocument _xml(Map<String, Uint8List> parts, String name) =>
    xml.XmlDocument.parse(utf8.decode(parts[name]!));

List<xml.XmlElement> _sections(Map<String, Uint8List> parts) {
  final body = _xml(
    parts,
    'word/document.xml',
  ).findAllElements('body', namespace: _w).single;
  return [
    for (final child in body.childElements)
      if (child.name.local == 'sectPr')
        child
      else if (child.name.local == 'p')
        ...child
            .findElements('pPr', namespace: _w)
            .expand(
              (properties) => properties.findElements('sectPr', namespace: _w),
            ),
  ];
}

String? _attribute(xml.XmlElement section, String element, String name) =>
    section
        .findElements(element, namespace: _w)
        .single
        .getAttribute(name, namespace: _w);

xml.XmlDocument _story(
  Map<String, Uint8List> parts,
  xml.XmlElement section,
  String kind,
  String type,
) {
  final reference = section
      .findElements('${kind}Reference', namespace: _w)
      .singleWhere((item) => item.getAttribute('type', namespace: _w) == type);
  final id = reference.getAttribute('id', namespace: _r);
  final relationship = _xml(parts, 'word/_rels/document.xml.rels')
      .findAllElements('Relationship', namespace: '*')
      .singleWhere((item) => item.getAttribute('Id') == id);
  expect(relationship.getAttribute('Type'), '$_r/$kind');
  final target = relationship.getAttribute('Target')!;
  final name = path.posix.normalize(
    target.startsWith('/')
        ? target.substring(1)
        : path.posix.join('word', target),
  );
  expect(parts, contains(name));
  return _xml(parts, name);
}

String _tokens(xml.XmlNode node) {
  final result = StringBuffer();
  for (final element in node.findAllElements('*', namespace: _w)) {
    switch (element.name.local) {
      case 't':
        expect(element.innerText, isNot(matches(RegExp(r'[\r\n\t]'))));
        result.write(element.innerText);
      case 'tab':
        result.write('\t');
      case 'br':
      case 'cr':
        result.write('\n');
    }
  }
  return result.toString();
}

Uint8List _fixtureWithAllStories() {
  // Extend the independently authored fixture with explicit first/even footer
  // and even header parts. No engine serializer authors the input or goldens.
  final parts = _parts(File(_fixture).readAsBytesSync());
  var document = utf8.decode(parts['word/document.xml']!);
  var rels = utf8.decode(parts['word/_rels/document.xml.rels']!);
  var types = utf8.decode(parts['[Content_Types].xml']!);
  final references = StringBuffer();
  for (final story in [
    (kind: 'header', type: 'even', text: 'Even header retained'),
    (kind: 'footer', type: 'default', text: 'Default footer retained'),
    (kind: 'footer', type: 'first', text: 'First footer retained'),
    (kind: 'footer', type: 'even', text: 'Even footer retained'),
  ]) {
    final id = 'host-${story.kind}-${story.type}';
    final name = '$id.xml';
    final root = story.kind == 'header' ? 'hdr' : 'ftr';
    references.write(
      '<w:${story.kind}Reference w:type="${story.type}" r:id="$id"/>',
    );
    rels = rels.replaceFirst(
      '</Relationships>',
      '<Relationship Id="$id" Type="$_r/${story.kind}" Target="$name"/></Relationships>',
    );
    types = types.replaceFirst(
      '</Types>',
      '<Override PartName="/word/$name" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.${story.kind}+xml"/></Types>',
    );
    parts['word/$name'] = Uint8List.fromList(
      utf8.encode(
        '<w:$root xmlns:w="$_w"><w:p><w:r><w:t>${story.text}</w:t></w:r></w:p></w:$root>',
      ),
    );
  }
  document = document.replaceFirst(
    '<w:footnotePr>',
    '$references<w:footnotePr>',
  );
  rels = rels.replaceFirst(
    '</Relationships>',
    '<Relationship Id="host-settings" Type="$_r/settings" Target="host-settings.xml"/></Relationships>',
  );
  types = types.replaceFirst(
    '</Types>',
    '<Override PartName="/word/host-settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>',
  );
  parts['word/host-settings.xml'] = Uint8List.fromList(
    utf8.encode(
      '<w:settings xmlns:w="$_w"><w:evenAndOddHeaders/></w:settings>',
    ),
  );
  parts['word/document.xml'] = Uint8List.fromList(utf8.encode(document));
  parts['word/_rels/document.xml.rels'] = Uint8List.fromList(utf8.encode(rels));
  parts['[Content_Types].xml'] = Uint8List.fromList(utf8.encode(types));
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, part.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

WordEditorController _open(Uint8List bytes) {
  final controller = WordEditorController.fromBytes(bytes);
  addTearDown(controller.dispose);
  return controller;
}

List<String> _paragraphs(WordEditorController controller) => [
  for (final paragraph in controller.document.paragraphs) paragraph.text,
];

void _saveArtifact(String name, Uint8List bytes) {
  final file = File('build/fidelity-host/$name.docx');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('section break commands retain imported settings and all stories through history and async saves', () async {
    var controller = _open(_fixtureWithAllStories());
    expect(controller.document.sections, hasLength(2));
    final original = controller.document.sections.first;
    final body = _paragraphs(controller);
    expect(original.differentOddEven, isTrue);
    expect(original.firstHeader.single.text, 'First page header retained');
    expect(original.evenHeader.single.text, 'Even header retained');
    controller.caret
      ..paragraphIndex = 0
      ..logicalIndex = body.first.length
      ..collapseSelection();
    controller.insertSectionBreak(kind: WmlSectionBreakKind.nextPage);
    expect(controller.document.sections, hasLength(3));
    expect(_paragraphs(controller), body);
    final inserted = controller.document.sections[1];
    expect(
      inserted.firstHeader.single,
      isNot(same(original.firstHeader.single)),
    );
    expect(inserted.evenHeader.single, isNot(same(original.evenHeader.single)));
    expect(
      inserted.firstFooter.single,
      isNot(same(original.firstFooter.single)),
    );
    expect(inserted.evenFooter.single, isNot(same(original.evenFooter.single)));
    expect(inserted.lineNumbers, isTrue);
    expect(inserted.linkToPrevious, original.linkToPrevious);
    expect(controller.isDirty, isTrue);
    controller.undo();
    expect(controller.document.sections, hasLength(2));
    expect(_paragraphs(controller), body);
    controller.redo();
    expect(controller.document.sections, hasLength(3));
    expect(_paragraphs(controller), body);

    String? insertedHistoryId;
    for (var cycle = 1; cycle <= 3; cycle++) {
      final bytes = await controller.saveBytesAsync();
      _saveArtifact('sections-$cycle', bytes);
      final parts = _parts(bytes);
      final sections = _sections(parts);
      expect(sections, hasLength(3));
      expect(
        [for (final s in sections) _attribute(s, 'pgNumType', 'start')],
        ['17', '17', '31'],
      );
      expect(
        [for (final s in sections) _attribute(s, 'docGrid', 'linePitch')],
        ['360', '360', '400'],
      );
      expect(
        [for (final s in sections) _attribute(s, 'pgMar', 'gutter')],
        ['240', '240', '120'],
      );
      expect(_attribute(sections[1], 'type', 'val'), 'nextPage');
      final histories = [
        for (final section in sections.take(2))
          section.findElements('sectPrChange', namespace: _w).single,
      ];
      final historyIds = [
        for (final history in histories)
          history.getAttribute('id', namespace: _w),
      ];
      expect(historyIds.first, '7');
      expect(
        historyIds.toSet(),
        hasLength(2),
        reason:
            'A cloned section must retain history with a unique revision ID.',
      );
      insertedHistoryId ??= historyIds[1];
      expect(historyIds[1], insertedHistoryId);
      for (final history in histories) {
        expect(
          _attribute(
            history.findElements('sectPr', namespace: _w).single,
            'pgNumType',
            'start',
          ),
          '99',
        );
      }
      for (final section in sections.take(2)) {
        expect(_attribute(section, 'lnNumType', 'countBy'), '5');
        expect(_attribute(section, 'lnNumType', 'restart'), 'newSection');
        expect(
          _tokens(_story(parts, section, 'header', 'default')),
          'Selected header fallback',
        );
        expect(
          _tokens(_story(parts, section, 'header', 'first')),
          'First page header retained',
        );
        expect(
          _tokens(_story(parts, section, 'header', 'even')),
          'Even header retained',
        );
        expect(
          _tokens(_story(parts, section, 'footer', 'default')),
          'Default footer retained',
        );
        expect(
          _tokens(_story(parts, section, 'footer', 'first')),
          'First footer retained',
        );
        expect(
          _tokens(_story(parts, section, 'footer', 'even')),
          'Even footer retained',
        );
      }
      controller = _open(bytes);
      expect(_paragraphs(controller), body);
      expect(controller.document.sections[1].differentFirstPage, isTrue);
      expect(controller.document.sections[1].differentOddEven, isTrue);
    }
  });

  test('body header and note text commands emit real breaks and tabs after undo redo and async reopen', () async {
    var controller = _open(File(_fixture).readAsBytesSync());
    final originalBody = controller.document.paragraphs.first.text;
    controller.jumpToParagraph(0);
    controller.selectParagraphAtCaret();
    controller.insertText('First\tcolumn\r\nSecond\rThird\n');
    controller.undo();
    expect(controller.document.paragraphs.first.text, originalBody);
    controller.redo();
    expect(
      controller.document.paragraphs.first.text,
      'First\tcolumn\r\nSecond\rThird\n',
    );

    controller.beginHeaderFooterEdit(0, footer: false);
    controller.insertText('Header\tstart\nnext\n');
    controller.undo();
    expect(
      controller.document.sections.first.header.single.text,
      'Selected header fallback',
    );
    controller.redo();
    controller.endHeaderFooterEdit();
    controller.jumpToParagraph(0);
    controller.caret
      ..logicalIndex = controller.document.paragraphs.first.text.length
      ..collapseSelection();
    controller.insertFootnote(text: 'Note one\r\nNote two\tend');
    expect(controller.document.footnotes.last.id, 4);
    controller.undo();
    expect(controller.document.footnotes, hasLength(1));
    controller.redo();
    expect(controller.document.footnotes, hasLength(2));

    for (var cycle = 1; cycle <= 3; cycle++) {
      final bytes = await controller.saveBytesAsync();
      _saveArtifact('text-breaks-$cycle', bytes);
      final parts = _parts(bytes);
      final first = _xml(parts, 'word/document.xml')
          .findAllElements('body', namespace: _w)
          .single
          .findElements('p', namespace: _w)
          .first;
      expect(_tokens(first), 'First\tcolumn\nSecond\nThird\n');
      expect(first.findAllElements('br', namespace: _w), hasLength(3));
      expect(first.findAllElements('tab', namespace: _w), hasLength(1));
      expect(
        first
            .findAllElements('footnoteReference', namespace: _w)
            .single
            .getAttribute('id', namespace: _w),
        '4',
      );
      final header = _story(parts, _sections(parts).first, 'header', 'default');
      expect(_tokens(header), 'Header\tstart\nnext\nSelected header fallback');
      expect(header.findAllElements('br', namespace: _w), hasLength(2));
      final notes = _xml(parts, 'word/footnotes.xml');
      final note = notes
          .findAllElements('footnote', namespace: _w)
          .singleWhere((item) => item.getAttribute('id', namespace: _w) == '4');
      expect(_tokens(note).trimLeft(), 'Note one\nNote two\tend');
      expect(note.findAllElements('br', namespace: _w), hasLength(1));
      expect(note.findAllElements('tab', namespace: _w), hasLength(1));
      controller = _open(bytes);
      expect(
        controller.document.paragraphs.first.text,
        'First\tcolumn\nSecond\nThird\n4',
      );
      expect(
        controller.document.footnotes.last.text,
        'Note one\nNote two\tend',
      );
    }
  });
}
