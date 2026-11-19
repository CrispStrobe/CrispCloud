import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';

/// Runs an MCP stdio server for one explicitly selected input/output pair.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/macros/office_macro_mcp.dart INPUT OUTPUT\n'
      'INPUT and OUTPUT must have the same Office extension. '
      'Document tools never accept file paths.',
    );
    exitCode = 64;
    return;
  }

  final OfficeMacroSession session;
  final output = File(arguments[1]).absolute;
  try {
    final inputExtension = _extension(arguments[0]);
    if (inputExtension != _extension(arguments[1])) {
      throw const FormatException(
        'Output must preserve the exact input Office extension',
      );
    }
    final format = _format(inputExtension);
    session = OfficeMacroSession(
      await File(arguments[0]).readAsBytes(),
      format: format,
    );
    // Refuse an unreadable package or a mislabeled family before handshaking.
    session.inspect();
  } on Object catch (error) {
    stderr.writeln('Cannot open Office macro session: $error');
    exitCode = 1;
    return;
  }

  final adapter = OfficeMacroMcp(session);
  // Await every call and output replacement before consuming the next request.
  try {
    await for (final line in _boundedLines(stdin)) {
      if (line == null) {
        _respond(OfficeMacroMcp.protocolError(-32600, 'Request is too large'));
        continue;
      }
      Object? message;
      try {
        message = jsonDecode(utf8.decode(line));
      } on FormatException {
        _respond(OfficeMacroMcp.protocolError(-32700, 'Invalid JSON'));
        continue;
      }
      final revision = session.revision;
      final response = await adapter.handleMessage(message);
      if (session.revision != revision) {
        try {
          await _persist(output, session.bytes);
        } on Object catch (error) {
          stderr.writeln('Cannot save macro output; stopping session: $error');
          if (response != null) {
            _respond(<String, Object?>{
              'jsonrpc': '2.0',
              'id': response['id'],
              'result': OfficeMacroMcp.toolResult(<String, Object?>{
                'error': <String, Object?>{
                  'code': 'persistence_failed',
                  'message':
                      'The updated document could not be saved. '
                      'The session has stopped; inspect the output before '
                      'starting another session.',
                },
              }, isError: true),
            });
          }
          exitCode = 1;
          return;
        }
      }
      if (response != null) _respond(response);
    }
  } on Object catch (error) {
    stderr.writeln('Office macro transport stopped: $error');
    exitCode = 1;
  }
}

void _respond(Map<String, Object?> message) =>
    stdout.writeln(jsonEncode(message));

/// Caps each wire message before UTF-8 or JSON decoding, including a peer that
/// streams an oversized line without a newline. Null marks one discarded line.
Stream<Uint8List?> _boundedLines(Stream<List<int>> input) async* {
  const maximumBytes = 2 * 1024 * 1024;
  final line = BytesBuilder(copy: false);
  var oversized = false;
  await for (final chunk in input) {
    var start = 0;
    while (start < chunk.length) {
      final newline = chunk.indexOf(10, start);
      final end = newline < 0 ? chunk.length : newline;
      if (!oversized) {
        if (line.length + end - start > maximumBytes) {
          line.clear();
          oversized = true;
        } else {
          line.add(chunk.sublist(start, end));
        }
      }
      if (newline >= 0) {
        yield oversized ? null : line.takeBytes();
        oversized = false;
      }
      start = newline < 0 ? chunk.length : newline + 1;
    }
  }
  if (oversized || line.length > 0) {
    yield oversized ? null : line.takeBytes();
  }
}

String _extension(String path) {
  final name = path.replaceAll('\\', '/').split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot < 0) throw const FormatException('Office file extension is required');
  return name.substring(dot + 1).toLowerCase();
}

OfficeMacroFormat _format(String extension) => switch (extension) {
  'docx' || 'docm' || 'dotx' || 'dotm' => OfficeMacroFormat.docx,
  'xlsx' || 'xlsm' || 'xltx' || 'xltm' => OfficeMacroFormat.xlsx,
  'pptx' ||
  'pptm' ||
  'potx' ||
  'potm' ||
  'ppsx' ||
  'ppsm' => OfficeMacroFormat.pptx,
  _ => throw FormatException('Unsupported Office extension: $extension'),
};

Future<void> _persist(File output, Uint8List bytes) async {
  await output.parent.create(recursive: true);
  final temporaryDirectory = await output.parent.createTemp('.quds-macro-');
  try {
    final temporary = File('${temporaryDirectory.path}/output');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(output.path);
  } finally {
    await temporaryDirectory.delete(recursive: true);
  }
}
