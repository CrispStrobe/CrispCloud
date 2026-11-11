import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

// Author an OPC layout whose part names differ from Word's usual filenames.
// Relative relationships, not conventional paths, identify the actual stories.
OpcPackage _relocatedFixture() {
  final OpcPackage package = OpcPackage.openBytes(
    File('test/fixtures/fidelity/story-media.docx').readAsBytesSync(),
  );
  const String main = '/content/manuscript.xml';
  const String notes = '/support/notes-7.xml';
  final PackagePart source = package.getPart('/word/document.xml')!;
  package.createPart(main, source.contentType, source.readBytes());
  final RelationshipCollection old = package.relationshipsFor(source.uri);
  final RelationshipCollection relocated = package.relationshipsFor(main);
  for (final PackageRelationship rel in old.items) {
    relocated.add(
      id: rel.id,
      type: rel.type,
      target: OpcUris.relativize(
        main,
        rel.type == RelationshipTypes.footnotes ? notes : old.resolve(rel),
      ),
      targetMode: rel.targetMode,
    );
  }
  final PackagePart originalNotes = package.getPart('/word/footnotes.xml')!;
  package.createPart(
    notes,
    originalNotes.contentType,
    originalNotes.readBytes(),
  );
  final RelationshipCollection noteRels = package.relationshipsFor(
    originalNotes.uri,
  );
  for (final PackageRelationship rel in noteRels.items) {
    package
        .relationshipsFor(notes)
        .add(
          id: rel.id,
          type: rel.type,
          target: OpcUris.relativize(notes, noteRels.resolve(rel)),
          targetMode: rel.targetMode,
        );
  }
  package.deletePart(source.uri);
  package.deletePart(originalNotes.uri);
  final PackageRelationship office = package.packageRelationships.firstByType(
    RelationshipTypes.officeDocument,
  )!;
  package.packageRelationships.removeById(office.id);
  package.packageRelationships.add(
    id: office.id,
    type: office.type,
    target: main.substring(1),
  );
  package.createPart(
    '/support/catalog-9.xml',
    OfficeContentTypes.wordStyles,
    utf8.encode(
      '<w:styles xmlns:w="${OfficeNamespaces.w}">'
      '<w:style w:type="paragraph" w:styleId="Manuscript">'
      '<w:name w:val="Manuscript"/><w:rPr><w:color w:val="336699"/>'
      '</w:rPr></w:style></w:styles>',
    ),
  );
  relocated.add(
    type: RelationshipTypes.styles,
    target: '../support/catalog-9.xml',
  );
  final PackagePart mainPart = package.getPart(main)!;
  mainPart.writeText(
    mainPart.readText().replaceFirst(
      '<w:p>',
      '<w:p><w:pPr><w:pStyle w:val="Manuscript"/></w:pPr>',
    ),
  );
  return package;
}

void main() {
  test(
    'edits use the actual main and note parts over asynchronous save cycles',
    () async {
      WmlDocument document = WordDeserializer().read(_relocatedFixture());
      expect(
        document.paragraphs.first.inlines
            .whereType<WmlRun>()
            .first
            .properties
            .color,
        '336699',
      );
      document.paragraphs.first.inlines.whereType<WmlRun>().first.text =
          'Edited manuscript';
      document.footnotes.single.paragraphs.first.inlines
              .whereType<WmlRun>()
              .last
              .text =
          'Edited relocated note';
      for (int cycle = 1; cycle <= 3; cycle++) {
        final Uint8List bytes = await OfficeIsolateSave.word(document);
        final OpcPackage saved = OpcPackage.openBytes(bytes);
        final PackageRelationship office = saved.packageRelationships
            .firstByType(RelationshipTypes.officeDocument)!;
        expect(
          saved.packageRelationships.resolve(office),
          '/content/manuscript.xml',
        );
        expect(saved.getPart('/word/document.xml'), isNull);
        expect(
          saved.getPart('/content/manuscript.xml')!.readText(),
          contains('Edited manuscript'),
        );
        expect(
          saved.getPart('/support/notes-7.xml')!.readText(),
          contains('Edited relocated note'),
        );
        expect(saved.getPart('/word/footnotes.xml'), isNull);
        expect(
          saved.getPart('/support/catalog-9.xml')!.readText(),
          contains('336699'),
        );
        final RelationshipCollection mainRels = saved.relationshipsFor(
          '/content/manuscript.xml',
        );
        expect(
          mainRels.resolve(mainRels.firstByType(RelationshipTypes.styles)!),
          '/support/catalog-9.xml',
        );
        for (final PackagePart part in saved.parts) {
          for (final PackageRelationship rel
              in saved.relationshipsFor(part.uri).items) {
            if (rel.targetMode == RelationshipTargetMode.external) continue;
            expect(
              saved.getPart(OpcUris.resolve(part.uri, rel.target)),
              isNotNull,
              reason:
                  '${part.uri} / ${rel.id} must resolve after relocating the main part',
            );
          }
        }
        Directory('build/fidelity-story-media').createSync(recursive: true);
        File(
          'build/fidelity-story-media/relocated-edited-$cycle.docx',
        ).writeAsBytesSync(bytes);
        document = WordDeserializer().readBytes(bytes);
        expect(document.paragraphs.first.text, startsWith('Edited manuscript'));
        expect(document.footnotes.single.text, 'Edited relocated note');
        expect(document.sections.single.headerVisuals, hasLength(1));
      }
    },
  );
}
