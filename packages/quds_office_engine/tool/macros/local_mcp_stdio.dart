import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _maxMessageBytes = 2 * 1024 * 1024;

Future<Uint8List> readLocalMcpInput(File file, int maxBytes) async {
  if (FileSystemEntity.typeSync(file.path) != FileSystemEntityType.file) {
    throw const FormatException('Input must be a regular file.');
  }
  final input = await file.open();
  try {
    final length = await input.length();
    if (length > maxBytes) {
      throw const FormatException('Input exceeds the size limit.');
    }
    final bytes = await input.read(length);
    if (bytes.length != length || await input.readByte() != -1) {
      throw const FormatException('Input changed while it was being read.');
    }
    return bytes;
  } finally {
    await input.close();
  }
}

Future<void> runLocalMcpStdio(
  Future<Map<String, Object?>?> Function(Object?) dispatch,
) async {
  await for (final line in _boundedLines(stdin)) {
    if (line == null) {
      _send(_error(-32600, 'Request is too large'));
      await stdout.flush();
      continue;
    }
    final Object? request;
    try {
      request = jsonDecode(utf8.decode(line));
    } on FormatException {
      _send(_error(-32700, 'Invalid JSON'));
      await stdout.flush();
      continue;
    }
    final response = await dispatch(request);
    if (response != null) {
      final json = jsonEncode(response);
      if (utf8.encode(json).length <= _maxMessageBytes) {
        stdout.writeln(json);
      } else {
        final error = _error(-32603, 'Response is too large');
        final id = response['id'];
        if (id is num || (id is String && id.length <= 256)) error['id'] = id;
        _send(error);
      }
    }
    await stdout.flush();
  }
}

Map<String, Object?> _error(int code, String message) => {
  'jsonrpc': '2.0',
  'id': null,
  'error': {'code': code, 'message': message},
};

void _send(Map<String, Object?> response) =>
    stdout.writeln(jsonEncode(response));

Stream<Uint8List?> _boundedLines(Stream<List<int>> input) async* {
  final line = BytesBuilder(copy: false);
  var oversized = false;
  await for (final chunk in input) {
    var start = 0;
    while (start < chunk.length) {
      final newline = chunk.indexOf(10, start);
      final end = newline < 0 ? chunk.length : newline;
      if (!oversized) {
        if (line.length + end - start > _maxMessageBytes) {
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
  if (oversized || line.length > 0) yield oversized ? null : line.takeBytes();
}
