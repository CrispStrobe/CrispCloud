// lib/services/fuse_filesystem.dart
//
// FuseFilesystem bridges FUSE kernel operations to CloudStorageClient calls.
//
// Architecture overview
// ─────────────────────
// Since there is no pure-Dart FUSE binding that embeds libfuse directly, this
// class implements the "userspace side" of a two-process FUSE setup:
//
//   Kernel ↔ libfuse (helper process, see FuseHelperScript) ↔ [IPC socket]
//        ↔ FuseFilesystem (this class, runs in the Flutter Dart VM)
//        ↔ CloudStorageClient
//
// The helper script sets up the actual FUSE mount and forwards filesystem
// operations over a local Unix domain socket (or named pipe on Windows).
// FuseFilesystem listens on that socket, interprets requests, and fulfils
// them via the CloudStorageClient API.
//
// NOTE: Users must install the platform FUSE library themselves:
//   Linux  → sudo apt install fuse3
//   macOS  → https://osxfuse.github.io (macFUSE) or brew install macfuse
//   Windows → https://winfsp.dev
//
// Caching layer
// ─────────────
//   • Directory listing cache: 30-second TTL per path.
//   • Read-ahead buffer: reads are satisfied from a 256 KB rolling window.
//   • Write-back cache: writes accumulate locally; flushed on RELEASE (close).

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'cloud_storage_interface.dart';
import 'log_service.dart';

// ---------------------------------------------------------------------------
// Cache models
// ---------------------------------------------------------------------------

/// A single cached directory listing.
class _DirCache {
  final List<Map<String, dynamic>> entries;
  final DateTime fetchedAt;
  static const ttl = Duration(seconds: 30);

  _DirCache(this.entries) : fetchedAt = DateTime.now();

  bool get isExpired => DateTime.now().difference(fetchedAt) > ttl;
}

/// Read-ahead buffer for a single open file handle.
class _ReadBuffer {
  static const int chunkSize = 256 * 1024; // 256 KB

  final String remotePath;
  int bufferOffset = 0; // byte offset of the first byte in [data].
  Uint8List data = Uint8List(0);
  bool eof = false;

  _ReadBuffer(this.remotePath);
}

/// Write-back buffer for a dirty (written) file handle.
class _WriteBuffer {
  final String remotePath;
  final String fileName;
  final String remoteDir;

  // Sparse map: offset → data chunk
  final Map<int, Uint8List> chunks = {};
  int fileSize = 0; // tracked logical size

  _WriteBuffer({
    required this.remotePath,
    required this.fileName,
    required this.remoteDir,
  });

  /// Merge all chunks into a contiguous byte array.
  Uint8List assemble() {
    if (chunks.isEmpty) return Uint8List(0);
    final buf = Uint8List(fileSize);
    for (final entry in chunks.entries) {
      final start = entry.key;
      final src = entry.value;
      final end = (start + src.length).clamp(0, fileSize);
      buf.setRange(start, end, src);
    }
    return buf;
  }
}

// ---------------------------------------------------------------------------
// Operation types for the IPC protocol
// ---------------------------------------------------------------------------

/// Opcodes for the lightweight binary IPC protocol between the FUSE helper
/// process and this class.  Each request is:
///   [4B opcode][4B request-id][payload-length BE uint32][payload bytes]
///
/// Each response is:
///   [4B request-id][4B errno (0 = success)][payload-length BE uint32][payload]
abstract class FuseOpcode {
  static const getattr = 1;
  static const readdir = 2;
  static const read = 3;
  static const write = 4;
  static const create = 5;
  static const mkdir = 6;
  static const unlink = 7;
  static const rmdir = 8;
  static const rename = 9;
  static const release = 10; // close / flush
  static const truncate = 11;
  static const statfs = 12;
}

// ---------------------------------------------------------------------------
// FuseFilesystem
// ---------------------------------------------------------------------------

class FuseFilesystem {
  static const _log = Log('FuseFilesystem');

  final CloudStorageClient client;

  /// Root path on the cloud provider exposed through this mount.
  final String remotePath;

  // Directory listing cache: remote path → _DirCache
  final _dirCache = <String, _DirCache>{};

  // Open file handles: handle-id → buffer
  final _readBuffers = <int, _ReadBuffer>{};
  final _writeBuffers = <int, _WriteBuffer>{};

  int _nextHandle = 1;

  ServerSocket? _server;
  bool _disposed = false;

  /// Unix socket / named-pipe path for IPC with the helper process.
  late final String _socketPath;

  FuseFilesystem({required this.client, required this.remotePath});

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Start listening for IPC requests from the FUSE helper process.
  ///
  /// This method runs until [dispose] is called.
  Future<void> serveRequests() async {
    _socketPath = _buildSocketPath();
    try {
      _server = await ServerSocket.bind(
        InternetAddress(_socketPath, type: InternetAddressType.unix),
        0,
      );
      _log.info('FuseFilesystem IPC socket: $_socketPath');
      await for (final socket in _server!) {
        if (_disposed) break;
        unawaited(_handleConnection(socket));
      }
    } catch (e, st) {
      if (!_disposed) {
        _log.error('FuseFilesystem IPC server error', e, st);
      }
    }
  }

  /// Tear down the filesystem bridge, flush pending writes.
  Future<void> dispose() async {
    _disposed = true;
    await _flushAllWrites();
    await _server?.close();
    _readBuffers.clear();
    _writeBuffers.clear();
    _dirCache.clear();
    // Remove the socket file.
    try {
      final f = File(_socketPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // IPC connection handler
  // ---------------------------------------------------------------------------

  Future<void> _handleConnection(Socket socket) async {
    _log.debug('FUSE helper connected from ${socket.remoteAddress.address}');
    final buf = <int>[];

    await for (final chunk in socket) {
      buf.addAll(chunk);
      while (buf.length >= 12) {
        // Minimum header size: 4+4+4 bytes
        final opcode = _readUint32(buf, 0);
        final reqId = _readUint32(buf, 4);
        final payloadLen = _readUint32(buf, 8);
        if (buf.length < 12 + payloadLen) break; // wait for more data

        final payload = Uint8List.fromList(buf.sublist(12, 12 + payloadLen));
        buf.removeRange(0, 12 + payloadLen);

        unawaited(_dispatchRequest(socket, opcode, reqId, payload));
      }
    }

    // Flush write buffers when the connection closes.
    await _flushAllWrites();
    _log.debug('FUSE helper disconnected');
  }

  Future<void> _dispatchRequest(
    Socket socket,
    int opcode,
    int reqId,
    Uint8List payload,
  ) async {
    try {
      Uint8List responsePayload;
      switch (opcode) {
        case FuseOpcode.getattr:
          responsePayload = await _opGetattr(payload);
          break;
        case FuseOpcode.readdir:
          responsePayload = await _opReaddir(payload);
          break;
        case FuseOpcode.read:
          responsePayload = await _opRead(payload);
          break;
        case FuseOpcode.write:
          responsePayload = await _opWrite(payload);
          break;
        case FuseOpcode.create:
          responsePayload = await _opCreate(payload);
          break;
        case FuseOpcode.mkdir:
          responsePayload = await _opMkdir(payload);
          break;
        case FuseOpcode.unlink:
          responsePayload = await _opUnlink(payload);
          break;
        case FuseOpcode.rmdir:
          responsePayload = await _opRmdir(payload);
          break;
        case FuseOpcode.rename:
          responsePayload = await _opRename(payload);
          break;
        case FuseOpcode.release:
          responsePayload = await _opRelease(payload);
          break;
        case FuseOpcode.truncate:
          responsePayload = await _opTruncate(payload);
          break;
        case FuseOpcode.statfs:
          responsePayload = _opStatfs();
          break;
        default:
          _sendError(socket, reqId, errno: 38); // ENOSYS
          return;
      }
      _sendResponse(socket, reqId, payload: responsePayload);
    } catch (e, st) {
      _log.error('FUSE op $opcode failed', e, st);
      _sendError(socket, reqId, errno: 5); // EIO
    }
  }

  // ---------------------------------------------------------------------------
  // FUSE operation implementations
  // ---------------------------------------------------------------------------

  /// getattr → fetch metadata from directory cache or listPath.
  Future<Uint8List> _opGetattr(Uint8List payload) async {
    final path = _decodeString(payload, 0);
    final remoteFull = _fullRemotePath(path);

    if (path == '/' || path.isEmpty) {
      // Root is always a directory.
      return _encodeAttr(isDir: true, size: 0);
    }

    // Look in the parent directory's cached listing.
    final parentRemote = _fullRemotePath(p.dirname(path));
    final cached = _cachedDir(parentRemote);
    if (cached.isNotEmpty) {
      final name = p.basename(path);
      final item = cached.firstWhereOrNull((e) => e['name'] == name);
      if (item != null) return _attrFromItem(item);
    }

    // Cache miss — try resolving via the provider.
    final info = await client.resolvePath(remoteFull);
    if (info == null) {
      throw const _FuseError(2); // ENOENT
    }
    return _attrFromItem(info);
  }

  /// readdir → list directory, cache result.
  Future<Uint8List> _opReaddir(Uint8List payload) async {
    final path = _decodeString(payload, 0);
    final remoteFull = _fullRemotePath(path);

    final entries = await _listCached(remoteFull);
    return _encodeDir(entries);
  }

  /// read → satisfy from read-ahead buffer or download.
  Future<Uint8List> _opRead(Uint8List payload) async {
    int offset = 0;
    final handleId = _readUint32(payload, offset); offset += 4;
    final readOffset = _readUint64(payload, offset); offset += 8;
    final readLen = _readUint32(payload, offset);

    final buf = _readBuffers[handleId];
    if (buf == null) throw const _FuseError(9); // EBADF

    final data = await _satisfyRead(buf, readOffset, readLen);
    return data;
  }

  /// write → buffer locally.
  Future<Uint8List> _opWrite(Uint8List payload) async {
    int offset = 0;
    final handleId = _readUint32(payload, offset); offset += 4;
    final writeOffset = _readUint64(payload, offset); offset += 8;
    final dataLen = _readUint32(payload, offset); offset += 4;
    final data = payload.sublist(offset, offset + dataLen);

    final buf = _writeBuffers[handleId];
    if (buf == null) throw const _FuseError(9); // EBADF

    buf.chunks[writeOffset] = data;
    final end = writeOffset + dataLen;
    if (end > buf.fileSize) buf.fileSize = end;

    return _encodeUint32(dataLen); // return bytes written
  }

  /// create → open a new file for writing.
  Future<Uint8List> _opCreate(Uint8List payload) async {
    final path = _decodeString(payload, 0);
    final remoteFull = _fullRemotePath(path);
    final handleId = _nextHandle++;

    _writeBuffers[handleId] = _WriteBuffer(
      remotePath: remoteFull,
      fileName: p.basename(path),
      remoteDir: p.dirname(remoteFull),
    );

    _invalidateDirCache(p.dirname(remoteFull));
    return _encodeUint32(handleId);
  }

  /// mkdir → create cloud folder.
  Future<Uint8List> _opMkdir(Uint8List payload) async {
    final path = _decodeString(payload, 0);
    final remoteFull = _fullRemotePath(path);
    await client.createFolderPath(remoteFull);
    _invalidateDirCache(p.dirname(remoteFull));
    return Uint8List(0);
  }

  /// unlink → delete a file.
  Future<Uint8List> _opUnlink(Uint8List payload) async {
    final path = _decodeString(payload, 0);
    final remoteFull = _fullRemotePath(path);
    await client.deletePath(remoteFull);
    _invalidateDirCache(p.dirname(remoteFull));
    return Uint8List(0);
  }

  /// rmdir → delete a (presumed empty) folder.
  Future<Uint8List> _opRmdir(Uint8List payload) async {
    return _opUnlink(payload); // providers handle both
  }

  /// rename → cloud rename/move.
  Future<Uint8List> _opRename(Uint8List payload) async {
    int off = 0;
    final oldPath = _decodeString(payload, off); off += 4 + oldPath.length;
    final newPath = _decodeString(payload, off);

    final oldRemote = _fullRemotePath(oldPath);
    final newRemote = _fullRemotePath(newPath);

    final oldDir = p.dirname(oldRemote);
    final newDir = p.dirname(newRemote);
    final newName = p.basename(newRemote);

    if (oldDir == newDir) {
      // Same directory → rename.
      await client.renamePath(oldRemote, newName);
    } else {
      // Cross-directory → move.
      await client.movePath(oldRemote, newRemote);
    }

    _invalidateDirCache(oldDir);
    _invalidateDirCache(newDir);
    return Uint8List(0);
  }

  /// release → flush write-back buffer on file close.
  Future<Uint8List> _opRelease(Uint8List payload) async {
    final handleId = _readUint32(payload, 0);
    await _flushHandle(handleId);
    _readBuffers.remove(handleId);
    _writeBuffers.remove(handleId);
    return Uint8List(0);
  }

  /// truncate → truncate write-back buffer.
  Future<Uint8List> _opTruncate(Uint8List payload) async {
    int off = 0;
    final handleId = _readUint32(payload, off); off += 4;
    final newSize = _readUint64(payload, off);

    final wbuf = _writeBuffers[handleId];
    if (wbuf != null) {
      wbuf.fileSize = newSize;
    }
    return Uint8List(0);
  }

  /// statfs → return a synthetic filesystem stat block.
  Uint8List _opStatfs() {
    // Return: blocks, bfree, bavail, files, ffree, bsize, namelen, frsize
    // (8 × uint64 = 64 bytes). Synthetic values.
    final out = Uint8List(64);
    final view = ByteData.view(out.buffer);
    view.setUint64(0, 1 << 40, Endian.big); // total "blocks" (1 TB)
    view.setUint64(8, 1 << 39, Endian.big); // free blocks  (512 GB)
    view.setUint64(16, 1 << 39, Endian.big); // available blocks
    view.setUint64(24, 1 << 32, Endian.big); // total inodes
    view.setUint64(32, 1 << 31, Endian.big); // free inodes
    view.setUint64(40, 4096, Endian.big); // block size
    view.setUint64(48, 255, Endian.big); // max name length
    view.setUint64(56, 512, Endian.big); // fragment size
    return out;
  }

  // ---------------------------------------------------------------------------
  // Read-ahead buffering
  // ---------------------------------------------------------------------------

  Future<Uint8List> _satisfyRead(
    _ReadBuffer buf,
    int offset,
    int length,
  ) async {
    // If the requested range is entirely within the buffer, return immediately.
    final bufEnd = buf.bufferOffset + buf.data.length;
    if (offset >= buf.bufferOffset && offset + length <= bufEnd) {
      final start = offset - buf.bufferOffset;
      return Uint8List.fromList(buf.data.sublist(start, start + length));
    }

    if (buf.eof && offset >= bufEnd) {
      return Uint8List(0); // past end of file
    }

    // Download a fresh chunk (providers that support range requests would
    // use offset + _ReadBuffer.chunkSize; we download the whole file here
    // since the CloudStorageClient API does not expose range fetches).
    try {
      final rawBytes = await client.downloadFileBytes(buf.remotePath);
      // Cache the entire file in the read-ahead buffer.
      buf.bufferOffset = 0;
      buf.data = rawBytes;
      buf.eof = true;

      final start = offset.clamp(0, rawBytes.length);
      final end = (offset + length).clamp(0, rawBytes.length);
      return Uint8List.fromList(rawBytes.sublist(start, end));
    } catch (e) {
      _log.error('Read-ahead fetch failed at $offset+${_ReadBuffer.chunkSize}', e);
      throw const _FuseError(5); // EIO
    }
  }

  // ---------------------------------------------------------------------------
  // Write-back flushing
  // ---------------------------------------------------------------------------

  Future<void> _flushHandle(int handleId) async {
    final wbuf = _writeBuffers[handleId];
    if (wbuf == null || wbuf.chunks.isEmpty) return;

    try {
      final assembled = wbuf.assemble();
      await client.uploadFile(assembled, wbuf.fileName, wbuf.remoteDir);
      _invalidateDirCache(wbuf.remoteDir);
      _log.debug('Flushed ${wbuf.fileName} (${assembled.length} bytes)');
    } catch (e) {
      _log.error('Write-back flush failed for ${wbuf.remotePath}', e);
      rethrow;
    }
  }

  Future<void> _flushAllWrites() async {
    for (final handleId in List<int>.from(_writeBuffers.keys)) {
      try {
        await _flushHandle(handleId);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Directory listing cache
  // ---------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _listCached(String remoteFull) async {
    final cached = _dirCache[remoteFull];
    if (cached != null && !cached.isExpired) return cached.entries;

    try {
      final result = await client.listPath(remoteFull);
      // CloudStorageClient.listPath returns a Map with an 'items' or similar key.
      final items = _extractItems(result);
      _dirCache[remoteFull] = _DirCache(items);
      return items;
    } catch (e) {
      _log.error('listPath failed for $remoteFull', e);
      throw const _FuseError(5); // EIO
    }
  }

  List<Map<String, dynamic>> _cachedDir(String remoteFull) {
    final cached = _dirCache[remoteFull];
    if (cached != null && !cached.isExpired) return cached.entries;
    return const [];
  }

  void _invalidateDirCache(String remoteFull) {
    _dirCache.remove(remoteFull);
  }

  /// Extract the list of file/folder entries from a listPath result map.
  ///
  /// Different provider adapters use different top-level keys. This method
  /// tries common ones and falls back to the raw map values.
  List<Map<String, dynamic>> _extractItems(Map<String, dynamic> result) {
    for (final key in ['items', 'files', 'children', 'entries', 'contents']) {
      final v = result[key];
      if (v is List) {
        return v.cast<Map<String, dynamic>>();
      }
    }
    // Some adapters return a flat map where keys are file names.
    return result.values
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Remote path helpers
  // ---------------------------------------------------------------------------

  String _fullRemotePath(String localRelativePath) {
    if (localRelativePath == '/' || localRelativePath.isEmpty) {
      return remotePath;
    }
    return p.join(remotePath, localRelativePath.replaceFirst('/', ''));
  }

  // ---------------------------------------------------------------------------
  // Attribute encoding helpers
  // ---------------------------------------------------------------------------

  Uint8List _attrFromItem(Map<String, dynamic> item) {
    final isDir = item['type'] == 'folder' ||
        item['type'] == 'directory' ||
        item['isDirectory'] == true;
    final size = (item['size'] as num?)?.toInt() ?? 0;
    final modTimeMs = _parseModTime(item);
    return _encodeAttr(isDir: isDir, size: size, modTimeMs: modTimeMs);
  }

  int _parseModTime(Map<String, dynamic> item) {
    final v = item['modificationTime'] ?? item['lastModified'] ?? item['modified'];
    if (v is int) return v;
    if (v is String) {
      final dt = DateTime.tryParse(v);
      if (dt != null) return dt.millisecondsSinceEpoch;
    }
    return DateTime.now().millisecondsSinceEpoch;
  }

  /// Encode file attributes into a 24-byte binary blob.
  ///
  /// Layout:
  ///   [0..3]   mode (uint32): 0x4000 = dir, 0x8000 = file  + permissions
  ///   [4..11]  size (uint64)
  ///   [12..19] mtime_ms (uint64)
  ///   [20..23] nlinks (uint32)
  Uint8List _encodeAttr({
    required bool isDir,
    required int size,
    int? modTimeMs,
  }) {
    final out = Uint8List(24);
    final view = ByteData.view(out.buffer);
    // Unix mode: directory = 0o40755, regular file = 0o100644
    final mode = isDir ? 0x41ED : 0x81A4;
    view.setUint32(0, mode, Endian.big);
    view.setUint64(4, size, Endian.big);
    view.setUint64(12, modTimeMs ?? DateTime.now().millisecondsSinceEpoch, Endian.big);
    view.setUint32(20, isDir ? 2 : 1, Endian.big);
    return out;
  }

  /// Encode a directory listing.
  ///
  /// Layout: [4B count][for each entry: 1B name_len][name bytes][24B attr]]
  Uint8List _encodeDir(List<Map<String, dynamic>> items) {
    final parts = <List<int>>[];
    for (final item in items) {
      final name = (item['name'] as String?) ?? '';
      final nameBytes = name.codeUnits;
      final attr = _attrFromItem(item);
      final entry = Uint8List(1 + nameBytes.length + 24);
      entry[0] = nameBytes.length;
      entry.setAll(1, nameBytes);
      entry.setAll(1 + nameBytes.length, attr);
      parts.add(entry);
    }
    // Also add synthetic . and ..
    final total = 4 + parts.fold<int>(0, (s, e) => s + e.length);
    final out = Uint8List(total);
    final view = ByteData.view(out.buffer);
    view.setUint32(0, parts.length, Endian.big);
    int cursor = 4;
    for (final part in parts) {
      out.setAll(cursor, part);
      cursor += part.length;
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // IPC wire helpers
  // ---------------------------------------------------------------------------

  void _sendResponse(Socket socket, int reqId, {Uint8List? payload}) {
    payload ??= Uint8List(0);
    final header = Uint8List(12);
    final view = ByteData.view(header.buffer);
    view.setUint32(0, reqId, Endian.big);
    view.setUint32(4, 0, Endian.big); // errno = 0
    view.setUint32(8, payload.length, Endian.big);
    socket.add(header);
    if (payload.isNotEmpty) socket.add(payload);
  }

  void _sendError(Socket socket, int reqId, {required int errno}) {
    final header = Uint8List(12);
    final view = ByteData.view(header.buffer);
    view.setUint32(0, reqId, Endian.big);
    view.setUint32(4, errno, Endian.big);
    view.setUint32(8, 0, Endian.big);
    socket.add(header);
  }

  // ---------------------------------------------------------------------------
  // Binary encoding / decoding
  // ---------------------------------------------------------------------------

  int _readUint32(List<int> buf, int offset) {
    return (buf[offset] << 24) |
        (buf[offset + 1] << 16) |
        (buf[offset + 2] << 8) |
        buf[offset + 3];
  }

  int _readUint64(List<int> buf, int offset) {
    // Dart integers are 64-bit on native, no risk of overflow for reasonable sizes.
    int value = 0;
    for (var i = 0; i < 8; i++) {
      value = (value << 8) | buf[offset + i];
    }
    return value;
  }

  Uint8List _encodeUint32(int value) {
    final out = Uint8List(4);
    final view = ByteData.view(out.buffer);
    view.setUint32(0, value, Endian.big);
    return out;
  }

  /// Decode a length-prefixed UTF-8 string: [4B length][bytes...].
  String _decodeString(List<int> buf, int offset) {
    final len = _readUint32(buf, offset);
    return String.fromCharCodes(buf.sublist(offset + 4, offset + 4 + len));
  }

  // ---------------------------------------------------------------------------
  // Socket path
  // ---------------------------------------------------------------------------

  String _buildSocketPath() {
    if (Platform.isWindows) {
      // Windows named pipe
      return r'\\.\pipe\crispcloud_fuse_' + _uniqueSuffix();
    }
    // Unix domain socket in a temp directory.
    final tmp = Directory.systemTemp.path;
    return p.join(tmp, 'crispcloud_fuse_${_uniqueSuffix()}.sock');
  }

  String _uniqueSuffix() =>
      DateTime.now().millisecondsSinceEpoch.toRadixString(36);
}

// ---------------------------------------------------------------------------
// Internal exception
// ---------------------------------------------------------------------------

class _FuseError implements Exception {
  final int errno;
  const _FuseError(this.errno);
  @override
  String toString() => 'FuseError(errno=$errno)';
}

// ---------------------------------------------------------------------------
// Iterable extension (avoids importing collection package)
// ---------------------------------------------------------------------------

extension _IterableFirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
