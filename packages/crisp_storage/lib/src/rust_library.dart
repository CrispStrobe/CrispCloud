// Helpers shared by the build hook and the runtime loader for the optional
// Rust SMB bridge. No FFI or Flutter imports: unit-testable anywhere.
import 'dart:io' show File;

/// The Cargo target for one Dart/Flutter build target.
class RustTarget {
  final String triple;

  /// File name Cargo produces for the cdylib on this target.
  final String cargoOutput;

  /// File name the build hook bundles (stable across targets of one OS).
  final String fileName;

  const RustTarget(this.triple, this.cargoOutput, this.fileName);

  /// [os] and [architecture] use package:code_assets names, case-insensitive
  /// for the OS (`ios`, `macos`, `linux`, `windows`, `android`; `arm64`, `x64`, ...). Returns null for a
  /// target the bridge is not built for.
  static RustTarget? of({
    required String os,
    required String architecture,
    bool iosSimulator = false,
  }) {
    const apple = 'libcrisp_smb_bridge.dylib';
    switch (os.toLowerCase()) {
      case 'ios':
        return switch ((architecture, iosSimulator)) {
          ('arm64', false) => const RustTarget(
            'aarch64-apple-ios',
            apple,
            apple,
          ),
          ('arm64', true) => const RustTarget(
            'aarch64-apple-ios-sim',
            apple,
            apple,
          ),
          ('x64', true) => const RustTarget('x86_64-apple-ios', apple, apple),
          _ => null,
        };
      case 'macos':
        return switch (architecture) {
          'arm64' => const RustTarget('aarch64-apple-darwin', apple, apple),
          'x64' => const RustTarget('x86_64-apple-darwin', apple, apple),
          _ => null,
        };
      case 'linux':
        const so = 'libcrisp_smb_bridge.so';
        return switch (architecture) {
          'x64' => const RustTarget('x86_64-unknown-linux-gnu', so, so),
          'arm64' => const RustTarget('aarch64-unknown-linux-gnu', so, so),
          _ => null,
        };
      case 'windows':
        const dll = 'crisp_smb_bridge.dll';
        return switch (architecture) {
          'x64' => const RustTarget('x86_64-pc-windows-msvc', dll, dll),
          'arm64' => const RustTarget('aarch64-pc-windows-msvc', dll, dll),
          _ => null,
        };
      default:
        return null;
    }
  }
}

/// The `xcrun --sdk` name for an Apple target, or null elsewhere.
String? appleSdkName({required String os, bool iosSimulator = false}) =>
    switch (os.toLowerCase()) {
      'ios' => iosSimulator ? 'iphonesimulator' : 'iphoneos',
      'macos' => 'macosx',
      _ => null,
    };

/// Locates `cargo`: `$CARGO`, then each `PATH` entry, then `~/.cargo/bin`.
/// Xcode build phases run with a reduced PATH that usually omits rustup.
String findCargo(
  Map<String, String> environment, {
  bool Function(String path)? exists,
  bool windows = false,
}) {
  final check = exists ?? _exists;
  final name = windows ? 'cargo.exe' : 'cargo';
  final explicit = environment['CARGO'];
  if (explicit != null && explicit.isNotEmpty && check(explicit)) {
    return explicit;
  }
  final separator = windows ? ';' : ':';
  final slash = windows ? r'\' : '/';
  for (final dir in (environment['PATH'] ?? '').split(separator)) {
    if (dir.isEmpty) continue;
    final candidate = '$dir$slash$name';
    if (check(candidate)) return candidate;
  }
  final home =
      environment['CARGO_HOME'] ??
      ((environment['HOME'] ?? environment['USERPROFILE']) == null
          ? null
          : '${environment['HOME'] ?? environment['USERPROFILE']}$slash.cargo');
  if (home != null) {
    final candidate = '$home${slash}bin$slash$name';
    if (check(candidate)) return candidate;
  }
  return name;
}

bool _exists(String path) => File(path).existsSync();

/// Where an app build may hold the bundled bridge, most specific first.
/// [executable] is `Platform.resolvedExecutable`.
List<String> bundledRustLibraryCandidates({
  required String os,
  required String executable,
  String? workingDirectory,
}) => [
  ..._appCandidates(os: os, executable: executable),
  // `flutter test` runs hooks too and places code assets here.
  if (workingDirectory != null)
    for (final name in switch (os) {
      'macos' => ['libcrisp_smb_bridge.dylib'],
      'linux' => ['libcrisp_smb_bridge.so'],
      'windows' => ['crisp_smb_bridge.dll'],
      _ => const <String>[],
    })
      os == 'windows'
          ? '$workingDirectory\\build\\native_assets\\windows\\$name'
          : '$workingDirectory/build/native_assets/$os/$name',
];

List<String> _appCandidates({required String os, required String executable}) {
  final slash = os == 'windows' ? r'\' : '/';
  final cut = executable.lastIndexOf(slash);
  final dir = cut < 0 ? '.' : executable.substring(0, cut);
  const stems = ['libcrisp_smb_bridge', 'crisp_smb_bridge'];
  switch (os) {
    case 'ios':
      return [
        for (final s in stems) '$dir/Frameworks/$s.framework/$s',
        for (final s in stems) '@rpath/$s.framework/$s',
      ];
    case 'macos':
      return [
        for (final s in stems) '$dir/../Frameworks/$s.framework/$s',
        for (final s in stems) '@rpath/$s.framework/$s',
        '$dir/../Frameworks/libcrisp_smb_bridge.dylib',
        // `dart build cli` bundle: bin/<exe>, lib/<library>.
        '$dir/../lib/libcrisp_smb_bridge.dylib',
      ];
    case 'linux':
      return [
        '$dir/lib/libcrisp_smb_bridge.so', // Flutter bundle
        '$dir/../lib/libcrisp_smb_bridge.so', // dart build cli bundle
        'libcrisp_smb_bridge.so',
      ];
    case 'windows':
      return [
        '$dir${slash}crisp_smb_bridge.dll',
        '$dir$slash..${slash}lib${slash}crisp_smb_bridge.dll',
        'crisp_smb_bridge.dll',
      ];
    case 'android':
      return ['libcrisp_smb_bridge.so'];
    default:
      return const [];
  }
}
