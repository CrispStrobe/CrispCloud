import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/note_fixture.dart';

String _noteText(OpcPackage package, bool endnote, int id) {
  final kind = endnote ? 'endnote' : 'footnote';
  final root = XmlDocument.parse(
    package.getPart('/word/${kind}s.xml')!.readText(),
  ).root!;
  final paragraph = root
      .childrenNamed(kind)
      .firstWhere((node) => node.getAttribute('id') == '$id')
      .firstChild('p')!;
  final text = StringBuffer();
  void visit(XmlElement node) {
    if (node.localName == 't') {
      text.write(node.text);
    } else if (node.localName == 'tab') {
      text.write('\t');
    } else {
      for (final child in node.childElements) {
        visit(child);
      }
    }
  }

  visit(paragraph);
  return text.toString();
}

void main() {
  for (final endnote in [false, true]) {
    for (final whitespace in ['', ' ', '  ', '\t']) {
      test(
        'imported note spacing remains exact: endnote=$endnote prefix=${whitespace.codeUnits}',
        () async {
          final package = richNoteFixture().package!;
          final kind = endnote ? 'endnote' : 'footnote';
          final id = endnote ? 3 : 12;
          package.getPart('/word/${kind}s.xml')!.writeText('''
<w:${kind}s xmlns:w="${OfficeNamespaces.w}"><w:$kind w:id="$id">
<w:p><w:r><w:${kind}Ref/></w:r><w:r><w:t xml:space="preserve">${whitespace}Rich note</w:t></w:r></w:p>
</w:$kind></w:${kind}s>''');
          var document = WordDeserializer().read(package);
          for (var cycle = 0; cycle < 3; cycle++) {
            final bytes = await OfficeIsolateSave.word(document);
            expect(
              _noteText(OpcPackage.openBytes(bytes), endnote, id),
              '${whitespace}Rich note',
            );
            document = WordDeserializer().readBytes(bytes);
            final note = (endnote ? document.endnotes : document.footnotes)
                .firstWhere((note) => note.id == id);
            expect(note.paragraphs.first.text, '${whitespace}Rich note');
          }
        },
      );
    }
    test(
      'new note gets exactly one reference separator: endnote=$endnote',
      () async {
        var document = WmlDocument.empty(text: 'Body');
        final note = WordNotes.insert(
          document,
          document.paragraphs.first,
          endnote: endnote,
          text: 'New note',
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          expect(
            _noteText(OpcPackage.openBytes(bytes), endnote, note.id),
            ' New note',
          );
          document = WordDeserializer().readBytes(bytes);
        }
      },
    );
  }
}
