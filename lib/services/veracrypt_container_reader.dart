// Copyright 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
// Format-level implementation; no VeraCrypt/TrueCrypt implementation is linked.

import 'dart:async';
import 'dart:typed_data';

import 'package:koni_archive/koni_archive.dart' as koni;

import 'archive_ext_reader.dart';
import 'archive_fat_reader.dart';
import 'archive_ntfs_reader.dart';
import 'archive_types.dart';
import 'veracrypt_header_worker.dart';
import 'veracrypt_service.dart';

/// The user selects one header; backup/hidden headers are never tried silently.
enum VeraCryptHeaderLocation { primary, backup, hidden, hiddenBackup }

extension VeraCryptHeaderLocationDetails on VeraCryptHeaderLocation {
  bool get isHidden =>
      this == VeraCryptHeaderLocation.hidden ||
      this == VeraCryptHeaderLocation.hiddenBackup;

  int offsetInContainer(int size) => switch (this) {
    VeraCryptHeaderLocation.primary => 0,
    VeraCryptHeaderLocation.hidden => 65536,
    VeraCryptHeaderLocation.backup => size - 131072,
    VeraCryptHeaderLocation.hiddenBackup => size - 65536,
  };
}

/// Opens a file container as a bounded read-only filesystem. Owns [source] on
/// success and failure. Its lifetime ends when the returned archive is closed.
///
/// Only AES-XTS file volumes and the existing FAT/NTFS/ext reader profiles are
/// admitted. No decrypted image is written to disk. On native platforms the
/// expensive header derivation runs in a cancellable worker isolate. Browser
/// derivation is synchronous and uses the service's stricter resource limits.
Future<ViewerArchive> openVeraCryptArchive(
  koni.ByteSource source, {
  required String password,
  VeraCryptUnlockOptions options = const VeraCryptUnlockOptions(),
  VeraCryptHeaderLocation headerLocation = VeraCryptHeaderLocation.primary,
  int maxMemberBytes = kArchiveReadLimit,
  bool Function()? isCancelled,
  FutureOr<void> Function()? validateUnchanged,
}) async {
  final owned = _EncryptedSource(source, isCancelled, validateUnchanged);
  VeraCryptUnlockedVolume? volume;
  VeraCryptDecryptedSource? decrypted;
  ViewerArchive? filesystem;
  _HeaderRequest? request;
  try {
    if (maxMemberBytes <= 0 || maxMemberBytes > kArchiveStreamingLimit) {
      throw ArgumentError.value(maxMemberBytes, 'maxMemberBytes');
    }
    if (source.length < 262144 + 512 ||
        source.length > 9007199254740991 ||
        source.length % 512 != 0) {
      throw const ArchiveViewException(
        'This file is too short or has unsupported container geometry.',
        code: ArchiveMessageCode.unsupported,
      );
    }
    final offset = headerLocation.offsetInContainer(source.length);
    final header = await owned.read(offset, 512);
    // Snapshot only the bytes the keyfile algorithm consumes. Caller-owned
    // buffers may be disposed while a cancelled asynchronous open completes.
    if (options.keyfiles.length > 64) {
      throw ArgumentError('At most 64 keyfiles are supported.');
    }
    request = _HeaderRequest(
      header,
      password,
      VeraCryptUnlockOptions(
        kdf: options.kdf,
        pim: options.pim,
        keyfiles: [
          for (final keyfile in options.keyfiles)
            Uint8List.fromList(
              keyfile.length > 1048576 ? keyfile.sublist(0, 1048576) : keyfile,
            ),
        ],
        trueCryptMode: options.trueCryptMode,
        maxArgon2MemoryKiB: options.maxArgon2MemoryKiB,
        maxArgon2Iterations: options.maxArgon2Iterations,
        maxPbkdf2Iterations: options.maxPbkdf2Iterations,
      ),
      source.length,
    );
    volume = await unlockVeraCryptHeaderAsync(
      request.header,
      request.password,
      options: request.options,
      containerSizeBytes: request.size,
      isCancelled: isCancelled,
    );
    await owned.checkpoint();
    if (volume == null) {
      throw const ArchivePasswordRequiredException(
        'The selected header could not be unlocked. Check the password, PIM, '
        'keyfiles, KDF, format and header location. Unsupported ciphers or a '
        'damaged header can produce the same result.',
        wrongPassword: true,
        code: ArchiveMessageCode.wrongOrCorrupt,
      );
    }
    if ((volume.header.hiddenVolumeSize > 0) != headerLocation.isHidden) {
      throw const ArchiveViewException(
        'The unlocked header does not match the selected normal/hidden volume.',
        code: ArchiveMessageCode.corrupt,
      );
    }
    decrypted = VeraCryptDecryptedSource(owned, volume);
    if (await hasNtfsVolumeRecognition(decrypted)) {
      filesystem = await openNtfsArchive(
        decrypted,
        maxMemberBytes: maxMemberBytes,
        isCancelled: isCancelled,
      );
    } else if (await hasFatVolumeRecognition(decrypted)) {
      filesystem = await openFatArchive(
        decrypted,
        maxMemberBytes: maxMemberBytes,
        isCancelled: isCancelled,
      );
    } else if (await hasExtVolumeRecognition(decrypted)) {
      filesystem = await openExtArchive(
        decrypted,
        maxMemberBytes: maxMemberBytes,
        isCancelled: isCancelled,
      );
    } else {
      throw const ArchiveViewException(
        'The container unlocked, but its filesystem is not supported. '
        'Bundled browsing supports the documented FAT12/16/32, NTFS and '
        'ext2/3/4 profiles. exFAT and other filesystems are not yet supported.',
        code: ArchiveMessageCode.unsupported,
      );
    }
    await owned.checkpoint();
    final opened = filesystem;
    final format = options.trueCryptMode ? 'TrueCrypt' : 'VeraCrypt';
    // Retain the filesystem's format identity: the shared namespace validator
    // uses it to omit ext/NTFS special files from regular-file extraction.
    return ViewerArchive.reader(
      formatName: opened.formatName,
      members: opened.members,
      maxStreamingMemberBytes: opened.maxStreamingMemberBytes,
      notices: [
        'Read-only $format AES-256-XTS container. '
            'Closing this view locks the in-memory session.',
        'XTS encryption does not authenticate file contents. Header CRCs '
            'detect accidental damage, not malicious modification.',
        ...opened.notices,
      ],
      read: (member, limit) => opened.readMember(member, maxBytes: limit),
      streamReader: (member, chunkSize) => opened.openMember(
        member,
        maxBytes: maxMemberBytes,
        chunkSize: chunkSize,
      ),
      close: opened.close,
    );
  } catch (error, stack) {
    try {
      if (filesystem != null) {
        await filesystem.close();
      } else if (decrypted != null) {
        await decrypted.close();
      } else {
        volume?.dispose();
        await owned.close();
      }
    } finally {
      Error.throwWithStackTrace(error, stack);
    }
  } finally {
    request?.clearKeyfiles();
  }
}

class _HeaderRequest {
  const _HeaderRequest(this.header, this.password, this.options, this.size);
  final Uint8List header;
  final String password;
  final VeraCryptUnlockOptions options;
  final int size;

  void clearKeyfiles() {
    for (final keyfile in options.keyfiles) {
      keyfile.fillRange(0, keyfile.length, 0);
    }
  }
}

/// Random access to the encrypted extent, without decrypting the entire image.
/// XTS uses 512-byte data units and absolute container offsets, even for a
/// filesystem whose logical sectors are 4096 bytes. Each request is bounded;
/// larger extraction proceeds through the filesystem readers' chunked streams.
class VeraCryptDecryptedSource implements koni.ByteSource {
  VeraCryptDecryptedSource(this._source, this._volume) {
    final header = _volume.header;
    if (header.encryptedAreaOffset < 0 ||
        header.encryptedAreaSize <= 0 ||
        header.encryptedAreaOffset > _source.length ||
        header.encryptedAreaSize >
            _source.length - header.encryptedAreaOffset ||
        header.encryptedAreaOffset % 512 != 0 ||
        header.encryptedAreaSize % 512 != 0) {
      throw const ArchiveViewException(
        'Encrypted extent leaves its container.',
      );
    }
  }

  static const _window = 64 * 1024;
  final koni.ByteSource _source;
  final VeraCryptUnlockedVolume _volume;
  bool _closed = false;
  Future<void>? _closing;

  @override
  int get length => _volume.header.encryptedAreaSize;
  @override
  String get name => 'decrypted-volume.img';
  bool get isClosed => _closed || _volume.isClosed;

  void _check() {
    if (isClosed) {
      throw const ArchiveViewException(
        'This encrypted container is locked.',
        code: ArchiveMessageCode.closed,
      );
    }
  }

  @override
  Future<Uint8List> read(int offset, int count) async {
    _check();
    if (offset < 0 || count < 0 || offset > length || count > length - offset) {
      throw const ArchiveViewException('Read leaves the encrypted volume.');
    }
    if (count > kArchiveReadLimit) {
      throw const ArchiveViewException(
        'A decrypted read exceeds the 64 MiB memory limit.',
        code: ArchiveMessageCode.archiveLimit,
      );
    }
    final result = Uint8List(count);
    try {
      var copied = 0;
      while (copied < count) {
        _check();
        final at = offset + copied;
        final unitStart = at - at % 512;
        final skip = at - unitStart;
        final take = count - copied < _window - skip
            ? count - copied
            : _window - skip;
        final alignedLength = ((skip + take + 511) ~/ 512) * 512;
        final absolute = _volume.header.encryptedAreaOffset + unitStart;
        final encrypted = await _source.read(absolute, alignedLength);
        _check();
        if (encrypted.length != alignedLength) {
          throw const ArchiveViewException(
            'The container source is truncated.',
          );
        }
        final plain = _volume.decryptDataUnits(
          encrypted,
          absoluteByteOffset: absolute,
        );
        try {
          result.setRange(copied, copied + take, plain, skip);
        } finally {
          plain.fillRange(0, plain.length, 0);
        }
        copied += take;
        if (copied < count) await Future<void>.delayed(Duration.zero);
      }
      _check();
      return result;
    } catch (_) {
      result.fillRange(0, result.length, 0);
      rethrow;
    }
  }

  @override
  Future<void> close() {
    _closed = true;
    _volume.dispose();
    return _closing ??= _source.close();
  }
}

/// Owns the input, serializes positional I/O and checks capture identity before
/// and after every read. This also makes failure cleanup idempotent.
class _EncryptedSource implements koni.ByteSource {
  _EncryptedSource(this.source, this.isCancelled, this.validateUnchanged)
    : length = source.length;
  final koni.ByteSource source;
  final bool Function()? isCancelled;
  final FutureOr<void> Function()? validateUnchanged;
  @override
  final int length;
  @override
  String? get name => source.name;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();
  Future<void>? _closing;

  void _check() {
    if (_closed) {
      throw const ArchiveViewException('The container source is closed.');
    }
    if ((isCancelled?.call() ?? false) || source.length != length) {
      throw const ArchiveViewException(
        'Container opening or reading was cancelled.',
      );
    }
  }

  Future<void> checkpoint() async {
    _check();
    await validateUnchanged?.call();
    _check();
  }

  @override
  Future<Uint8List> read(int offset, int count) {
    final result = Completer<Uint8List>();
    _tail = _tail.then((_) async {
      try {
        await checkpoint();
        if (offset < 0 ||
            count < 0 ||
            offset > length ||
            count > length - offset) {
          throw const ArchiveViewException(
            'Read leaves the captured container.',
          );
        }
        if (count > 64 * 1024) {
          throw const ArchiveViewException(
            'Container read window is too large.',
          );
        }
        final bytes = await source.read(offset, count);
        await checkpoint();
        if (bytes.length != count) {
          throw const ArchiveViewException(
            'The container source is truncated.',
          );
        }
        result.complete(Uint8List.fromList(bytes));
      } catch (error, stack) {
        result.completeError(error, stack);
      }
    });
    return result.future;
  }

  @override
  Future<void> close() {
    _closed = true;
    return _closing ??= _tail.then((_) => source.close());
  }
}
