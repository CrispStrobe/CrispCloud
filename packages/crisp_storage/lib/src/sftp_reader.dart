import 'host_keys.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dartssh2/dartssh2.dart';
import 'package:path/path.dart' as p;
import 'remote_client.dart';
import 'download_state.dart';

/// Read-only SFTP adapter with a pinned host key and a canonical root boundary.
class SftpReader {
  final RemoteConnection connection;
  final Uri Function(String) resolve;
  SSHClient? _ssh;
  SftpClient? _sftp;
  String? _root;
  bool _closed = false;
  SftpReader(this.connection, this.resolve);
  void _checkOpen() {
    if (_closed) throw const RemoteException('Download paused.');
  }

  Future<SftpClient> _open() async {
    _checkOpen();
    if (_sftp != null) return _sftp!;
    String? observed;
    try {
      final socket = await SSHSocket.connect(
        connection.url.host,
        connection.url.hasPort ? connection.url.port : 22,
        timeout: const Duration(seconds: 10),
      );
      if (_closed) {
        await socket.close();
        _checkOpen();
      }
      final ssh = await openVerifiedSsh(socket,
          username: connection.username,
          password: connection.secret,
          onCreated: (client) => _ssh = client,
          verify: (_, fingerprint) {
            observed = utf8.decode(fingerprint);
            if (observed != connection.hostKey) {
              throw SftpHostKeyException(observed!,
                  expected: connection.hostKey);
            }
            return true;
          });
      _ssh = ssh;
      if (_closed) {
        await ssh.close();
        _checkOpen();
      }
      _checkOpen();
      final client = _sftp = await ssh.sftp().timeout(
            const Duration(seconds: 15),
          );
      _root = p.posix.normalize(
        await client
            .absolute(Uri.decodeComponent(connection.url.path))
            .timeout(const Duration(seconds: 15)),
      );
      return client;
    } catch (error) {
      close();
      if (error is SftpHostKeyException) rethrow;
      if (observed != null && observed != connection.hostKey) {
        throw SftpHostKeyException(observed!);
      }
      throw const RemoteException(
        'Could not connect to SFTP. Check the server, username and password.',
      );
    }
  }

  Future<String> _path(String path) async {
    final client = await _open();
    final resolved = resolve(path.isEmpty ? connection.url.toString() : path);
    final canonical = p.posix.normalize(
      await client
          .absolute(Uri.decodeComponent(resolved.path))
          .timeout(const Duration(seconds: 15)),
    );
    if (canonical != _root && !p.posix.isWithin(_root!, canonical)) {
      throw const RemoteException(
        'The SFTP path is outside this connection’s root.',
      );
    }
    return canonical;
  }

  Future<List<RemoteEntry>> browse(String path) async {
    final target = await _path(path);
    final listing =
        await _sftp!.listdir(target).timeout(const Duration(seconds: 20));
    if (listing.length > 10000) {
      throw const RemoteException('SFTP folder is too large.');
    }
    final parent = resolve(path.isEmpty ? connection.url.toString() : path);
    final result = <RemoteEntry>[];
    for (final entry in listing) {
      final name = entry.filename;
      if (name == '.' ||
          name == '..' ||
          name.contains('/') ||
          name.contains('\\') ||
          name.contains('\u0000') ||
          (!entry.attr.isDirectory && !entry.attr.isFile)) {
        continue;
      }
      final uri = parent.replace(
        path: p.posix.join(Uri.decodeComponent(parent.path), name) +
            (entry.attr.isDirectory ? '/' : ''),
      );
      result.add(
        RemoteEntry(
          uri.toString(),
          name,
          entry.attr.isDirectory ? 'folder' : 'file',
          size: entry.attr.size,
        ),
      );
    }
    result.sort(
      (a, b) => a.type == b.type
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.type == 'folder'
              ? -1
              : 1,
    );
    return result;
  }

  Future<void> download(
    String path,
    File output, {
    void Function(int)? onBytes,
    required int limit,
  }) async {
    final canonical = await _path(path);
    final file = await _sftp!
        .open(canonical, mode: SftpFileOpenMode.read)
        .timeout(const Duration(seconds: 15));
    try {
      final attrs = await file.stat().timeout(const Duration(seconds: 15));
      final size = attrs.size;
      if (!attrs.isFile || size == null || size <= 0 || size > limit) {
        throw const RemoteException(
          'SFTP file is empty, unsupported or exceeds the download limit.',
        );
      }
      final validator =
          attrs.modifyTime == null ? '' : '${attrs.modifyTime}:$size';
      final source = resolve(path).toString();
      final saved = await DownloadState.read(output);
      var offset = await output.exists() ? await output.length() : 0;
      if (validator.isEmpty ||
          saved?.source != source ||
          saved?.validator != validator ||
          offset > size) {
        offset = 0;
      }
      final sink = output.openWrite(
        mode: offset > 0 ? FileMode.append : FileMode.write,
      );
      var received = offset;
      try {
        await sink.flush();
        await DownloadState(source, validator, size).save(output);
        onBytes?.call(received);
        if (offset < size) {
          await for (final bytes in file
              .read(offset: offset, length: size - offset)
              .timeout(const Duration(seconds: 30))) {
            _checkOpen();
            received += bytes.length;
            if (received > size || received > limit) {
              throw const RemoteException('SFTP file changed during download.');
            }
            sink.add(bytes);
            if (received % (1024 * 1024) < bytes.length) await sink.flush();
            onBytes?.call(received);
          }
        }
        await sink.flush();
        if (received != size) {
          throw const RemoteException('SFTP download was incomplete.');
        }
        final after = await file.stat().timeout(const Duration(seconds: 15));
        if (after.size != size || after.modifyTime != attrs.modifyTime) {
          throw const RemoteException(
            'SFTP file changed during download. Retry it.',
          );
        }
      } finally {
        await sink.close();
      }
    } finally {
      try {
        await file.close().timeout(const Duration(seconds: 5));
      } catch (_) {
        /* Session may have been paused. */
      }
    }
  }

  void close() {
    _closed = true;
    final ssh = _ssh;
    if (ssh != null) unawaited(ssh.close().catchError((Object _) {}));
  }
}
