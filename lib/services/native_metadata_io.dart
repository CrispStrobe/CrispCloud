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
typedef _ChmodMacN = Int32 Function(Int32, Uint16);
typedef _ChmodD = int Function(int, int);
typedef _ChmodPathN = Int32 Function(Pointer<Utf8>, Uint32);
typedef _ChmodPathD = int Function(Pointer<Utf8>, int);
typedef _ChownPathN = Int32 Function(Pointer<Utf8>, Uint32, Uint32);
typedef _ChownPathD = int Function(Pointer<Utf8>, int, int);
typedef _TimesN = Int32 Function(Int32, Pointer<_Timespec>);
typedef _TimesD = int Function(int, Pointer<_Timespec>);
typedef _TimesPathN = Int32 Function(
  Int32,
  Pointer<Utf8>,
  Pointer<_Timespec>,
  Int32,
);
typedef _TimesPathD = int Function(int, Pointer<Utf8>, Pointer<_Timespec>, int);
typedef _ListN = IntPtr Function(Int32, Pointer<Uint8>, Size);
typedef _ListD = int Function(int, Pointer<Uint8>, int);
typedef _ListPathN = IntPtr Function(Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _ListPathD = int Function(Pointer<Utf8>, Pointer<Uint8>, int);
typedef _ListMacN = IntPtr Function(Int32, Pointer<Uint8>, Size, Int32);
typedef _ListMacD = int Function(int, Pointer<Uint8>, int, int);
typedef _GetN = IntPtr Function(Int32, Pointer<Utf8>, Pointer<Uint8>, Size);
typedef _GetD = int Function(int, Pointer<Utf8>, Pointer<Uint8>, int);
typedef _GetPathN = IntPtr Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Size,
);
typedef _GetPathD = int Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
);
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
typedef _SetPathN = Int32 Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  Size,
  Int32,
);
typedef _SetPathD = int Function(
  Pointer<Utf8>,
  Pointer<Utf8>,
  Pointer<Uint8>,
  int,
  int,
);
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
typedef _RemovePathN = Int32 Function(Pointer<Utf8>, Pointer<Utf8>);
typedef _RemovePathD = int Function(Pointer<Utf8>, Pointer<Utf8>);
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
bool _unsupported(int code) =>
    (_mac ? const [45, 78] : const [38, 95]).contains(code);
Never _fail(String operation, String path, int code) =>
    throw FileSystemException(operation, path, OSError('OS error $code', code));

T _withDescriptor<T>(
  String path,
  T Function(DynamicLibrary, int, String?) action,
) {
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
  final pathOnly = !_mac && lib.providesSymbol('statx');
  final name = path.toNativeUtf8();
  late int fd;
  try {
    // Linux O_PATH does not require read permission on the object's data.
    // statx verifies its actual type before /proc/self/fd operations below.
    // O_NOFOLLOW | O_CLOEXEC applies to every descriptor. Older libc versions
    // without statx retain the read-handle path rather than weakening checks.
    fd = lib.lookupFunction<_OpenN, _OpenD>('open')(
      name,
      _mac
          ? 0x1000104
          : pathOnly
          ? 0x2a0000
          : 0xa0800,
      0,
    );
  } finally {
    calloc.free(name);
  }
  if (fd < 0) _fail('Opening metadata failed', path, _errno(lib));
  try {
    if (pathOnly) {
      final mode = _statxMetadata(lib, fd, path, 1).getUint16(28, Endian.host);
      if ((mode & 0xf000) != 0x8000 && (mode & 0xf000) != 0x4000) {
        throw FileSystemException(
          'Metadata requires a regular file or directory.',
          path,
        );
      }
    } else if (_mac && lib.providesSymbol('fgetattrlist')) {
      final attrs = calloc<_AttrList>();
      final buffer = calloc<Uint32>(2);
      try {
        attrs.ref
          ..bitmapCount = 5
          ..common = 8; // ATTR_CMN_OBJTYPE: vtype_t (VREG=1, VDIR=2).
        if (lib.lookupFunction<_GetattrN, _GetattrD>('fgetattrlist')(
              fd,
              attrs,
              buffer,
              8,
              0,
            ) !=
            0) {
          _fail('Reading descriptor type failed', path, _errno(lib));
        }
        if (buffer[0] != 8 || (buffer[1] != 1 && buffer[1] != 2)) {
          throw FileSystemException(
            'Metadata requires a regular file or directory.',
            path,
          );
        }
      } finally {
        calloc.free(attrs);
        calloc.free(buffer);
      }
    }
    // Never fall back to the original pathname if procfs is unavailable: it
    // could have been replaced since open. The descriptor keeps this inode
    // stable even when its original pathname is renamed or unlinked.
    return action(lib, fd, pathOnly ? '/proc/self/fd/$fd' : null);
  } finally {
    lib.lookupFunction<_CloseN, _CloseD>('close')(fd);
  }
}

T _withPath<T>(String path, T Function(Pointer<Utf8>) action) {
  final name = path.toNativeUtf8();
  try {
    return action(name);
  } finally {
    calloc.free(name);
  }
}

ByteData _statxMetadata(DynamicLibrary lib, int fd, String path, int mask) {
  final empty = ''.toNativeUtf8();
  final buffer = calloc<Uint8>(256);
  try {
    if (lib.lookupFunction<_StatxN, _StatxD>('statx')(
          fd,
          empty,
          0x1100,
          mask,
          buffer,
        ) !=
        0) {
      _fail('Reading descriptor metadata failed', path, _errno(lib));
    }
    final values = ByteData.sublistView(
      Uint8List.fromList(buffer.asTypedList(256)),
    );
    if ((values.getUint32(0, Endian.host) & mask) != mask) {
      throw FileSystemException('Descriptor metadata is unavailable.', path);
    }
    return values;
  } finally {
    calloc.free(empty);
    calloc.free(buffer);
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
  final values = _statxMetadata(lib, fd, path, 0x18);
  return (
    '${values.getUint32(20, Endian.host)}',
    '${values.getUint32(24, Endian.host)}',
  );
}

int _list(
  DynamicLibrary lib,
  int fd,
  Pointer<Uint8> bytes,
  int size,
  String? descriptorPath,
) => descriptorPath != null
    ? _withPath(
        descriptorPath,
        (path) => lib.lookupFunction<_ListPathN, _ListPathD>('listxattr')(
          path,
          bytes,
          size,
        ),
      )
    : _mac
    ? lib.lookupFunction<_ListMacN, _ListMacD>('flistxattr')(fd, bytes, size, 0)
    : lib.lookupFunction<_ListN, _ListD>('flistxattr')(fd, bytes, size);

List<String> _attributeNames(
  DynamicLibrary lib,
  int fd,
  String path,
  String? descriptorPath,
) {
  for (var attempt = 0; attempt < 3; attempt++) {
    final length = _list(lib, fd, nullptr, 0, descriptorPath);
    if (length < 0) {
      final code = _errno(lib);
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
      final count = _list(lib, fd, data, length, descriptorPath);
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
  String? descriptorPath,
) => descriptorPath != null
    ? _withPath(
        descriptorPath,
        (path) => lib.lookupFunction<_GetPathN, _GetPathD>('getxattr')(
          path,
          name,
          data,
          length,
        ),
      )
    : _mac
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
  String? descriptorPath,
}) {
  final nativeName = name.toNativeUtf8();
  try {
    for (var attempt = 0; attempt < 3; attempt++) {
      final length = _get(lib, fd, nativeName, nullptr, 0, descriptorPath);
      if (length < 0) {
        final code = _errno(lib);
        if (optional && _absent(code)) return null;
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
        final count = _get(lib, fd, nativeName, data, length, descriptorPath);
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

String? _readAcl(
  DynamicLibrary lib,
  int fd,
  String path,
  String? descriptorPath,
) {
  try {
    return _readSupportedAcl(lib, fd, path, descriptorPath);
  } on FileSystemException catch (error) {
    if (_unsupported(error.osError?.errorCode ?? -1)) return null;
    rethrow;
  }
}

String _readSupportedAcl(
  DynamicLibrary lib,
  int fd,
  String path,
  String? descriptorPath,
) {
  if (!_mac) {
    final access = _attribute(
      lib,
      fd,
      path,
      _linuxAccess,
      optional: true,
      descriptorPath: descriptorPath,
    );
    final defaults = _attribute(
      lib,
      fd,
      path,
      _linuxDefault,
      optional: true,
      descriptorPath: descriptorPath,
    );
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
}) => _withDescriptor(path, (lib, fd, descriptorPath) {
  final owners = ownership && supportsNativeOwnership
      ? _ownership(lib, fd, path)
      : null;
  final attributes = <String, Uint8List>{};
  var total = 0;
  if (extendedAttributes && supportsNativeExtendedAttributes) {
    for (final name in _attributeNames(lib, fd, path, descriptorPath)) {
      if (_isAclAttribute(name)) continue;
      final bytes = _attribute(
        lib,
        fd,
        path,
        name,
        descriptorPath: descriptorPath,
      )!;
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
        ? _readAcl(lib, fd, path, descriptorPath)
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
  Uint8List? value, {
  String? descriptorPath,
}) {
  final nativeName = name.toNativeUtf8();
  Pointer<Uint8> bytes = nullptr;
  try {
    int result;
    if (value == null) {
      // Only Linux ACL removal uses this path. Ordinary xattrs are merged;
      // unrelated destination metadata is not removed by preservation.
      result = descriptorPath != null
          ? _withPath(
              descriptorPath,
              (descriptor) => lib.lookupFunction<_RemovePathN, _RemovePathD>(
                'removexattr',
              )(descriptor, nativeName),
            )
          : lib.lookupFunction<_RemoveN, _RemoveD>('fremovexattr')(
              fd,
              nativeName,
            );
      if (result != 0 && _absent(_errno(lib))) {
        return;
      }
    } else {
      bytes = calloc<Uint8>(value.isEmpty ? 1 : value.length);
      bytes.asTypedList(value.length).setAll(0, value);
      result = descriptorPath != null
          ? _withPath(
              descriptorPath,
              (descriptor) => lib.lookupFunction<_SetPathN, _SetPathD>(
                'setxattr',
              )(descriptor, nativeName, bytes, value.length, 0),
            )
          : _mac
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
  if (parsed.values.any((value) => value != null && value is! String)) {
    throw const FormatException('Invalid Linux ACL value.');
  }
  final values = {
    for (final key in ['access', 'default'])
      key: parsed[key] == null ? null : base64Decode(parsed[key] as String),
  };
  for (final value in values.values) {
    if (value != null) _validateLinuxAcl(value);
  }
  return values;
}

void _validateLinuxAcl(Uint8List value) {
  if (value.length < 4 ||
      value.length > _maxValue ||
      (value.length - 4) % 8 != 0) {
    throw const FormatException('Invalid Linux ACL entry length.');
  }
  final data = ByteData.sublistView(value);
  if (data.getUint32(0, Endian.little) != 2) {
    throw const FormatException('Unsupported Linux ACL version.');
  }
  if (value.length == 4) return; // The kernel accepts an empty ACL as removal.
  final required = <int>{1, 4, 32};
  final singleton = <int>{};
  var previousTag = 0;
  var named = false;
  for (var offset = 4; offset < value.length; offset += 8) {
    final tag = data.getUint16(offset, Endian.little);
    final permissions = data.getUint16(offset + 2, Endian.little);
    final id = data.getUint32(offset + 4, Endian.little);
    if (!const [1, 2, 4, 8, 16, 32].contains(tag) ||
        permissions > 7 ||
        tag < previousTag) {
      throw const FormatException('Invalid Linux ACL entry.');
    }
    if (tag == 2 || tag == 8) {
      named = true;
      if (id == 0xffffffff) {
        throw const FormatException('Invalid Linux ACL identity.');
      }
    } else {
      if (id != 0xffffffff || !singleton.add(tag)) {
        throw const FormatException('Invalid Linux ACL base entry.');
      }
      required.remove(tag);
    }
    previousTag = tag;
  }
  if (required.isNotEmpty || (named && !singleton.contains(16))) {
    throw const FormatException('Linux ACL is missing required entries.');
  }
}

void _write(String path, TransferMetadata metadata) {
  final linuxAcl = _validate(metadata);
  final process = DynamicLibrary.process();
  Pointer<Void> darwinAcl = nullptr;
  if (_mac && metadata.acl != null) {
    darwinAcl = _withPath(
      metadata.acl!.substring(_darwinAclPrefix.length),
      (text) =>
          process.lookupFunction<_AclFromN, _AclFromD>('acl_from_text')(text),
    );
    if (darwinAcl == nullptr) {
      throw const FormatException('Invalid macOS ACL metadata.');
    }
    if (process.lookupFunction<_FreeAclN, _FreeAclD>('acl_valid')(darwinAcl) !=
        0) {
      process.lookupFunction<_FreeAclN, _FreeAclD>('acl_free')(darwinAcl);
      throw const FormatException('Invalid macOS ACL metadata.');
    }
  }
  try {
    _withDescriptor(path, (lib, fd, descriptorPath) {
      if (metadata.owner != null || metadata.group != null) {
        final owner = _numericOwner(metadata.owner, 'Owner');
        final group = _numericOwner(metadata.group, 'Group');
        final result = descriptorPath != null
            ? _withPath(
                descriptorPath,
                (descriptor) => lib.lookupFunction<_ChownPathN, _ChownPathD>(
                  'chown',
                )(descriptor, owner, group),
              )
            : lib.lookupFunction<_ChownN, _ChownD>('fchown')(fd, owner, group);
        if (result != 0) _fail('Setting ownership failed', path, _errno(lib));
      }
      for (final entry in metadata.extendedAttributes.entries) {
        _setAttribute(
          lib,
          fd,
          path,
          entry.key,
          entry.value,
          descriptorPath: descriptorPath,
        );
      }
      // Ownership can clear set-id bits, so explicitly requested modes follow it.
      if (metadata.mode != null) {
        final mode = metadata.mode! & 0xfff;
        final result = descriptorPath != null
            ? _withPath(
                descriptorPath,
                (descriptor) => lib.lookupFunction<_ChmodPathN, _ChmodPathD>(
                  'chmod',
                )(descriptor, mode),
              )
            : _mac
            ? lib.lookupFunction<_ChmodMacN, _ChmodD>('fchmod')(fd, mode)
            : lib.lookupFunction<_ChmodN, _ChmodD>('fchmod')(fd, mode);
        if (result != 0) {
          _fail('Setting permissions failed', path, _errno(lib));
        }
      }
      if (metadata.acl != null) {
        if (_mac) {
          if (lib.lookupFunction<_SetAclN, _SetAclD>('acl_set_fd_np')(
                fd,
                darwinAcl,
                0x100,
              ) !=
              0) {
            _fail('Setting ACL failed', path, _errno(lib));
          }
        } else {
          _setAttribute(
            lib,
            fd,
            path,
            _linuxAccess,
            linuxAcl!['access'],
            descriptorPath: descriptorPath,
          );
          _setAttribute(
            lib,
            fd,
            path,
            _linuxDefault,
            linuxAcl['default'],
            descriptorPath: descriptorPath,
          );
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
          final result = descriptorPath != null
              ? _withPath(
                  descriptorPath,
                  (descriptor) => lib.lookupFunction<_TimesPathN, _TimesPathD>(
                    'utimensat',
                  )(-100, descriptor, times, 0),
                )
              : lib.lookupFunction<_TimesN, _TimesD>('futimens')(fd, times);
          if (result != 0) {
            _fail('Setting timestamps failed', path, _errno(lib));
          }
        } finally {
          calloc.free(times);
        }
      }
    });
  } finally {
    if (darwinAcl != nullptr) {
      process.lookupFunction<_FreeAclN, _FreeAclD>('acl_free')(darwinAcl);
    }
  }
}
