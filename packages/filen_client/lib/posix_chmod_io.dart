import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Best-effort chmod without spawning a process. No-op on Windows.
void chmodPath(String path, int mode) {
  if (Platform.isWindows) return;
  final nativePath = path.toNativeUtf8();
  try {
    final chmod = DynamicLibrary.process().lookupFunction<
        Int32 Function(Pointer<Utf8>, Uint32),
        int Function(Pointer<Utf8>, int)>('chmod');
    chmod(nativePath, mode);
  } catch (_) {
    // Some platforms do not expose chmod through the process library.
  } finally {
    calloc.free(nativePath);
  }
}
