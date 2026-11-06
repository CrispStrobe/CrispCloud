import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'panel_source_service.dart';
import 'storage_identity.dart';
import 'sync_database.dart';

/// Identifies the two storage accounts and roots explicitly chosen for a pair.
/// A new token on every rebind invalidates work queued under the old binding,
/// including when a user binds to the same account again.
class SyncSourceBinding {
  const SyncSourceBinding({
    required this.token,
    required this.local,
    required this.remote,
    required this.localRoot,
    required this.remoteRoot,
  });

  final String token;
  final StorageReference local;
  final StorageReference remote;
  final String localRoot;
  final String remoteRoot;

  static StorageReference get currentLocal =>
      storageReferenceForSource(const LocalPanelSource('/'));

  factory SyncSourceBinding.capture({
    required String localPath,
    required String remotePath,
    required CloudStorageClient client,
  }) {
    final local = currentLocal;
    final remote = storageReferenceForClient(client);
    if (!client.isAuthenticated || !local.persistent || !remote.persistent) {
      throw StateError(
        'Connect an identified account and initialize this device before binding a sync pair.',
      );
    }
    if (!p.isAbsolute(localPath) || !p.posix.isAbsolute(remotePath)) {
      throw const FormatException('Sync roots must be absolute paths.');
    }
    return SyncSourceBinding(
      token: const Uuid().v4(),
      local: local,
      remote: remote,
      localRoot: p.normalize(localPath),
      remoteRoot: p.posix.normalize(remotePath),
    );
  }

  String encode() => jsonEncode({
    'version': 1,
    'token': token,
    'local': local.toJson(),
    'remote': remote.toJson(),
    'localRoot': localRoot,
    'remoteRoot': remoteRoot,
  });

  static SyncSourceBinding? decode(String? value) {
    if (value == null) return null;
    try {
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['version'] != 1 ||
          json['token'] is! String ||
          (json['token'] as String).isEmpty ||
          json['localRoot'] is! String ||
          json['remoteRoot'] is! String) {
        return null;
      }
      final local = StorageReference.fromJson(
        Map<String, dynamic>.from(json['local'] as Map),
      );
      final remote = StorageReference.fromJson(
        Map<String, dynamic>.from(json['remote'] as Map),
      );
      if (!local.isLocal ||
          remote.isLocal ||
          !local.persistent ||
          !remote.persistent) {
        return null;
      }
      return SyncSourceBinding(
        token: json['token'] as String,
        local: local,
        remote: remote,
        localRoot: json['localRoot'] as String,
        remoteRoot: json['remoteRoot'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  bool matchesLocal(SyncPair pair) =>
      local == currentLocal &&
      currentLocal.persistent &&
      localRoot == p.normalize(pair.localPath) &&
      remoteRoot == p.posix.normalize(pair.remotePath);

  bool matches(SyncPair pair, CloudStorageClient client) =>
      matchesLocal(pair) &&
      client.isAuthenticated &&
      remote == storageReferenceForClient(client);

  static SyncSourceBinding requireLocal(SyncPair pair) {
    final binding = decode(pair.sourceBinding);
    if (binding == null) {
      throw StateError(
        'This sync pair needs account review. Bind it to the connected account before continuing.',
      );
    }
    if (!binding.matchesLocal(pair)) {
      throw StateError(
        'The saved sync device or folder changed. Review and bind this pair again.',
      );
    }
    return binding;
  }

  static SyncSourceBinding require(SyncPair pair, CloudStorageClient client) {
    final binding = requireLocal(pair);
    if (!binding.matches(pair, client)) {
      throw StateError(
        'Connect the account and storage root saved for this sync pair, or explicitly bind it again.',
      );
    }
    return binding;
  }
}

/// Queue paths are relative to the captured pair root, never arbitrary paths.
String validateSyncRelativePath(String value) {
  if (value.isEmpty ||
      value.contains('\u0000') ||
      value.contains('\\') ||
      p.posix.isAbsolute(value) ||
      RegExp(r'^[a-zA-Z]:').hasMatch(value) ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw const FormatException(
      'A sync path must stay inside its saved folder.',
    );
  }
  return value;
}
