import 'package:path/path.dart' as p;

/// User's real home directory on desktop, independent of Dart's current
/// working directory. Windows normally sets USERPROFILE, not HOME; some
/// deployments expose only HOMEDRIVE + HOMEPATH.
String? nativeHomeDirectory(
  Map<String, String> environment, {
  required bool windows,
}) {
  final paths = windows ? p.windows : p.posix;
  final candidates = <String?>[
    if (windows) environment['USERPROFILE'],
    if (windows &&
        environment['HOMEDRIVE']?.isNotEmpty == true &&
        environment['HOMEPATH']?.isNotEmpty == true)
      '${environment['HOMEDRIVE']}${environment['HOMEPATH']}',
    environment['HOME'],
  ];
  for (final candidate in candidates) {
    if (candidate == null || candidate.trim().isEmpty) continue;
    final path = candidate.trim();
    // On Windows a POSIX-style HOME such as Git Bash's '/c/Users/x' is only
    // root-relative (no drive or UNC share) and must not become '\\c\\...'.
    if (paths.isAbsolute(path) && !(windows && paths.isRootRelative(path))) {
      return paths.normalize(path);
    }
  }
  return null;
}
