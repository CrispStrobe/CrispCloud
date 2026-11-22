import 'package:quds_office_engine/quds_office_automation.dart';
import 'package:quds_office_engine/quds_office_engine.dart';
import 'package:quds_office_engine/src/automation/operations/word_steps.dart'
    as native;
import 'package:test/test.dart';

WmlParagraph _paragraph(String text) => WmlParagraph(
  inlines: [
    WmlRun(
      text: text,
      properties: WmlRunProps(italic: true, color: '123456'),
    ),
  ],
);

WmlTable _table(String name) => WmlTable(
  grid: [80, 90],
  rows: [
    for (var row = 0; row < 2; row++)
      WmlTableRow(
        cells: [
          for (var column = 0; column < 2; column++)
            WmlTableCell(blocks: [_paragraph('$name $row/$column')]),
        ],
      ),
  ],
);

WmlDocument _document() => WmlDocument(
  sections: [
    WmlSection(blocks: [_paragraph('Body'), _table('First')]),
    WmlSection(blocks: [_table('Second')]),
  ],
);

WmlTable _firstTable(WmlDocument document) =>
    document.sections.first.blocks.whereType<WmlTable>().single;

WmlParagraph _target(WmlDocument document) =>
    _firstTable(document).rows.first.cells.first.blocks.single as WmlParagraph;

Map<String, Object?> _arguments([Map<String, Object?> changes = const {}]) => {
  'story': 'tableCell',
  'table': 0,
  'row': 0,
  'column': 0,
  'paragraph': 0,
  'bold': true,
  ...changes,
};

void _refuse(
  WmlDocument document,
  Map<String, Object?> arguments, {
  Matcher matcher = throwsArgumentError,
  String tool = 'docx.runFormat',
  bool lowLevel = false,
}) {
  final target = _target(document);
  final inlines = target.inlines;
  final paragraphProperties = target.properties;
  final run = target.inlines.first as WmlRun;
  final runProperties = run.properties;
  final text = target.text;
  final before = (
    runProperties.bold,
    runProperties.italic,
    runProperties.color,
  );
  final body = document.sections.first.blocks.first as WmlParagraph;
  final bodyInlines = body.inlines;
  final bodyRun = body.inlines.single as WmlRun;
  final bodyProperties = bodyRun.properties;
  final bodyBefore = (
    body.text,
    bodyProperties.bold,
    bodyProperties.italic,
    bodyProperties.color,
  );
  expect(() {
    if (lowLevel) {
      native.applyStep(document, {'op': tool.split('.').last, ...arguments});
    } else {
      OfficeOperationCatalog.apply(document, tool, arguments);
    }
  }, matcher);
  expect(target.inlines, same(inlines));
  expect(target.properties, same(paragraphProperties));
  expect(run.properties, same(runProperties));
  expect(target.text, text);
  expect((
    runProperties.bold,
    runProperties.italic,
    runProperties.color,
  ), before);
  expect(body.inlines, same(bodyInlines));
  expect(bodyRun.properties, same(bodyProperties));
  expect((
    body.text,
    bodyProperties.bold,
    bodyProperties.italic,
    bodyProperties.color,
  ), bodyBefore);
}

void main() {
  test(
    'formatting selects direct tables across sections without changing owners',
    () {
      final document = _document();
      final table = document.sections.last.blocks.single as WmlTable;
      final cell = table.rows[1].cells[1];
      final paragraph = cell.blocks.single as WmlParagraph;
      OfficeOperationCatalog.apply(
        document,
        'docx.runFormat',
        _arguments({'table': 1, 'row': 1, 'column': 1, 'color': 'A1B2C3'}),
      );
      expect(document.sections.last.blocks.single, same(table));
      expect(table.rows[1].cells[1], same(cell));
      expect(cell.blocks.single, same(paragraph));
      expect(paragraph.text, 'Second 1/1');
      final run = paragraph.inlines.single as WmlRun;
      expect(run.properties.bold, isTrue);
      expect(run.properties.italic, isTrue);
      expect(run.properties.color, 'A1B2C3');
      expect(
        (_target(document).inlines.single as WmlRun).properties.bold,
        isFalse,
      );
      expect(
        (table.rows[1].cells[0].blocks.single as WmlParagraph).text,
        'Second 1/0',
      );
    },
  );

  for (final (label, changes) in <(String, Map<String, Object?>)>[
    ('body fallback', {'story': 'body'}),
    ('header fallback', {'story': 'header'}),
    ('unknown story', {'story': 'typo'}),
    ('section mixing', {'section': 0}),
    ('note mixing', {'note': 1}),
    ('comment mixing', {'comment': 1}),
    ('start offset', {'start': 0}),
    ('end offset', {'end': 9}),
    ('another paragraph', {'paragraph': 1}),
    ('negative table', {'table': -1}),
    ('fractional row', {'row': 0.5}),
    ('boolean column', {'column': false}),
    ('null coordinate', {'table': null}),
    ('missing table', {'table': 2}),
    ('missing row', {'row': 2}),
    ('missing column', {'column': 2}),
  ]) {
    test('rejects $label without formatting the body or a different cell', () {
      _refuse(_document(), _arguments(changes));
    });
  }

  for (final key in ['story', 'table', 'row', 'column', 'paragraph']) {
    test('requires explicit cell selector field $key', () {
      _refuse(_document(), _arguments()..remove(key));
    });
  }

  test('low-level native dispatch has the same cell-selector contract', () {
    _refuse(_document(), _arguments({'story': 'body'}), lowLevel: true);
  });

  test('cell story does not enable arbitrary native text edits', () {
    final document = _document();
    _refuse(
      document,
      {'story': 'tableCell', 'paragraph': 0, 'text': 'unsupported'},
      tool: 'docx.replaceText',
      matcher: throwsUnsupportedError,
    );
  });

  test('invalid formatting fails before splitting or changing runs', () {
    final document = _document();
    _target(document).inlines.add(WmlRun(text: ' second run'));
    _refuse(document, _arguments({'color': 'not a color'}));
    _refuse(document, _arguments({'size': -1}));
    _refuse(document, _arguments({'allCaps': true, 'smallCaps': true}));
  });

  test(
    'shared cell paragraph ownership is refused before ordinary admission',
    () {
      final document = _document();
      _firstTable(document).rows[0].cells[1].blocks = [_target(document)];
      _refuse(document, _arguments(), matcher: throwsUnsupportedError);
    },
  );

  test('shared cell run ownership is refused before ordinary admission', () {
    final document = _document();
    final other =
        _firstTable(document).rows[0].cells[1].blocks.single as WmlParagraph;
    other.inlines.add(_target(document).inlines.single);
    _refuse(document, _arguments(), matcher: throwsUnsupportedError);
  });

  test('cyclic table graph is refused before recursive admission', () {
    final document = _document();
    final table = _firstTable(document);
    table.rows[1].cells[1].blocks.add(table);
    _refuse(document, _arguments(), matcher: throwsUnsupportedError);
  });

  test('shared run properties do not leak formatting into another cell', () {
    final document = _document();
    final paragraph = _target(document);
    final selected = paragraph.inlines.single as WmlRun;
    final other =
        _firstTable(document).rows[0].cells[1].blocks.single as WmlParagraph;
    final shared = selected.properties;
    (other.inlines.single as WmlRun).properties = shared;
    OfficeOperationCatalog.apply(document, 'docx.runFormat', _arguments());
    final updated = (paragraph.inlines.single as WmlRun).properties;
    expect(updated.bold, isTrue);
    expect(updated, isNot(same(shared)));
    expect((other.inlines.single as WmlRun).properties, same(shared));
    expect(shared.bold, isFalse);
    expect(shared.explicitProperties, isEmpty);
  });

  test('shared imported property maps remain unchanged outside the cell', () {
    final document = _document();
    final selected = _target(document).inlines.single as WmlRun;
    final body = document.sections.first.blocks.first as WmlParagraph;
    final other = body.inlines.single as WmlRun;
    final shared = <String, String>{'b': '0', 'color': '123456'};
    selected.properties.importedValues = shared;
    other.properties.importedValues = shared;
    OfficeOperationCatalog.apply(
      document,
      'docx.runFormat',
      _arguments({'color': 'A1B2C3'}),
    );
    final updated = (_target(document).inlines.single as WmlRun).properties;
    expect(updated.bold, isTrue);
    expect(updated.color, 'A1B2C3');
    expect(updated.importedValues, isEmpty);
    expect(other.properties.importedValues, same(shared));
    expect(shared, {'b': '0', 'color': '123456'});
    expect(other.properties.color, '123456');
  });

  test('empty cells retain paragraph formatting without creating a run', () {
    final document = _document();
    final paragraph = _target(document)..inlines.clear();
    final arguments = _arguments({'alignment': 'right', 'after': 6})
      ..remove('bold');
    OfficeOperationCatalog.apply(document, 'docx.paragraphFormat', arguments);
    expect(paragraph.inlines, isEmpty);
    expect(paragraph.properties.justification, WmlJustification.right);
    expect(paragraph.properties.spacingAfter, 6);
    expect(
      () => OfficeOperationCatalog.apply(
        document,
        'docx.runFormat',
        _arguments(),
      ),
      throwsArgumentError,
    );
    expect(paragraph.inlines, isEmpty);
  });
}
