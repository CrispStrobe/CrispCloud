import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'storage_transfer_contract.dart';

// Descriptor APIs keep a final-component symlink from redirecting metadata
// changes. The limits apply to metadata, never to the file's content length.
const _maxNames = 64 * 1024;
const _maxValue = 16 * 1024 * 1024;
const _maxMetadata = 32 * 1024 * 1024;
const _linuxAccess = 'system.posix_acl_access';
const _linuxDefault = 'system.posix_acl_default';
const _linuxAclPrefix = 'linux-posix-v1:';
const _darwinAclPrefix = 'darwin-acl-v1:';

bool get supportsNativeMetadata =>
    (Platform.isLinux || Platform.isMacOS) && sizeOf<IntPtr>() == 8;
bool get supportsNativeOwnership =>
    supportsNativeMetadata &&
    DynamicLibrary.process().providesSymbol(
      Platform.isMacOS ? 'fgetattrlist' : 'statx',
    );
bool get supportsNativeExtendedAttributes =>
    supportsNativeMetadata &&
    DynamicLibrary.process().providesSymbol('flistxattr') &&
    DynamicLibrary.process().providesSymbol('fgetxattr') &&
    DynamicLibrary.process().providesSymbol('fsetxattr');
bool get supportsNativeAccessControlLists =>
    supportsNativeMetadata &&
    (Platform.isLinux
        ? supportsNativeExtendedAttributes
        : DynamicLibrary.process().providesSymbol('acl_get_fd_np') &&
              DynamicLibrary.process().providesSymbol('acl_set_fd_np'));

Future<TransferMetadata> readNativeMetadata(
  String path, {
  bool ownership = true,
  bool extendedAttributes = true,
  bool acl = true,
}) => Isolate.run(
  () => _read(
    path,
    ownership: ownership,
    extendedAttributes: extendedAttributes,
    acl: acl,
  ),
);

Future<void> writeNativeMetadata(String path, TransferMetadata metadata) =>
    Isolate.run(() => _write(path, metadata));

typedef _OpenN = Int32 Function(Pointer<Utf8>, Int32, VarArgs<(Int32,)>);
typedef _OpenD = int Function(Pointer<Utf8>, int, int);
typedef _CloseN = Int32 Function(Int32);
typedef _CloseD = int Function(int);
typedef _ErrnoN = Pointer<Int32> Function();
typedef _ErrnoD = Pointer<Int32> Function();
typedef _StatxN = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Int32,
  Uint32,
  Pointer<Uint8>,
);
typedef _StatxD = int Function(int, Pointer<Utf8>, int, int, Pointer<Uint8>);
typedef _GetattrN = Int32 Function(
  Int32,
  Pointer<_AttrList>,
  Pointer<Uint32>,
  Size,
  UnsignedLong,
);
typedef _GetattrD = int Function(
  int,
  Pointer<_AttrList>,
  Pointer<Uint32>,
  int,
  int,
);
typedef _ChownN = Int32 Function(Int32, Uint32, Uint32);
typedef _ChownD = int Function(int, int, int);
typedef _ChmodN = Int32 Function(Int32, Uint32);
typedef _ChmodD = int Function(int, int);
typedef _TimesN = Int32 Function(Int32, Pointer<_Timespec>);
typedef _TimesD = int Function(int, Pointer<_Timespec>);
typedef _ListN = IntPtr Function(Int32, Pointer<Uint8>, Size);
typedef _ListD = int Function(int, Pointer<Uint8>, int);
typedef _ListMacN = IntPtr Function(Int32, Pointer<Uint8>, Size, Int32);
typedef _ListMacD = int Function(int, Pointer<Uint8>, int, int);
typedef _GetN = IntPtr Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _GetD = int Function(int, Pointer<Utf8>, Pointer<Uint8>, int);
typedef _GetMacN = IntPtr Function(
  Int32,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Size,
  Uint32,
  Int32,
);
typedef _GetMacD = int Function(
  int,
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
  int,
  int,
);
typedef _SetN = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Size,
  Int32,
);
typedef _SetD = int Function(int, Pointer<Utf8>, Pointer<Uint8>, int, int);
typedef _SetMacN = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Size,
  Uint32,
  Int32,
);
typedef _SetMacD = int Function(
  int,
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
  int,
  int,
);
typedef _RemoveN = Int32 Function(Int32, Pointer<Utf8>);
typedef _RemoveD = int Function(int, Pointer<Utf8>);
typedef _GetAclN = Pointer<Void> Function(Int32, Int32);
typedef _GetAclD = Pointer<Void> Function(int, int);
typedef _AclTextN = Pointer<Utf8> Function(Pointer<Void>, Pointer<IntPtr>);
typedef _AclTextD = Pointer<Utf8> Function(Pointer<Void>, Pointer<IntPtr>);
typedef _AclFromN = Pointer<Void> Function(Pointer<Utf8>);
typedef _AclFromD = Pointer<Void> Function(Pointer<Utf8>);
typedef _SetAclN = Int32 Function(Int32, Pointer<Void>, Int32);
typedef _SetAclD = int Function(int, Pointer<Void>, int);
typedef _FreeAclN = Int32 Function(Pointer<Void>);
typedef _FreeAclD = int Function(Pointer<Void>);

final class _AttrList extends Struct {
  @Uint16()
  external int bitmapCount;
  @Uint16()
  external int reserved;
  @Uint32()
  external int common;
  @Uint32()
  external int volume;
  @Uint32()
  external int directory;
  @Uint32()
  external int file;
  @Uint32()
  external int fork;
}

final class _Timespec extends Struct {
  @Int64()
  external int seconds;
  @Int64()
  external int nanoseconds;
}

bool get _mac => Platform.isMacOS;
int _errno(DynamicLibrary lib) => lib
    .lookupFunction<_ErrnoN, _ErrnoD>(_mac ? '__error' : '__errno_location')()
    .value;
bool _absent(int code) => code == (_mac ? 93 : 61);
bool _unsupported(int code) => const [38, 45, 78, 95].contains(code);
Never _fail(String operation, String path, int code) =>
    throw FileSystemException(operation, path, OSError('OS error $code', code));

T _withDescriptor<T>(String path, T Function(DynamicLibrary, int) action) {
  if (!supportsNativeMetadata) {
    throw UnsupportedError('Native metadata is unavailable on this platform.');
  }
  if (path.isEmpty || path.contains('\u0000')) {
    throw ArgumentError('A path cannot be empty or contain a null character.');
  }
  final kind = FileSystemEntity.typeSync(path, followLinks: false);
  if (kind != FileSystemEntityType.file &&
      kind != FileSystemEntityType.directory) {
    throw FileSystemException(
      'Metadata requires a regular file or directory.',
      path,
    );
  }
  final lib = DynamicLibrary.process();
  final name = path.toNativeUtf8();
  late int fd;
  try {
    // O_RDONLY | O_NOFOLLOW | O_NONBLOCK; directories need no write handle.
    fd = lib.lookupFunction<_OpenN, _OpenD>('open')(
      name,
      _mac ? 0x104 : 0x20800,
      0,
    );
  } finally {
    calloc.free(name);
  }
  if (fd < 0) _fail('Opening metadata failed', path, _errno(lib));
  try {
    return action(lib, fd);
  } finally {
    lib.lookupFunction<_CloseN, _CloseD>('close')(fd);
  }
}

(String, String) _ownership(DynamicLibrary lib, int fd, String path) {
  if (_mac) {
    final attrs = calloc<_AttrList>();
    final buffer = calloc<Uint32>(3);
    try {
      // ATTR_CMN_OWNERID | ATTR_CMN_GRPID. The packed result is length, uid, gid.
      attrs.ref
        ..bitmapCount = 5
        ..common = 0x00018000;
      final result = lib.lookupFunction<_GetattrN, _GetattrD>('fgetattrlist')(
        fd,
        attrs,
        buffer,
        12,
        0,
      );
      if (result != 0) _fail('Reading ownership failed', path, _errno(lib));
      if (buffer[0] != 12) {
        throw FileSystemException('Incomplete ownership metadata.', path);
      }
      return ('${buffer[1]}', '${buffer[2]}');
    } finally {
      calloc.free(attrs);
      calloc.free(buffer);
    }
  }
  // statx has an architecture-independent ABI, unlike libc's struct stat.
  // AT_EMPTY_PATH binds the query to the already-open descriptor.
  final empty = ''.toNativeUtf8();
  final buffer = calloc<Uint8>(256);
  try {
    final result = lib.lookupFunction<_StatxN, _StatxD>('statx')(
      fd,
      empty,
      0x1000,
      0x18,
      buffer,
    );
    if (result != 0) _fail('Reading ownership failed', path, _errno(lib));
    final values = ByteData.sublistView(buffer.asTypedList(256));
    if ((values.getUint32(0, Endian.host) & 0x18) != 0x18) {
      throw FileSystemException('Ownership metadata is unavailable.', path);
    }
    return (
      '${values.getUint32(20, Endian.host)}',
      '${values.getUint32(24, Endian.host)}',
    );
  } finally {
    calloc.free(empty);
    calloc.free(buffer);
  }
}

int _list(DynamicLibrary lib, int fd, Pointer<Uint8> bytes, int size) => _mac
    ? lib.lookupFunction<_ListMacN, _ListMacD>('flistxattr')(fd, bytes, size, 0)
    : lib.lookupFunction<_ListN, _ListD>('flistxattr')(fd, bytes, size);

List<String> _attributeNames(DynamicLibrary lib, int fd, String path) {
  for (var attempt = 0; attempt < 3; attempt++) {
    final length = _list(lib, fd, nullptr, 0);
    if (length < 0) {
      final code = _errno(lib);
      if (_unsupported(code)) return const [];
      _fail('Listing extended attributes failed', path, code);
    }
    if (length == 0) return const [];
    if (length > _maxNames) {
      throw FileSystemException(
        'Extended attribute names exceed 64 KiB.',
        path,
      );
    }
    final data = calloc<Uint8>(length);
    try {
      final count = _list(lib, fd, data, length);
      if (count < 0) {
        if (_errno(lib) == 34) {
          continue; // ERANGE: names changed during reading.
        }
        _fail('Reading extended attribute names failed', path, _errno(lib));
      }
      if (count > length) {
        throw FileSystemException(
          'Invalid extended attribute name length.',
          path,
        );
      }
      final names = utf8.decode(data.asTypedList(count)).split('\u0000');
      return names.where((name) => name.isNotEmpty).toList(growable: false);
    } finally {
      calloc.free(data);
    }
  }
  throw FileSystemException('Extended attributes changed while reading.', path);
}

int _get(
  DynamicLibrary lib,
  int fd,
  Pointer<Utf8> name,
  Pointer<Uint8> data,
  int length,
) => _mac
    ? lib.lookupFunction<_GetMacN, _GetMacD>('fgetxattr')(
        fd,
        name,
        data,
        length,
        0,
        0,
      )
    : lib.lookupFunction<_GetN, _GetD>('fgetxattr')(fd, name, data, length);

Uint8List? _attribute(
  DynamicLibrary lib,
  int fd,
  String path,
  String name, {
  bool optional = false,
}) {
  final nativeName = name.toNativeUtf8();
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      final length = _get(lib, fd, nativeName, nullptr, 0);
      if (length < 0) {
        final code = _errno(lib);
        if (optional && (_absent(code) || _unsupported(code))) return null;
        _fail('Reading extended attribute $name failed', path, code);
      }
      if (length > _maxValue) {
        throw FileSystemException(
          'An extended attribute exceeds 16 MiB.',
          path,
        );
      }
      if (length == 0) return Uint8List(0);
      final data = calloc<Uint8>(length);
      try {
        final count = _get(lib, fd, nativeName, data, length);
        if (count < 0) {
          if (_errno(lib) == 34) continue;
          _fail('Reading extended attribute $name failed', path, _errno(lib));
        }
        if (count > length) {
          throw FileSystemException('Invalid extended attribute length.', path);
        }
        return Uint8List.fromList(data.asTypedList(count));
      } finally {
        calloc.free(data);
      }
    }
  } finally {
    calloc.free(nativeName);
  }
  throw FileSystemException('Extended attribute changed while reading.', path);
}

bool _isAclAttribute(String name) =>
    name == _linuxAccess ||
    name == _linuxDefault ||
    name == 'com.apple.system.Security';

String _readAcl(DynamicLibrary lib, int fd, String path) {
  if (!_mac) {
    final access = _attribute(lib, fd, path, _linuxAccess, optional: true);
    final defaults = _attribute(lib, fd, path, _linuxDefault, optional: true);
    return '$_linuxAclPrefix${jsonEncode({'access': access == null ? null : base64Encode(access), 'default': defaults == null ? null : base64Encode(defaults)})}';
  }
  final acl = lib.lookupFunction<_GetAclN, _GetAclD>('acl_get_fd_np')(
    fd,
    0x100,
  );
  if (acl == nullptr) _fail('Reading ACL failed', path, _errno(lib));
  final release = lib.lookupFunction<_FreeAclN, _FreeAclD>('acl_free');
  final length = calloc<IntPtr>();
  Pointer<Utf8> text = nullptr;
  try {
    text = lib.lookupFunction<_AclTextN, _AclTextD>('acl_to_text')(acl, length);
    if (text == nullptr) _fail('Serializing ACL failed', path, _errno(lib));
    if (length.value < 0 || length.value > _maxValue) {
      throw FileSystemException('ACL exceeds its metadata limit.', path);
    }
    return '$_darwinAclPrefix${text.toDartString(length: length.value).replaceFirst(RegExp(r'\x00$'), '')}';
  } finally {
    if (text != nullptr) release(text.cast());
    release(acl);
    calloc.free(length);
  }
}

TransferMetadata _read(
  String path, {
  required bool ownership,
  required bool extendedAttributes,
  required bool acl,
}) => _withDescriptor(path, (lib, fd) {
  final owners = ownership && supportsNativeOwnership
      ? _ownership(lib, fd, path)
      : null;
  final attributes = <String, Uint8List>{};
  var total = 0;
  if (extendedAttributes && supportsNativeExtendedAttributes) {
    for (final name in _attributeNames(lib, fd, path)) {
      if (_isAclAttribute(name)) continue;
      final bytes = _attribute(lib, fd, path, name)!;
      total += bytes.length;
      if (total > _maxMetadata) {
        throw FileSystemException('Extended attributes exceed 32 MiB.', path);
      }
      attributes[name] = bytes;
    }
  }
  return TransferMetadata(
    owner: owners?.$1,
    group: owners?.$2,
    extendedAttributes: attributes,
    acl: acl && supportsNativeAccessControlLists
        ? _readAcl(lib, fd, path)
        : null,
  );
});

int _numericOwner(String? value, String kind) {
  if (value == null) return 0xffffffff; // fchown: leave this field unchanged.
  final parsed = int.tryParse(value);
  if (!RegExp(r'^[0-9]+$').hasMatch(value) ||
      parsed == null ||
      parsed < 0 ||
      parsed >= 0xffffffff) {
    throw FormatException('$kind must be a numeric POSIX ID.');
  }
  return parsed;
}

void _setAttribute(
  DynamicLibrary lib,
  int fd,
  String path,
  String name,
  Uint8List? value,
) {
  final nativeName = name.toNativeUtf8();
  Pointer<Uint8> bytes = nullptr;
  try {
    int result;
    if (value == null) {
      // Only Linux ACL removal uses this path. Ordinary xattrs are merged;
      // unrelated destination metadata is not removed by preservation.
      result = lib.lookupFunction<_RemoveN, _RemoveD>('fremovexattr')(
        fd,
        nativeName,
      );
      if (result != 0 && (_absent(_errno(lib)) || _unsupported(_errno(lib)))) {
        return;
      }
    } else {
      bytes = calloc<Uint8>(value.isEmpty ? 1 : value.length);
      bytes.asTypedList(value.length).setAll(0, value);
      result = _mac
          ? lib.lookupFunction<_SetMacN, _SetMacD>('fsetxattr')(
              fd,
              nativeName,
              bytes,
              value.length,
              0,
              0,
            )
          : lib.lookupFunction<_SetN, _SetD>('fsetxattr')(
              fd,
              nativeName,
              bytes,
              value.length,
              0,
            );
    }
    if (result != 0) {
      _fail('Setting extended attribute $name failed', path, _errno(lib));
    }
  } finally {
    calloc.free(nativeName);
    if (bytes != nullptr) calloc.free(bytes);
  }
}

Map<String, Uint8List?>? _validate(TransferMetadata metadata) {
  _numericOwner(metadata.owner, 'Owner');
  _numericOwner(metadata.group, 'Group');
  if (metadata.mode != null &&
      (metadata.mode! < 0 || metadata.mode! > 0xffff)) {
    throw const FormatException('Invalid permission bits.');
  }
  var total = 0;
  for (final entry in metadata.extendedAttributes.entries) {
    if (entry.key.isEmpty ||
        entry.key.contains('\u0000') ||
        utf8.encode(entry.key).length > 255 ||
        _isAclAttribute(entry.key)) {
      throw const FormatException('Invalid extended attribute name.');
    }
    total += entry.value.length;
    if (entry.value.length > _maxValue || total > _maxMetadata) {
      throw const FormatException(
        'Extended attributes exceed the metadata limit.',
      );
    }
  }
  final acl = metadata.acl;
  if (acl == null) return null;
  if (acl.length > _maxMetadata || acl.contains('\u0000')) {
    throw const FormatException('Invalid ACL metadata.');
  }
  if (_mac) {
    if (!acl.startsWith(_darwinAclPrefix)) {
      throw const FormatException('This ACL is not a macOS ACL.');
    }
    return null;
  }
  if (!acl.startsWith(_linuxAclPrefix)) {
    throw const FormatException('This ACL is not a Linux POSIX ACL.');
  }
  final parsed = jsonDecode(acl.substring(_linuxAclPrefix.length));
  if (parsed is! Map ||
      parsed.length != 2 ||
      !parsed.containsKey('access') ||
      !parsed.containsKey('default')) {
    throw const FormatException('Invalid Linux ACL metadata.');
  }
  return {
    for (final key in ['access', 'default'])
      key: parsed[key] == null ? null : base64Decode(parsed[key] as String),
  };
}

void _write(String path, TransferMetadata metadata) {
  final linuxAcl = _validate(metadata);
  _withDescriptor(path, (lib, fd) {
    if (metadata.owner != null || metadata.group != null) {
      final result = lib.lookupFunction<_ChownN, _ChownD>('fchown')(
        fd,
        _numericOwner(metadata.owner, 'Owner'),
        _numericOwner(metadata.group, 'Group'),
      );
      if (result != 0) _fail('Setting ownership failed', path, _errno(lib));
    }
    for (final entry in metadata.extendedAttributes.entries) {
      _setAttribute(lib, fd, path, entry.key, entry.value);
    }
    // Ownership can clear set-id bits, so explicitly requested modes follow it.
    if (metadata.mode != null) {
      if (lib.lookupFunction<_ChmodN, _ChmodD>('fchmod')(
            fd,
            metadata.mode! & 0xfff,
          ) !=
          0) {
        _fail('Setting permissions failed', path, _errno(lib));
      }
    }
    if (metadata.acl != null) {
      if (_mac) {
        final text = metadata.acl!
            .substring(_darwinAclPrefix.length)
            .toNativeUtf8();
        Pointer<Void> acl = nullptr;
        try {
          acl = lib.lookupFunction<_AclFromN, _AclFromD>('acl_from_text')(text);
          if (acl == nullptr) _fail('Parsing ACL failed', path, _errno(lib));
          if (lib.lookupFunction<_SetAclN, _SetAclD>('acl_set_fd_np')(
                fd,
                acl,
                0x100,
              ) !=
              0) {
            _fail('Setting ACL failed', path, _errno(lib));
          }
        } finally {
          if (acl != nullptr) {
            lib.lookupFunction<_FreeAclN, _FreeAclD>('acl_free')(acl);
          }
          calloc.free(text);
        }
      } else {
        _setAttribute(lib, fd, path, _linuxAccess, linuxAcl!['access']);
        _setAttribute(lib, fd, path, _linuxDefault, linuxAcl['default']);
      }
    }
    if (metadata.modified != null || metadata.accessed != null) {
      final times = calloc<_Timespec>(2);
      try {
        for (var index = 0; index < 2; index++) {
          final date = index == 0 ? metadata.accessed : metadata.modified;
          if (date == null) {
            times[index].nanoseconds = _mac ? -2 : 1073741822; // UTIME_OMIT
          } else {
            final micros = date.toUtc().microsecondsSinceEpoch;
            final remainder = micros % 1000000;
            final seconds = (micros - remainder) ~/ 1000000;
            times[index]
              ..seconds = seconds
              ..nanoseconds = remainder * 1000;
          }
        }
        if (lib.lookupFunction<_TimesN, _TimesD>('futimens')(fd, times) != 0) {
          _fail('Setting timestamps failed', path, _errno(lib));
        }
      } finally {
        calloc.free(times);
      }
    }
  });
}
