import 'dart:io';

import 'package:flutter_pty2/src/internal/ffi_driver.dart';
import 'package:flutter_pty2/src/pty_exception.dart';
import 'package:flutter_pty2/src/pty_session.dart';
import 'package:flutter_pty2/src/pty_spawn_options.dart';

/// Entry point for the clean-slate PTY session API.
abstract final class Pty {
  /// Spawns a process in a PTY and returns once the native session is ready.
  static Future<PtySession> spawn(PtySpawnOptions options) {
    // Match hook/build.dart: mobile builds intentionally contain no PTY asset.
    if (!(Platform.isLinux || Platform.isMacOS || Platform.isWindows)) {
      return Future.error(
        const PtyUnsupportedException(
          'Local PTY shells are available on desktop only. Use SSH on mobile.',
        ),
      );
    }
    return FfiPtyDriver.instance.spawn(options);
  }
}
