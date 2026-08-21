/// Configuration and state management for the Filen CLI.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

import 'package:filen_client/config_storage.dart';
import 'package:filen_client/credential_crypto.dart' as cred;

// Credential-at-rest format (CLI, file-backed storage only). The stored map is a
// small JSON envelope {"fmt","src","ct"} where ct is the credentials JSON
// encrypted with a wrapping key whose source is "src":
//   - env    : FILEN_CREDENTIALS_KEY (a key you supply; good for CI)
//   - static : a public app constant (obfuscation only; the file is also 0600)
// Legacy plaintext-JSON credential files are read and migrated on first read.
// NOTE: when a custom ConfigStorage is injected (e.g. a host app's secure
// storage), this encryption is SKIPPED — that consumer encrypts at its own
// layer, so double-encrypting would be wrong.
const String credentialsFmt = 'filen-cred-v1';
const String credentialsKeyEnv = 'FILEN_CREDENTIALS_KEY';
const String _staticCredentialsKey = 'QFK2N9R7P4M8XTZB';

class ConfigService {
  late final String configDir;
  late final String credentialsFile;
  late final String batchStateDir;
  late final String webdavPidFile;
  late final ConfigStorage _storage;

  /// Whether ConfigService encrypts credentials itself before persisting. True
  /// only when using the default file-backed storage (the standalone CLI);
  /// false when a consumer injects its own (already-secure) storage.
  late final bool _encryptCredentials;

  ConfigService({required String configPath, ConfigStorage? storage}) {
    configDir = configPath;
    credentialsFile = p.join(configDir, 'credentials.json');
    batchStateDir = p.join(configDir, 'batch_states');
    webdavPidFile = p.join(configDir, 'webdav.pid');

    _encryptCredentials = storage == null;
    _storage = storage ?? FileConfigStorage(credentialsFile: credentialsFile);

    try {
      Directory(configDir).createSync(recursive: true);
      Directory(batchStateDir).createSync(recursive: true);
    } catch (e) {
      print("⚠️ Warning: Could not create config directory: $e");
    }
    if (_encryptCredentials) _restrictPerms(configDir, '700');
  }

  /// The active credential storage backend (FileConfigStorage by default).
  ConfigStorage get storage => _storage;

  /// Best-effort POSIX chmod (dart:io has no native chmod). No-op on Windows
  /// (relies on user-profile ACLs) and if `chmod` isn't available. The path is
  /// the only argv — no secret is exposed.
  void _restrictPerms(String path, String mode) {
    if (Platform.isWindows) return;
    try {
      Process.runSync('chmod', [mode, path]);
    } catch (_) {/* best effort */}
  }

  (String, String) _wrappingSecretForSave() {
    final envKey = Platform.environment[credentialsKeyEnv];
    if (envKey != null && envKey.isNotEmpty) return ('env', envKey);
    return ('static', _staticCredentialsKey);
  }

  String? _resolveWrappingSecret(String? src) {
    if (src == 'env') {
      final k = Platform.environment[credentialsKeyEnv];
      return (k != null && k.isNotEmpty) ? k : null;
    }
    if (src == 'static') return _staticCredentialsKey;
    return null;
  }

  // --- Credential management ---
  // Encrypted at rest for the file-backed CLI (envelope + chmod 600); a custom
  // injected ConfigStorage is left to encrypt at its own layer. See the
  // credential-format note at the top of this file.

  Future<void> saveCredentials(Map<String, dynamic> data) async {
    if (!_encryptCredentials) {
      // Custom storage encrypts at its own layer.
      await _storage.saveCredentials(data);
      return;
    }
    final (src, secret) = _wrappingSecretForSave();
    final ct = cred.encryptTextWithKey(json.encode(data), secret);
    await _storage
        .saveCredentials({'fmt': credentialsFmt, 'src': src, 'ct': ct});
    _restrictPerms(credentialsFile, '600');
  }

  Future<Map<String, dynamic>?> readCredentials() async {
    final stored = await _storage.readCredentials();
    if (stored == null) return null;
    if (!_encryptCredentials) return stored;
    try {
      if (stored['fmt'] == credentialsFmt) {
        final secret = _resolveWrappingSecret(stored['src'] as String?);
        if (secret == null) return null; // wrapping key unavailable
        final plain = cred.decryptTextWithKey(stored['ct'] as String, secret);
        return json.decode(plain) as Map<String, dynamic>;
      }
      // Legacy plaintext-JSON credentials → migrate to the encrypted envelope.
      try {
        await saveCredentials(stored);
      } catch (_) {/* keep legacy on failure */}
      return stored;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCredentials() => _storage.clearCredentials();

  // --- WebDAV PID management ---

  Future<int?> readWebdavPid() async {
    final file = File(webdavPidFile);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return int.tryParse(content.trim());
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> saveWebdavPid(int pid) async {
    final file = File(webdavPidFile);
    await file.writeAsString(pid.toString());
  }

  Future<void> clearWebdavPid() async {
    final file = File(webdavPidFile);
    if (await file.exists()) {
      await file.delete();
    }
  }

  // --- Batch state management ---

  String generateBatchId(
      String operationType, List<String> sources, String target) {
    final input = '$operationType-${sources.join('|')}-$target';
    final bytes = utf8.encode(input);
    final digest = crypto.sha1.convert(bytes);
    return digest.toString().substring(0, 16);
  }

  String getBatchStateFilePath(String batchId) {
    return p.join(batchStateDir, 'batch_state_$batchId.json');
  }

  Future<Map<String, dynamic>?> loadBatchState(String batchId) async {
    final filePath = getBatchStateFilePath(batchId);
    final file = File(filePath);
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        return json.decode(content) as Map<String, dynamic>;
      } catch (e) {
        print("⚠️ Could not read batch state: $e");
        await deleteBatchState(batchId);
        return null;
      }
    }
    return null;
  }

  Future<void> saveBatchState(
      String batchId, Map<String, dynamic> state) async {
    final filePath = getBatchStateFilePath(batchId);
    final file = File(filePath);
    try {
      await file.writeAsString(json.encode(state));
    } catch (e) {
      print("⚠️ Could not save batch state: $e");
    }
  }

  Future<void> deleteBatchState(String batchId) async {
    final filePath = getBatchStateFilePath(batchId);
    final file = File(filePath);
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (e) {
        print("⚠️ Could not delete batch state: $e");
      }
    }
  }
}
