// lib/adapters/cli_storage_client.dart
//
// Abstract interface for CLI storage adapters.
// Mirrors the core CloudStorageClient interface but:
//   - Has no Flutter dependencies
//   - Uses simpler/more CLI-friendly types
//   - Returns CliFileItem instead of raw maps

/// Represents a single file or folder listing entry.
class CliFileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int? size;
  final String? modifiedAt; // ISO-8601 or provider-native string

  const CliFileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size,
    this.modifiedAt,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'type': isDirectory ? 'folder' : 'file',
        if (size != null) 'size': size,
        if (modifiedAt != null) 'modified': modifiedAt,
      };
}

/// Abstract interface every CLI adapter must implement.
abstract class CliStorageClient {
  String get providerName;

  /// List files and folders at [remotePath].
  Future<List<CliFileItem>> list(String remotePath);

  /// Upload bytes [data] to [remoteDir]/[fileName].
  Future<void> upload(
    List<int> data,
    String fileName,
    String remoteDir, {
    void Function(int sent, int total)? onProgress,
  });

  /// Download remote file at [remotePath] to [localPath].
  Future<void> download(
    String remotePath,
    String localPath, {
    void Function(int received, int total)? onProgress,
  });

  /// Download remote file and return raw bytes.
  Future<List<int>> downloadBytes(String remotePath);

  /// Create a remote directory (including parents where supported).
  Future<void> createDirectory(String remotePath);

  /// Delete a file or directory at [remotePath].
  Future<void> delete(String remotePath);

  /// Rename/move [sourcePath] to [targetPath].
  Future<void> move(String sourcePath, String targetPath);

  /// Check whether [remotePath] exists. Returns null if not found.
  Future<CliFileItem?> stat(String remotePath);

  /// Generate a time-limited share link. Returns the URL string.
  /// Throws [UnsupportedError] if the provider does not support sharing.
  Future<String> share(String remotePath, {Duration? expires});

  /// Close any open connections / release resources.
  Future<void> dispose();
}
