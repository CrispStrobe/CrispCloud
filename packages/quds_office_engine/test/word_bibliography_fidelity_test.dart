import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

const _b = 'http://schemas.openxmlformats.org/officeDocument/2006/bibliography';
const _extension = 'urn:crispcloud:bibliography-extension';
const _main = '/office/content/body.xml';
const _catalog = '/customXml/catalog42.xml';
const _unrelatedItem =
    '<Sources xmlns="urn:crispcloud:unrelated"><Source>Keep item1 exactly</Source></Sources>';
const _unrelatedSources =
    '<audit xmlns="urn:crispcloud:unrelated">Keep sources.xml exactly</audit>';
const _props =
    '<ds:datastoreItem xmlns:ds="http://schemas.openxmlformats.org/officeDocument/2006/customXml" ds:itemID="{6AD1A1C2-1B2A-4DFB-A9AD-000000000001}"><ds:schemaRefs><ds:schemaRef ds:uri="$_b"/></ds:schemaRefs></ds:datastoreItem>';

OpcPackage _source({bool native = true}) {
  final package = OpcPackage.empty();
  package.createPart(
    _main,
    OfficeContentTypes.wordMain,
    utf8.encode(
      '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
      '<w:r><w:t xml:space="preserve">Before </w:t></w:r>'
      '<w:fldSimple w:instr=" CITATION Native "><w:r><w:t>(Original cached source)</w:t></w:r></w:fldSimple>'
      '<w:r><w:t xml:space="preserve"> after</w:t></w:r></w:p><w:sectPr/></w:body></w:document>',
    ),
  );
  package.packageRelationships.add(
    type: RelationshipTypes.officeDocument,
    target: _main.substring(1),
  );
  final rels = package.relationshipsFor(_main);
  package.createPart(
    '/customXml/item1.xml',
    'application/xml',
    utf8.encode(_unrelatedItem),
  );
  package.createPart(
    '/customXml/sources.xml',
    'application/xml',
    utf8.encode(_unrelatedSources),
  );
  rels.add(
    type: RelationshipTypes.customXml,
    target: '../../customXml/item1.xml',
  );
  if (native) {
    package.createPart(
      _catalog,
      'application/xml',
      File('test/fixtures/fidelity/bibliography_sources.xml').readAsBytesSync(),
    );
    rels.add(
      type: RelationshipTypes.customXml,
      target: '../../customXml/catalog42.xml',
      id: 'nativeBibliography',
    );
    package.createPart(
      '/customXml/itemProps42.xml',
      'application/vnd.openxmlformats-officedocument.customXmlProperties+xml',
      utf8.encode(_props),
    );
    package
        .relationshipsFor(_catalog)
        .add(
          type: '${OfficeNamespaces.r}/customXmlProps',
          target: 'itemProps42.xml',
        );
  }
  return package;
}

XmlElement _catalogRoot(OpcPackage package, {String main = _main}) {
  final rels = package.relationshipsFor(main);
  final roots = <XmlElement>[
    for (final rel in rels.items)
      if (rel.type == RelationshipTypes.customXml &&
          rel.targetMode == RelationshipTargetMode.internal)
        if (package.getPart(rels.resolve(rel)) case final PackagePart part)
          if (XmlDocument.parse(part.readText()).root
              case final XmlElement root)
            if (root.namespaceUri == _b && root.localName == 'Sources') root,
  ];
  expect(
    roots,
    hasLength(1),
    reason: 'exactly one native bibliography owned by the main part',
  );
  return roots.single;
}

XmlElement _byTag(XmlElement root, String tag) => root
    .childrenNamed('Source', namespaceUri: _b)
    .singleWhere(
      (source) => source.firstChild('Tag', namespaceUri: _b)?.text == tag,
    );

String? _value(XmlElement source, String name) =>
    source.firstChild(name, namespaceUri: _b)?.text;

void _assertPreserved(OpcPackage package) {
  expect(package.getPart('/customXml/item1.xml')!.readText(), _unrelatedItem);
  expect(
    package.getPart('/customXml/sources.xml')!.readText(),
    _unrelatedSources,
  );
  expect(package.getPart('/customXml/itemProps42.xml')!.readText(), _props);
  final rel = package.relationshipsFor(_catalog).items.single;
  expect(rel.type, '${OfficeNamespaces.r}/customXmlProps');
  expect(
    package.relationshipsFor(_catalog).resolve(rel),
    '/customXml/itemProps42.xml',
  );
  final root = _catalogRoot(package);
  expect(root.getAttribute('SelectedStyle'), '/APA.XSL');
  expect(root.getAttribute('StyleName'), 'APA');
  expect(root.getAttribute('Version'), '6');
  final source = _byTag(root, 'Native');
  expect(
    source.getAttribute('kept', namespaceUri: _extension),
    'native-extension',
  );
  expect(
    source.firstChild('Title', namespaceUri: _extension)!.text,
    'Foreign title must remain',
  );
  expect(_value(source, 'SourceType'), 'Book');
  expect(_value(source, 'Guid'), '{6AD1A1C2-1B2A-4DFB-A9AD-000000000001}');
  expect(_value(source, 'Publisher'), 'Native publisher');
  expect(_value(source, 'City'), 'London');
  expect(_value(source, 'URL'), 'https://example.org/native-source');
  final outer = source.firstChild('Author', namespaceUri: _b)!;
  final people = outer
      .firstChild('Author', namespaceUri: _b)!
      .firstChild('NameList', namespaceUri: _b)!
      .childrenNamed('Person', namespaceUri: _b)
      .toList();
  expect(people.map((p) => _value(p, 'Last')), <String>['Lovelace', 'Hopper']);
  expect(people.map((p) => _value(p, 'First')), <String>['Ada', 'Grace']);
  expect(_value(people.first, 'Middle'), 'Byron');
  expect(
    outer
        .firstChild('Editor', namespaceUri: _b)!
        .firstChild('NameList', namespaceUri: _b)!
        .firstChild('Person', namespaceUri: _b)!
        .firstChild('Last', namespaceUri: _b)!
        .text,
    'Editor',
  );
  expect(
    root
        .childrenNamed('Source', namespaceUri: _b)
        .where((s) => s.firstChild('Tag', namespaceUri: _b) == null)
        .single
        .firstChild('Comments', namespaceUri: _b)!
        .text,
    'Unmodeled source without a tag',
  );
}

void main() {
  test(
    'native owned bibliography imports structured authors and pages by namespace',
    () {
      final document = WordDeserializer().read(_source());
      final citation = document.citations.single;
      expect(citation.tag, 'Native');
      expect(citation.author, 'Ada Byron Lovelace; Grace Hopper');
      expect(citation.title, 'Original title');
      expect(citation.year, '1843');
      expect(citation.pages, '1-9');
      expect(citation.sourceXml, contains('Native publisher'));
      expect(citation.importedValues!['author'], citation.author);
      expect(
        () => citation.importedValues!['title'] = 'Changed',
        throwsUnsupportedError,
      );
      _assertPreserved(WordSerializer().write(document));
    },
  );

  for (final isolate in <bool>[false, true]) {
    final mode = isolate ? 'isolate' : 'direct';
    test(
      '$mode source edits preserve native metadata and unrelated XML through three saves',
      () async {
        var document = WordDeserializer().read(_source());
        document.citations.single
          ..title = 'Edited & expanded'
          ..year = '2026'
          ..pages = '12-19';
        document.citations.add(
          WmlCitation(
            tag: 'Added',
            author: 'CrispCloud Team',
            title: 'Added source',
            year: '2025',
          ),
        );
        for (var cycle = 1; cycle <= 3; cycle++) {
          final bytes = isolate
              ? await OfficeIsolateSave.word(document)
              : WordSerializer().writeBytes(document);
          final package = OpcPackage.openBytes(bytes);
          _assertPreserved(package);
          final native = _byTag(_catalogRoot(package), 'Native');
          expect(_value(native, 'Title'), 'Edited & expanded');
          expect(_value(native, 'Year'), '2026');
          expect(_value(native, 'Pages'), '12-19');
          final added = _byTag(_catalogRoot(package), 'Added');
          expect(_value(added, 'SourceType'), 'Misc');
          expect(
            added
                .firstChild('Author', namespaceUri: _b)!
                .firstChild('Author', namespaceUri: _b)!
                .firstChild('Corporate', namespaceUri: _b)!
                .text,
            'CrispCloud Team',
          );
          expect(
            package.relationshipsFor(_main).byId('nativeBibliography')!.target,
            '../../customXml/catalog42.xml',
          );
          final output = File('build/fidelity-bibliography/$mode-$cycle.docx');
          output.parent.createSync(recursive: true);
          output.writeAsBytesSync(bytes);
          document = WordDeserializer().readBytes(bytes);
          expect(document.citations.map((c) => c.tag), <String>[
            'Native',
            'Added',
          ]);
          expect(
            document.citations.first.author,
            'Ada Byron Lovelace; Grace Hopper',
          );
          expect(
            document.paragraphs.single.text,
            'Before (Original cached source) after',
          );
        }
      },
    );
  }

  test(
    'tag and scalar author edits retain editor roles and unrelated source fields',
    () {
      final document = WordDeserializer().read(_source());
      document.citations.single
        ..tag = 'Renamed'
        ..author = 'Literal changed author'
        ..pages = '';
      final root = _catalogRoot(WordSerializer().write(document));
      final source = _byTag(root, 'Renamed');
      expect(_value(source, 'SourceType'), 'Book');
      expect(_value(source, 'Publisher'), 'Native publisher');
      expect(_value(source, 'Pages'), isNull);
      final outer = source.firstChild('Author', namespaceUri: _b)!;
      expect(outer.firstChild('Editor', namespaceUri: _b), isNotNull);
      expect(
        outer
            .firstChild('Author', namespaceUri: _b)!
            .firstChild('Corporate', namespaceUri: _b)!
            .text,
        'Literal changed author',
      );
      final opened = WordDeserializer().readBytes(
        WordSerializer().writeBytes(document),
      );
      expect(opened.citations.single.tag, 'Renamed');
      expect(opened.citations.single.author, 'Literal changed author');
    },
  );

  test(
    'clearing sources persists deletion without resurrecting imported native data',
    () {
      var document = WordDeserializer().read(_source());
      document.citations.clear();
      for (var cycle = 0; cycle < 3; cycle++) {
        final package = WordSerializer().write(document);
        final root = _catalogRoot(package);
        expect(
          root
              .childrenNamed('Source', namespaceUri: _b)
              .where((s) => s.firstChild('Tag', namespaceUri: _b) != null),
          isEmpty,
        );
        expect(
          package.getPart('/customXml/item1.xml')!.readText(),
          _unrelatedItem,
        );
        document = WordDeserializer().readBytes(package.save());
        expect(document.citations, isEmpty);
      }
    },
  );

  test(
    'new bibliography allocation preserves colliding unrelated XML and native ownership',
    () {
      final package = _source(native: false);
      package.createPart(
        '/customXml/bibliography.xml',
        'application/xml',
        utf8.encode('<private>Collision must remain</private>'),
      );
      final document = WordDeserializer().read(package);
      expect(document.citations, isEmpty);
      WordCitations.insert(
        document,
        document.paragraphs.single,
        WmlCitation(tag: 'New', author: 'Team', title: 'Source'),
      );
      final saved = WordSerializer().write(document);
      expect(saved.getPart('/customXml/item1.xml')!.readText(), _unrelatedItem);
      expect(
        saved.getPart('/customXml/sources.xml')!.readText(),
        _unrelatedSources,
      );
      expect(
        saved.getPart('/customXml/bibliography.xml')!.readText(),
        '<private>Collision must remain</private>',
      );
      expect(saved.getPart('/customXml/bibliography2.xml'), isNotNull);
      expect(
        _byTag(
          _catalogRoot(saved),
          'New',
        ).firstChild('SourceType', namespaceUri: _b)!.text,
        'Misc',
      );
      expect(
        WordDeserializer().readBytes(saved.save()).citations.single.tag,
        'New',
      );
    },
  );

  test(
    'legacy unowned scalar sources are linked and normalized without overwriting item1',
    () {
      final package = _source(native: false);
      package
          .getPart('/customXml/sources.xml')!
          .writeText(
            '<b:Sources xmlns:b="$_b"><b:Source><b:Tag>Legacy</b:Tag><b:Author>Ada</b:Author><b:Title>Old source</b:Title><b:Year>2020</b:Year></b:Source></b:Sources>',
          );
      final document = WordDeserializer().read(package);
      expect(document.citations.single.author, 'Ada');
      final saved = WordSerializer().write(document);
      expect(saved.getPart('/customXml/item1.xml')!.readText(), _unrelatedItem);
      final source = _byTag(_catalogRoot(saved), 'Legacy');
      expect(_value(source, 'SourceType'), 'Misc');
      expect(
        source
            .firstChild('Author', namespaceUri: _b)!
            .firstChild('Author', namespaceUri: _b)!
            .firstChild('Corporate', namespaceUri: _b)!
            .text,
        'Ada',
      );
      expect(saved.getPart('/customXml/bibliography.xml'), isNull);
    },
  );

  test(
    'external custom XML relationships do not supply native bibliography ownership',
    () {
      final package = _source(native: false);
      package
          .relationshipsFor(_main)
          .add(
            type: RelationshipTypes.customXml,
            target: 'https://example.org/sources.xml',
            targetMode: RelationshipTargetMode.external,
          );
      final document = WordDeserializer().read(package);
      expect(document.citations, isEmpty);
      final saved = WordSerializer().write(document);
      expect(saved.getPart('/customXml/bibliography.xml'), isNull);
      expect(saved.getPart('/customXml/item1.xml')!.readText(), _unrelatedItem);
    },
  );
}
