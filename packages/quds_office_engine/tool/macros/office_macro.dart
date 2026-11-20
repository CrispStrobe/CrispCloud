import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';

/// Explicit, headless macro invocation. Input documents never auto-run code.
Future<void> main(List<String> args) async {
  try {
    if (args.length == 1 && args.first == 'operations') {
      _print(<String, Object?>{
        for (final format in OfficeMacroFormat.values)
          format.name: <String, Object?>{
            for (final operation in OfficeOperationCatalog.fields(
              format,
            ).entries)
              '${format.name}.${operation.key}': operation.value,
          },
      });
      return;
    }
    final compileWordVba = args.isNotEmpty && args.first == 'compile-word-vba';
    final compileVba =
        args.isNotEmpty && (args.first == 'compile-vba' || compileWordVba);
    if ((args.length == 3 && args.first == 'compile') ||
        (compileVba && (args.length == 3 || args.length == 4))) {
      final languages = OfficeMacroLanguages();
      final source = compileVba
          ? _vbaSource(
              args[1],
              args.length == 4 ? args[3] : 'Main',
              word: compileWordVba,
            )
          : OfficeMacroSource.fromJson(_readObject(args[1]));
      final macro = languages.compile(source);
      _write(args[2], Uint8List.fromList(utf8.encode(macro.encode())));
      _print(<String, Object?>{
        'name': macro.name,
        'language': source.language,
        'output': args[2],
      });
      return;
    }
    if (args.length == 2 && args.first == 'inspect') {
      _print(_session(args[1]).inspect());
      return;
    }
    final wordVba =
        args.isNotEmpty &&
        (args.first == 'run-word-vba' || args.first == 'validate-word-vba');
    final vba =
        args.isNotEmpty &&
        (args.first == 'run-vba' || args.first == 'validate-vba' || wordVba);
    final run =
        args.isNotEmpty &&
        (args.first == 'run' ||
            args.first == 'run-vba' ||
            args.first == 'run-word-vba');
    final validate =
        args.isNotEmpty &&
        (args.first == 'validate' ||
            args.first == 'validate-vba' ||
            args.first == 'validate-word-vba');
    if ((!run && !validate) ||
        (run && (args.length < 4 || args.length > 5)) ||
        (validate && (args.length < 3 || args.length > 4))) {
      stderr.writeln(
        'Usage: dart run tool/macros/office_macro.dart\n'
        '  operations\n'
        '  inspect INPUT\n'
        '  run INPUT MACRO.json OUTPUT [PARAMETERS.json]\n'
        '  validate INPUT MACRO.json [PARAMETERS.json]\n'
        '  compile SOURCE.json OUTPUT.json\n'
        '  compile-vba SOURCE.bas OUTPUT.json [ENTRYPOINT]\n'
        '  run-vba INPUT SOURCE.bas OUTPUT [ENTRYPOINT]\n'
        '  validate-vba INPUT SOURCE.bas [ENTRYPOINT]\n'
        '  compile-word-vba SOURCE.bas OUTPUT.json [ENTRYPOINT]\n'
        '  run-word-vba INPUT SOURCE.bas OUTPUT [ENTRYPOINT]\n'
        '  validate-word-vba INPUT SOURCE.bas [ENTRYPOINT]\n'
        'VBA commands use vba-excel; word-vba commands use vba-word '
        '(default entry: Main).\n'
        'Office input/output must have the same extension. Image assets require '
        'a host resolver through the Dart API.',
      );
      exitCode = 64;
      return;
    }
    if (run && _extension(args[1]) != _extension(args[3])) {
      throw const FormatException(
        'Output must have the same extension as input.',
      );
    }
    final session = _session(args[1]);
    final parameterIndex = run ? 4 : 3;
    final macro = vba
        ? OfficeMacroLanguages().compile(
            _vbaSource(
              args[2],
              args.length > parameterIndex ? args[parameterIndex] : 'Main',
              word: wordVba,
            ),
          )
        : OfficeMacro.parse(_readText(args[2]));
    final parameters = !vba && args.length > parameterIndex
        ? _readObject(args[parameterIndex])
        : const <String, Object?>{};
    final result = validate
        ? await session.validate(macro, parameters: parameters)
        : await session.run(macro, parameters: parameters);
    if (run) _write(args[3], session.bytes);
    _print(<String, Object?>{
      ...result.toJson(),
      if (vba) 'language': wordVba ? 'vba-word' : 'vba-excel',
      if (run) 'output': args[3],
    });
  } on OfficeMacroException catch (error) {
    stderr.writeln(jsonEncode(<String, Object?>{'error': error.toJson()}));
    exitCode = 1;
  } on Object catch (error) {
    stderr.writeln(
      jsonEncode(<String, Object?>{
        'error': <String, Object?>{
          'code': 'input_output_error',
          'message': error.toString(),
        },
      }),
    );
    exitCode = 1;
  }
}

OfficeMacroSession _session(String path) {
  final format = switch (_extension(path)) {
    'docx' || 'docm' || 'dotx' || 'dotm' => OfficeMacroFormat.docx,
    'xlsx' || 'xlsm' || 'xltx' || 'xltm' => OfficeMacroFormat.xlsx,
    'pptx' ||
    'pptm' ||
    'potx' ||
    'potm' ||
    'ppsx' ||
    'ppsm' => OfficeMacroFormat.pptx,
    _ => throw const FormatException('Unsupported Office filename extension.'),
  };
  final file = File(path);
  if (file.lengthSync() > 64 * 1024 * 1024) {
    throw const FormatException('Document exceeds 64 MiB.');
  }
  return OfficeMacroSession(file.readAsBytesSync(), format: format);
}

String _extension(String path) => path.split('.').last.toLowerCase();

OfficeMacroSource _vbaSource(
  String path,
  String entryPoint, {
  bool word = false,
}) {
  final filename = File(path).uri.pathSegments.last;
  final dot = filename.lastIndexOf('.');
  return OfficeMacroSource(
    language: word ? 'vba-word' : 'vba-excel',
    source: _readText(path),
    format: word ? OfficeMacroFormat.docx : OfficeMacroFormat.xlsx,
    moduleName: dot > 0 ? filename.substring(0, dot) : filename,
    entryPoint: entryPoint,
  );
}

String _readText(String path) {
  final file = File(path);
  if (file.lengthSync() > 1024 * 1024) {
    throw const FormatException('Macro/source/parameters exceeds 1 MiB.');
  }
  return file.readAsStringSync();
}

Map<String, Object?> _readObject(String path) {
  final Object? value = jsonDecode(_readText(path));
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  return value;
}

void _print(Map<String, Object?> value) =>
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(value));

/// Save only complete results; the selected output stays untouched on failure.
void _write(String path, Uint8List bytes) {
  final output = File(path).absolute;
  output.parent.createSync(recursive: true);
  final directory = output.parent.createTempSync('.quds-macro-');
  final temporary = File('${directory.path}/output');
  try {
    temporary.writeAsBytesSync(bytes, flush: true);
    temporary.renameSync(output.path);
  } finally {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}
