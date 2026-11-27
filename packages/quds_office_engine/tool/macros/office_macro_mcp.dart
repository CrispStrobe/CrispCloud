import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:quds_office_engine/quds_office_automation.dart';

import 'local_mcp_stdio.dart';

/// Runs an MCP stdio server for one explicitly selected input/output pair.
Future<void> main(List<String> arguments) async {
  final writable = arguments.length == 3 && arguments.first == '--write';
  if (!writable &&
      (arguments.length != 1 || arguments.first.startsWith('--'))) {
    stderr.writeln(
      'Usage: dart run tool/macros/office_macro_mcp.dart INPUT\n'
      'Write mode: dart run tool/macros/office_macro_mcp.dart --write INPUT OUTPUT',
    );
    exitCode = 64;
    return;
  }

  final OfficeMacroFormat format;
  final Uint8List bytes;
  final input = File(arguments[writable ? 1 : 0]).absolute;
  final output = writable ? File(arguments[2]).absolute : null;
  final policy = OfficeMacroPolicy(allowMutation: writable);
  try {
    final extension = _extension(input.path);
    if (output != null) {
      if (extension != _extension(output.path)) {
        throw const FormatException(
          'Output must preserve the exact input Office extension',
        );
      }
      if (output.existsSync() &&
          FileSystemEntity.identicalSync(input.path, output.path)) {
        throw const FormatException('Output must be different from input.');
      }
    }
    format = _format(extension);
    bytes = await readLocalMcpInput(input, policy.maxDocumentBytes);
  } on FormatException catch (error) {
    stderr.writeln('Cannot open Office macro session: ${error.message}');
    exitCode = 1;
    return;
  } on Object {
    stderr.writeln('Cannot open Office macro session.');
    exitCode = 1;
    return;
  }

  final replies = ReceivePort();
  final responses = StreamIterator<Object?>(replies);
  Isolate? worker;
  Future<Object?> receive() async =>
      await responses.moveNext().timeout(policy.maxDuration)
      ? responses.current
      : null;
  try {
    worker = await Isolate.spawn(
      _serveDocument,
      (
        replies.sendPort,
        TransferableTypedData.fromList([bytes]),
        format,
        policy,
      ),
      onExit: replies.sendPort,
      onError: replies.sendPort,
    );
    final requests = await receive();
    if (requests is! SendPort) {
      stderr.writeln('Cannot open Office macro session.');
      exitCode = 1;
      return;
    }
    await runLocalMcpStdio((message) async {
      requests.send((message,));
      final reply = await receive();
      if (reply is! _DocumentReply) {
        throw StateError('Document session stopped');
      }
      final (response, updatedBytes) = reply;
      if (output != null && updatedBytes != null) {
        try {
          await _persist(output, updatedBytes.materialize().asUint8List());
        } on Object {
          stderr.writeln('Cannot save macro output; stopping session.');
          throw _PersistenceFailure(response?['id']);
        }
      }
      return response;
    });
  } on _PersistenceFailure catch (error) {
    stdout.writeln(jsonEncode(error.result));
    await stdout.flush();
    exitCode = 1;
  } on TimeoutException {
    stderr.writeln('Office macro session exceeded its time limit and stopped.');
    exitCode = 1;
  } on Object {
    stderr.writeln('Office macro transport stopped.');
    exitCode = 1;
  } finally {
    worker?.kill(priority: Isolate.immediate);
    replies.close();
    await responses.cancel();
  }
}

typedef _DocumentReply = (Map<String, Object?>?, TransferableTypedData?);

Future<void> _serveDocument(
  (SendPort, TransferableTypedData, OfficeMacroFormat, OfficeMacroPolicy) start,
) async {
  final (replies, bytes, format, policy) = start;
  final session = OfficeMacroSession(
    bytes.materialize().asUint8List(),
    format: format,
    policy: policy,
  );
  session.inspect();
  final adapter = OfficeMacroMcp(session);
  final requests = ReceivePort();
  replies.send(requests.sendPort);
  await for (final request in requests.cast<(Object?,)>()) {
    final revision = session.revision;
    final response = await adapter.handleMessage(request.$1);
    final bytes = session.revision == revision
        ? null
        : TransferableTypedData.fromList([session.bytes]);
    replies.send((response, bytes));
  }
}

final class _PersistenceFailure implements Exception {
  _PersistenceFailure(this.id);
  final Object? id;

  Map<String, Object?> get result => {
    'jsonrpc': '2.0',
    'id': id,
    'result': OfficeMacroMcp.toolResult({
      'error': {
        'code': 'persistence_failed',
        'message':
            'The updated document could not be saved. The session stopped.',
      },
    }, isError: true),
  };
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
  _ => throw const FormatException('Unsupported Office extension'),
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
