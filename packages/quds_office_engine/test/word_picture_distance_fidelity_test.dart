import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _distances = ['distT', 'distB', 'distL', 'distR'];

List<XmlElement> _containers(XmlElement root) => [
  for (final child in root.childElements) ...[
    if (child.localName == 'inline' || child.localName == 'anchor') child,
    ..._containers(child),
  ],
];

XmlDocument _main(OpcPackage package) =>
    XmlDocument.parse(package.getPart('/word/document.xml')!.readText());

List<double> _modelDistances(OfficeVisual picture) => [
  picture.picture.wrapDistT,
  picture.picture.wrapDistB,
  picture.picture.wrapDistL,
  picture.picture.wrapDistR,
];

WmlDocument _importedDistances(List<int?> expected) {
  // Author source attributes directly rather than through the writer under test.
  final source = OpcPackage.openBytes(
    File('test/fixtures/fidelity/word.docx').readAsBytesSync(),
  );
  final xml = _main(source);
  final inline = _containers(xml.root!).single;
  for (var i = 0; i < _distances.length; i++) {
    inline.removeAttribute(_distances[i]);
    if (expected[i] != null) {
      inline.setAttribute(_distances[i], '${expected[i]}');
    }
  }
  source.getPart('/word/document.xml')!.writeText(xml.toXmlString());
  return WordDeserializer().read(source);
}

List<int?> _savedDistances(XmlElement container) => [
  for (final name in _distances)
    int.tryParse(container.getAttribute(name) ?? ''),
];

void main() {
  final cases = <String, List<int?>>{
    'omitted': [null, null, null, null],
    'explicit zero': [0, 0, 0, 0],
    'below eight points': [1, 9525, 25400, 95250],
    'mixed existing values': [0, 12700, 114300, 254000],
    'mixed omitted and explicit values': [0, null, 9525, null],
  };
  for (final entry in cases.entries) {
    test(
      'imported inline ${entry.key} distances remain exact for three cycles',
      () async {
        final expected = entry.value;
        var document = _importedDistances(expected);
        for (var cycle = 0; cycle < 3; cycle++) {
          final distances = _modelDistances(document.visuals.single.visual);
          for (var i = 0; i < 4; i++) {
            expect(distances[i], closeTo((expected[i] ?? 0) / 12700, 0.000001));
          }
          final bytes = await OfficeIsolateSave.word(document);
          final saved = _containers(
            _main(OpcPackage.openBytes(bytes)).root!,
          ).single;
          expect(saved.localName, 'inline');
          expect(_savedDistances(saved), expected);
          document = WordDeserializer().readBytes(bytes);
        }
      },
    );
  }

  test(
    'cloned omissions remain absent while deliberate zero and small edits emit',
    () async {
      var document = _importedDistances([null, null, null, null]);
      final clone = WmlClone.visual(document.visuals.single);
      clone.visual.picture
        ..wrapDistL = 0
        ..wrapDistR = 2;
      document.sections.first.blocks.add(clone);
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        final containers = _containers(
          _main(OpcPackage.openBytes(bytes)).root!,
        );
        expect(containers, hasLength(2));
        expect(_savedDistances(containers.first), [null, null, null, null]);
        expect(_savedDistances(containers.last), [null, null, 0, 25400]);
        document = WordDeserializer().readBytes(bytes);
      }
    },
  );

  test(
    'clearing explicit nonzero distances writes zero and keeps other omissions',
    () async {
      var document = _importedDistances([12700, null, 9525, null]);
      document.visuals.single.visual.picture
        ..wrapDistT = 0
        ..wrapDistL = 0;
      for (var cycle = 0; cycle < 3; cycle++) {
        final bytes = await OfficeIsolateSave.word(document);
        expect(
          _savedDistances(
            _containers(_main(OpcPackage.openBytes(bytes)).root!).single,
          ),
          [0, null, 0, null],
        );
        document = WordDeserializer().readBytes(bytes);
      }
    },
  );

  for (final floating in [false, true]) {
    test(
      'new picture distances use model values, floating=$floating',
      () async {
        final adjustment = floating
            ? PictureAdjust(
                wrap: PictureWrap.square,
                wrapDistT: 0,
                wrapDistB: 1,
                wrapDistL: 2,
                wrapDistR: 3.5,
              )
            : PictureAdjust();
        final expected = floating
            ? [0, 12700, 25400, 44450]
            : [0, 0, 114300, 114300];
        var document = WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlVisual(
                  visual: OfficeVisual(
                    kind: OfficeVisualKind.picture,
                    title: 'New picture',
                    imageBytes: File(
                      'test/fixtures/fidelity/scripts/replacement.png',
                    ).readAsBytesSync(),
                    width: 36,
                    height: 18,
                    picture: adjustment,
                  ),
                ),
              ],
            ),
          ],
        );
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final container = _containers(
            _main(OpcPackage.openBytes(bytes)).root!,
          ).single;
          expect(container.localName, floating ? 'anchor' : 'inline');
          expect(
            _distances.map((name) => int.parse(container.getAttribute(name)!)),
            expected,
          );
          document = WordDeserializer().readBytes(bytes);
        }
      },
    );
  }
}
