import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

import 'storage_transfer_contract.dart';

// Native metadata only: no shell commands, account-name guessing, privilege
// enabling, or path-based write after the handle has been checked.
// Win32 contracts:
// https://learn.microsoft.com/windows/win32/api/aclapi/nf-aclapi-setsecurityinfo
// https://learn.microsoft.com/windows/win32/api/winbase/ns-winbase-file_basic_info
// https://learn.microsoft.com/windows/win32/api/fileapi/nf-fileapi-createfilew
// https://learn.microsoft.com/windows-hardware/drivers/ddi/ntifs/nf-ntifs-ntsetsecurityobject
const _readControl = 0x00020000;
const _writeDac = 0x00040000;
const _writeOwner = 0x00080000;
const _readAttributes = 0x80;
const _writeAttributes = 0x100;
const _ownerInformation = 1;
const _groupInformation = 2;
const _daclInformation = 4;
const _protectedDaclInformation = 0x80000000;
const _unprotectedDaclInformation = 0x20000000;
const _daclProtected = 0x1000;
const _saclPresent = 0x10;
const _reparsePoint = 0x400;
const _normalAttribute = 0x80;
const _editableAttributes = 0x27;
const _aclPrefix = 'windows-sddl-v1:';
const _epochMicroseconds = 11644473600000000;

bool get supportsWindowsNativeMetadata =>
    Platform.isWindows && sizeOf<IntPtr>() == 8;

final class _BasicInfo extends Struct {
  @Int64()
  external int created;
  @Int64()
  external int accessed;
  @Int64()
  external int modified;
  @Int64()
  external int changed;
  @Uint32()
  external int attributes;
}

typedef _CreateN = IntPtr Function(
  Pointer<Utf16>,
  Uint32,
  Uint32,
  Pointer<Void>,
  Uint32,
  Uint32,
  IntPtr,
);
typedef _CreateD = int Function(
  Pointer<Utf16>,
  int,
  int,
  Pointer<Void>,
  int,
  int,
  int,
);
typedef _CloseN = Int32 Function(IntPtr);
typedef _CloseD = int Function(int);
typedef _LastErrorN = Uint32 Function();
typedef _LastErrorD = int Function();
typedef _FileTypeN = Uint32 Function(IntPtr);
typedef _FileTypeD = int Function(int);
typedef _BasicN = Int32 Function(IntPtr, Int32, Pointer<Void>, Uint32);
typedef _BasicD = int Function(int, int, Pointer<Void>, int);
typedef _FreeN = Pointer<Void> Function(Pointer<Void>);
typedef _FreeD = Pointer<Void> Function(Pointer<Void>);
typedef _GetSecurityN = Uint32 Function(
  IntPtr,
  Int32,
  Uint32,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
);
typedef _GetSecurityD = int Function(
  int,
  int,
  int,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
  Pointer<Pointer<Void>>,
);
typedef _SetSecurityN = Uint32 Function(
  IntPtr,
  Int32,
  Uint32,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _SetSecurityD = int Function(
  int,
  int,
  int,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
  Pointer<Void>,
);
typedef _SetObjectSecurityN = Int32 Function(IntPtr, Uint32, Pointer<Void>);
typedef _SetObjectSecurityD = int Function(int, int, Pointer<Void>);
typedef _StatusErrorN = Uint32 Function(Int32);
typedef _StatusErrorD = int Function(int);
typedef _SidTextN = Int32 Function(Pointer<Void>, Pointer<Pointer<Utf16>>);
typedef _SidTextD = int Function(Pointer<Void>, Pointer<Pointer<Utf16>>);
typedef _TextSidN = Int32 Function(Pointer<Utf16>, Pointer<Pointer<Void>>);
typedef _TextSidD = int Function(Pointer<Utf16>, Pointer<Pointer<Void>>);
typedef _DescriptorTextN = Int32 Function(
  Pointer<Void>,
  Uint32,
  Uint32,
  Pointer<Pointer<Utf16>>,
  Pointer<Uint32>,
);
typedef _DescriptorTextD = int Function(
  Pointer<Void>,
  int,
  int,
  Pointer<Pointer<Utf16>>,
  Pointer<Uint32>,
);
typedef _TextDescriptorN = Int32 Function(
  Pointer<Utf16>,
  Uint32,
  Pointer<Pointer<Void>>,
  Pointer<Uint32>,
);
typedef _TextDescriptorD = int Function(
  Pointer<Utf16>,
  int,
  Pointer<Pointer<Void>>,
  Pointer<Uint32>,
);
typedef _DaclN = Int32 Function(
  Pointer<Void>,
  Pointer<Int32>,
  Pointer<Pointer<Void>>,
  Pointer<Int32>,
);
typedef _DaclD = int Function(
  Pointer<Void>,
  Pointer<Int32>,
  Pointer<Pointer<Void>>,
  Pointer<Int32>,
);
typedef _ControlN = Int32 Function(
  Pointer<Void>,
  Pointer<Uint16>,
  Pointer<Uint32>,
);
typedef _ControlD = int Function(
  Pointer<Void>,
  Pointer<Uint16>,
  Pointer<Uint32>,
);
typedef _DescriptorSidN = Int32 Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Pointer<Int32>,
);
typedef _DescriptorSidD = int Function(
  Pointer<Void>,
  Pointer<Pointer<Void>>,
  Pointer<Int32>,
);

class _WindowsApi {
  _WindowsApi()
    : kernel = DynamicLibrary.open('kernel32.dll'),
      security = DynamicLibrary.open('advapi32.dll'),
      native = DynamicLibrary.open('ntdll.dll') {
    _getLastError = kernel.lookupFunction<_LastErrorN, _LastErrorD>(
      'GetLastError',
    );
  }

  final DynamicLibrary kernel;
  final DynamicLibrary security;
  final DynamicLibrary native;
  late final _LastErrorD _getLastError;

  int get lastError => _getLastError();

  Never fail(String operation, String path, [int? code]) =>
      throw FileSystemException(
        operation,
        path,
        OSError('Windows metadata operation failed', code ?? lastError),
      );

  void free(Pointer pointer) {
    if (pointer != nullptr) {
      kernel.lookupFunction<_FreeN, _FreeD>('LocalFree')(pointer.cast());
    }
  }

  T withHandle<T>(String path, int access, T Function(int, _BasicInfo) action) {
    if (path.isEmpty || path.contains('\u0000')) {
      throw ArgumentError.value(path, 'path', 'A file path is required.');
    }
    final absolute = p.windows.normalize(File(path).absolute.path);
    final extended =
        absolute.startsWith(r'\\?\') || absolute.startsWith(r'\\.\')
        ? absolute
        : absolute.startsWith(r'\\')
        ? r'\\?\UNC\' + absolute.substring(2)
        : r'\\?\' + absolute;
    final native = extended.toNativeUtf16();
    final handle = kernel.lookupFunction<_CreateN, _CreateD>('CreateFileW')(
      native,
      access | _readAttributes,
      7, // FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE.
      nullptr,
      3, // OPEN_EXISTING never creates or truncates an object.
      0x02200000, // BACKUP_SEMANTICS | OPEN_REPARSE_POINT.
      0,
    );
    final openError = handle == -1 || handle == 0 ? lastError : 0;
    calloc.free(native);
    if (handle == -1 || handle == 0) {
      fail('Cannot open metadata handle', path, openError);
    }
    final basic = calloc<_BasicInfo>();
    try {
      if (kernel.lookupFunction<_FileTypeN, _FileTypeD>('GetFileType')(
            handle,
          ) !=
          1) {
        throw UnsupportedError('Metadata requires a disk file or directory.');
      }
      if (kernel.lookupFunction<_BasicN, _BasicD>(
            'GetFileInformationByHandleEx',
          )(handle, 0, basic.cast(), sizeOf<_BasicInfo>()) ==
          0) {
        fail('Cannot read file attributes', path);
      }
      if (basic.ref.attributes & _reparsePoint != 0) {
        throw UnsupportedError('Metadata on reparse points is not changed.');
      }
      return action(handle, basic.ref);
    } finally {
      calloc.free(basic);
      kernel.lookupFunction<_CloseN, _CloseD>('CloseHandle')(handle);
    }
  }

  String sidText(Pointer<Void> sid, String path) {
    if (sid == nullptr) fail('No owner or group SID was returned', path, 1337);
    final text = calloc<Pointer<Utf16>>();
    try {
      if (security.lookupFunction<_SidTextN, _SidTextD>(
            'ConvertSidToStringSidW',
          )(sid, text) ==
          0) {
        fail('Cannot encode owner or group SID', path);
      }
      return text.value.toDartString();
    } finally {
      free(text.value);
      calloc.free(text);
    }
  }

  int descriptorControl(Pointer<Void> descriptor, String path) {
    final control = calloc<Uint16>();
    final revision = calloc<Uint32>();
    try {
      if (security.lookupFunction<_ControlN, _ControlD>(
            'GetSecurityDescriptorControl',
          )(descriptor, control, revision) ==
          0) {
        fail('Cannot inspect security descriptor', path);
      }
      return control.value;
    } finally {
      calloc.free(control);
      calloc.free(revision);
    }
  }

  ({Pointer<Void> pointer, bool present}) descriptorDacl(
    Pointer<Void> descriptor,
    String path,
  ) {
    final present = calloc<Int32>();
    final dacl = calloc<Pointer<Void>>();
    final defaulted = calloc<Int32>();
    try {
      if (security.lookupFunction<_DaclN, _DaclD>('GetSecurityDescriptorDacl')(
            descriptor,
            present,
            dacl,
            defaulted,
          ) ==
          0) {
        fail('Cannot inspect discretionary ACL', path);
      }
      return (pointer: dacl.value, present: present.value != 0);
    } finally {
      calloc.free(present);
      calloc.free(dacl);
      calloc.free(defaulted);
    }
  }

  String daclText(Pointer<Void> descriptor, String path) {
    final dacl = descriptorDacl(descriptor, path);
    if (!dacl.present) {
      throw UnsupportedError('The file has no preservable discretionary ACL.');
    }
    if (dacl.pointer == nullptr) {
      // Null and empty ACLs have opposite meanings. The normal SDDL encoder
      // can reject a present null DACL; encode its explicit Windows 7+ token.
      final protected =
          descriptorControl(descriptor, path) & _daclProtected != 0;
      return '$_aclPrefix'
          'D:${protected ? 'P' : ''}NO_ACCESS_CONTROL';
    }
    final text = calloc<Pointer<Utf16>>();
    try {
      if (security.lookupFunction<_DescriptorTextN, _DescriptorTextD>(
            'ConvertSecurityDescriptorToStringSecurityDescriptorW',
          )(descriptor, 1, _daclInformation, text, nullptr) ==
          0) {
        fail('Cannot encode discretionary ACL', path);
      }
      return '$_aclPrefix${text.value.toDartString()}';
    } finally {
      free(text.value);
      calloc.free(text);
    }
  }
}

TransferMetadata readWindowsNativeMetadata(
  String path, {
  bool ownership = true,
  bool acl = true,
  bool created = true,
  bool windowsAttributes = true,
}) {
  if (!supportsWindowsNativeMetadata) {
    throw UnsupportedError('Windows native metadata is unavailable.');
  }
  final api = _WindowsApi();
  return api.withHandle(path, ownership || acl ? _readControl : 0, (
    handle,
    basic,
  ) {
    String? owner;
    String? group;
    String? dacl;
    if (ownership || acl) {
      final ownerPointer = calloc<Pointer<Void>>();
      final groupPointer = calloc<Pointer<Void>>();
      final descriptor = calloc<Pointer<Void>>();
      try {
        final code =
            api.security.lookupFunction<_GetSecurityN, _GetSecurityD>(
              'GetSecurityInfo',
            )(
              handle,
              1,
              (ownership ? _ownerInformation | _groupInformation : 0) |
                  (acl ? _daclInformation : 0),
              ownership ? ownerPointer : nullptr,
              ownership ? groupPointer : nullptr,
              nullptr,
              nullptr,
              descriptor,
            );
        if (code != 0) api.fail('Cannot read file security', path, code);
        if (ownership) {
          owner = api.sidText(ownerPointer.value, path);
          group = api.sidText(groupPointer.value, path);
        }
        if (acl) dacl = api.daclText(descriptor.value, path);
      } finally {
        api.free(descriptor.value);
        calloc.free(descriptor);
        calloc.free(ownerPointer);
        calloc.free(groupPointer);
      }
    }
    return TransferMetadata(
      owner: owner,
      group: group,
      acl: dacl,
      created: created ? _fromFileTime(basic.created) : null,
      windowsAttributes: windowsAttributes ? basic.attributes : null,
    );
  });
}

DateTime _fromFileTime(int value) => DateTime.fromMicrosecondsSinceEpoch(
  value ~/ 10 - _epochMicroseconds,
  isUtc: true,
);

int _toFileTime(DateTime? time, String field) {
  if (time == null) return 0; // Leave an unselected timestamp unchanged.
  final ticks =
      (BigInt.from(time.microsecondsSinceEpoch) +
          BigInt.from(_epochMicroseconds)) *
      BigInt.from(10);
  // Zero is the API's "leave unchanged" sentinel, not an editable instant.
  if (ticks <= BigInt.zero || ticks > BigInt.parse('9223372036854775807')) {
    throw ArgumentError.value(
      time,
      field,
      'Outside editable Windows timestamp range.',
    );
  }
  return ticks.toInt();
}

Pointer<Void> _parseSid(_WindowsApi api, String? value, String path) {
  if (value == null) return nullptr;
  if (value.length > 256 || !RegExp(r'^S-\d+(?:-\d+)+$').hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'SID',
      'Expected a Windows SID, such as S-1-5-21-…',
    );
  }
  final text = value.toNativeUtf16();
  final sid = calloc<Pointer<Void>>();
  try {
    if (api.security.lookupFunction<_TextSidN, _TextSidD>(
          'ConvertStringSidToSidW',
        )(text, sid) ==
        0) {
      api.fail('Invalid Windows owner or group SID', path);
    }
    return sid.value;
  } finally {
    calloc.free(text);
    calloc.free(sid);
  }
}

Pointer<Void> _parseAcl(_WindowsApi api, String? value, String path) {
  if (value == null) return nullptr;
  if (!value.startsWith(_aclPrefix) ||
      value.length > 1024 * 1024 ||
      value.contains('\u0000')) {
    throw const FormatException(
      'Expected a Windows discretionary ACL descriptor.',
    );
  }
  final sddl = value.substring(_aclPrefix.length);
  if (!sddl.startsWith('D:')) {
    throw const FormatException(
      'A Windows ACL descriptor must contain a DACL.',
    );
  }
  final text = sddl.toNativeUtf16();
  final descriptor = calloc<Pointer<Void>>();
  var success = false;
  try {
    if (api.security.lookupFunction<_TextDescriptorN, _TextDescriptorD>(
          'ConvertStringSecurityDescriptorToSecurityDescriptorW',
        )(text, 1, descriptor, nullptr) ==
        0) {
      api.fail('Invalid Windows discretionary ACL', path);
    }
    final control = api.descriptorControl(descriptor.value, path);
    final sid = calloc<Pointer<Void>>();
    final defaulted = calloc<Int32>();
    try {
      for (final function in [
        'GetSecurityDescriptorOwner',
        'GetSecurityDescriptorGroup',
      ]) {
        if (api.security.lookupFunction<_DescriptorSidN, _DescriptorSidD>(
              function,
            )(descriptor.value, sid, defaulted) ==
            0) {
          api.fail('Invalid Windows security descriptor', path);
        }
        if (sid.value != nullptr) {
          throw const FormatException(
            'The ACL descriptor must not include ownership.',
          );
        }
      }
    } finally {
      calloc.free(sid);
      calloc.free(defaulted);
    }
    if (control & _saclPresent != 0 ||
        !api.descriptorDacl(descriptor.value, path).present) {
      throw const FormatException('Only a discretionary ACL can be preserved.');
    }
    success = true;
    return descriptor.value;
  } finally {
    if (!success) api.free(descriptor.value);
    calloc.free(text);
    calloc.free(descriptor);
  }
}

void writeWindowsNativeMetadata(String path, TransferMetadata metadata) {
  if (!supportsWindowsNativeMetadata) {
    throw UnsupportedError('Windows native metadata is unavailable.');
  }
  if (metadata.mode != null || metadata.extendedAttributes.isNotEmpty) {
    throw UnsupportedError(
      'POSIX permissions and extended attributes are unavailable on Windows.',
    );
  }
  final attributes = metadata.windowsAttributes;
  final mask = metadata.windowsAttributesMask;
  if (mask < 0 ||
      mask & ~_editableAttributes != 0 ||
      (attributes != null && (attributes < 0 || attributes > 0xffffffff))) {
    throw ArgumentError(
      'Only read-only, hidden, system, and archive attribute bits can be changed.',
    );
  }
  final created = _toFileTime(metadata.created, 'created');
  final modified = _toFileTime(metadata.modified, 'modified');
  final accessed = _toFileTime(metadata.accessed, 'accessed');
  final api = _WindowsApi();
  Pointer<Void> owner = nullptr;
  Pointer<Void> group = nullptr;
  Pointer<Void> descriptor = nullptr;
  try {
    // Parse every requested value before opening or changing the destination.
    owner = _parseSid(api, metadata.owner, path);
    group = _parseSid(api, metadata.group, path);
    descriptor = _parseAcl(api, metadata.acl, path);
    final writesBasic =
        metadata.created != null ||
        metadata.modified != null ||
        metadata.accessed != null ||
        attributes != null;
    var access = writesBasic ? _writeAttributes : 0;
    if (owner != nullptr || group != nullptr) access |= _writeOwner;
    if (descriptor != nullptr) {
      access |= _writeDac;
    }
    api.withHandle(path, access, (handle, basic) {
      final securityFlags =
          (owner != nullptr ? _ownerInformation : 0) |
          (group != nullptr ? _groupInformation : 0);
      if (securityFlags != 0) {
        final code = api.security.lookupFunction<_SetSecurityN, _SetSecurityD>(
          'SetSecurityInfo',
        )(handle, 1, securityFlags, owner, group, nullptr, nullptr);
        if (code != 0) api.fail('Cannot set file security', path, code);
      }
      if (descriptor != nullptr) {
        // SetSecurityInfo applies directory inheritance to existing children,
        // even with MAXIMUM_ALLOWED (which can protect their inherited ACEs).
        // The documented user-mode native setter changes this checked object
        // only. No recursive ACL rewrite is part of a metadata patch.
        final protected =
            api.descriptorControl(descriptor, path) & _daclProtected != 0;
        final status =
            api.native.lookupFunction<_SetObjectSecurityN, _SetObjectSecurityD>(
              'NtSetSecurityObject',
            )(
              handle,
              _daclInformation |
                  (protected
                      ? _protectedDaclInformation
                      : _unprotectedDaclInformation),
              descriptor,
            );
        if (status < 0) {
          final code = api.native.lookupFunction<_StatusErrorN, _StatusErrorD>(
            'RtlNtStatusToDosError',
          )(status);
          api.fail('Cannot set discretionary ACL', path, code);
        }
      }
      if (writesBasic) {
        final update = calloc<_BasicInfo>();
        try {
          update.ref
            ..created = created
            ..modified = modified
            ..accessed = accessed;
          if (attributes != null) {
            var merged = (basic.attributes & ~mask) | (attributes & mask);
            // NORMAL is an exclusive flag. Zero would mean "do not change".
            if (merged & ~_normalAttribute != 0) merged &= ~_normalAttribute;
            if (merged == 0) merged = _normalAttribute;
            update.ref.attributes = merged;
          }
          if (api.kernel.lookupFunction<_BasicN, _BasicD>(
                'SetFileInformationByHandle',
              )(handle, 0, update.cast(), sizeOf<_BasicInfo>()) ==
              0) {
            api.fail('Cannot set file attributes or timestamps', path);
          }
        } finally {
          calloc.free(update);
        }
      }
    });
  } finally {
    api.free(owner);
    api.free(group);
    api.free(descriptor);
  }
}
