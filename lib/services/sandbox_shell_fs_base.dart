// Shared filesystem boundary for CrispCloud's built-in, sandbox-safe shell.
//
// The shell never launches a host executable. It operates on a small POSIX-like
// view of files through this interface instead, so the same terminal works on
// macOS App Sandbox, iOS, Android, Windows, Linux and the web.

class ShellEntry {
  const ShellEntry({
    required this.name,
    required this.isDirectory,
    this.size = 0,
    this.modified,
  });

  final String name;
  final bool isDirectory;
  final int size;
  final DateTime? modified;
}

/// A deliberately small filesystem surface used by the built-in shell.
///
/// Implementations must reject paths they cannot safely normalise rather than
/// silently escaping the shell root.
abstract class SandboxShellFs {
  /// Writable starting directory for the shell (usually the user's home).
  Future<String> get home;

  /// Human-readable platform name for `uname` and the welcome banner.
  String get platformName;

  /// True for the in-memory browser filesystem.
  bool get isMemory;

  /// Resolve [path] against [cwd], expanding `~` and removing `.`/`..`.
  Future<String> normalize(String path, String cwd);

  Future<bool> exists(String path);
  Future<bool> isDirectory(String path);
  Future<List<ShellEntry>> list(String path);
  Future<List<int>> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<void> createDirectory(String path, {bool recursive = true});
  Future<void> delete(String path, {bool recursive = false});
  Future<void> rename(String from, String to);
  Future<void> copy(String from, String to, {bool recursive = false});
  Future<ShellEntry> stat(String path);
}
