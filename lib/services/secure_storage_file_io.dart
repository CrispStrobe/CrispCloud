import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../utils/async_lock.dart';
import 'native_system.dart';
import 'secure_storage_service.dart';
import 'secure_storage_web.dart';

/// File-backed key/value store for [WebEncryptedStorage].
///
/// The file contains only AES-256-GCM ciphertext and the unencrypted PBKDF2
/// salt/verification/iteration metadata. It is created with mode 0600.
class FileStorageBackend implements WebStorageBackend {
  FileStorageBackend(this.file);

  final File file;
  final _lock = AsyncLock();
  Map<String, String>? _cache;

  Future<Map<String, String>> _load() async {
    final existing = _cache;
    if (existing != null) return existing;
    if (!await file.exists()) {
      return _cache = <String, String>{};
    }
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return _cache = <String, String>{};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('Credential vault is not a JSON object.');
      }
      return _cache = <String, String>{
        for (final entry in decoded.entries)
          if (entry.key is String && entry.value is String)
            entry.key as String: entry.value as String,
      };
    } catch (error) {
      throw StateError('Credential vault could not be read: $error');
    }
  }

  Future<void> _save(Map<String, String> data) async {
    final parent = file.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    if (Platform.isWindows && await file.exists()) {
      await file.delete();
    }
    await temporary.rename(file.path);
    setFileMode(file.path, 0x180 /* 0600 */);
    _cache = data;
  }

  @override
  Future<String?> getItem(String key) => _lock.synchronized(() async {
    return (await _load())[key];
  });

  @override
  Future<void> setItem(String key, String value) =>
      _lock.synchronized(() async {
        final data = Map<String, String>.of(await _load());
        data[key] = value;
        await _save(data);
      });

  @override
  Future<void> removeItem(String key) => _lock.synchronized(() async {
    final data = Map<String, String>.of(await _load());
    data.remove(key);
    await _save(data);
  });

  @override
  Future<List<String>> allKeys() => _lock.synchronized(() async {
    return (await _load()).keys.toList();
  });
}

/// Native equivalent of the web vault: AES-256-GCM values in a local file,
/// unlocked by a master password instead of an OS keychain.
class EncryptedFileStorage extends WebEncryptedStorage {
  EncryptedFileStorage(File file) : super(FileStorageBackend(file));
}

Future<SecureStorage> createEncryptedFileStorage({
  String? masterPassword,
}) async {
  final directory = await getApplicationSupportDirectory();
  final storage = EncryptedFileStorage(
    File(p.join(directory.path, 'credential-vault.json')),
  );
  if (masterPassword != null) {
    await storage.initialize(masterPassword);
  }
  return storage;
}
