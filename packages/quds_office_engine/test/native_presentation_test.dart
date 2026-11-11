import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';

void main() {
  test(
    'independent deck retains templates, distinct visuals, notes and sections',
    () async {
      var deck = SlideDeserializer().readBytes(
        File('test/fixtures/fidelity/native.pptx').readAsBytesSync(),
      );
      final package = deck.package!;
      final master = package
          .getPart('/ppt/slideMasters/slideMaster1.xml')!
          .readBytes();
      final theme = package.getPart('/ppt/theme/theme1.xml')!.readBytes();
      final images = [
        for (final s in deck.slides)
          s.shapes
              .firstWhere((s) => s.visual?.isPicture ?? false)
              .visual!
              .imageBytes!,
      ];
      deck.sections.addAll([
        PmlSection(name: 'First', startIndex: 0),
        PmlSection(name: 'Second', startIndex: 1),
      ]);
      for (int cycle = 1; cycle <= 3; cycle++) {
        final bytes = await OfficeIsolateSave.presentation(deck);
        final out = Directory('build/fidelity-native')
          ..createSync(recursive: true);
        File('${out.path}/native-slides-$cycle.pptx').writeAsBytesSync(bytes);
        deck = SlideDeserializer().readBytes(bytes);
        expect(deck.slides, hasLength(2));
        expect(deck.sections.map((s) => s.name), ['First', 'Second']);
        expect(deck.sections.map((s) => s.startIndex), [0, 1]);
        expect(
          deck.package!
              .getPart('/ppt/slideMasters/slideMaster1.xml')!
              .readBytes(),
          master,
        );
        expect(
          deck.package!.getPart('/ppt/theme/theme1.xml')!.readBytes(),
          theme,
        );
        for (int i = 0; i < 2; i++) {
          final slide = deck.slides[i];
          expect(slide.notes, contains('Speaker note ${i + 1}'));
          final picture = slide.shapes
              .firstWhere((s) => s.visual?.isPicture ?? false)
              .visual!;
          expect(picture.imageBytes, images[i]);
          final chart = slide.shapes
              .firstWhere((s) => s.visual?.isChart ?? false)
              .visual!;
          expect(chart.points.map((p) => p.value), [i + 2, i + 5]);
          final rels = deck.package!.relationshipsFor(slide.sourcePartUri!);
          expect(rels.firstByType(RelationshipTypes.slideLayout), isNotNull);
          final notes = rels.resolve(
            rels.firstByType(RelationshipTypes.notesSlide)!,
          );
          final noteRels = deck.package!.relationshipsFor(notes);
          expect(
            noteRels.resolve(noteRels.firstByType(RelationshipTypes.slide)!),
            slide.sourcePartUri,
          );
          expect(
            noteRels.firstByType(RelationshipTypes.notesMaster),
            isNotNull,
          );
        }
      }
      final firstUri = deck.slides.first.sourcePartUri;
      deck.slides = deck.slides.reversed.toList();
      deck.slides.first.notes = 'Revised speaker note';
      deck.slides.last.notes = '';
      deck.sections.clear();
      deck = SlideDeserializer().readBytes(
        await OfficeIsolateSave.presentation(deck),
      );
      expect(deck.slides.last.sourcePartUri, firstUri);
      expect(deck.slides.first.notes, 'Revised speaker note');
      expect(deck.slides.last.notes, isEmpty);
      expect(deck.sections, isEmpty);
      expect(
        deck.slides.first.shapes
            .firstWhere((s) => s.visual?.isChart ?? false)
            .visual!
            .points
            .first
            .value,
        3,
      );
    },
  );

  test('new presentations include masters layouts and required notes size', () {
    final package = SlideSerializer().write(PmlPresentation());
    final rels = package.relationshipsFor('/ppt/presentation.xml');
    final master = rels.firstByType(RelationshipTypes.slideMaster)!;
    expect(package.getPart(rels.resolve(master)), isNotNull);
    final xml = package.getPart('/ppt/presentation.xml')!.readText();
    expect(xml, contains('notesSz'));
    expect(xml, contains('sldMasterIdLst'));
  });
}
