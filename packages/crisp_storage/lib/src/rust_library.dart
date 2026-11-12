// Helpers shared by the build hook and the runtime loaders for the optional
// Rust bridges (`crisp_smb_bridge` for SMB, `crisp_cloud_bridge` for
// Filen/Internxt). No FFI or Flutter imports: unit-testable anywhere.
import 'dart:io' show File;

/// Library stem of the Rust SMB bridge (`rust/`).
const smbBridgeStem = 'crisp_smb_bridge';

/// Library stem of the Rust Filen/Internxt bridge (`rust_cloud/`).
const cloudBridgeStem = 'crisp_cloud_bridge';

/// The Cargo target for one Dart/Flutter build target.
class RustTarget {
  final String triple;

  /// File name Cargo produces for the cdylib on this target.
  final String cargoOutput;

  /// File name the build hook bundles (stable across targets of one OS).
  final String fileName;

  RustTarget(this.triple, this.cargoOutput, this.fileName);

  /// [os] and [architecture] use package:code_assets names, case-insensitive
  /// for the OS (`ios`, `macos`, `linux`, `windows`, `android`; `arm64`, `x64`, ...). Returns null for a
  /// target the bridge is not built for.
  static RustTarget? of({
    required String os,
    required String architecture,
    bool iosSimulator = false,
    String stem = smbBridgeStem,
  }) {
    final apple = 'lib$stem.dylib';
    switch (os.toLowerCase()) {
      case 'ios':
        return switch ((architecture, iosSimulator)) {
          ('arm64', false) => RustTarget(
            'aarch64-apple-ios',
            apple,
            apple,
          ),
          ('arm64', true) => RustTarget(
            'aarch64-apple-ios-sim',
            apple,
            apple,
          ),
          ('x64', true) => RustTarget('x86_64-apple-ios', apple, apple),
          _ => null,
        };
      case 'macos':
        return switch (architecture) {
          'arm64' => RustTarget('aarch64-apple-darwin', apple, apple),
          'x64' => RustTarget('x86_64-apple-darwin', apple, apple),
          _ => null,
        };
      case 'linux':
        final so = 'lib$stem.so';
        return switch (architecture) {
          'x64' => RustTarget('x86_64-unknown-linux-gnu', so, so),
          'arm64' => RustTarget('aarch64-unknown-linux-gnu', so, so),
          _ => null,
        };
      case 'windows':
        final dll = '$stem.dll';
        return switch (architecture) {
          'x64' => RustTarget('x86_64-pc-windows-msvc', dll, dll),
          'arm64' => RustTarget('aarch64-pc-windows-msvc', dll, dll),
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
  String stem = smbBridgeStem,
}) => [
  ..._appCandidates(os: os, executable: executable, stem: stem),
  // `flutter test` runs hooks too and places code assets here.
  if (workingDirectory != null)
    for (final name in switch (os) {
      'macos' => ['lib$stem.dylib'],
      'linux' => ['lib$stem.so'],
      'windows' => ['$stem.dll'],
      _ => const <String>[],
    })
      os == 'windows'
          ? '$workingDirectory\\build\\native_assets\\windows\\$name'
          : '$workingDirectory/build/native_assets/$os/$name',
];

List<String> _appCandidates({
  required String os,
  required String executable,
  required String stem,
}) {
  final slash = os == 'windows' ? r'\' : '/';
  final cut = executable.lastIndexOf(slash);
  final dir = cut < 0 ? '.' : executable.substring(0, cut);
  final stems = ['lib$stem', stem];
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
        '$dir/../Frameworks/lib$stem.dylib',
        // `dart build cli` bundle: bin/<exe>, lib/<library>.
        '$dir/../lib/lib$stem.dylib',
      ];
    case 'linux':
      return [
        '$dir/lib/lib$stem.so', // Flutter bundle
        '$dir/../lib/lib$stem.so', // dart build cli bundle
        'lib$stem.so',
      ];
    case 'windows':
      return [
        '$dir$slash$stem.dll',
        '$dir$slash..${slash}lib$slash$stem.dll',
        '$stem.dll',
      ];
    case 'android':
      return ['lib$stem.so'];
    default:
      return const [];
  }
}
