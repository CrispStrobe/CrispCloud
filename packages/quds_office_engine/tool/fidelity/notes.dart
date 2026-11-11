import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'note_fixture.dart';

Future<void> main() async {
  final Directory output = Directory('build/fidelity-notes')
    ..createSync(recursive: true);
  for (final bool edited in <bool>[false, true]) {
    WmlDocument doc = richNoteFixture();
    if (!edited)
      File('${output.path}/source.docx').writeAsBytesSync(doc.package!.save());
    if (edited) {
      final WmlNote note = doc.footnotes.single;
      final WmlRun run = note.paragraphs.first.inlines
          .whereType<WmlRun>()
          .firstWhere((WmlRun r) => r.text.contains('Rich note'));
      run.text = 'Revised note';
      run.properties.color = '224466';
      final WmlTable table = note.blocks.whereType<WmlTable>().single;
      table.rows.first.cells.first.blocks
              .whereType<WmlParagraph>()
              .first
              .inlines
              .whereType<WmlRun>()
              .first
              .text =
          'Revised table';
      note.visuals.single.visual
        ..width = 72
        ..height = 48;
    }
    for (var cycle = 1; cycle <= 3; cycle++) {
      final bytes = await OfficeIsolateSave.word(doc);
      File(
        '${output.path}/${edited ? 'edited' : 'unchanged'}-$cycle.docx',
      ).writeAsBytesSync(bytes);
      doc = WordDeserializer().readBytes(bytes);
    }
  }
}
