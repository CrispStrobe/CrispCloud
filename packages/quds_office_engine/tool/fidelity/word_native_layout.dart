// Explicit native reference producer; never runs or regenerates goldens in tests.
// dart run tool/fidelity/word_native_layout.dart /absolute/corpus/directory
import 'dart:convert';
import 'dart:io';

import 'package:quds_office_engine/quds_office_engine.dart';

void main(List<String> args) {
  if (args.length != 1) {
    throw ArgumentError('Supply a corpus directory containing manifest.json.');
  }
  final directory = Directory(args.single);
  final cases =
      jsonDecode(File('${directory.path}/manifest.json').readAsStringSync())
          as List;
  if (cases.isEmpty) {
    throw StateError('A native layout corpus must not be empty.');
  }
  final results = <Object>[];
  for (final value in cases) {
    final entry = value as Map<String, dynamic>;
    final name = entry['name'] as String;
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(name)) {
      throw FormatException('Invalid fixture name: $name');
    }
    final fontFile = File(entry['font'] as String);
    final font = SfntFont.parse(fontFile.readAsBytesSync());
    final fonts = OfficeFontSet(
      faces: [OfficeFontFace(font: font, family: entry['family'] as String)],
    );
    final document = WordDeserializer().readBytes(
      File('${directory.path}/$name.docx').readAsBytesSync(),
    );
    final laid = WordLayoutEngine(font: null, fonts: fonts).layout(document);
    File('${directory.path}/$name-quds.pdf').writeAsBytesSync(
      OfficePdfExport.word(document, fonts: fonts, laidOut: laid),
    );
    results.add({
      'name': name,
      'font': {
        'unitsPerEm': font.unitsPerEm,
        'ascender': font.ascender,
        'descender': font.descender,
        'lineGap': font.lineGap,
        'winAscent': font.winAscent,
        'winDescent': font.winDescent,
      },
      'pages': [
        for (final page in laid.pages)
          {
            'width': page.width,
            'height': page.height,
            'lines': [
              for (final line in page.lines)
                {
                  'text': line.text,
                  'x': line.x,
                  'y': line.y,
                  'height': line.height,
                  'width': line.width,
                },
            ],
          },
      ],
    });
  }
  File('${directory.path}/quds-layout.json').writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(results)}\n',
  );
  stdout.writeln('Rendered ${results.length} native-reference cases.');
}
