import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../models/file_item.dart';

typedef ApplicationOpenRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Launch Services opens the bundle as an application without a shell.
class MacApplicationLauncher {
  MacApplicationLauncher({bool? supported, ApplicationOpenRunner? run})
    : supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS),
      _run =
          run ??
          ((executable, arguments) => Process.run(executable, arguments));

  final bool supported;
  final ApplicationOpenRunner _run;

  bool isApplicationBundle(FileItem file) =>
      supported && file.isFolder && file.name.toLowerCase().endsWith('.app');

  Future<void> launch(String path) async {
    if (!supported ||
        !p.isAbsolute(path) ||
        path.contains('\u0000') ||
        !p.basename(p.normalize(path)).toLowerCase().endsWith('.app')) {
      throw ArgumentError('A local macOS application bundle is required.');
    }
    final result = await _run('/usr/bin/open', ['-a', path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        '/usr/bin/open',
        ['-a', path],
        result.stderr.toString(),
        result.exitCode,
      );
    }
  }
}

final macApplicationLauncherProvider = Provider<MacApplicationLauncher>(
  (_) => MacApplicationLauncher(),
);
