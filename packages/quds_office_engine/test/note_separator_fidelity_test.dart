import 'dart:convert';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/note_fixture.dart';

XmlElement _noteParagraph(OpcPackage package, bool endnote, int id) {
  final kind = endnote ? 'endnote' : 'footnote';
  final root = XmlDocument.parse(
    package.getPart('/word/${kind}s.xml')!.readText(),
  ).root!;
  return root
      .childrenNamed(kind)
      .firstWhere((node) => node.getAttribute('id') == '$id')
      .firstChild('p')!;
}

XmlElement? _markerProperties(OpcPackage package, bool endnote, int id) {
  final marker = endnote ? 'endnoteRef' : 'footnoteRef';
  return _noteParagraph(package, endnote, id)
      .childrenNamed('r')
      .firstWhere((run) => run.firstChild(marker) != null)
      .firstChild('rPr');
}

String _noteText(OpcPackage package, bool endnote, int id) {
  final paragraph = _noteParagraph(package, endnote, id);
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

OpcPackage _nativeSeparators(
  bool endnote, {
  required bool custom,
  bool aliases = false,
  int noticeId = 42,
}) {
  final kind = endnote ? 'endnote' : 'footnote';
  final prefix = aliases ? 'q' : 'w';
  final context = aliases ? ' mc:Ignorable="w" w:custom="retained"' : '';
  final chrome = custom
      ? '<$prefix:$kind $prefix:id="$noticeId" $prefix:type="continuationNotice"$context>'
            '<$prefix:p><$prefix:r><$prefix:t>Continued on next page</$prefix:t></$prefix:r></$prefix:p></$prefix:$kind>'
            '<$prefix:$kind $prefix:id="-1" $prefix:type="separator">'
            '<$prefix:p><$prefix:pPr><$prefix:spacing $prefix:after="80"/><$prefix:jc $prefix:val="center"/></$prefix:pPr>'
            '<$prefix:r><$prefix:rPr><$prefix:color $prefix:val="225588"/><$prefix:sz $prefix:val="18"/></$prefix:rPr>'
            '<$prefix:separator/></$prefix:r></$prefix:p></$prefix:$kind>'
            '<$prefix:$kind $prefix:id="0" $prefix:type="continuationSeparator">'
            '<$prefix:p><$prefix:r><$prefix:continuationSeparator/></$prefix:r></$prefix:p></$prefix:$kind>'
      : '';
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        '<w:document xmlns:w="${OfficeNamespaces.w}"><w:body><w:p>'
        '<w:r><w:t>Body</w:t></w:r><w:r><w:${kind}Reference w:id="12"/></w:r>'
        '</w:p><w:sectPr/></w:body></w:document>',
      );
  package.createPart(
    '/custom/${kind}s.xml',
    endnote
        ? OfficeContentTypes.wordEndnotes
        : OfficeContentTypes.wordFootnotes,
    utf8.encode(
      '<$prefix:${kind}s xmlns:$prefix="${OfficeNamespaces.w}" '
      '${aliases ? 'xmlns:w="urn:foreign" ' : ''}xmlns:mc="${OfficeNamespaces.mc}">'
      '$chrome<$prefix:$kind $prefix:id="12"><$prefix:p>'
      '<$prefix:r><$prefix:${kind}Ref/></$prefix:r>'
      '<$prefix:r><$prefix:t>Native note</$prefix:t></$prefix:r>'
      '</$prefix:p></$prefix:$kind></$prefix:${kind}s>',
    ),
  );
  package
      .relationshipsFor('/word/document.xml')
      .add(
        id: 'nativeNotes',
        type: endnote
            ? RelationshipTypes.endnotes
            : RelationshipTypes.footnotes,
        target: '../custom/${kind}s.xml',
      );
  return package;
}

String _mainPartUri(OpcPackage package) {
  final office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  )!;
  return package.packageRelationships.resolve(office);
}

XmlElement _noteRoot(OpcPackage package, bool endnote) {
  final kind = endnote ? 'endnote' : 'footnote';
  final mainUri = _mainPartUri(package);
  final relations = package.relationshipsFor(mainUri);
  final relationship = relations.firstByType(
    endnote ? RelationshipTypes.endnotes : RelationshipTypes.footnotes,
  );
  final uri = relationship == null
      ? OpcUris.resolve(mainUri, '${kind}s.xml')
      : relations.resolve(relationship);
  return XmlDocument.parse(package.getPart(uri)!.readText()).root!;
}

List<XmlElement> _separatorDefinitions(OpcPackage package, bool endnote) {
  final kind = endnote ? 'endnote' : 'footnote';
  return _noteRoot(package, endnote)
      .childrenNamed(kind, namespaceUri: OfficeNamespaces.w)
      .where(
        (node) => const {
          'separator',
          'continuationSeparator',
          'continuationNotice',
        }.contains(node.getAttribute('type', namespaceUri: OfficeNamespaces.w)),
      )
      .toList();
}

void _relocateMain(OpcPackage package, String mainUri) {
  final previous = _mainPartUri(package);
  final part = package.getPart(previous)!;
  package.createPart(mainUri, part.contentType, part.readBytes());
  final relations = package.relationshipsFor(previous);
  for (final relationship in relations.items) {
    package
        .relationshipsFor(mainUri)
        .add(
          id: relationship.id,
          type: relationship.type,
          target: OpcUris.relativize(mainUri, relations.resolve(relationship)),
        );
  }
  final office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  )!;
  package.packageRelationships
    ..removeById(office.id)
    ..add(
      id: office.id,
      type: RelationshipTypes.officeDocument,
      target: mainUri.substring(1),
    );
  package.deletePart(previous);
}

Object _nativeSnapshot(XmlElement node) => [
  node.namespaceUri,
  node.localName,
  (node.attributes
      .where(
        (attribute) =>
            attribute.prefix != 'xmlns' && attribute.qualifiedName != 'xmlns',
      )
      .map(
        (attribute) =>
            '${attribute.namespaceUri}|${attribute.localName}|${attribute.value}',
      )
      .toList()
    ..sort()),
  node.text,
  node.childElements.map(_nativeSnapshot).toList(),
];

List<LaidOutBox> _previewSeparators(WmlDocument document) =>
    WordLayoutEngine(font: null)
        .layout(document)
        .pages
        .expand((page) => page.frames)
        .where((box) => box.kind == LaidOutBoxKind.footnote)
        .toList();

void main() {
  for (final endnote in [false, true]) {
    for (final relocateMain in [false, true]) {
      test(
        'inserting notes reserves native special IDs through three saves: endnote=$endnote relocatedMain=$relocateMain',
        () async {
          final source = _nativeSeparators(
            endnote,
            custom: true,
            aliases: true,
            noticeId: 13,
          );
          if (relocateMain) _relocateMain(source, '/legacy/word/main.xml');
          final mainUri = _mainPartUri(source);
          final kind = endnote ? 'endnote' : 'footnote';
          final noteUri = '/custom/${kind}s.xml';
          final nativeDefinitions = _separatorDefinitions(
            source,
            endnote,
          ).map(_nativeSnapshot).toList();
          var document = WordDeserializer().read(source);
          for (var cycle = 0; cycle < 3; cycle++) {
            final package = document.package!;
            final originalNoteXml = package.getPart(noteUri)!.readText();
            final originalMainXml = package.getPart(mainUri)!.readText();
            final originalRelations = package.relationshipsFor(mainUri).toXml();
            final note = WordNotes.insert(
              document,
              document.paragraphs.first,
              endnote: endnote,
              text: 'Inserted $cycle',
            );
            expect(note.id, 14 + cycle);
            expect(
              document.paragraphs.first.inlines
                  .whereType<WmlRun>()
                  .where((run) => run.noteRefId == note.id)
                  .single
                  .noteRefEndnote,
              endnote,
            );
            // Allocation only reads the package. Native definitions and their
            // source relationship remain byte-for-byte intact until save.
            expect(package.getPart(noteUri)!.readText(), originalNoteXml);
            expect(package.getPart(mainUri)!.readText(), originalMainXml);
            expect(
              package.relationshipsFor(mainUri).toXml(),
              originalRelations,
            );

            final saved = OpcPackage.openBytes(
              await OfficeIsolateSave.word(document),
            );
            final ids = _noteRoot(saved, endnote)
                .childrenNamed(kind, namespaceUri: OfficeNamespaces.w)
                .map(
                  (node) =>
                      node.getAttribute('id', namespaceUri: OfficeNamespaces.w),
                )
                .toList();
            expect(ids, [
              '13',
              '-1',
              '0',
              '12',
              for (var i = 0; i <= cycle; i++) '${14 + i}',
            ]);
            expect(ids.toSet().length, ids.length);
            expect(
              _separatorDefinitions(
                saved,
                endnote,
              ).map(_nativeSnapshot).toList(),
              nativeDefinitions,
            );
            expect(_mainPartUri(saved), mainUri);
            final owner = saved.relationshipsFor(mainUri);
            expect(owner.resolve(owner.byId('nativeNotes')!), noteUri);
            expect(saved.getPart('/word/${kind}s.xml'), isNull);
            document = WordDeserializer().read(saved);
            expect(
              (endnote ? document.endnotes : document.footnotes).map(
                (note) => note.id,
              ),
              [12, for (var i = 0; i <= cycle; i++) 14 + i],
            );
          }
        },
      );
    }
    test(
      'legacy unowned note part reserves its retained special IDs: endnote=$endnote',
      () async {
        final source = _nativeSeparators(endnote, custom: true, noticeId: 13);
        final kind = endnote ? 'endnote' : 'footnote';
        final previousUri = '/custom/${kind}s.xml';
        final part = source.getPart(previousUri)!;
        source.createPart(
          '/word/${kind}s.xml',
          part.contentType,
          part.readBytes(),
        );
        source.deletePart(previousUri);
        source.relationshipsFor('/word/document.xml').removeById('nativeNotes');
        final expected = _separatorDefinitions(
          source,
          endnote,
        ).map(_nativeSnapshot).toList();
        final document = WordDeserializer().read(source);
        expect(
          WordNotes.insert(
            document,
            document.paragraphs.first,
            endnote: endnote,
          ).id,
          14,
        );
        final saved = OpcPackage.openBytes(
          await OfficeIsolateSave.word(document),
        );
        expect(
          _separatorDefinitions(saved, endnote).map(_nativeSnapshot).toList(),
          expected,
        );
        expect(
          _noteRoot(
            saved,
            endnote,
          ).childrenNamed(kind).map((node) => node.getAttribute('id')),
          ['13', '-1', '0', '12', '14'],
        );
      },
    );
    test(
      'an unrelated high special ID does not renumber the next note: endnote=$endnote',
      () {
        final document = WordDeserializer().read(
          _nativeSeparators(endnote, custom: true),
        );
        expect(
          WordNotes.insert(
            document,
            document.paragraphs.first,
            endnote: endnote,
          ).id,
          13,
        );
      },
    );
    for (final (custom, aliases) in [
      (false, false),
      (true, false),
      (true, true),
    ]) {
      test(
        'native separator definitions preserve absence, metadata and owner through clone/edit/save: endnote=$endnote custom=$custom aliases=$aliases',
        () async {
          final source = _nativeSeparators(
            endnote,
            custom: custom,
            aliases: aliases,
          );
          final expected = _separatorDefinitions(
            source,
            endnote,
          ).map(_nativeSnapshot).toList();
          var document = WordDeserializer().read(source);
          for (var cycle = 0; cycle < 3; cycle++) {
            if (!endnote) {
              expect(document.sourceFootnoteSeparatorsPresent, custom);
              expect(_previewSeparators(document).isNotEmpty, custom);
            }
            final note =
                (endnote ? document.endnotes : document.footnotes).single;
            final cloned = note.blocks.map(WmlClone.block).toList();
            note.blocks
              ..clear()
              ..addAll(cloned);
            note.paragraphs.single.inlines.whereType<WmlRun>().single.text =
                'Edited note $cycle';
            if (!endnote) {
              expect(_previewSeparators(document).isNotEmpty, custom);
            }
            final saved = OpcPackage.openBytes(
              await OfficeIsolateSave.word(document),
            );
            expect(
              _separatorDefinitions(
                saved,
                endnote,
              ).map(_nativeSnapshot).toList(),
              expected,
            );
            expect(
              saved.getPart('/word/${endnote ? 'endnote' : 'footnote'}s.xml'),
              isNull,
            );
            final relationship = saved
                .relationshipsFor('/word/document.xml')
                .byId('nativeNotes')!;
            expect(
              relationship.target,
              '../custom/${endnote ? 'endnote' : 'footnote'}s.xml',
            );
            if (aliases) {
              final notice = _separatorDefinitions(saved, endnote).first;
              expect(
                notice.getAttribute('custom', namespaceUri: 'urn:foreign'),
                'retained',
              );
              expect(
                notice.getAttribute(
                  'Ignorable',
                  namespaceUri: OfficeNamespaces.mc,
                ),
                'w',
              );
            }
            document = WordDeserializer().read(saved);
          }
          if (!endnote) expect(_previewSeparators(document).isNotEmpty, custom);
        },
      );
    }
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
              _markerProperties(OpcPackage.openBytes(bytes), endnote, id),
              isNull,
            );
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
      'imported note mark retains its own explicit properties: endnote=$endnote',
      () async {
        final package = richNoteFixture().package!;
        final kind = endnote ? 'endnote' : 'footnote';
        final id = endnote ? 3 : 12;
        package.getPart('/word/${kind}s.xml')!.writeText('''
<w:${kind}s xmlns:w="${OfficeNamespaces.w}"><w:$kind w:id="$id">
<w:p><w:r><q:rPr xmlns:q="${OfficeNamespaces.w}"><q:color q:val="123456"/><q:sz q:val="20"/><q:vertAlign q:val="baseline"/></q:rPr><w:${kind}Ref/></w:r><w:r><w:t>Rich note</w:t></w:r></w:p>
</w:$kind></w:${kind}s>''');
        var document = WordDeserializer().read(package);
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          final properties = _markerProperties(
            OpcPackage.openBytes(bytes),
            endnote,
            id,
          )!;
          expect(properties.firstChild('color')!.getAttribute('val'), '123456');
          expect(properties.firstChild('sz')!.getAttribute('val'), '20');
          expect(
            properties.firstChild('vertAlign')!.getAttribute('val'),
            'baseline',
          );
          expect(properties.firstChild('rStyle'), isNull);
          document = WordDeserializer().readBytes(bytes);
        }
      },
    );
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
        expect(note.id, 1);
        if (!endnote) {
          expect(document.sourceFootnoteSeparatorsPresent, isNull);
          expect(_previewSeparators(document), isNotEmpty);
        }
        for (var cycle = 0; cycle < 3; cycle++) {
          final bytes = await OfficeIsolateSave.word(document);
          expect(
            _separatorDefinitions(
              OpcPackage.openBytes(bytes),
              endnote,
            ).map((node) => node.getAttribute('type')),
            ['separator', 'continuationSeparator'],
          );
          expect(
            _markerProperties(
              OpcPackage.openBytes(bytes),
              endnote,
              note.id,
            )!.firstChild('vertAlign')!.getAttribute('val'),
            'superscript',
          );
          expect(
            _noteText(OpcPackage.openBytes(bytes), endnote, note.id),
            ' New note',
          );
          document = WordDeserializer().readBytes(bytes);
          if (!endnote) {
            expect(document.sourceFootnoteSeparatorsPresent, isTrue);
            expect(_previewSeparators(document), isNotEmpty);
          }
        }
      },
    );
  }
  test('footnotes and endnotes reserve IDs in separate domains', () {
    final document = WordDeserializer().read(
      _nativeSeparators(false, custom: true, noticeId: 13),
    );
    document.endnotes.add(WmlNote(id: 12, endnote: true)..text = 'Endnote');
    final paragraph = document.paragraphs.first;
    expect(WordNotes.insert(document, paragraph, endnote: true).id, 13);
    expect(WordNotes.insert(document, paragraph, endnote: false).id, 14);
  });
}
