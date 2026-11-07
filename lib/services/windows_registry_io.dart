import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Writes a REG_SZ value under HKCU without running `reg.exe`.
bool registrySetString(String subKey, String? valueName, String value) {
  if (!Platform.isWindows) return false;
  final key = calloc<IntPtr>();
  final nativeSubKey = subKey.toNativeUtf16();
  Pointer<Utf16>? nativeValueName;
  Pointer<Utf16>? nativeData;
  try {
    final create = RegCreateKeyEx(
      HKEY_CURRENT_USER,
      nativeSubKey,
      0,
      nullptr.cast<Utf16>(),
      0,
      KEY_WRITE,
      nullptr.cast<SECURITY_ATTRIBUTES>(),
      key,
      nullptr.cast<Uint32>(),
    );
    if (create != 0) return false;

    nativeValueName = valueName?.toNativeUtf16();
    nativeData = value.toNativeUtf16();
    final set = RegSetValueEx(
      key.value,
      nativeValueName ?? nullptr.cast<Utf16>(),
      0,
      REG_SZ,
      nativeData.cast<Uint8>(),
      (value.length + 1) * 2,
    );
    return set == 0;
  } catch (_) {
    return false;
  } finally {
    if (key.value != 0) RegCloseKey(key.value);
    calloc.free(nativeSubKey);
    if (nativeValueName != null) calloc.free(nativeValueName);
    if (nativeData != null) calloc.free(nativeData);
    calloc.free(key);
  }
}

/// True when the HKCU key exists.
bool registryKeyExists(String subKey) {
  if (!Platform.isWindows) return false;
  final key = calloc<IntPtr>();
  final nativeSubKey = subKey.toNativeUtf16();
  try {
    final result = RegOpenKeyEx(
      HKEY_CURRENT_USER,
      nativeSubKey,
      0,
      KEY_READ,
      key,
    );
    return result == 0;
  } catch (_) {
    return false;
  } finally {
    if (key.value != 0) RegCloseKey(key.value);
    calloc.free(nativeSubKey);
    calloc.free(key);
  }
}

/// Deletes the HKCU key and its children. A missing key is success.
bool registryDeleteTree(String subKey) {
  if (!Platform.isWindows) return false;
  final nativeSubKey = subKey.toNativeUtf16();
  try {
    final result = RegDeleteTree(HKEY_CURRENT_USER, nativeSubKey);
    return result == 0 || result == 2; // ERROR_FILE_NOT_FOUND
  } catch (_) {
    return false;
  } finally {
    calloc.free(nativeSubKey);
  }
}
