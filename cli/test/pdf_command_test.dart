import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:crisp/cli_app.dart';
import 'package:crisp/commands/pdf.dart';
import 'package:crisp/config/cli_config.dart';
import 'package:pdf_operations/pdf_operations.dart';
import 'package:test/test.dart';

const _password = 'crispcloud-pdf-fixture';
const _imageBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAgAAAAECAIAAAA8r+mnAAAAFElEQVR4nGPcImfDgA0wYRUlSwIAacgBFketwNoAAAAASUVORK5CYII=';

void main() {
  late Directory temporary;
  late CliConfig config;
  late File source;
  late File encrypted;
  late String font;
  final service = PdfOperationsService();

  String repositoryFile(String name) {
    for (final prefix in ['..', '.']) {
      final file = File('$prefix/$name');
      if (file.existsSync()) return file.absolute.path;
    }
    throw StateError('Missing repository fixture: $name');
  }

  String target(String name) => '${temporary.path}/$name';

  Future<_Result> run(List<String> arguments, {String? stdinText}) async {
    final output = StringBuffer();
    final errors = StringBuffer();
    final runner = CommandRunner<int>('crisp', 'PDF tests')
      ..addCommand(PdfCommand(config,
          output: output, errors: errors,
          input: stdinText == null ? null : Stream.value(utf8.encode(stdinText)),
          inputHasTerminal: false));
    final code = await runner.run(['pdf', ...arguments]);
    return _Result(code ?? 0, output.toString(), errors.toString());
  }

  Future<File> passwordFile(String text) async {
    final file = File(target('password.txt'))..writeAsStringSync(text);
    if (!Platform.isWindows) {
      expect((await Process.run('chmod', ['600', file.path])).exitCode, 0);
    }
    return file;
  }

  PdfInspection inspectOutput(String name, {String password = ''}) =>
      service.inspect(PdfInput(File(target(name)).readAsBytesSync(), password: password));

  void retain(String name) {
    final destination = Platform.environment['PDF_CLI_VERIFY_DIR'];
    if (destination == null || destination.isEmpty) return;
    Directory(destination).createSync(recursive: true);
    File(target(name)).copySync('$destination/$name');
  }

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('crisp_pdf_command_');
    config = CliConfig(path: target('config.yaml'));
    source = File(repositoryFile('test/fixtures/pdf_editor/form_rotated.pdf'))
        .copySync(target('source.pdf'));
    encrypted = File(repositoryFile('test/fixtures/pdf_editor/form_rotated_encrypted.pdf'))
        .copySync(target('encrypted.pdf'));
    font = repositoryFile('assets/fonts/Roboto-Regular.ttf');
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('root runner exposes the complete PDF command family', () {
    final runner = buildRunner(configPath: config.configPath);
    expect(runner.commands['pdf']!.subcommands.keys,
        containsAll(['info', 'text', 'search', 'merge', 'extract', 'rotate',
          'reorder', 'delete-pages', 'watermark', 'fill', 'insert-image', 'ocr']));
  });

  test('info describes named fields and rotated page geometry as JSON', () async {
    final result = await run(['info', source.path, '--json']);
    expect(result.code, 0, reason: result.errors);
    expect(result.json['pageCount'], 2);
    expect((result.json['pages'] as List)[1]['rotation'], 90);
    expect((result.json['fields'] as List).map((field) => field['name']), contains('reviewer'));
    expect(result.json['encrypted'], isFalse);
  });

  test('text and regex search honor page ranges', () async {
    final result = await run(['text', source.path, '--pages', '2', '--json']);
    expect(result.code, 0, reason: result.errors);
    final pages = result.json['pages'] as List;
    expect(pages, hasLength(1));
    expect(pages.single['page'], 2);
    expect(pages.single['text'], contains('CRISPCLOUD_PAGE_TWO'));

    final search = await run(['search', source.path,
      'CRISPCLOUD_PAGE_(ONE|TWO)', '--regex', '--json']);
    expect(search.code, 0, reason: search.errors);
    final matches = search.json['matches'] as List;
    expect(matches.map((match) => match['page']).toSet(), {1, 2});
    expect(matches.every((match) => (match['bounds'] as List).isNotEmpty), isTrue);
  });

  test('merge preserves input order and imports form fields', () async {
    final result = await run(['merge', source.path, source.path,
      '--output', target('merged.pdf'), '--json']);
    expect(result.code, 0, reason: result.errors);
    final merged = inspectOutput('merged.pdf');
    expect(merged.pageCount, 4);
    expect(merged.pages.map((page) => page.rotation), [0, 90, 0, 90]);
    expect(merged.fields.map((field) => field.name), containsAll(['reviewer', 'reviewer_2']));
    retain('merged.pdf');
  });

  test('merge accepts ordered page selections without splitting their commas', () async {
    final result = await run(['merge', source.path, source.path,
      '--source-pages', '2,1', '--source-pages', '2',
      '--output', target('selected_merge.pdf'), '--json']);
    expect(result.code, 0, reason: result.errors);
    expect(inspectOutput('selected_merge.pdf').pages.map((page) => page.rotation), [90, 0, 90]);
  });

  test('extract, reorder, delete and rotate write separate valid PDFs', () async {
    final commands = <List<String>>[
      ['extract', source.path, '--pages', '1', '-o', target('extracted.pdf')],
      ['reorder', source.path, '--pages', '2,1', '-o', target('reordered.pdf')],
      ['delete-pages', source.path, '--pages', '2', '-o', target('deleted.pdf')],
      ['rotate', source.path, '--pages', '2', '--degrees', '90', '-o', target('rotated.pdf')],
    ];
    final original = source.readAsBytesSync();
    for (final command in commands) {
      final result = await run([...command, '--json']);
      expect(result.code, 0, reason: '${command.first}: ${result.errors}');
    }
    expect(inspectOutput('extracted.pdf').pageCount, 1);
    expect(inspectOutput('extracted.pdf').fields.map((field) => field.name), contains('reviewer'));
    expect(inspectOutput('reordered.pdf').pages.map((page) => page.rotation), [90, 0]);
    expect(inspectOutput('deleted.pdf').pageCount, 1);
    expect(inspectOutput('rotated.pdf').pages.map((page) => page.rotation), [0, 180]);
    expect(source.readAsBytesSync(), original);
    retain('extracted.pdf');
    retain('rotated.pdf');
  });

  test('invalid page lists never create an output', () async {
    for (final command in [
      ['extract', source.path, '--pages', '0'],
      ['rotate', source.path, '--pages', '99'],
      ['reorder', source.path, '--pages', '1,1'],
      ['delete-pages', source.path, '--pages', 'all'],
    ]) {
      final result = await run([...command, '-o', target('invalid.pdf'), '--json']);
      expect(result.code, isNot(0));
      expect(File(target('invalid.pdf')).existsSync(), isFalse);
    }
  });

  test('encrypted extraction requires explicit decryption consent', () async {
    final password = await passwordFile('$_password\n');
    final arguments = ['extract', encrypted.path, '--pages', '1',
      '--password-file', password.path, '-o', target('decrypted_extract.pdf'), '--json'];
    final rejected = await run(arguments);
    expect(rejected.code, isNot(0));
    expect(rejected.errorJson['code'], 'decryptionRequired');
    expect(File(target('decrypted_extract.pdf')).existsSync(), isFalse);
    final allowed = await run([...arguments, '--allow-decryption']);
    expect(allowed.code, 0, reason: allowed.errors);
    expect(inspectOutput('decrypted_extract.pdf').encrypted, isFalse);
  });

  test('encrypted rotation keeps protection and reads a password from stdin', () async {
    final result = await run(['rotate', encrypted.path, '--pages', '1',
      '--password-file', '-', '-o', target('encrypted_rotated.pdf'), '--json'],
      stdinText: '$_password\n');
    expect(result.code, 0, reason: result.errors);
    expect(inspectOutput('encrypted_rotated.pdf', password: _password).encrypted, isTrue);
    expect(() => inspectOutput('encrypted_rotated.pdf'), throwsA(isA<PdfOperationException>()));
    expect(result.output, isNot(contains(_password)));
    retain('encrypted_rotated.pdf');
  });

  test('merge supports separate input passwords without putting them in argv', () async {
    final passwords = await passwordFile(jsonEncode(['', _password]));
    final result = await run(['merge', source.path, encrypted.path,
      '--passwords-file', passwords.path, '--allow-decryption',
      '-o', target('password_merge.pdf'), '--json']);
    expect(result.code, 0, reason: result.errors);
    expect(inspectOutput('password_merge.pdf').pageCount, 4);
    expect(result.output, isNot(contains(_password)));
  });

  test('malformed password JSON never leaks its source in diagnostics', () async {
    const secret = 'sensitive-test-password-123';
    final passwords = await passwordFile('["$secret",');
    final result = await run(['merge', source.path, encrypted.path,
      '--passwords-file', passwords.path, '-o', target('bad_passwords.pdf'), '--json']);
    expect(result.code, isNot(0));
    expect(result.errorJson['code'], 'invalidJson');
    expect(result.errors, isNot(contains(secret)));
    expect(File(target('bad_passwords.pdf')).existsSync(), isFalse);
  });

  test('form fill is strict and accepts Unicode using an explicit font', () async {
    const value = 'Ζωή — résumé';
    final data = File(target('form.json'))..writeAsStringSync(jsonEncode({'reviewer': value}));
    final filled = await run(['fill', source.path, '--data', data.path,
      '--font', font, '-o', target('filled.pdf'), '--json']);
    expect(filled.code, 0, reason: filled.errors);
    expect(inspectOutput('filled.pdf').fields.singleWhere((field) => field.name == 'reviewer').values,
        contains(value));
    expect(filled.json['filledFields'], ['reviewer']);
    retain('filled.pdf');

    data.writeAsStringSync(jsonEncode({'reviewer': 'Valid', 'missing.field': 'invalid'}));
    final rejected = await run(['fill', source.path, '--data', data.path,
      '-o', target('partial.pdf'), '--json']);
    expect(rejected.code, isNot(0));
    expect(rejected.errorJson['fieldErrors'], contains('missing.field'));
    expect(File(target('partial.pdf')).existsSync(), isFalse);
  });

  test('watermark is searchable on only the selected page', () async {
    final result = await run(['watermark', source.path, '--text', 'CLI_WATERMARK',
      '--pages', '2', '--angle', '0', '--font-size', '20', '--opacity', '.35',
      '-o', target('watermarked.pdf'), '--json']);
    expect(result.code, 0, reason: result.errors);
    final matches = service.search(PdfInput(File(target('watermarked.pdf')).readAsBytesSync()),
        query: 'CLI_WATERMARK');
    expect(matches, isNotEmpty);
    expect(matches.every((match) => match.pageIndex == 1), isTrue);
    expect(inspectOutput('watermarked.pdf').fields.map((field) => field.name), contains('reviewer'));
    retain('watermarked.pdf');
  });

  test('image insertion and image watermark accept a PNG and retain forms', () async {
    final image = File(target('logo.png'))..writeAsBytesSync(base64Decode(_imageBase64));
    for (final command in ['insert-image', 'watermark']) {
      final result = await run([command, source.path, '--image', image.path,
        '--pages', '2', '-o', target('$command.pdf'), '--json']);
      expect(result.code, 0, reason: result.errors);
      final inspected = inspectOutput('$command.pdf');
      expect(inspected.pageCount, 2);
      expect(inspected.fields.map((field) => field.name), contains('reviewer'));
      retain('$command.pdf');
    }
  });

  test('OCR import skips existing text unless explicitly overridden', () async {
    final data = File(target('ocr.json'))..writeAsStringSync(jsonEncode([
      {'page': 1, 'spans': [
        {'text': 'CLI_OCR_MARKER', 'bounds': [70, 100, 240, 120], 'confidence': .9},
        {'text': 'LOW_CONFIDENCE', 'bounds': [70, 130, 240, 150], 'confidence': .1},
      ]},
    ]));
    final skipped = await run(['ocr', source.path, '--data', data.path,
      '-o', target('ocr_skipped.pdf'), '--json']);
    expect(skipped.code, 0, reason: skipped.errors);
    expect((skipped.json['warnings'] as List).join(' '), contains('skipped'));
    final result = await run(['ocr', source.path, '--data', data.path,
      '--no-skip-existing-text', '--min-confidence', '.8',
      '-o', target('ocr.pdf'), '--json']);
    expect(result.code, 0, reason: result.errors);
    final input = PdfInput(File(target('ocr.pdf')).readAsBytesSync());
    expect(service.search(input, query: 'CLI_OCR_MARKER'), isNotEmpty);
    expect(service.search(input, query: 'LOW_CONFIDENCE'), isEmpty);
    retain('ocr.pdf');
  });

  test('Unicode OCR import is searchable with the supplied font', () async {
    final result = await run(['ocr', source.path, '--data', '-', '--font', font,
      '--no-skip-existing-text', '-o', target('ocr_unicode.pdf'), '--json'],
      stdinText: jsonEncode([{'page': 2, 'spans': [
        {'text': 'Привет', 'bounds': [70, 100, 240, 120]},
      ]}]));
    expect(result.code, 0, reason: result.errors);
    expect(service.search(PdfInput(File(target('ocr_unicode.pdf')).readAsBytesSync()),
        query: 'Привет'), isNotEmpty);
    retain('ocr_unicode.pdf');
  });

  test('existing output is refused unless explicitly selected for overwrite', () async {
    final destination = File(target('existing.pdf'))..writeAsStringSync('keep me');
    final arguments = ['rotate', source.path, '-o', destination.path, '--json'];
    final refused = await run(arguments);
    expect(refused.code, isNot(0));
    expect(refused.errorJson['code'], 'outputExists');
    expect(destination.readAsStringSync(), 'keep me');
    final replaced = await run([...arguments, '--overwrite']);
    expect(replaced.code, 0, reason: replaced.errors);
    expect(inspectOutput('existing.pdf').pageCount, 2);
  });

  test('source replacement is refused even with --overwrite', () async {
    final original = Uint8List.fromList(source.readAsBytesSync());
    final result = await run(['rotate', source.path, '-o', source.path,
      '--overwrite', '--json']);
    expect(result.code, isNot(0));
    expect(result.errorJson['code'], 'sourceOutput');
    expect(source.readAsBytesSync(), original);
  });

  test('watermark rejects conflicting sources and non-finite geometry', () async {
    final image = File(target('logo.png'))..writeAsBytesSync(base64Decode(_imageBase64));
    await expectLater(run(['watermark', source.path,
      '--text', 'Draft', '--image', image.path, '-o', target('bad.pdf')]),
      throwsA(isA<UsageException>()));
    await expectLater(run(['watermark', source.path,
      '--text', 'Draft', '--opacity', 'NaN', '-o', target('bad.pdf')]),
      throwsA(isA<UsageException>()));
    expect(File(target('bad.pdf')).existsSync(), isFalse);
  });
}

class _Result {
  const _Result(this.code, this.output, this.errors);

  final int code;
  final String output;
  final String errors;

  Map<String, dynamic> get json => jsonDecode(output) as Map<String, dynamic>;
  Map<String, dynamic> get errorJson => jsonDecode(errors) as Map<String, dynamic>;
}
