/// Pluggable storage backend for credentials.
///
/// Allows swapping between file-based storage (production) and
/// in-memory storage (tests) without changing business logic.
import 'dart:convert';
import 'dart:io';

abstract class ConfigStorage {
  Future<Map<String, dynamic>?> readCredentials();
  Future<void> saveCredentials(Map<String, dynamic> data);
  Future<void> clearCredentials();
}

/// File-based credential storage (default for CLI usage).
class FileConfigStorage implements ConfigStorage {
  final String credentialsFile;

  FileConfigStorage({required this.credentialsFile});

  @override
  Future<void> saveCredentials(Map<String, dynamic> data) async {
    await File(credentialsFile).writeAsString(json.encode(data));
  }

  @override
  Future<Map<String, dynamic>?> readCredentials() async {
    final file = File(credentialsFile);
    if (await file.exists()) {
      try {
        return json.decode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Corrupt/unreadable credentials file -> treat as "not logged in"
        // rather than crashing the CLI.
        return null;
      }
    }
    return null;
  }

  @override
  Future<void> clearCredentials() async {
    final file = File(credentialsFile);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

/// In-memory credential storage for unit tests.
class InMemoryConfigStorage implements ConfigStorage {
  Map<String, dynamic>? _credentials;

  @override
  Future<void> saveCredentials(Map<String, dynamic> data) async {
    _credentials = Map.from(data);
  }

  @override
  Future<Map<String, dynamic>?> readCredentials() async {
    return _credentials != null ? Map.from(_credentials!) : null;
  }

  @override
  Future<void> clearCredentials() async {
    _credentials = null;
  }
}
