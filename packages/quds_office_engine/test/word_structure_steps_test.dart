import 'dart:convert';
import 'dart:io';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:test/test.dart';
import '../tool/fidelity/office_steps.dart' as cli;
import '../tool/fidelity/step_input.dart';

WmlDocument source() {
  final package = OpcPackage.create(OpcPackageKind.word);
  package
      .getPart('/word/document.xml')!
      .writeText(
        File(
          'test/fixtures/fidelity/word_structure_source.xml',
        ).readAsStringSync(),
      );
  return WordDeserializer().read(package);
}

void main() {
  test(
    'authored structural scripts retain each phase across async exports',
    () async {
      const root = 'build/fidelity-structure';
      final package = OpcPackage.create(OpcPackageKind.word);
      package
          .getPart('/word/document.xml')!
          .writeText(
            File(
              'test/fixtures/fidelity/word_structure_source.xml',
            ).readAsStringSync(),
          );
      writeOutput('$root/source.docx', package.save());
      var input = '$root/source.docx';
      for (final phase in ['create', 'edit', 'remove']) {
        final output = '$root/$phase/edited.docx';
        await cli.execute([
          'modify',
          input,
          'test/fixtures/fidelity/scripts/word-structure-$phase.json',
          output,
        ]);
        await cli.execute(['roundtrip', output, '$root/$phase', '3']);
        final document = WordDeserializer().readBytes(
          File(output).readAsBytesSync(),
        );
        final inspected = cli.inspectWord(document);
        expect(inspected['tables'], hasLength(1));
        expect(inspected['comments'], hasLength(phase == 'remove' ? 0 : 2));
        expect(inspected['frames'], hasLength(phase == 'remove' ? 0 : 1));
        expect(inspected['tocs'], hasLength(phase == 'remove' ? 0 : 1));
        input = '$root/$phase/roundtrip-3.docx';
      }
    },
  );

  for (final step in <Map<String, Object?>>[
    {'op': 'tableAdd', 'rows': 0, 'columns': 2, 'width': 100},
    {'op': 'tableAdd', 'rows': 2, 'columns': 0, 'width': 100},
    {'op': 'tableAdd', 'rows': 2, 'columns': 2, 'width': double.nan},
    {'op': 'tableAdd', 'rows': 2, 'columns': 2, 'width': 100, 'index': 100},
    {'op': 'tocAdd', 'minLevel': 3, 'maxLevel': 2},
    {'op': 'bookmarkSet', 'paragraph': 1, 'name': 'invalid name'},
    {'op': 'reference', 'paragraph': 1, 'bookmark': 'Missing'},
    {
      'op': 'commentAdd',
      'paragraph': 1,
      'start': 2,
      'end': 2,
      'text': 'unanchored',
    },
    {'op': 'commentAdd', 'paragraph': 1, 'text': 'x', 'date': 'not a date'},
    {'op': 'commentReply', 'id': 999, 'text': 'orphan'},
    {'op': 'commentResolve', 'id': 999, 'resolved': true},
    {'op': 'frameAdd', 'text': 'x', 'width': 0},
    {'op': 'frameAdd', 'text': 'x', 'wrap': 'tight'},
    {
      'op': 'paragraphFormat',
      'paragraph': 1,
      'left': 12,
      'firstLine': 2,
      'hanging': 2,
    },
    {
      'op': 'paragraphFormat',
      'paragraph': 1,
      'tabs': [
        {'position': 12},
        {'position': 12},
      ],
    },
    {
      'op': 'paragraphFormat',
      'paragraph': 1,
      'tabs': [
        {'position': 12, 'alginment': 'right'},
      ],
    },
  ]) {
    test(
      'reject ${step['op']} invalid fields without modifying the model: $step',
      () {
        final doc = source();
        final before = jsonEncode(cli.inspectWord(doc));
        expect(() => cli.applyStep(doc, step), throwsArgumentError);
        expect(jsonEncode(cli.inspectWord(doc)), before);
      },
    );
  }
  test(
    'structural table edits reject merged grids until explicitly unmerged',
    () {
      final doc = source();
      cli.applyStep(doc, {
        'op': 'tableAdd',
        'rows': 2,
        'columns': 2,
        'width': 240,
      });
      cli.applyStep(doc, {
        'op': 'tableMerge',
        'table': 0,
        'row': 0,
        'column': 0,
        'endRow': 0,
        'endColumn': 1,
      });
      final before = jsonEncode(cli.inspectWord(doc));
      for (final op in [
        'tableRowInsert',
        'tableRowDelete',
        'tableColumnInsert',
        'tableColumnDelete',
      ]) {
        expect(
          () => cli.applyStep(doc, {
            'op': op,
            'table': 0,
            op.startsWith('tableRow') ? 'row' : 'column': 0,
          }),
          throwsArgumentError,
        );
        expect(jsonEncode(cli.inspectWord(doc)), before);
      }
      cli.applyStep(doc, {
        'op': 'tableUnmerge',
        'table': 0,
        'row': 0,
        'column': 0,
      });
      cli.applyStep(doc, {'op': 'tableColumnInsert', 'table': 0, 'column': 1});
      final table = doc.sections.single.blocks.whereType<WmlTable>().single;
      expect(table.rows.map((row) => row.cells.length), [3, 3]);
    },
  );
  test('comment range cannot cut an emoji or atomic note reference', () {
    final doc = source();
    doc.paragraphs.first.inlines = [
      WmlRun(text: 'A😀B'),
      WmlRun(text: '12', noteRefId: 12),
    ];
    for (final (start, end) in [(1, 2), (5, 6)]) {
      expect(
        () => cli.applyStep(doc, {
          'op': 'commentAdd',
          'paragraph': 0,
          'start': start,
          'end': end,
          'text': 'invalid',
        }),
        throwsArgumentError,
      );
      expect(doc.comments, isEmpty);
    }
  });
  test(
    'failed late structural step cannot replace an existing output',
    () async {
      final tmp = Directory.systemTemp.createTempSync('word-structure-');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final input = File('${tmp.path}/source.docx')
        ..writeAsBytesSync(WordSerializer().write(source()).save());
      final output = File('${tmp.path}/existing.docx')
        ..writeAsStringSync('keep existing output');
      final script = File('${tmp.path}/steps.json')
        ..writeAsStringSync(
          jsonEncode([
            {'op': 'tableAdd', 'rows': 2, 'columns': 2, 'width': 240},
            {'op': 'tableUnmerge', 'table': 0, 'row': 0, 'column': 0},
          ]),
        );
      await expectLater(
        cli.execute(['modify', input.path, script.path, output.path]),
        throwsStateError,
      );
      expect(output.readAsStringSync(), 'keep existing output');
      expect(tmp.listSync().length, 3);
    },
  );
}
