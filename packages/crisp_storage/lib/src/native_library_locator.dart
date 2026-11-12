import 'dart:io';

/// Candidate paths for an optional Rust bridge library, in priority order:
/// an explicit path (dart-define or environment), then the location used by
/// `tool/bundle_rust_engines_macos.sh` / platform packaging next to the
/// executable. Returns an empty list when nothing is configured or bundled;
/// callers then fall back to flutter_rust_bridge's default loader.
List<String> rustLibraryCandidates({
  required String stem,
  required String definedPath,
  required String environmentVariable,
  Map<String, String>? environment,
  String? executable,
  String? operatingSystem,
}) {
  final env = environment ?? Platform.environment;
  final os = operatingSystem ?? Platform.operatingSystem;
  final result = <String>[];
  if (definedPath.isNotEmpty) result.add(definedPath);
  final fromEnv = env[environmentVariable];
  if (fromEnv != null && fromEnv.isNotEmpty) result.add(fromEnv);
  final exe = executable ?? Platform.resolvedExecutable;
  final dir = File(exe).parent.path;
  switch (os) {
    case 'macos':
      result.add('$dir/../Frameworks/lib$stem.dylib');
    case 'linux':
      result.add('$dir/lib/lib$stem.so');
    case 'windows':
      result.add('$dir\\$stem.dll');
    case 'android':
      result.add('lib$stem.so');
  }
  return result;
}

/// First candidate that exists on disk (Android names resolve via the
/// loader, so they are accepted as-is).
String? firstExistingLibrary(List<String> candidates, {String? operatingSystem}) {
  final os = operatingSystem ?? Platform.operatingSystem;
  for (final path in candidates) {
    if (os == 'android' && !path.contains('/')) return path;
    if (File(path).existsSync()) return path;
  }
  return null;
}
