import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

import '../tool/fidelity/slide_steps.dart';

const _p14 = 'http://schemas.microsoft.com/office/powerpoint/2010/main';
const _fixture = 'test/fixtures/fidelity/slide-sections.pptx';
const _ids = [701, 503, 907, 509, 1201, 803];
const _names = [
  'Leading empty',
  'Intro & agenda',
  'Gap empty',
  'Body',
  'Conclusion',
  'Trailing empty',
];
const _states = <String, (List<int>, List<int>)>{
  'unchanged': ([701, 503, 907, 509, 1201, 803], [0, 0, 2, 2, 4, 6]),
  'within': ([503, 701, 907, 509, 1201, 803], [0, 0, 2, 2, 4, 6]),
  'forward': ([503, 907, 509, 701, 1201, 803], [0, 0, 1, 1, 4, 6]),
  'backward': ([701, 803, 503, 907, 509, 1201], [0, 0, 3, 3, 5, 6]),
  'emptied': ([907, 701, 503, 509, 1201, 803], [0, 0, 0, 0, 4, 6]),
};

PmlPresentation _open() =>
    SlideDeserializer().readBytes(File(_fixture).readAsBytesSync());

void _expectState(PmlPresentation deck, String scenario) {
  expect(deck.sectionSource?.issue, isNull);
  expect(deck.slides.map((slide) => slide.id), _states[scenario]!.$1);
  expect(deck.sections.map((section) => section.name), _names);
  expect(
    deck.sections.map((section) => section.startIndex),
    _states[scenario]!.$2,
  );
  expect(deck.sections.map((section) => section.id), [
    for (int id = 1; id <= 6; id++)
      '{A71D8B00-3E2F-4A20-9F10-${id.toRadixString(16).toUpperCase().padLeft(12, '0')}}',
  ]);
}

void _edit(PmlPresentation deck, String scenario) {
  switch (scenario) {
    case 'unchanged':
      break;
    case 'within':
      PmlSections.reorderSlide(deck, 1, 0);
    case 'forward':
      applySlideStep(deck, {'op': 'slideOrder', 'slide': 0, 'to': 3});
    case 'backward':
      PmlSections.reorderSlide(deck, 5, 1);
    case 'emptied':
      applySlideStep(deck, {'op': 'slideOrder', 'slide': 1, 'to': 2});
      applySlideStep(deck, {'op': 'slideOrder', 'slide': 0, 'to': 1});
  }
}

XmlElement _nativeList(XmlElement root) => root
    .firstChild('extLst', namespaceUri: OfficeNamespaces.p)!
    .childElements
    .firstWhere(
      (ext) =>
          ext.getAttribute('uri') == '{521415D9-36F7-43E2-AB2F-B90AF26B5E84}',
    )
    .firstChild('sectionLst', namespaceUri: _p14)!;

List<XmlElement> _members(XmlElement section) => section
    .firstChild('sldIdLst', namespaceUri: _p14)!
    .childrenNamed('sldId', namespaceUri: _p14);

PmlPresentation _mutated(void Function(XmlElement) mutate) {
  final package = OpcPackage.openBytes(File(_fixture).readAsBytesSync());
  final part = package.getPart('/ppt/presentation.xml')!;
  final document = XmlDocument.parse(part.readText());
  mutate(document.root!);
  part.writeText(document.toXmlString());
  return SlideDeserializer().read(package);
}

Map<String, Uint8List> _parts(PmlPresentation deck) => {
  for (final part in deck.package!.parts)
    part.uri: Uint8List.fromList(part.readBytes()),
};

void main() {
  test(
    'native GUIDs, empty sections and namespace distinctions are imported',
    () {
      final deck = _open();
      _expectState(deck, 'unchanged');
      expect(
        deck.sections.every((section) => section.nativeXml != null),
        isTrue,
      );
    },
  );

  for (final mode in ['direct', 'isolate']) {
    for (final scenario in _states.keys) {
      test(
        '$mode $scenario retains section identity and membership through three saves',
        () async {
          final source = File(_fixture).readAsBytesSync();
          var deck = mode == 'isolate'
              ? await OfficeIsolateOpen.presentation(source)
              : SlideDeserializer().readBytes(source);
          final directory = Directory('build/fidelity-slide-sections/$mode')
            ..createSync(recursive: true);
          File('${directory.path}/source.pptx').writeAsBytesSync(source);
          _edit(deck, scenario);
          _expectState(deck, scenario);
          for (int cycle = 1; cycle <= 3; cycle++) {
            final bytes = mode == 'isolate'
                ? await OfficeIsolateSave.presentation(deck)
                : SlideSerializer().writeBytes(deck);
            File(
              '${directory.path}/$scenario-$cycle.pptx',
            ).writeAsBytesSync(bytes);
            deck = mode == 'isolate'
                ? await OfficeIsolateOpen.presentation(bytes)
                : SlideDeserializer().readBytes(bytes);
            _expectState(deck, scenario);
          }
        },
      );
    }
  }

  test(
    'a planned cross-section move restores exact boundaries on undo and redo',
    () {
      final deck = _open();
      final originalSlides = [...deck.slides];
      final originalSections = [...deck.sections];
      final plan = PmlSections.planReorder(deck, 0, 3);
      _expectState(deck, 'unchanged');
      plan.apply();
      _expectState(deck, 'forward');
      plan.undo();
      _expectState(deck, 'unchanged');
      expect(deck.slides, originalSlides);
      expect(deck.sections, originalSections);
      plan.apply();
      _expectState(deck, 'forward');
    },
  );

  test(
    'a stale plan rejects changed section state without touching slides',
    () {
      final deck = _open();
      final plan = PmlSections.planReorder(deck, 0, 3);
      deck.sections[2].startIndex = 1;
      expect(plan.apply, throwsStateError);
      expect(deck.slides.map((slide) => slide.id), _ids);
      expect(deck.sections[2].startIndex, 1);
    },
  );

  test(
    'moving to or from an unsectioned prefix preserves unaffected membership',
    () {
      final deck = PmlPresentation(
        slides: [for (final id in _ids) PmlSlide(id: id)],
        sections: [
          PmlSection(name: 'Group', startIndex: 2),
          PmlSection(name: 'Empty', startIndex: 6),
        ],
      );
      final intoGroup = PmlSections.planReorder(deck, 0, 3);
      intoGroup.apply();
      expect(deck.sections.map((section) => section.startIndex), [1, 6]);
      expect(PmlSections.nameOf(deck, 0), isNull);
      expect(PmlSections.nameOf(deck, 3), 'Group');
      intoGroup.undo();
      final intoPrefix = PmlSections.planReorder(deck, 5, 0);
      intoPrefix.apply();
      expect(deck.sections.map((section) => section.startIndex), [3, 6]);
      expect(PmlSections.nameOf(deck, 0), isNull);
      intoPrefix.undo();
      expect(deck.slides.map((slide) => slide.id), _ids);
      expect(deck.sections.map((section) => section.startIndex), [2, 6]);
    },
  );

  final malformed = <String, void Function(XmlElement)>{
    'duplicate membership': (root) {
      final members = _members(_nativeList(root).childElements.elementAt(1));
      members[1].setAttribute('id', '701');
    },
    'orphan membership': (root) => _members(
      _nativeList(root).childElements.elementAt(1),
    )[1].setAttribute('id', '888888'),
    'nonconsecutive membership': (root) {
      final list = _nativeList(
        root,
      ).childElements.elementAt(1).firstChild('sldIdLst', namespaceUri: _p14)!;
      list.children.setAll(0, list.children.reversed.toList());
    },
    'duplicate GUID': (root) {
      final sections = _nativeList(root).childElements.toList();
      sections[2].setAttribute('id', sections[0].getAttribute('id')!);
    },
    'invalid GUID': (root) => _nativeList(
      root,
    ).childElements.first.setAttribute('id', 'invalid-guid'),
    'duplicate native list': (root) {
      final list = _nativeList(root);
      list.parent!.addChild(list.copy());
    },
    'unmodeled membership child': (root) {
      final list = _nativeList(
        root,
      ).childElements.elementAt(1).firstChild('sldIdLst', namespaceUri: _p14)!;
      list.addChild(
        XmlElement(
          localName: 'futureMembership',
          prefix: 'q',
          namespaceUri: _p14,
        ),
      );
    },
    'unmodeled membership property': (root) =>
        _members(_nativeList(root).childElements.elementAt(1))[0].setAttribute(
          'futureBinding',
          'position-sensitive',
          prefix: 'kept',
          namespaceUri: 'urn:quds:independent-section-properties',
        ),
    'duplicate slide ID': (root) => root
        .firstChild('sldIdLst', namespaceUri: OfficeNamespaces.p)!
        .childElements
        .elementAt(1)
        .setAttribute('id', '701'),
  };
  for (final entry in malformed.entries) {
    test('${entry.key} guards script/API/save before any package mutation', () {
      final deck = _mutated(entry.value);
      expect(deck.sectionSource?.issue, isNotNull);
      final ids = [for (final slide in deck.slides) slide.id];
      final parts = _parts(deck);
      expect(() => PmlSections.reorderSlide(deck, 0, 3), throwsStateError);
      expect(
        () => applySlideStep(deck, {'op': 'slideOrder', 'slide': 0, 'to': 3}),
        throwsStateError,
      );
      expect(deck.slides.map((slide) => slide.id), ids);
      expect(_parts(deck), parts);
      deck.slides = deck.slides.reversed.toList();
      expect(() => SlideSerializer().writeBytes(deck), throwsStateError);
      expect(_parts(deck), parts);
    });
  }

  test('invalid model boundaries and ranges reject before mutation', () {
    final deck = _open();
    final parts = _parts(deck);
    expect(() => PmlSections.reorderSlide(deck, -1, 0), throwsRangeError);
    expect(() => PmlSections.reorderSlide(deck, 0, 6), throwsRangeError);
    deck.sections[3].startIndex = 7;
    expect(() => PmlSections.reorderSlide(deck, 0, 3), throwsStateError);
    expect(() => SlideSerializer().writeBytes(deck), throwsStateError);
    expect(deck.slides.map((slide) => slide.id), _ids);
    expect(_parts(deck), parts);
  });

  for (final issue in [
    'missing relationship',
    'wrong relationship type',
    'external target',
    'missing target part',
    'wrong target part type',
  ]) {
    test('$issue guards section reorder and bypassed saves', () {
      final package = OpcPackage.openBytes(File(_fixture).readAsBytesSync());
      final rels = package.relationshipsFor('/ppt/presentation.xml');
      final original = rels.firstByType(RelationshipTypes.slide)!;
      if (issue == 'missing target part') {
        package.deletePart(rels.resolve(original));
      } else {
        rels.removeById(original.id);
        if (issue != 'missing relationship') {
          rels.add(
            id: original.id,
            type: issue == 'wrong relationship type'
                ? RelationshipTypes.slideLayout
                : original.type,
            target: switch (issue) {
              'external target' => 'https://example.invalid/slide.xml',
              'wrong target part type' => 'notesSlides/notesSlide1.xml',
              _ => original.target,
            },
            targetMode: issue == 'external target'
                ? RelationshipTargetMode.external
                : RelationshipTargetMode.internal,
          );
        }
      }
      final deck = SlideDeserializer().read(package);
      expect(deck.sectionSource?.issue, isNotNull);
      final parts = _parts(deck);
      expect(() => PmlSections.reorderSlide(deck, 0, 3), throwsStateError);
      expect(
        () => applySlideStep(deck, {'op': 'slideOrder', 'slide': 0, 'to': 3}),
        throwsStateError,
      );
      expect(deck.slides.map((slide) => slide.id), _ids);
      expect(_parts(deck), parts);
      deck.slides = deck.slides.reversed.toList();
      expect(() => SlideSerializer().writeBytes(deck), throwsStateError);
      expect(_parts(deck), parts);
    });
  }

  test(
    'moving a native entry preserves a prefix scoped to its original section',
    () {
      var deck = _mutated((root) {
        final section = _nativeList(root).childElements.elementAt(1);
        section.attributes.add(
          XmlAttribute(localName: 'entry', prefix: 'xmlns', value: _p14),
        );
        for (final member in _members(section)) {
          member.prefix = 'entry';
        }
      });
      _expectState(deck, 'unchanged');
      PmlSections.reorderSlide(deck, 0, 3);
      for (int cycle = 0; cycle < 3; cycle++) {
        deck = SlideDeserializer().readBytes(
          SlideSerializer().writeBytes(deck),
        );
        _expectState(deck, 'forward');
      }
    },
  );

  test('opaque attributes sharing native local names are not rewritten', () {
    const opaque = 'urn:section-attribute-proof';
    var deck = _mutated((root) {
      final section = _nativeList(root).childElements.elementAt(1);
      section.attributes.insertAll(0, [
        XmlAttribute(localName: 'opaque', prefix: 'xmlns', value: opaque),
        XmlAttribute(
          localName: 'name',
          prefix: 'opaque',
          namespaceUri: opaque,
          value: 'Retained opaque name',
        ),
        XmlAttribute(
          localName: 'id',
          prefix: 'opaque',
          namespaceUri: opaque,
          value: 'Retained opaque id',
        ),
      ]);
    });
    PmlSections.reorderSlide(deck, 0, 3);
    for (int cycle = 0; cycle < 3; cycle++) {
      deck = SlideDeserializer().readBytes(SlideSerializer().writeBytes(deck));
      _expectState(deck, 'forward');
      final section = deck.sections[1].nativeXml!;
      expect(
        section.getAttribute('name', namespaceUri: opaque),
        'Retained opaque name',
      );
      expect(
        section.getAttribute('id', namespaceUri: opaque),
        'Retained opaque id',
      );
    }
  });

  test(
    'optional native name and GUID absence survives a section-aware move',
    () {
      var deck = _mutated((root) {
        final section = _nativeList(root).childElements.first;
        section.removeAttribute('name');
        section.removeAttribute('id');
      });
      expect(deck.sectionSource?.issue, isNull);
      PmlSections.reorderSlide(deck, 0, 3);
      for (int cycle = 0; cycle < 3; cycle++) {
        final bytes = SlideSerializer().writeBytes(deck);
        deck = SlideDeserializer().readBytes(bytes);
        final root = XmlDocument.parse(
          deck.package!.getPart('/ppt/presentation.xml')!.readText(),
        ).root!;
        expect(
          _nativeList(root).childElements.first.getAttribute('name'),
          isNull,
        );
        expect(
          _nativeList(root).childElements.first.getAttribute('id'),
          isNull,
        );
        expect(deck.sections, hasLength(6));
      }
    },
  );

  test(
    'unmodeled native membership is preserved when slide order is unchanged',
    () {
      var deck = _mutated(malformed['nonconsecutive membership']!);
      final original = _nativeList(
        XmlDocument.parse(
          deck.package!.getPart('/ppt/presentation.xml')!.readText(),
        ).root!,
      ).copy();
      for (int cycle = 0; cycle < 3; cycle++) {
        deck = SlideDeserializer().readBytes(
          SlideSerializer().writeBytes(deck),
        );
        expect(deck.sectionSource?.issue, isNotNull);
        final actual = _nativeList(
          XmlDocument.parse(
            deck.package!.getPart('/ppt/presentation.xml')!.readText(),
          ).root!,
        );
        final before = XmlDocument(root: original);
        final after = XmlDocument(root: actual);
        expect(after.toXmlString(), before.toXmlString());
      }
    },
  );
}
