import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/office_steps.dart' as cli;

Iterable<XmlElement> _descendants(XmlElement root, String localName) sync* {
  if (root.namespaceUri == OfficeNamespaces.w && root.localName == localName) {
    yield root;
  }
  for (final child in root.childElements) {
    yield* _descendants(child, localName);
  }
}

void _nativeShape(
  OpcPackage package,
  int id, {
  required bool endnote,
  required bool marked,
}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final root = XmlDocument.parse(
    package.getPart('/word/${kind}s.xml')!.readText(),
  ).root!;
  final note = root.childElements.singleWhere(
    (element) =>
        element.localName == kind &&
        element.getAttribute('id', namespaceUri: OfficeNamespaces.w) == '$id',
  );
  expect(
    _descendants(note, 'p'),
    hasLength(1),
    reason: 'A whole-note replacement remains one paragraph',
  );
  expect(
    _descendants(note, 'br'),
    hasLength(1),
    reason: 'The newline is a native hard break',
  );
  expect(_descendants(note, '${kind}Ref'), hasLength(marked ? 1 : 0));
}

void _cycles(
  WmlDocument document,
  int id, {
  required bool endnote,
  required bool marked,
}) {
  var doc = document;
  for (var cycle = 0; cycle < 3; cycle++) {
    final note = WordNotes.byId(doc, id, endnote: endnote)!;
    expect(note.blocks, hasLength(1));
    expect(note.text, 'First line\nSecond line');
    final package = WordSerializer().write(doc);
    _nativeShape(package, id, endnote: endnote, marked: marked);
    doc = WordDeserializer().readBytes(package.save());
  }
}

void main() {
  test(
    'scripted whole-note replacement keeps one paragraph and native hard break for imported rich notes',
    () {
      final doc = WordDeserializer().readBytes(
        File('test/fixtures/fidelity/word.docx').readAsBytesSync(),
      );
      final note = WordNotes.byId(doc, 12, endnote: false)!;
      expect(note.paragraphs, hasLength(2));
      expect(
        note.paragraphs.last.inlines.whereType<WmlRun>().any(
          (run) => run.hyperlink != null,
        ),
        isTrue,
      );
      cli.applyStep(doc, {
        'op': 'editNote',
        'id': 12,
        'text': 'First line\nSecond line',
      });
      _cycles(doc, 12, endnote: false, marked: true);
    },
  );

  for (final endnote in [false, true]) {
    test(
      '${endnote ? 'endnote' : 'footnote'} whole-note replacement keeps its automatic mark through three hard-break exports',
      () {
        final doc = WmlDocument.empty(text: 'Body');
        cli.applyStep(doc, {
          'op': 'addNote',
          'paragraph': 0,
          'endnote': endnote,
          'text': 'Initial note',
        });
        final id = (endnote ? doc.endnotes : doc.footnotes).single.id;
        cli.applyStep(doc, {
          'op': 'editNote',
          'id': id,
          'endnote': endnote,
          'text': 'First line\nSecond line',
        });
        _cycles(doc, id, endnote: endnote, marked: true);
      },
    );
  }

  test(
    'whole-note hard-break replacement preserves imported marker absence',
    () {
      final doc = WmlDocument(
        footnotes: [
          WmlNote(
            id: 9,
            endnote: false,
            addReference: false,
            paragraphs: [
              WmlParagraph(inlines: [WmlRun(text: 'Original first paragraph')]),
              WmlParagraph(
                inlines: [WmlRun(text: 'Original second paragraph')],
              ),
            ],
          ),
        ],
      );
      cli.applyStep(doc, {
        'op': 'editNote',
        'id': 9,
        'text': 'First line\nSecond line',
      });
      _cycles(doc, 9, endnote: false, marked: false);
    },
  );
}
