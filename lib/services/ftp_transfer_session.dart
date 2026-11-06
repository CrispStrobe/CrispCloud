import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bounded_transfer_stream.dart';

/// One FTP/implicit-FTPS data transfer per control connection. This deliberately
/// avoids sharing navigation commands or a library's unbounded sink.add loop.
/// Reply sequencing and passive data channels follow RFC 959/2428; TLS data
/// protection follows RFC 4217, with normal certificate validation.
class FtpTransferSession {
  FtpTransferSession({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.secure,
    required this.isCurrent,
    this.timeout = const Duration(seconds: 30),
  });
  final String host;
  final int port;
  final String username;
  final String password;
  final bool secure;
  final bool Function() isCurrent;
  final Duration timeout;
  Socket? _control;
  Socket? _data;
  StreamIterator<String>? _lines;
  bool _closed = false;

  void _check() {
    if (_closed || !isCurrent()) {
      throw StateError('The original FTP connection is no longer available.');
    }
  }

  Future<void> connect() async {
    _check();
    try {
      final connection = secure
          ? await SecureSocket.connect(host, port, timeout: timeout)
          : await Socket.connect(host, port, timeout: timeout);
      if (_closed || !isCurrent()) {
        connection.destroy();
        throw StateError('The original FTP connection is no longer available.');
      }
      _control = connection;
      _lines = StreamIterator(_replyLines(_control!));
      _expect(await _reply(), {220}, 'greeting');
      final user = await _command('USER $username');
      if (user.$1 == 331) {
        _expect(await _command('PASS $password'), {230}, 'login');
      } else {
        _expect(user, {230}, 'login');
      }
      if (secure) {
        _expect(await _command('PBSZ 0'), {200}, 'TLS buffer setup');
        _expect(await _command('PROT P'), {200}, 'TLS data protection');
      }
      _expect(await _command('TYPE I'), {200}, 'binary transfer setup');
      _check();
    } catch (_) {
      close();
      rethrow;
    }
  }

  Future<void> upload(
    String path,
    Stream<List<int>> source,
    int length, {
    void Function(int, int)? onProgress,
  }) async {
    if (length < 0) throw ArgumentError.value(length, 'length');
    _validateArgument(path);
    try {
      final finalReplyReceived = await _openData('STOR $path');
      var sent = 0;
      await _data!.addStream(
        validatedTransferParts(source, length, 64 * 1024).map((part) {
          _check();
          sent += part.length;
          onProgress?.call(sent, length);
          return part;
        }),
      );
      await _data!.flush();
      await _data!.close();
      _check();
      if (!finalReplyReceived) {
        _expect(await _reply(), {226, 250}, 'upload completion');
      }
    } finally {
      close();
    }
  }

  Stream<List<int>> download(
    String path, {
    void Function(int, int)? onProgress,
  }) async* {
    _validateArgument(path);
    try {
      final sizeReply = await _command('SIZE $path');
      final expected = sizeReply.$1 == 213
          ? int.tryParse(sizeReply.$2.substring(4).trim())
          : null;
      if (sizeReply.$1 == 550) {
        throw StateError('The FTP source is unavailable.');
      }
      final finalReplyReceived = await _openData('RETR $path');
      var received = 0;
      await for (final chunk in _data!.timeout(timeout)) {
        _check();
        received += chunk.length;
        if (expected != null && received > expected) {
          throw StateError('The FTP source exceeded its expected length.');
        }
        onProgress?.call(received, expected ?? received);
        yield chunk;
      }
      if (expected != null && received != expected) {
        throw StateError('The FTP source ended before its expected length.');
      }
      _check();
      if (!finalReplyReceived) {
        _expect(await _reply(), {226, 250}, 'download completion');
      }
    } finally {
      close();
    }
  }

  Future<bool> _openData(String command) async {
    _check();
    var passive = await _command('EPSV');
    int? dataPort;
    if (passive.$1 == 229) {
      final group = RegExp(r'\(([^)]*)\)').firstMatch(passive.$2)?.group(1);
      if (group != null && group.isNotEmpty) {
        final fields = group.split(group[0]);
        if (fields.length == 5 &&
            fields.take(3).every((part) => part.isEmpty) &&
            fields.last.isEmpty) {
          dataPort = int.tryParse(fields[3]);
        }
      }
    } else {
      passive = await _command('PASV');
      _expect(passive, {227}, 'passive mode');
      final group = RegExp(r'\(([^)]*)\)').firstMatch(passive.$2)?.group(1);
      final parts = group
          ?.split(',')
          .map((part) => int.tryParse(part.trim()))
          .toList();
      if (parts != null &&
          parts.length == 6 &&
          parts.every((part) => part != null && part >= 0 && part <= 255)) {
        dataPort = parts[4]! * 256 + parts[5]!;
      }
    }
    if (dataPort == null || dataPort <= 0 || dataPort > 65535) {
      throw StateError('FTP returned an invalid passive data port.');
    }
    _check();
    // Use the control peer, never a third-party address supplied by PASV.
    _data = await Socket.connect(
      _control!.remoteAddress,
      dataPort,
      timeout: timeout,
    );
    final response = await _command(command);
    _expect(response, {125, 150, 226, 250}, 'data transfer');
    if (secure) {
      _data = await SecureSocket.secure(_data!, host: host).timeout(timeout);
    }
    return response.$1 == 226 || response.$1 == 250;
  }

  Future<(int, String)> _command(String command) async {
    _check();
    _validateArgument(command);
    _control!.add(utf8.encode('$command\r\n'));
    await _control!.flush();
    return _reply();
  }

  Future<(int, String)> _reply() async {
    _check();
    if (!await _lines!.moveNext().timeout(timeout)) {
      throw StateError(
        'FTP closed the control connection before confirming completion.',
      );
    }
    final first = _lines!.current;
    final prefix = RegExp(r'^(\d{3})([ -])').firstMatch(first);
    if (prefix == null) throw StateError('FTP returned a malformed reply.');
    final code = int.parse(prefix.group(1)!);
    if (prefix.group(2) == '-') {
      var bytes = first.length;
      for (var count = 0; count < 256; count++) {
        if (!await _lines!.moveNext().timeout(timeout)) {
          throw StateError('FTP returned an incomplete multiline reply.');
        }
        final line = _lines!.current;
        bytes += line.length;
        if (bytes > 64 * 1024) {
          throw StateError('FTP reply exceeded the metadata limit.');
        }
        if (line.startsWith('$code ')) return (code, line);
      }
      throw StateError('FTP reply exceeded the line limit.');
    }
    return (code, first);
  }

  void _expect((int, String) reply, Set<int> accepted, String operation) {
    _check();
    if (!accepted.contains(reply.$1)) {
      throw StateError('FTP $operation failed (reply ${reply.$1}).');
    }
  }

  void close() {
    _data?.destroy();
    _control?.destroy();
    if (_closed) return;
    _closed = true;
    unawaited(_lines?.cancel().catchError((Object _) {}));
  }
}

void _validateArgument(String value) {
  if (value.contains('\r') ||
      value.contains('\n') ||
      value.contains('\u0000')) {
    throw ArgumentError('FTP arguments cannot contain control characters.');
  }
}

Stream<String> _replyLines(Stream<List<int>> source) async* {
  final pending = <int>[];
  await for (final chunk in source) {
    for (final byte in chunk) {
      if (byte == 10) {
        if (pending.isNotEmpty && pending.last == 13) pending.removeLast();
        yield utf8.decode(pending);
        pending.clear();
      } else {
        pending.add(byte);
        if (pending.length > 64 * 1024) {
          throw StateError('FTP reply exceeded the metadata limit.');
        }
      }
    }
  }
  if (pending.isNotEmpty) {
    throw StateError('FTP ended with an incomplete reply.');
  }
}
