import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ftpconnect/ftp_transport.dart';

import 'bounded_transfer_stream.dart';
import 'ftp_download_snapshot.dart';
import 'ftp_security_mode.dart';

/// One FTP/FTPS/FTPES data transfer per control connection. This deliberately
/// avoids sharing navigation commands or a library's unbounded sink.add loop.
/// Reply sequencing and passive data channels follow RFC 959/2428; TLS data
/// protection follows RFC 4217, with normal certificate validation.
class FtpTransferSession {
  FtpTransferSession({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    bool? secure,
    FtpSecurityMode? securityMode,
    required this.isCurrent,
    this.securityContext,
    this.timeout = const Duration(seconds: 30),
  }) : assert(secure == null || securityMode == null),
       securityMode =
           securityMode ??
           (secure == true
               ? FtpSecurityMode.implicitTls
               : FtpSecurityMode.plain);
  final String host;
  final int port;
  final String username;
  final String password;
  final FtpSecurityMode securityMode;
  bool get secure => securityMode.isSecure;
  final SecurityContext? securityContext;
  final bool Function() isCurrent;
  final Duration timeout;
  Socket? _control;
  Socket? _data;
  final _controlTransport = FtpSocketTransport();
  FtpSocketTransport? _dataTransport;
  StreamIterator<String>? _lines;
  bool _closed = false;

  String get connectionIdentity => FtpDownloadSnapshot.identity(
    host: host,
    port: port,
    username: username,
    securityMode: securityMode,
  );

  void _check() {
    if (_closed || !isCurrent()) {
      throw StateError('The original FTP connection is no longer available.');
    }
  }

  Future<void> connect() async {
    _check();
    try {
      await _controlTransport.connect(
        host,
        port,
        timeout: timeout,
        tlsHost: securityMode == FtpSecurityMode.implicitTls ? host : null,
        securityContext: securityContext,
      );
      _check();
      _control = _controlTransport.socket;
      _lines = StreamIterator(_replyLines(_control!));
      _expect(await _reply(), {220}, 'greeting');
      if (securityMode == FtpSecurityMode.explicitTls) {
        // Never send credentials or fall back to plaintext after a TLS refusal.
        _expect(await _command('AUTH TLS'), {234}, 'TLS upgrade');
        final oldLines = _lines!;
        await _controlTransport.secure(
          host,
          timeout: timeout,
          securityContext: securityContext,
        );
        _check();
        _control = _controlTransport.socket;
        _lines = StreamIterator(_replyLines(_control!));
        // The old iterator paused at the AUTH reply. TLS detached its socket;
        // cancelling it now cannot consume any encrypted response bytes.
        await oldLines.cancel();
      }
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

  /// Obtain exact SIZE/MDTM evidence without treating it as an immutable
  /// revision. The caller must retain a full source digest for durable resume.
  Future<FtpDownloadSnapshot> captureDownloadSnapshot(String path) async {
    _validateArgument(path);
    final sizeReply = await _command('SIZE $path');
    _expect(sizeReply, {213}, 'source size');
    final sizeText = sizeReply.$2.substring(4);
    final size = RegExp(r'^[0-9]+$').hasMatch(sizeText)
        ? int.tryParse(sizeText)
        : null;
    if (size == null || size < 0) {
      throw StateError('FTP returned an invalid source length.');
    }
    final modified = await _command('MDTM $path');
    _expect(modified, {213}, 'source modification time');
    return FtpDownloadSnapshot(
      connectionIdentity: connectionIdentity,
      path: path,
      size: size,
      modified: modified.$2.substring(4),
    );
  }

  /// Read [offset, offset + length), or through EOF when length is absent.
  /// FTP REST has no end bound, so a bounded range drains and validates the
  /// complete remaining wire transfer before reporting successful completion.
  /// The stream owns both sockets, including while REST/TLS setup is pending.
  /// Received bytes remain provisional until stream completion and the caller's
  /// full-file digest check; a 350 reply alone cannot prove the server's offset.
  Stream<List<int>> downloadRange(
    String path,
    int offset, {
    required FtpDownloadSnapshot expected,
    int? length,
    void Function(int, int)? onProgress,
  }) {
    late StreamController<List<int>> output;
    StreamSubscription<List<int>>? source;
    var cancelled = false;
    output = StreamController<List<int>>(
      sync: true,
      onListen: () {
        source =
            _downloadRange(
              path,
              offset,
              expected: expected,
              length: length,
              onProgress: onProgress,
            ).listen(
              (part) {
                if (!cancelled) output.add(part);
              },
              onError: (Object error, StackTrace stack) {
                if (!cancelled) output.addError(error, stack);
              },
              onDone: () {
                if (!cancelled) unawaited(output.close());
              },
            );
        if (output.isPaused) source!.pause();
      },
      onPause: () => source?.pause(),
      onResume: () => source?.resume(),
      onCancel: () {
        cancelled = true;
        close();
        unawaited(source?.cancel().catchError((Object _) {}));
      },
    );
    return output.stream;
  }

  Stream<List<int>> _downloadRange(
    String path,
    int offset, {
    required FtpDownloadSnapshot expected,
    int? length,
    void Function(int, int)? onProgress,
  }) async* {
    try {
      _validateArgument(path);
      if (offset < 0 ||
          offset > expected.size ||
          (length != null && (length < 0 || length > expected.size - offset))) {
        throw RangeError('The FTP range is outside the captured source.');
      }
      if (expected.connectionIdentity != connectionIdentity ||
          expected.path != path) {
        throw StateError('The original FTP source connection does not match.');
      }
      final features = await _command('FEAT');
      if (features.$1 != 211 ||
          !features.$2
              .split('\n')
              .any(
                (line) =>
                    line.startsWith(' ') &&
                    line.substring(1).toUpperCase() == 'REST STREAM',
              )) {
        throw UnsupportedError(
          'FTP resume requires advertised REST STREAM support. '
          'Review a complete restart instead.',
        );
      }
      _expect(await _command('MODE S'), {200}, 'stream transfer mode');
      _expect(await _command('STRU F'), {200}, 'file transfer structure');
      if (!expected.matches(await captureDownloadSnapshot(path))) {
        throw StateError('The FTP source changed since the saved transfer.');
      }
      final selectedLength = length ?? expected.size - offset;
      if (selectedLength == 0) return;
      final finalReplyReceived = await _openData(
        'RETR $path',
        restartOffset: offset,
      );
      final wireLength = expected.size - offset;
      var received = 0;
      var emitted = 0;
      await for (final chunk in _data!.timeout(timeout)) {
        _check();
        received += chunk.length;
        if (received > wireLength) {
          throw StateError('FTP did not honor the captured restart offset.');
        }
        onProgress?.call(offset + received, expected.size);
        final remaining = selectedLength - emitted;
        if (remaining > 0) {
          final part = chunk.length <= remaining
              ? chunk
              : chunk.sublist(0, remaining);
          emitted += part.length;
          yield part;
        }
      }
      if (received != wireLength || emitted != selectedLength) {
        throw StateError(
          'The FTP resumed source ended before its expected length.',
        );
      }
      _check();
      if (!finalReplyReceived) {
        _expect(await _reply(), {226, 250}, 'resumed download completion');
      }
      if (!expected.matches(await captureDownloadSnapshot(path))) {
        throw StateError('The FTP source changed during the resumed transfer.');
      }
    } finally {
      close();
    }
  }

  Future<bool> _openData(String command, {int? restartOffset}) async {
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
    final dataTransport = FtpSocketTransport();
    _dataTransport = dataTransport;
    await dataTransport.connect(
      _control!.remoteAddress,
      dataPort,
      timeout: timeout,
    );
    _check();
    if (restartOffset != null) {
      // RFC 3659 requires the transfer command immediately after REST. Passive
      // endpoint negotiation is complete before sending this marker.
      final restart = await _command('REST $restartOffset');
      if (const {500, 502, 504}.contains(restart.$1)) {
        throw UnsupportedError(
          'The FTP server refused byte-offset resume. '
          'Review a complete restart instead.',
        );
      }
      _expect(restart, {350}, 'restart offset');
    }
    final response = await _command(command);
    _expect(response, {125, 150, 226, 250}, 'data transfer');
    if (secure) {
      await dataTransport.secure(
        host,
        timeout: timeout,
        securityContext: securityContext,
      );
    }
    _check();
    _data = dataTransport.socket;
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
      final replyLines = <String>[first];
      for (var count = 0; count < 256; count++) {
        if (!await _lines!.moveNext().timeout(timeout)) {
          throw StateError('FTP returned an incomplete multiline reply.');
        }
        final line = _lines!.current;
        replyLines.add(line);
        bytes += line.length;
        if (bytes > 64 * 1024) {
          throw StateError('FTP reply exceeded the metadata limit.');
        }
        if (line.startsWith('$code ')) return (code, replyLines.join('\n'));
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
    _dataTransport?.close();
    _controlTransport.close();
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
