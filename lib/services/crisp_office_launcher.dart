import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

typedef CrispOfficeOpenRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Opens a verified local legacy document in the installed CrispOffice app.
///
/// CrispOffice owns `.doc` parsing and saves back through its own document
/// flow. CrispCloud deliberately does not convert just because a file was
/// opened; conversion remains an explicit context-menu action.
class CrispOfficeLauncher {
  CrispOfficeLauncher({bool? supported, CrispOfficeOpenRunner? run})
    : supported =
          supported ??
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS),
      _run =
          run ??
          ((executable, arguments) => Process.run(executable, arguments));

  final bool supported;
  final CrispOfficeOpenRunner _run;

  static const bundleIdentifier = 'com.crispstrobe.crispoffice';

  Future<bool> open(String path) async {
    if (!supported ||
        !p.isAbsolute(path) ||
        path.contains('\u0000') ||
        path.length > 4096) {
      return false;
    }
    final result = await _run('/usr/bin/open', ['-b', bundleIdentifier, path]);
    return result.exitCode == 0;
  }
}

final crispOfficeLauncherProvider = Provider<CrispOfficeLauncher>(
  (_) => CrispOfficeLauncher(),
);
