import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _w = OfficeNamespaces.w;
const _extension = 'urn:macro-separator-integration';
const _noteText = 'Research evidence — résumé 😀.';
const _separator = WmlFootnoteSeparator(
  beforeSpacing: 3.25,
  thickness: 0.75,
  afterSpacing: 4.5,
  relativeWidth: 0.5,
  alignment: WmlFootnoteSeparatorAlignment.right,
  color: 0x9f2040,
);
const _paint = '''
If StrComp("Ready", "Ready", vbBinaryCompare) = 0 Then
  ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdGreen
End If
With ActiveDocument.Paragraphs(2).Range.Font
  .ColorIndex = wdBlue
  .Color = wdColorAutomatic
End With
ActiveDocument.Paragraphs(3).Range.Font.ColorIndex = wdAuto
''';

OfficeMacro _compile(String body) => OfficeMacroLanguages().compile(
  OfficeMacroSource(
    language: 'vba-word',
    format: OfficeMacroFormat.docx,
    moduleName: 'ColorsWithFootnoteSeparator',
    source: 'Sub Main()\n$body\nEnd Sub',
  ),
);

XmlElement _root(OpcPackage package, String path) =>
    XmlDocument.parse(package.getPart(path)!.readText()).root!;

Uint8List _input() {
  final document = WmlDocument(
    footnoteSeparator: _separator,
    sections: [
      WmlSection(
        pageSize: const WmlPageSize(width: 600, height: 840),
        margins: const WmlPageMargins(top: 72, bottom: 72, left: 72, right: 72),
        blocks: [
          for (final text in [
            'Ready for review',
            'Automatic packed color',
            'Automatic palette color',
            'Evidence cited here ',
          ])
            WmlParagraph(
              inlines: [
                WmlRun(
                  text: text,
                  properties: WmlRunProps(color: '2468AC', italic: true),
                ),
              ],
            ),
        ],
      ),
    ],
  );
  WordNotes.insert(
    document,
    document.paragraphs.last,
    endnote: false,
    text: _noteText,
  );
  final package = WordSerializer().write(document);

  // Imported special-note IDs need not be the conventional -1 and 0.
  for (final (path, parentName) in [
    ('/word/footnotes.xml', 'footnotes'),
    ('/word/settings.xml', 'footnotePr'),
  ]) {
    final xml = XmlDocument.parse(package.getPart(path)!.readText());
    final parent = parentName == 'footnotes'
        ? xml.root!
        : xml.root!.firstChild(parentName, namespaceUri: _w)!;
    for (final node in parent.childrenNamed('footnote', namespaceUri: _w)) {
      final id = node.getAttribute('id', namespaceUri: _w);
      if (id == '-1' || id == '0') {
        node.setAttribute(
          'id',
          id == '-1' ? '17' : '23',
          prefix: 'w',
          namespaceUri: _w,
        );
      }
    }
    package.getPart(path)!.writeText(xml.toXmlString());
  }
  final main = package.getPart('/word/document.xml')!;
  final xml = XmlDocument.parse(main.readText());
  final color = xml.root!
      .firstChild('body', namespaceUri: _w)!
      .childrenNamed('p', namespaceUri: _w)
      .first
      .firstChild('r', namespaceUri: _w)!
      .firstChild('rPr', namespaceUri: _w)!
      .firstChild('color', namespaceUri: _w)!;
  color
    ..setAttribute('themeColor', 'accent2', prefix: 'w', namespaceUri: _w)
    ..setAttribute('themeTint', '44', prefix: 'w', namespaceUri: _w)
    ..setAttribute('x', _extension, prefix: 'xmlns')
    ..setAttribute('token', 'retained', prefix: 'x', namespaceUri: _extension);
  main.writeText(xml.toXmlString());
  return package.save();
}

void _expectNotes(Uint8List bytes) {
  final document = WordDeserializer().readBytes(bytes);
  expect(document.footnoteSeparator, _separator);
  expect(document.footnotes.single.id, 1);
  expect(document.footnotes.single.text, _noteText);
  expect(document.endnotes, isEmpty);
  expect(
    document.paragraphs.last.inlines
        .whereType<WmlRun>()
        .where((run) => run.noteRefId != null)
        .map((run) => (run.noteRefId, run.noteRefEndnote)),
    [(1, false)],
  );
  final package = OpcPackage.openBytes(bytes);
  final special = _root(package, '/word/footnotes.xml')
      .childrenNamed('footnote', namespaceUri: _w)
      .where((note) => note.getAttribute('type', namespaceUri: _w) != null);
  expect(
    special.map(
      (note) => (
        note.getAttribute('type', namespaceUri: _w),
        note.getAttribute('id', namespaceUri: _w),
      ),
    ),
    [('separator', '17'), ('continuationSeparator', '23')],
  );
  expect(
    _root(package, '/word/settings.xml')
        .firstChild('footnotePr', namespaceUri: _w)!
        .childrenNamed('footnote', namespaceUri: _w)
        .map((note) => note.getAttribute('id', namespaceUri: _w)),
    ['17', '23'],
  );
}

void _expectColors(Uint8List bytes) {
  final package = OpcPackage.openBytes(bytes);
  final paragraphs = _root(package, '/word/document.xml')
      .firstChild('body', namespaceUri: _w)!
      .childrenNamed('p', namespaceUri: _w)
      .take(3);
  final colors = [
    for (final paragraph in paragraphs)
      paragraph
          .firstChild('r', namespaceUri: _w)!
          .firstChild('rPr', namespaceUri: _w)!
          .firstChild('color', namespaceUri: _w)!,
  ];
  expect(colors.map((color) => color.getAttribute('val', namespaceUri: _w)), [
    '008000',
    'auto',
    'auto',
  ]);
  expect(
    colors.first.getAttribute('token', namespaceUri: _extension),
    'retained',
  );
  for (final color in colors) {
    expect(color.getAttribute('themeColor', namespaceUri: _w), isNull);
    expect(color.getAttribute('themeTint', namespaceUri: _w), isNull);
  }
}

void main() {
  test(
    'palette and both automatic colors preserve active separators across two native reopens',
    () async {
      final input = _input();
      _expectNotes(input);
      final session = OfficeMacroSession(input, format: OfficeMacroFormat.docx);
      final plan = _compile(_paint);
      await session.validate(plan);
      expect(session.bytes, input);
      expect(session.revision, 0);
      await session.run(plan);
      expect(session.revision, 1);
      var bytes = session.bytes;
      _expectColors(bytes);
      _expectNotes(bytes);
      for (var cycle = 0; cycle < 2; cycle++) {
        bytes = WordSerializer().writeBytes(
          WordDeserializer().readBytes(bytes),
        );
        _expectColors(bytes);
        _expectNotes(bytes);
      }
    },
  );

  test(
    'late macro failure rolls back colors and active separator state',
    () async {
      final session = OfficeMacroSession(
        _input(),
        format: OfficeMacroFormat.docx,
      );
      await session.run(_compile(_paint));
      final before = Uint8List.fromList(session.bytes);
      session.startRecording('Refused color and separator edit');
      final refused = _compile('''
ActiveDocument.Paragraphs(1).Range.Font.ColorIndex = wdRed
ActiveDocument.Paragraphs(2).Range.Font.ColorIndex = wdBlue
ActiveDocument.Paragraphs(99).Range.Font.Color = wdColorAutomatic
''');
      for (final action in [session.validate, session.run]) {
        await expectLater(
          action(refused),
          throwsA(
            isA<OfficeMacroException>().having(
              (error) => error.stepIndex,
              'failed step',
              2,
            ),
          ),
        );
        expect(session.bytes, before);
        expect(session.revision, 1);
        _expectColors(session.bytes);
        _expectNotes(session.bytes);
      }
      expect(session.stopRecording().steps, isEmpty);
    },
  );
}
