import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const String _fixture = 'test/fixtures/fidelity/story-media.docx';
const List<String> _storyKinds = <String>[
  'default header',
  'default footer',
  'first header',
  'first footer',
  'even header',
  'even footer',
];

Iterable<XmlElement> _descendants(XmlElement root, String localName) sync* {
  for (final XmlElement child in root.childElements) {
    if (child.localName == localName) yield child;
    yield* _descendants(child, localName);
  }
}

String _mainUri(OpcPackage package) => package.packageRelationships.resolve(
  package.packageRelationships.firstByType(RelationshipTypes.officeDocument)!,
);

Map<String, String> _storyUris(OpcPackage package) {
  final String main = _mainUri(package);
  final XmlElement root = XmlDocument.parse(
    package.getPart(main)!.readText(),
  ).root!;
  final RelationshipCollection rels = package.relationshipsFor(main);
  return <String, String>{
    for (final XmlElement node in _descendants(
      root,
      'sectPr',
    ).single.childElements)
      if (node.localName == 'headerReference' ||
          node.localName == 'footerReference')
        '${node.getAttribute('type')} ${node.localName.replaceAll('Reference', '')}':
            rels.resolve(
              rels.byId(
                node.getAttribute('id', namespaceUri: OfficeNamespaces.r)!,
              )!,
            ),
  };
}

List<PackagePart> _pictures(OpcPackage package, String uri) {
  final XmlElement root = XmlDocument.parse(
    package.getPart(uri)!.readText(),
  ).root!;
  final RelationshipCollection rels = package.relationshipsFor(uri);
  return <PackagePart>[
    for (final XmlElement node in _descendants(root, 'blip'))
      package.getPart(
        rels.resolve(
          rels.byId(
            node.getAttribute('embed', namespaceUri: OfficeNamespaces.r)!,
          )!,
        ),
      )!,
  ];
}

List<List<WmlVisual>> _visuals(WmlSection section) => <List<WmlVisual>>[
  section.headerVisuals,
  section.footerVisuals,
  section.firstHeaderVisuals,
  section.firstFooterVisuals,
  section.evenHeaderVisuals,
  section.evenFooterVisuals,
];

void main() {
  test(
    'all six stories retain owned media over three asynchronous save cycles',
    () async {
      final Uint8List source = File(_fixture).readAsBytesSync();
      final OpcPackage original = OpcPackage.openBytes(source);
      final Map<String, String> sourceUris = _storyUris(original);
      final Map<String, Uint8List> expected = <String, Uint8List>{
        for (final String kind in _storyKinds)
          kind: _pictures(original, sourceUris[kind]!).single.readBytes(),
      };
      for (final bool edited in <bool>[false, true]) {
        WmlDocument document = WordDeserializer().readBytes(source);
        expect(
          _visuals(
            document.sections.single,
          ).map((List<WmlVisual> v) => v.length),
          everyElement(1),
        );
        if (edited) {
          document.visuals.first.visual
            ..imageBytes = original
                .getPart('/word/media/image2.png')!
                .readBytes()
            ..width = 81
            ..height = 45;
          document.sections.single.headerVisuals.single.visual
            ..imageBytes = original.getPart('/word/media/body.png')!.readBytes()
            ..width = 72;
          document.sections.single.footer.add(
            WmlParagraph(
              inlines: <WmlInline>[
                WmlRun(
                  text: 'Edited footer',
                  hyperlink: const WmlHyperlink(
                    url: 'https://example.test/footer',
                  ),
                ),
              ],
            ),
          );
        }
        int? mediaCount;
        for (int cycle = 1; cycle <= 3; cycle++) {
          final Uint8List bytes = await OfficeIsolateSave.word(document);
          final OpcPackage saved = OpcPackage.openBytes(bytes);
          final Map<String, String> stories = _storyUris(saved);
          expect(stories.keys, unorderedEquals(_storyKinds));
          for (final String kind in _storyKinds) {
            final String uri = stories[kind]!;
            expect(
              _pictures(saved, uri).single.readBytes(),
              edited && kind == 'default header'
                  ? original.getPart('/word/media/body.png')!.readBytes()
                  : expected[kind],
            );
            final XmlElement root = XmlDocument.parse(
              saved.getPart(uri)!.readText(),
            ).root!;
            // Drawing-only story paragraphs must not multiply on reopen.
            expect(
              root.childrenNamed('p').length,
              edited && kind == 'default footer' ? 2 : 1,
            );
            for (final XmlElement extent in _descendants(root, 'extent')) {
              expect(
                extent.getAttribute('cx'),
                edited && kind == 'default header' ? '914400' : '457200',
              );
              expect(extent.getAttribute('cy'), '228600');
            }
          }
          final String main = _mainUri(saved);
          final List<PackagePart> body = _pictures(saved, main);
          expect(body, hasLength(2));
          expect(
            body.first.readBytes(),
            original
                .getPart(
                  edited ? '/word/media/image2.png' : '/word/media/body.png',
                )!
                .readBytes(),
          );
          expect(
            body.last.readBytes(),
            original.getPart('/word/media/image2.png')!.readBytes(),
          );
          final RelationshipCollection mainRels = saved.relationshipsFor(main);
          final String notesUri = mainRels.resolve(
            mainRels.firstByType(RelationshipTypes.footnotes)!,
          );
          expect(
            _pictures(saved, notesUri).single.readBytes(),
            original.getPart('/word/media/note.png')!.readBytes(),
          );
          // An opaque consumer still refers to the original shared payload.
          expect(
            saved.getPart('/word/media/image1.png')!.readBytes(),
            original.getPart('/word/media/image1.png')!.readBytes(),
          );
          expect(
            saved.getPart('/customXml/consumer.xml')!.readBytes(),
            original.getPart('/customXml/consumer.xml')!.readBytes(),
          );
          final int count = saved.partNames
              .where((String p) => p.startsWith('/word/media/'))
              .length;
          mediaCount ??= count;
          expect(
            count,
            mediaCount,
            reason: 'unchanged subsequent saves must not accumulate media',
          );
          Directory('build/fidelity-story-media').createSync(recursive: true);
          File(
            'build/fidelity-story-media/story-${edited ? 'edited' : 'imported'}-$cycle.docx',
          ).writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
        }
      }
    },
  );

  test(
    'reordered and replaced media do not mutate retained chart and image parts',
    () async {
      final OpcPackage original = OpcPackage.openBytes(
        File(_fixture).readAsBytesSync(),
      );
      final WmlDocument document = WordDeserializer().read(original);
      final List<WmlBlock> blocks = document.sections.single.blocks;
      final WmlBlock firstPicture = blocks.removeAt(1);
      blocks.insert(2, firstPicture);
      blocks.add(
        WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartColumn,
            title: 'New body chart',
            points: <ChartPoint>[
              const ChartPoint(label: 'A', value: 2),
              const ChartPoint(label: 'B', value: 7),
            ],
          ),
        ),
      );
      document.sections.single.firstHeaderVisuals.add(
        WmlVisual(
          visual: OfficeVisual(
            kind: OfficeVisualKind.chartLine,
            title: 'New header chart',
            points: <ChartPoint>[
              const ChartPoint(label: 'A', value: 11),
              const ChartPoint(label: 'B', value: 13),
            ],
          ),
        ),
      );
      final Uint8List preservedChart = original
          .getPart('/word/charts/chart1.xml')!
          .readBytes();
      final Uint8List preservedImage = original
          .getPart('/word/media/image1.png')!
          .readBytes();
      final Uint8List savedBytes = await OfficeIsolateSave.word(document);
      final OpcPackage saved = OpcPackage.openBytes(savedBytes);
      expect(
        saved.getPart('/word/charts/chart1.xml')!.readBytes(),
        preservedChart,
      );
      expect(
        saved.getPart('/word/media/image1.png')!.readBytes(),
        preservedImage,
      );
      for (final MapEntry<String, String> story in <String, String>{
        _mainUri(saved): 'New body chart',
        _storyUris(saved)['first header']!: 'New header chart',
      }.entries) {
        final XmlElement xml = XmlDocument.parse(
          saved.getPart(story.key)!.readText(),
        ).root!;
        final XmlElement chart = _descendants(xml, 'chart').single;
        final RelationshipCollection rels = saved.relationshipsFor(story.key);
        final PackageRelationship rel = rels.byId(
          chart.getAttribute('id', namespaceUri: OfficeNamespaces.r)!,
        )!;
        expect(rel.type, RelationshipTypes.chart);
        expect(
          saved.getPart(rels.resolve(rel))!.readText(),
          contains(story.value),
        );
      }
      final WmlDocument reopened = WordDeserializer().readBytes(savedBytes);
      expect(
        reopened.visuals.last.visual.points.map((ChartPoint p) => p.value),
        <double>[2, 7],
      );
      expect(
        reopened.sections.single.firstHeaderVisuals.last.visual.points.map(
          (ChartPoint p) => p.value,
        ),
        <double>[11, 13],
      );
    },
  );

  test(
    'changing PNG to JPEG updates the content type without corrupting PNG consumers',
    () {
      final OpcPackage original = OpcPackage.openBytes(
        File(_fixture).readAsBytesSync(),
      );
      final WmlDocument document = WordDeserializer().read(original);
      // Minimal JPEG signature suffices here: the serializer preserves payloads,
      // while image decoding is covered separately by the visual golden tests.
      final Uint8List jpeg = Uint8List.fromList(<int>[
        0xff,
        0xd8,
        0xff,
        0xe0,
        0xff,
        0xd9,
      ]);
      document.visuals.first.visual.imageBytes = jpeg;
      final OpcPackage saved = OpcPackage.openBytes(
        WordSerializer().writeBytes(document),
      );
      final PackagePart picture = _pictures(saved, _mainUri(saved)).first;
      expect(picture.contentType, 'image/jpeg');
      expect(picture.uri, endsWith('.jpeg'));
      expect(picture.readBytes(), jpeg);
      expect(
        saved.getPart('/word/media/image1.png')!.readBytes(),
        original.getPart('/word/media/image1.png')!.readBytes(),
      );
    },
  );
}
