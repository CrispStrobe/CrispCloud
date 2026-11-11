import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/office_steps.dart' as cli;
import '../tool/fidelity/sheet_steps.dart';
import '../tool/fidelity/slide_steps.dart';
import '../tool/fidelity/step_input.dart';

void main() {
  const fixtures = 'test/fixtures/fidelity';
  for (final entry in <String, String>{
    'word': 'docx',
    'sheet': 'xlsx',
    'slide': 'pptx',
  }.entries) {
    test('${entry.value}: script and three async export/reopen cycles', () async {
      final input = entry.key == 'word'
          ? '$fixtures/word.docx'
          : '$fixtures/native.${entry.value}';
      final output =
          'build/fidelity-scripted/${entry.key}/edited.${entry.value}';
      await cli.execute([
        'modify',
        input,
        '$fixtures/scripts/${entry.key}.json',
        output,
      ]);
      await cli.execute([
        'roundtrip',
        output,
        'build/fidelity-scripted/${entry.key}',
        '3',
      ]);
      for (var cycle = 1; cycle <= 3; cycle++) {
        expect(
          File(
            'build/fidelity-scripted/${entry.key}/roundtrip-$cycle.${entry.value}',
          ).lengthSync(),
          greaterThan(1000),
        );
      }
    });
  }
  WmlDocument fixture() => WordDeserializer().readBytes(
    File('$fixtures/word.docx').readAsBytesSync(),
  );
  for (final step in <Map<String, Object?>>[
    {'op': 'heading', 'paragraph': 0, 'level': 10},
    {'op': 'heading', 'paragraph': 0, 'level': 2, 'levle': 2},
    {'op': 'heading', 'paragraph': -1, 'level': 2},
    {'op': 'replaceText', 'paragraph': 0, 'start': 99, 'text': 'x'},
    {'op': 'replaceText', 'paragraph': 0, 'start': 4, 'end': 2, 'text': 'x'},
    {'op': 'runFormat', 'paragraph': 0, 'color': 'NOTRGB'},
    {'op': 'runFormat', 'paragraph': 0, 'size': 0},
    {'op': 'imageSize', 'image': 0, 'width': -1},
    {'op': 'imageSize', 'image': 0},
    {
      'op': 'imageReplace',
      'image': 0,
      'file': 'test/fixtures/fidelity/scripts/word.json',
    },
    {'op': 'paragraphFormat', 'paragraph': 0, 'lineSpacing': 0},
    {'op': 'paragraphFormat', 'paragraph': 0, 'bold': true},
    {'op': 'applyStyle', 'paragraph': 0, 'style': 'AbsentStyle'},
    {'op': 'characterStyle', 'paragraph': 0, 'run': 0, 'style': 'Heading1'},
    {'op': 'tableStyle', 'table': 0, 'style': 'Heading1'},
    {'op': 'list', 'paragraph': 0, 'numbered': true, 'level': 9},
    {'op': 'listRestart', 'paragraph': 0},
    {'op': 'headerFooterText', 'story': 'wrong', 'text': 'x'},
    {'op': 'sectionFormat', 'left': 600, 'right': 600},
    {'op': 'sectionFormat', 'columns': 45, 'columnSpace': 600},
    {
      'op': 'runFormat',
      'paragraph': 0,
      'story': 'footnote',
      'note': 999,
      'bold': true,
    },
  ]) {
    test('reject invalid step ${jsonEncode(step)}', () {
      expect(() => cli.applyStep(fixture(), step), throwsArgumentError);
    });
  }
  test('text operations reject offsets inside emoji or a note marker', () {
    final doc = WmlDocument(
      sections: [
        WmlSection(
          blocks: [
            WmlParagraph(inlines: [WmlRun(text: 'A😀B')]),
          ],
        ),
      ],
    );
    expect(
      () => cli.applyStep(doc, {
        'op': 'paragraphSplit',
        'paragraph': 0,
        'offset': 2,
      }),
      throwsArgumentError,
    );
    final imported = fixture();
    expect(
      () => cli.applyStep(imported, {
        'op': 'addNote',
        'paragraph': 1,
        'offset': 10,
        'text': 'bad offset',
      }),
      throwsArgumentError,
    );
  });
  test(
    'failed later edit leaves input and existing output untouched',
    () async {
      final temporary = Directory.systemTemp.createTempSync('office-script-');
      addTearDown(() => temporary.deleteSync(recursive: true));
      final input = File('$fixtures/word.docx');
      final before = input.readAsBytesSync();
      final output = File('${temporary.path}/existing.docx')
        ..writeAsStringSync('sentinel');
      final script = File('${temporary.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {'op': 'heading', 'paragraph': 0, 'level': 2},
            {'op': 'imageReplace', 'image': 0, 'file': 'missing.png'},
          ]),
        );
      await expectLater(
        cli.execute(['modify', input.path, script.path, output.path]),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'sentinel');
      expect(input.readAsBytesSync(), before);
      expect(temporary.listSync().length, 2);
    },
  );
  test('output extension mismatch fails without creating output', () async {
    final tmp = Directory.systemTemp.createTempSync('office-format-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    await expectLater(
      cli.execute(['export', '$fixtures/word.docx', '${tmp.path}/wrong.xlsx']),
      throwsArgumentError,
    );
    expect(tmp.listSync(), isEmpty);
  });
  test('script JSON must be an array of objects', () {
    final tmp = Directory.systemTemp.createTempSync('office-json-');
    addTearDown(() => tmp.deleteSync(recursive: true));
    for (final data in ['{}', '[2]', '[null]']) {
      final path = '${tmp.path}/steps.json';
      File(path).writeAsStringSync(data);
      expect(() => readSteps(path), throwsFormatException);
    }
  });
  test('spreadsheet rejects out-of-bounds cells and duplicate sheet names', () {
    final book = SheetDeserializer().readBytes(
      File('$fixtures/native.xlsx').readAsBytesSync(),
    );
    for (final address in ['A0', 'XFE1', 'A1048577']) {
      expect(
        () => applySheetStep(book, {
          'op': 'cellValue',
          'cell': address,
          'value': 1,
        }),
        throwsArgumentError,
      );
    }
    expect(
      () => applySheetStep(book, {
        'op': 'renameSheet',
        'sheet': 1,
        'name': 'data',
      }),
      throwsArgumentError,
    );
    expect(
      () => applySheetStep(book, {
        'op': 'cellFormula',
        'cell': 'A1',
        'formula': '=',
      }),
      throwsArgumentError,
    );
  });
  test('presentation refuses to edit a picture as text', () {
    final deck = SlideDeserializer().readBytes(
      File('$fixtures/native.pptx').readAsBytesSync(),
    );
    expect(
      () => applySlideStep(deck, {'op': 'shapeText', 'shape': 1, 'text': 'x'}),
      throwsArgumentError,
    );
    expect(
      () => applySlideStep(deck, {'op': 'shapeFormat', 'shape': 1, 'size': 30}),
      throwsArgumentError,
    );
    expect(
      () =>
          applySlideStep(deck, {'op': 'shapeGeometry', 'shape': 0, 'width': 0}),
      throwsArgumentError,
    );
  });
}
