import 'dart:io';

import 'package:path/path.dart' as p;

/// True when the running macOS bundle was installed by the Mac App Store.
///
/// App Store builds are expected to stay sandbox-only. Features that require a
/// third-party kernel extension, a privileged helper or a host process are
/// hidden rather than shown and then failing at runtime.
bool isMacAppStoreBuild() {
  if (!Platform.isMacOS) return false;
  try {
    final executable = Platform.resolvedExecutable;
    final contents = p.dirname(p.dirname(executable));
    return File(p.join(contents, '_MASReceipt', 'receipt')).existsSync();
  } catch (_) {
    return false;
  }
}
