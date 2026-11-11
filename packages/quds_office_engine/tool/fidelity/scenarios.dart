import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_engine.dart';

/// Run from the engine package: dart run tool/fidelity/scenarios.dart [out-dir].
Future<void> main(List<String> args) async {
  final Directory out = Directory(args.isEmpty ? 'build/fidelity' : args.single)
    ..createSync(recursive: true);
  final Uint8List input = File(
    'test/fixtures/fidelity/word.docx',
  ).readAsBytesSync();
  final WordSerializer writer = WordSerializer();
  WmlDocument doc = WordDeserializer().readBytes(input);
  for (var cycle = 1; cycle <= 3; cycle++) {
    final Uint8List bytes = writer.writeBytes(doc);
    File('${out.path}/unchanged-$cycle.docx').writeAsBytesSync(bytes);
    doc = WordDeserializer().readBytes(bytes);
  }
  doc = WordDeserializer().readBytes(input);
  final List<WmlParagraph> paragraphs = doc.paragraphs.toList();
  WmlRunEdit.replaceRange(
    paragraphs[0],
    0,
    paragraphs[0].text.length,
    'Revised heading',
  );
  WmlRunEdit.replaceRange(paragraphs[1], 0, 'Body text'.length, 'Edited body');
  final WmlParagraph note = doc.footnotes.single.paragraphs.first;
  WmlRunEdit.replaceRange(note, 0, note.text.length, ' Edited footnote');
  doc.visuals.single.visual.width = 72;
  for (var cycle = 1; cycle <= 3; cycle++) {
    final Uint8List bytes = await OfficeIsolateSave.word(doc);
    File('${out.path}/edited-$cycle.docx').writeAsBytesSync(bytes);
    doc = WordDeserializer().readBytes(bytes);
  }
  stdout.writeln('Wrote six DOCX exports to ${out.path}.');
}
