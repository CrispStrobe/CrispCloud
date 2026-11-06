/// Optional adapter identity for namespaces not fully described by user/bucket.
/// This must contain endpoint/root identity only, never passwords or tokens.
abstract interface class StorageNamespaceIdentity {
  String get storageNamespace;
}

/// A serializable account reference. Authentication is resolved separately.
class StorageReference {
  const StorageReference({
    required this.kind,
    required this.provider,
    required this.accountKey,
    this.root = '/',
    this.persistent = true,
  });

  final String kind;
  final String provider;
  final String accountKey;
  final String root;
  final bool persistent;

  String get id => '$kind:$provider:$accountKey';
  bool get isLocal => kind == 'local';

  Map<String, dynamic> toJson() => {
    'version': 1,
    'kind': kind,
    'provider': provider,
    'accountKey': accountKey,
    'root': root,
    'persistent': persistent,
  };

  factory StorageReference.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1 ||
        !const ['local', 'remote'].contains(json['kind']) ||
        json['provider'] is! String ||
        json['accountKey'] is! String ||
        (json['accountKey'] as String).isEmpty) {
      throw const FormatException('Invalid storage reference.');
    }
    return StorageReference(
      kind: json['kind'] as String,
      provider: json['provider'] as String,
      accountKey: json['accountKey'] as String,
      root: json['root'] as String? ?? '/',
      persistent: json['persistent'] != false,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StorageReference && id == other.id && root == other.root;

  @override
  int get hashCode => Object.hash(id, root);
}

/// Identifies one original object independently of its current panel or tab.
class FileReference {
  const FileReference({
    required this.storage,
    required this.path,
    this.objectId,
    this.version,
  });

  final StorageReference storage;
  final String path;
  final String? objectId;
  final String? version;
  String get id => '${storage.id}:${objectId ?? path}';

  Map<String, dynamic> toJson() => {
    'storage': storage.toJson(),
    'path': path,
    if (objectId != null) 'objectId': objectId,
    if (version != null) 'version': version,
  };

  factory FileReference.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    if (path is! String || path.isEmpty || path.contains('\u0000')) {
      throw const FormatException('Invalid file reference path.');
    }
    return FileReference(
      storage: StorageReference.fromJson(
        Map<String, dynamic>.from(json['storage'] as Map),
      ),
      path: path,
      objectId: json['objectId'] as String?,
      version: json['version'] as String?,
    );
  }
}
