import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:args/command_runner.dart';
import 'package:pdf_operations/pdf_operations.dart';

import '../adapters/bounded_download.dart';
import '../config/cli_config.dart';
import '../pdf/pdf_io.dart';

/// Preserves the PDF command family's JSON error contract even when argument
/// parsing fails before a subcommand runs. Other CLI commands keep the normal
/// [CommandRunner] usage behavior.
class PdfAwareCommandRunner extends CommandRunner<int> {
  PdfAwareCommandRunner(super.executableName, super.description,
      {StringSink? errors})
      : _errors = errors ?? stderr;

  final StringSink _errors;

  @override
  Future<int?> run(Iterable<String> args) async {
    final arguments = args.toList();
    try {
      return await super.run(arguments);
    } on UsageException {
      // Stop at -- so a search query or filename named --json remains data.
      final options = arguments.takeWhile((argument) => argument != '--');
      if (arguments.firstOrNull != 'pdf' ||
          !options.any((argument) =>
              argument == '--json' || argument == '-j' ||
              argument == '--json=true')) {
        rethrow;
      }
      _errors.writeln(jsonEncode({
        'status': 'error',
        'command': 'pdf',
        'code': 'usage',
        // Parser errors may quote argument values. Do not include their source
        // in machine-readable logs (a mistaken argument could be a secret).
        'message': 'Invalid PDF command arguments. Run crisp pdf --help or '
            'crisp pdf <command> --help for usage.',
      }));
      return 2;
    }
  }
}

/// PDF commands use the same byte-oriented operations as the graphical app.
/// The CLI owns file access, credentials, output consent and presentation.
class PdfCommand extends Command<int> {
  PdfCommand(
    this.config, {
    PdfOperationsService? service,
    this.adapterFactory,
    StringSink? output,
    StringSink? errors,
    this.input,
    this.inputHasTerminal,
  }) : service = service ?? PdfOperationsService(),
       output = output ?? stdout,
       errors = errors ?? stderr {
    for (final operation in _PdfOperation.values) {
      addSubcommand(_PdfOperationCommand(operation, this));
    }
  }

  final CliConfig config;
  final PdfOperationsService service;
  final PdfCliAdapterFactory? adapterFactory;
  final StringSink output;
  final StringSink errors;
  final Stream<List<int>>? input;
  final bool? inputHasTerminal;

  @override
  String get name => 'pdf';

  @override
  String get description =>
      'Inspect, search and edit PDFs from local paths or cloud://profile/path.';
}

enum _PdfOperation {
  info,
  text,
  search,
  merge,
  extract,
  rotate,
  reorder,
  deletePages,
  watermark,
  fill,
  insertImage,
  ocr,
}

class _PdfOperationCommand extends Command<int> {
  _PdfOperationCommand(this.operation, this.host) {
    argParser
      ..addFlag('json', abbr: 'j', negatable: false,
          help: 'Write structured JSON metadata. Errors are JSON on stderr.')
      ..addOption('password-file',
          help: 'Read the PDF password from a private local file, or - for stdin.');

    if (_writes) {
      argParser
        ..addOption('output', abbr: 'o', mandatory: true,
            help: 'Separate output file or cloud://profile/path; never an input.')
        ..addFlag('overwrite', negatable: false,
            help: 'Allow replacing an existing separate output after preflight.');
    }
    if (_hasPages) {
      argParser.addOption('pages',
          defaultsTo: _requiresPages ? null :
              (operation == _PdfOperation.insertImage ? '1' : 'all'),
          mandatory: _requiresPages,
          help: 'One-based page expression, e.g. 1-3,7 or 5-1; all selects all.');
    }
    switch (operation) {
      case _PdfOperation.merge:
        argParser
          ..addMultiOption('source-pages', splitCommas: false,
              help: 'Repeat once per input, in input order; defaults to all.')
          ..addOption('passwords-file',
              help: 'Private JSON array of passwords in input order, or - for stdin.')
          ..addFlag('allow-decryption', negatable: false,
              help: 'Allow encrypted input pages in an unencrypted merged output.');
      case _PdfOperation.extract:
        argParser.addFlag('allow-decryption', negatable: false,
            help: 'Allow an unencrypted extracted PDF from encrypted input.');
      case _PdfOperation.rotate:
        argParser.addOption('degrees', defaultsTo: '90',
            help: 'Clockwise turn: 90, 180, 270 or -90.');
      case _PdfOperation.search:
        argParser
          ..addFlag('case-sensitive', negatable: false)
          ..addFlag('regex', negatable: false,
              help: 'Treat the query as a regular expression.')
          ..addFlag('whole-word', negatable: false);
      case _PdfOperation.watermark:
        argParser
          ..addOption('text', help: 'Watermark text; use exactly one text or image source.')
          ..addOption('text-file', help: 'Read UTF-8 watermark text from a file or stdin.')
          ..addOption('image', help: 'PNG/JPEG logo file or cloud://profile/path.')
          ..addOption('font-size', defaultsTo: '36', help: 'Text size in PDF points.')
          ..addOption('color', defaultsTo: '808080', help: 'Text RGB as six hex digits.')
          ..addOption('anchor', defaultsTo: 'center',
              allowed: PdfPlacementAnchor.values.map((value) => value.name).toList())
          ..addOption('width', defaultsTo: '.65', help: 'Maximum fraction of displayed page width.')
          ..addOption('margin', defaultsTo: '24', help: 'Margin in PDF points.');
      case _PdfOperation.insertImage:
        argParser
          ..addOption('image', mandatory: true, help: 'PNG/JPEG file or cloud://profile/path.')
          ..addOption('x', defaultsTo: '.1', help: 'Left position as a fraction of displayed page width.')
          ..addOption('y', defaultsTo: '.1', help: 'Top position as a fraction of displayed page height.')
          ..addOption('width', defaultsTo: '.3', help: 'Fraction of displayed page width.')
          ..addOption('height', help: 'Fraction of displayed page height; omit to keep aspect ratio.');
      case _PdfOperation.fill:
        argParser.addOption('data', mandatory: true,
            help: 'JSON object mapping exact field names to typed values; - reads stdin.');
      case _PdfOperation.ocr:
        argParser
          ..addOption('data', mandatory: true,
              help: 'Recognized pages/spans JSON array; - reads stdin. No model is bundled.')
          ..addOption('min-confidence', defaultsTo: '0')
          ..addFlag('skip-existing-text', defaultsTo: true,
              help: 'Skip pages that already contain searchable text.');
      case _PdfOperation.info:
      case _PdfOperation.text:
      case _PdfOperation.reorder:
      case _PdfOperation.deletePages:
        break;
    }
    if (operation == _PdfOperation.watermark || operation == _PdfOperation.insertImage) {
      argParser
        ..addOption('opacity', defaultsTo: operation == _PdfOperation.watermark ? '.2' : '1',
            help: 'Opacity from 0 to 1.')
        ..addOption('angle', defaultsTo: operation == _PdfOperation.watermark ? '-35' : '0',
            help: 'Clockwise visual angle in degrees.')
        ..addFlag('flatten', defaultsTo: true,
            help: 'Bake only the new mark into page content; preserve other annotations.');
    }
    if (operation == _PdfOperation.watermark ||
        operation == _PdfOperation.fill ||
        operation == _PdfOperation.ocr) {
      argParser.addOption('font',
          help: 'TTF/OTF font file for Unicode appearances or OCR; must cover the text.');
    }
  }

  final _PdfOperation operation;
  final PdfCommand host;

  bool get _writes => !{
    _PdfOperation.info, _PdfOperation.text, _PdfOperation.search,
  }.contains(operation);

  bool get _requiresPages => {
    _PdfOperation.extract, _PdfOperation.reorder, _PdfOperation.deletePages,
  }.contains(operation);

  bool get _hasPages => {
    _PdfOperation.text, _PdfOperation.search, _PdfOperation.extract,
    _PdfOperation.rotate, _PdfOperation.reorder, _PdfOperation.deletePages,
    _PdfOperation.watermark, _PdfOperation.insertImage,
  }.contains(operation);

  @override
  String get name => switch (operation) {
    _PdfOperation.deletePages => 'delete-pages',
    _PdfOperation.insertImage => 'insert-image',
    _ => operation.name,
  };

  @override
  List<String> get aliases => operation == _PdfOperation.ocr ? ['import-ocr'] : const [];

  @override
  String get description => switch (operation) {
    _PdfOperation.info => 'Inspect pages, encryption, signatures and named form fields.',
    _PdfOperation.text => 'Extract the existing text layer, without OCR.',
    _PdfOperation.search => 'Search existing PDF text and return page locations.',
    _PdfOperation.merge => 'Combine input PDFs in the specified order.',
    _PdfOperation.extract => 'Export selected pages to a separate PDF.',
    _PdfOperation.rotate => 'Rotate selected pages in a separate copy.',
    _PdfOperation.reorder => 'Reorder every page using an explicit permutation.',
    _PdfOperation.deletePages => 'Remove selected pages from a copy; not secure erasure.',
    _PdfOperation.watermark => 'Apply a foreground text or image watermark.',
    _PdfOperation.fill => 'Fill known AcroForm fields using a typed JSON mapping.',
    _PdfOperation.insertImage => 'Place a PNG/JPEG on selected pages.',
    _PdfOperation.ocr => 'Import externally recognized text as a searchable layer.',
  };

  @override
  String get invocation => switch (operation) {
    _PdfOperation.merge => 'crisp pdf merge <input.pdf> <input.pdf>... --output <file> [options]',
    _PdfOperation.search => 'crisp pdf search <input.pdf> <query> [options]',
    _ => 'crisp pdf $name <input.pdf> ${_writes ? '--output <file> ' : ''}[options]',
  };

  @override
  Future<int> run() async {
    final store = PdfCliFileStore(host.config,
        adapterFactory: host.adapterFactory,
        input: host.input,
        inputHasTerminal: host.inputHasTerminal);
    try {
      final rest = argResults!.rest;
      final expected = operation == _PdfOperation.search ? 2 : 1;
      if (operation == _PdfOperation.merge ? rest.length < 2 : rest.length != expected) {
        usageException('Usage: $invocation');
      }
      final paths = operation == _PdfOperation.merge ? rest : [rest.first];
      final passwords = await _passwords(store, paths.length);
      final inputs = <PdfInput>[];
      var totalBytes = 0;
      for (var i = 0; i < paths.length; i++) {
        final bytes = await store.readBytes(paths[i]);
        totalBytes += bytes.length;
        if (totalBytes > 256 * 1024 * 1024) {
          throw const PdfCliException('totalInputLimit', 'Combined PDF inputs exceed 256 MiB.');
        }
        inputs.add(PdfInput(bytes,
            name: PdfCliLocation.parse(paths[i]).name, password: passwords[i]));
      }

      if (!_writes) return _readOnly(inputs.single, rest);

      final options = await _loadOptions(store);
      final outputPath = argResults!['output'] as String;
      final output = await store.prepareOutput(outputPath,
          overwrite: argResults!['overwrite'] as bool);
      final result = _transform(inputs, options);
      final warnings = [
        ...result.warnings,
        ...await store.writeOutput(output, result.bytes),
      ];
      final metadata = {
        'status': 'ok',
        'command': name,
        'output': outputPath,
        ...result.toJson(),
        'warnings': warnings,
      };
      if (_json) {
        _writeJson(host.output, metadata);
      } else {
        host.output.writeln(
            'Saved ${result.pageCount} pages (${result.bytes.length} bytes) to ${_terminalSafe(outputPath)}');
        if (result.filledFields.isNotEmpty) {
          host.output.writeln('Filled ${result.filledFields.length} fields.');
        }
        for (final warning in warnings) {
          host.errors.writeln('Warning: ${_terminalSafe(warning)}');
        }
      }
      return 0;
    } on UsageException catch (error) {
      if (_json) {
        _report('usage', error.message);
        return 2;
      }
      rethrow;
    } on PdfOperationException catch (error) {
      _report(error.code, error.message, fields: error.fieldErrors);
      return 2;
    } on PdfCliException catch (error) {
      _report(error.code, error.message);
      return 1;
    } on CliDownloadLimitException catch (error) {
      _report('inputLimit', error.toString());
      return 1;
    } on CliConfigException catch (error) {
      _report('configuration', error.message);
      return 1;
    } on FileSystemException catch (error) {
      _report('fileSystem', error.message);
      return 1;
    } catch (error) {
      // Transport/parser exceptions can include response bodies or input data.
      // Do not echo those (or password/form content) into terminal logs.
      _report('operationFailed',
          'The operation failed (${error.runtimeType}); no successful result was reported.');
      return 1;
    } finally {
      await store.dispose();
    }
  }

  bool get _json => argResults!['json'] as bool;
  String get _pages => argResults!['pages'] as String;

  int _readOnly(PdfInput input, List<String> rest) {
    switch (operation) {
      case _PdfOperation.info:
        final info = host.service.inspect(input);
        if (_json) {
          _writeJson(host.output, {'status': 'ok', ...info.toJson()});
        } else {
          host.output.writeln('Pages: ${info.pageCount}');
          host.output.writeln('Encrypted: ${info.encrypted}; signatures: ${info.hasSignatures}; XFA: ${info.hasXfa}');
          for (final page in info.pages) {
            host.output.writeln('Page ${page.pageIndex + 1}: ${page.width} × ${page.height} pt, rotation ${page.rotation}°');
          }
          host.output.writeln('Form fields: ${info.fields.length}');
          for (final field in info.fields) {
            host.output.writeln('  ${_terminalSafe(field.name)}: ${field.type}'
                '${field.readOnly ? ' (read only)' : ''}${field.password ? ' (password; omitted)' : ''}');
          }
          for (final warning in info.warnings) {
            host.errors.writeln('Warning: ${_terminalSafe(warning)}');
          }
        }
        return 0;
      case _PdfOperation.text:
        final pages = host.service.text(input, pages: _pages);
        if (_json) {
          _writeJson(host.output, {
            'status': 'ok',
            'pages': [for (final page in pages) page.toJson()],
          });
        } else {
          host.output.writeln(pages.map((page) => _terminalSafe(page.text)).join('\n\f\n'));
        }
        return 0;
      case _PdfOperation.search:
        final matches = host.service.search(input,
            query: rest[1], pages: _pages,
            caseSensitive: argResults!['case-sensitive'] as bool,
            regex: argResults!['regex'] as bool,
            wholeWord: argResults!['whole-word'] as bool);
        if (_json) {
          _writeJson(host.output, {
            'status': 'ok', 'count': matches.length,
            'matches': [for (final match in matches) match.toJson()],
          });
        } else {
          for (final match in matches) {
            host.output.writeln('${match.pageIndex + 1}:${match.start}-${match.end}: ${_terminalSafe(match.text)}');
          }
          if (matches.isEmpty) host.output.writeln('No matching text. Image-only scans need OCR.');
        }
        return 0;
      default:
        throw StateError('Not a read operation.');
    }
  }

  Future<List<String>> _passwords(PdfCliFileStore store, int count) async {
    final path = argResults!['password-file'] as String?;
    final listPath = operation == _PdfOperation.merge
        ? argResults!['passwords-file'] as String? : null;
    if (path != null && listPath != null) {
      usageException('Use either --password-file or --passwords-file.');
    }
    if (listPath != null) {
      final raw = _decodeJson(await store.readUtf8(listPath,
          secret: true, maxBytes: 64 * 1024));
      if (raw is! List || raw.length != count || raw.any((value) => value is! String)) {
        throw const PdfCliException('invalidPasswords',
            'The password file must contain one JSON string per input, in order.');
      }
      return raw.cast<String>();
    }
    if (path == null) return List.filled(count, '');
    var password = await store.readUtf8(path, secret: true, maxBytes: 64 * 1024);
    if (password.endsWith('\n')) password = password.substring(0, password.length - 1);
    if (password.endsWith('\r')) password = password.substring(0, password.length - 1);
    if (password.contains('\n') || password.contains('\r')) {
      throw const PdfCliException('invalidPasswordFile',
          'A password file must contain one line (a final newline is allowed).');
    }
    return List.filled(count, password);
  }

  Future<_LoadedOptions> _loadOptions(PdfCliFileStore store) async {
    final args = argResults!;
    PdfEmbeddedFont? font;
    if (operation == _PdfOperation.watermark ||
        operation == _PdfOperation.fill ||
        operation == _PdfOperation.ocr) {
      final path = args['font'] as String?;
      if (path != null) {
        final bytes = await store.readBytes(path, maxBytes: 16 * 1024 * 1024);
        try {
          font = PdfEmbeddedFont.parse(bytes, resourceName: 'CrispPdfCli');
        } catch (_) {
          throw const PdfCliException('invalidFont', 'The supplied font could not be parsed.');
        }
      }
    }
    Uint8List? image;
    if (operation == _PdfOperation.watermark || operation == _PdfOperation.insertImage) {
      final path = args['image'] as String?;
      if (path != null) image = await store.readBytes(path, maxBytes: 16 * 1024 * 1024);
    }
    String? text;
    if (operation == _PdfOperation.watermark) {
      text = args['text'] as String?;
      final textPath = args['text-file'] as String?;
      final count = [text, textPath, image].where((value) => value != null).length;
      if (count != 1) {
        usageException('Use exactly one of --text, --text-file or --image.');
      }
      if (textPath != null) text = await store.readUtf8(textPath);
    }
    Object? data;
    if (operation == _PdfOperation.fill || operation == _PdfOperation.ocr) {
      data = _decodeJson(await store.readUtf8(args['data'] as String,
          maxBytes: operation == _PdfOperation.ocr ? 16 * 1024 * 1024 : 4 * 1024 * 1024));
    }
    return _LoadedOptions(font: font, image: image, text: text, data: data);
  }

  PdfOperationResult _transform(List<PdfInput> inputs, _LoadedOptions options) {
    final service = host.service;
    final args = argResults!;
    final input = inputs.first;
    switch (operation) {
      case _PdfOperation.merge:
        final selections = args['source-pages'] as List<String>;
        if (selections.isNotEmpty && selections.length != inputs.length) {
          usageException('Repeat --source-pages once for each input, or omit it for all pages.');
        }
        return service.merge([
          for (var i = 0; i < inputs.length; i++)
            PdfMergeInput(inputs[i], pages: selections.isEmpty ? 'all' : selections[i]),
        ], allowDecryption: args['allow-decryption'] as bool);
      case _PdfOperation.extract:
        return service.extract(input, pages: _pages,
            allowDecryption: args['allow-decryption'] as bool);
      case _PdfOperation.rotate:
        final degrees = int.tryParse(args['degrees'] as String);
        if (degrees == null || !{-270, -180, -90, 90, 180, 270}.contains(degrees)) {
          usageException('--degrees must be ±90, ±180 or ±270.');
        }
        return service.rotate(input, pages: _pages, degrees: degrees);
      case _PdfOperation.reorder:
        return service.reorder(input, pages: _pages);
      case _PdfOperation.deletePages:
        return service.deletePages(input, pages: _pages);
      case _PdfOperation.watermark:
        final rawColor = (args['color'] as String).replaceFirst(RegExp(r'^#'), '');
        if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(rawColor)) {
          usageException('--color must have exactly six hexadecimal digits.');
        }
        return service.watermark(input, pages: _pages,
            watermark: PdfWatermarkOptions(
              text: options.text, imageBytes: options.image,
              font: options.font, fontSize: _number('font-size'),
              color: int.parse(rawColor, radix: 16), opacity: _number('opacity'),
              angleDegrees: _number('angle'), widthFraction: _number('width'),
              margin: _number('margin'), flatten: args['flatten'] as bool,
              anchor: PdfPlacementAnchor.values.byName(args['anchor'] as String),
            ));
      case _PdfOperation.fill:
        final raw = options.data;
        if (raw is! Map<String, dynamic>) {
          throw const PdfCliException('invalidFormData',
              'Form data must be a JSON object of field names and typed values.');
        }
        return service.fillForm(input, values: Map<String, Object?>.from(raw),
            appearanceFont: options.font);
      case _PdfOperation.insertImage:
        return service.insertImage(input, imageBytes: options.image!, pages: _pages,
            placement: PdfImagePlacement(
              x: _number('x'), y: _number('y'), width: _number('width'),
              height: args['height'] == null ? null : _number('height'),
              opacity: _number('opacity'), angleDegrees: _number('angle'),
              flatten: args['flatten'] as bool,
            ));
      case _PdfOperation.ocr:
        final raw = options.data;
        if (raw is! List || raw.any((value) => value is! Map<String, dynamic>)) {
          throw const PdfCliException('invalidOcr', 'OCR data must be a JSON array of pages and spans.');
        }
        return service.applyOcr(input,
            pages: [for (final value in raw)
              PdfOcrPage.fromJson(Map<String, Object?>.from(value as Map))],
            font: options.font, minConfidence: _number('min-confidence'),
            skipExistingText: args['skip-existing-text'] as bool);
      default:
        throw StateError('Not a write operation.');
    }
  }

  double _number(String name) {
    final parsed = double.tryParse(argResults![name] as String);
    if (parsed == null || !parsed.isFinite) usageException('--$name must be a finite number.');
    return parsed;
  }

  static Object? _decodeJson(String source) {
    try {
      return jsonDecode(source);
    } on FormatException {
      // FormatException.toString includes the source text, including secrets.
      throw const PdfCliException('invalidJson', 'The input is not valid JSON.');
    }
  }

  void _report(String code, String message, {Map<String, String> fields = const {}}) {
    if (_json) {
      _writeJson(host.errors, {
        'status': 'error', 'command': name, 'code': code, 'message': message,
        if (fields.isNotEmpty) 'fieldErrors': fields,
      });
    } else {
      host.errors.writeln('PDF $name: ${_terminalSafe(message)}');
      for (final entry in fields.entries) {
        host.errors.writeln('  ${_terminalSafe(entry.key)}: ${_terminalSafe(entry.value)}');
      }
    }
  }

  static void _writeJson(StringSink sink, Object value) =>
      sink.writeln(const JsonEncoder.withIndent('  ').convert(value));

  static String _terminalSafe(String value) => value.replaceAll(
      RegExp(r'[\x00-\x08\x0b\x0e-\x1f\x7f-\x9f]'), '\uFFFD');
}

class _LoadedOptions {
  const _LoadedOptions({this.font, this.image, this.text, this.data});

  final PdfEmbeddedFont? font;
  final Uint8List? image;
  final String? text;
  final Object? data;
}
