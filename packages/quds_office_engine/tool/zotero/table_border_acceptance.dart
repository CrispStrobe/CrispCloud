// Actual LibreOffice file-save acceptance for editable Zotero table borders.
// This runs a local converter, not an installed Zotero plugin or Microsoft Word.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _json = JsonEncoder.withIndent('  ');
const _fixture = 'test/fixtures/zotero/converter/docx-cycle-1/cell.docx';
const _fixtureSha256 =
    'a91012793ddfd2d83fea7ee1754496fe9d4c0996f1fcce2701f001aa7286d5ef';

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _writeJson(File file, Object? value) =>
    file.writeAsStringSync('${_json.convert(value)}\n');

String _hash(File file) => sha256.convert(file.readAsBytesSync()).toString();

WmlParagraph _cited(String id) {
  final paragraph = WmlParagraph(inlines: [WmlRun(text: 'Research source ')]);
  WordZotero.insertCitation(
    paragraph,
    ZoteroCitation.fromJson({
      'citationID': id,
      'citationItems': [
        {
          'id': 'http://zotero.org/users/42/items/ABCD1234',
          'uris': ['http://zotero.org/users/42/items/ABCD1234'],
          'locator': '12–14',
          'label': 'page',
          'prefix': 'see ',
          'suffix': ' et seq.',
          'suppress-author': true,
          'itemData': {
            'id': 17,
            'type': 'book',
            'title': 'Bordered research table',
          },
          'futureItem': {'preserve': true},
        },
      ],
      'properties': {'plainCitation': '(Source)', 'noteIndex': 0},
      'futureCitation': ['preserve', 42, null],
    }),
    index: paragraph.text.length,
  );
  return paragraph;
}

WmlParagraph _text(String text) => WmlParagraph(inlines: [WmlRun(text: text)]);

WmlDocument _native({required bool merged}) {
  final table = WmlTable(
    grid: [180, 120],
    properties: WmlTableProps(
      borders: true,
      borderColor: merged ? '336699' : '2468AC',
      borderWidth: merged ? 0.75 : 1.25,
      cellMargin: merged ? 4 : 5,
    ),
    rows: [
      WmlTableRow(
        cells: [
          WmlTableCell(
            width: 180,
            vMerge: merged ? WmlVMerge.restart : WmlVMerge.none,
            blocks: [_cited(merged ? 'merged-owner' : 'colour-owner')],
          ),
          WmlTableCell(
            width: 120,
            borderRight: merged ? null : false,
            blocks: [_text('Neighbouring prose')],
          ),
        ],
      ),
      if (merged)
        WmlTableRow(
          cells: [
            WmlTableCell(
              width: 180,
              vMerge: WmlVMerge.cont,
              blocks: [WmlParagraph()],
            ),
            WmlTableCell(width: 120, blocks: [_text('Second row')]),
          ],
        ),
    ],
  );
  return WmlDocument(
    zoteroDocumentData: jsonEncode({
      'dataVersion': 4,
      'sessionID': 'table-border-acceptance',
      'style': {
        'styleID': 'http://www.zotero.org/styles/apa',
        'locale': 'en-US',
      },
      'prefs': {'fieldType': 'Field', 'noteType': 0},
      'futureDocument': {'preserve': true},
    }),
    sections: [
      WmlSection(blocks: [table, _text('After the research table.')]),
    ],
  );
}

Map<String, Object?> _snapshot(WmlDocument document) {
  final tables = <Map<String, Object?>>[];
  final owners = Map<WmlParagraph, String>.identity();
  final prose = <Map<String, Object?>>[];
  void walk(Iterable<WmlBlock> blocks, String owner) {
    var paragraphIndex = 0;
    var tableIndex = 0;
    for (final block in blocks) {
      if (block is WmlParagraph) {
        final location = '$owner/p${paragraphIndex++}';
        owners[block] = location;
        prose.add({'owner': location, 'text': block.text.trim()});
      } else if (block is WmlTable) {
        final location = '$owner/t${tableIndex++}';
        final cells = <Map<String, Object?>>[];
        for (var r = 0; r < block.rows.length; r++) {
          final row = block.rows[r];
          for (var c = 0; c < row.cells.length; c++) {
            final cell = row.cells[c];
            final cellOwner = '$location/r$r/c$c';
            cells.add({
              'owner': cellOwner,
              'span': cell.gridSpan,
              'merge': cell.vMerge.name,
              'sides': [
                cell.borderTop ?? block.properties.borders,
                cell.borderRight ?? block.properties.borders,
                cell.borderBottom ?? block.properties.borders,
                cell.borderLeft ?? block.properties.borders,
              ],
            });
            walk(cell.blocks, cellOwner);
          }
        }
        tables.add({
          'owner': location,
          'width': block.properties.borderWidth,
          'color': (block.properties.borderColor ?? '000000').toUpperCase(),
          'padding': block.properties.cellMargin,
          'grid': [...block.grid],
          'cells': cells,
        });
      }
    }
  }

  for (var index = 0; index < document.sections.length; index++) {
    walk(document.sections[index].blocks, 'section$index');
  }
  _require(document.footnotes.isEmpty, 'Unexpected footnotes');
  _require(document.endnotes.isEmpty, 'Unexpected endnotes');
  final fields = WordZotero.fields(document);
  _require(fields.isNotEmpty, 'Missing active citation fields');
  _require(
    WordFieldSpans.unbalanced(document).isEmpty,
    'Unbalanced active field structures',
  );
  return {
    'tables': tables,
    'prose': prose,
    'preferences': jsonDecode(WordZoteroDocumentData.read(document)),
    'fields': [
      for (final field in fields)
        {
          'data': field.citation?.toJson(),
          'text': field.cachedText,
          'editable': field.canEdit,
          'owner': owners[field.paragraph],
        },
    ],
  };
}

void _checkRetainedSourceBorders(WmlDocument document) {
  // Independent source oracle: the unchanged, hash-bound Writer DOCX fixture
  // has top/start/bottom/end single black 4-eighth-point borders on both cells.
  // Deriving expectations only from the deserialized native snapshot would
  // conceal an importer that had already discarded logical start/end edges.
  final table = document.sections.single.blocks.whereType<WmlTable>().single;
  _require(table.rows.single.cells.length == 2, 'Retained source grid changed');
  _require(
    table.properties.borderWidth == 0.5,
    'Retained source stroke width changed',
  );
  _require(
    (table.properties.borderColor ?? '000000').toUpperCase() == '000000',
    'Retained source stroke color changed',
  );
  for (final cell in table.rows.single.cells) {
    _require(
      [
        cell.borderTop ?? table.properties.borders,
        cell.borderRight ?? table.properties.borders,
        cell.borderBottom ?? table.properties.borders,
        cell.borderLeft ?? table.properties.borders,
      ].every((edge) => edge),
      'Retained DOCX logical start/end borders were not imported as visible sides',
    );
  }
}

void _compare(Object? expected, Object? actual, [String path = 'document']) {
  if (expected is Map<String, Object?> && actual is Map<String, Object?>) {
    _require(
      expected.length == actual.length &&
          expected.keys.every(actual.containsKey),
      '$path: map keys changed',
    );
    for (final key in expected.keys) {
      _compare(expected[key], actual[key], '$path/$key');
    }
  } else if (expected is List<Object?> && actual is List<Object?>) {
    _require(expected.length == actual.length, '$path: list length changed');
    for (var index = 0; index < expected.length; index++) {
      _compare(expected[index], actual[index], '$path/$index');
    }
  } else if (expected is num &&
      actual is num &&
      path.startsWith('document/tables/')) {
    // Word rounds dimensions to twips; Writer serializes ODF metric lengths.
    // Compare every cycle with the original, so accumulated drift cannot pass.
    final tolerance = path.endsWith('/width') ? 0.000001 : 0.05;
    _require(
      (expected - actual).abs() <= tolerance,
      '$path: $actual differs from $expected (tolerance $tolerance)',
    );
  } else {
    _require(actual == expected, '$path: $actual differs from $expected');
  }
}

Map<String, String> _sourceHashes(Directory package) {
  final files = <File>[
    ...Directory('${package.path}/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart')),
    File.fromUri(Platform.script),
    File('${package.path}/$_fixture'),
    File('${package.path}/pubspec.yaml'),
    File('${package.parent.parent.path}/pubspec.yaml'),
    File('${package.parent.parent.path}/pubspec.lock'),
    File('${package.parent.parent.path}/.dart_tool/package_config.json'),
  ]..sort((a, b) => a.path.compareTo(b.path));
  return {for (final file in files) file.absolute.path: _hash(file)};
}

Future<Map<String, Object?>> _command(
  String executable,
  List<String> arguments,
  Directory output,
  String label,
) async {
  final started = DateTime.now().toUtc();
  final result = await Process.run(executable, arguments);
  File(
    '${output.path}/$label.stdout',
  ).writeAsStringSync(result.stdout as String);
  File(
    '${output.path}/$label.stderr',
  ).writeAsStringSync(result.stderr as String);
  final record = <String, Object?>{
    'executable': executable,
    'arguments': arguments,
    'startedUtc': started.toIso8601String(),
    'finishedUtc': DateTime.now().toUtc().toIso8601String(),
    'exitCode': result.exitCode,
  };
  _writeJson(File('${output.path}/$label.command.json'), record);
  _require(result.exitCode == 0, '$label failed with exit ${result.exitCode}');
  return record;
}

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/zotero/table_border_acceptance.dart '
      'NEW_OUTPUT_DIRECTORY [SOFFICE_EXECUTABLE]',
    );
    exitCode = 64;
    return;
  }
  final output = Directory(args.first).absolute;
  _require(
    !output.existsSync(),
    'Use a new output directory to retain prior evidence.',
  );
  output.createSync(recursive: true);
  final package = File.fromUri(Platform.script).parent.parent.parent;
  final converter = args.length == 2 ? args[1] : 'soffice';
  final before = _sourceHashes(package);
  _writeJson(File('${output.path}/source-before.json'), before);
  final git = await Process.run('git', [
    'rev-parse',
    'HEAD',
  ], workingDirectory: package.path);
  final summary = <String, Object?>{
    'startedUtc': DateTime.now().toUtc().toIso8601String(),
    'sourceCommit': (git.stdout as String).trim(),
    'dartVersion': Platform.version,
    'scope':
        'Actual LibreOffice file saves and native field/geometry preservation; '
        'not installed Zotero-plugin or Microsoft Word acceptance, or pixel-equivalent layout.',
    'cases': <Map<String, Object?>>[],
  };
  final cases = summary['cases']! as List<Map<String, Object?>>;
  var passed = true;
  try {
    await _command(converter, ['--version'], output, 'converter-version');
    summary['converterVersion'] = File(
      '${output.path}/converter-version.stdout',
    ).readAsStringSync().trim();
    final fixture = File('${package.path}/$_fixture');
    summary['retainedFixtureSha256'] = _hash(fixture);
    _require(
      _hash(fixture) == _fixtureSha256,
      'The retained fixture no longer matches its independently reviewed source',
    );
    File(
      '${output.path}/retained-cell-input.docx',
    ).writeAsBytesSync(fixture.readAsBytesSync());
    final documents = <String, WmlDocument>{
      'retained-cell': WordDeserializer().readBytes(fixture.readAsBytesSync()),
      'coloured-sides': _native(merged: false),
      'merged-colour': _native(merged: true),
    };
    for (final entry in documents.entries) {
      final record = <String, Object?>{'name': entry.key, 'stages': <String>[]};
      final stages = record['stages']! as List<String>;
      cases.add(record);
      final folder = Directory('${output.path}/${entry.key}')..createSync();
      try {
        if (entry.key == 'retained-cell') {
          _checkRetainedSourceBorders(entry.value);
        }
        final expected = _snapshot(entry.value);
        _require(
          (expected['fields']! as List<Object?>).every(
            (value) => (value! as Map<String, Object?>)['editable'] == true,
          ),
          'Input fields are not editable',
        );
        _writeJson(File('${folder.path}/expected.json'), expected);
        var document = entry.value;
        for (var externalCycle = 1; externalCycle <= 2; externalCycle++) {
          final generated = Directory('${folder.path}/generated-$externalCycle')
            ..createSync();
          final source = File('${generated.path}/${entry.key}.odt');
          source.writeAsBytesSync(
            OdtDocumentWriter.writeEditableZoteroBytes(document),
          );
          final inventory = await OdfZotero.inspect(source.readAsBytesSync());
          _require(
            inventory.issues.isEmpty &&
                inventory.fields.every((field) => field.isImportCandidate),
            'Generated ODT has invalid citation inventory',
          );
          _compare(
            expected,
            _snapshot(
              await OdtDocumentReader.readBytes(source.readAsBytesSync()),
            ),
          );
          stages.add('generated-$externalCycle');
          final returned = Directory(
            '${folder.path}/libreoffice-$externalCycle',
          )..createSync();
          final profile = Directory('${folder.path}/profile-$externalCycle');
          await _command(
            converter,
            [
              '-env:UserInstallation=${profile.uri}',
              '--headless',
              '--convert-to',
              'odt',
              '--outdir',
              returned.path,
              source.path,
            ],
            folder,
            'libreoffice-$externalCycle',
          );
          final saved = File('${returned.path}/${entry.key}.odt');
          _require(saved.existsSync(), 'LibreOffice produced no saved ODT');
          document = await OdtDocumentReader.readBytes(saved.readAsBytesSync());
          _writeJson(
            File('${folder.path}/returned-$externalCycle.json'),
            _snapshot(document),
          );
          _compare(expected, _snapshot(document));
          stages.add('libreoffice-$externalCycle');
          for (var nativeCycle = 1; nativeCycle <= 2; nativeCycle++) {
            final name = 'cycle-$externalCycle-$nativeCycle';
            final docx = File('${folder.path}/$name.docx');
            docx.writeAsBytesSync(WordSerializer().writeBytes(document));
            document = WordDeserializer().readBytes(docx.readAsBytesSync());
            _compare(expected, _snapshot(document));
            final odt = File('${folder.path}/$name.odt');
            odt.writeAsBytesSync(
              OdtDocumentWriter.writeEditableZoteroBytes(document),
            );
            document = await OdtDocumentReader.readBytes(odt.readAsBytesSync());
            _compare(expected, _snapshot(document));
            stages.add(name);
          }
        }
        record['status'] = 'passed';
      } catch (error, stack) {
        passed = false;
        record['status'] = 'failed';
        record['error'] = '$error';
        record['stack'] = '$stack';
      }
    }
  } catch (error, stack) {
    passed = false;
    summary['error'] = '$error';
    summary['stack'] = '$stack';
  } finally {
    final after = _sourceHashes(package);
    _writeJson(File('${output.path}/source-after.json'), after);
    final changed = {
      ...before.keys,
      ...after.keys,
    }.where((path) => before[path] != after[path]).toList()..sort();
    summary['changedInputs'] = changed;
    summary['capturedInputs'] = before.length;
    if (changed.isNotEmpty) passed = false;
    summary['success'] = passed;
    summary['finishedUtc'] = DateTime.now().toUtc().toIso8601String();
    _writeJson(File('${output.path}/summary.json'), summary);
    final artifacts =
        output
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => !file.path.contains('/profile-'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    _writeJson(File('${output.path}/artifacts.json'), {
      for (final file in artifacts)
        file.path.substring(output.path.length + 1): {
          'bytes': file.lengthSync(),
          'sha256': _hash(file),
        },
    });
    stdout.writeln(_json.convert(summary));
    if (!passed) exitCode = 1;
  }
}
