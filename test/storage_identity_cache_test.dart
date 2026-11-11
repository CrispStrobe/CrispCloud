import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/models/storage_reference.dart';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/encrypted_storage_wrapper.dart';
import 'package:crisp_cloud/services/file_operation_backend.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/storage_identity.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

class _Client extends Fake implements CloudStorageClient {
  String provider = 'Fixture';
  String? account = 'reader@example.test';
  String? bucket = 'bucket-a';
  String root = '/vault';
  bool authenticated = true;
  String? throwingField;
  final reads = <String, int>{};

  void read(String field) {
    reads.update(field, (count) => count + 1, ifAbsent: () => 1);
    if (throwingField == field)
      throw StateError('Unavailable $field identity.');
  }

  @override
  String get providerName {
    read('provider');
    return provider;
  }

  @override
  String? get userId {
    read('account');
    return account;
  }

  @override
  String? get bucketId {
    read('bucket');
    return bucket;
  }

  @override
  String get rootPath {
    read('root');
    return root;
  }

  @override
  bool get isAuthenticated {
    read('authentication');
    return authenticated;
  }
}

class _NamespacedClient extends _Client implements StorageNamespaceIdentity {
  String namespace = 'https://files.example.test:8443';

  @override
  String get storageNamespace {
    read('namespace');
    return namespace;
  }
}

class _EqualClient extends _Client {
  @override
  bool operator ==(Object other) => other is _EqualClient;
  @override
  int get hashCode => 0;
}

// Independent copy of the established wire identity, using fixture fields
// directly. It neither calls the production helper nor reads its cache.
StorageReference _legacyReference({
  required String provider,
  required String account,
  required String? bucket,
  required String namespace,
  required String root,
}) => StorageReference(
  kind: 'remote',
  provider: provider,
  accountKey: sha256
      .convert(
        utf8.encode(jsonEncode([provider, account, bucket, namespace, root])),
      )
      .toString(),
  root: root,
  persistent: true,
);

StorageReference _expected(_Client client) => _legacyReference(
  provider: client.provider,
  account: client.account!,
  bucket: client.bucket,
  namespace: client is _NamespacedClient ? client.namespace : client.root,
  root: client.root,
);

StorageReference _expectedEncrypted(_Client inner) => _legacyReference(
  provider: '${inner.provider} (Encrypted)',
  account: inner.account!,
  bucket: inner.bucket,
  namespace: 'encrypted:${_expected(inner).id}',
  root: inner.root,
);

void main() {
  test(
    'cached references preserve the existing digest and serialized fields',
    () {
      final client = _NamespacedClient();
      final reference = storageReferenceForClient(client);
      expect(
        reference.accountKey,
        'fd3b2cffbca29c4dbe79716714828a6e3e86b361f94a93b103075c6c11a4cbd4',
      );
      expect(reference.toJson(), _expected(client).toJson());
      expect(identical(storageReferenceForClient(client), reference), isTrue);
      expect(jsonEncode(reference.toJson()), isNot(contains(client.account!)));
      expect(jsonEncode(reference.toJson()), isNot(contains(client.namespace)));
    },
  );

  test('every cache hit rereads each current identity field', () {
    final client = _NamespacedClient();
    final first = storageReferenceForClient(client);
    final before = Map<String, int>.of(client.reads);
    expect(identical(storageReferenceForClient(client), first), isTrue);
    for (final field in [
      'provider',
      'account',
      'bucket',
      'namespace',
      'root',
    ]) {
      expect(client.reads[field], before[field]! + 1, reason: field);
    }
  });

  final changes = <(String, void Function(_NamespacedClient))>[
    ('provider', (client) => client.provider = 'Other fixture'),
    ('account', (client) => client.account = 'another@example.test'),
    ('bucket', (client) => client.bucket = 'bucket-b'),
    ('null bucket', (client) => client.bucket = null),
    (
      'namespace',
      (client) => client.namespace = 'https://files.example.test:9443',
    ),
    ('root', (client) => client.root = '/another-root'),
  ];
  for (final (field, change) in changes) {
    test('a changed $field invalidates only the matching client cache', () {
      final client = _NamespacedClient();
      final equivalent = _NamespacedClient();
      final first = storageReferenceForClient(client);
      final other = storageReferenceForClient(equivalent);
      expect(first, other);
      expect(identical(first, other), isFalse);
      change(client);
      final updated = storageReferenceForClient(client);
      expect(updated.toJson(), _expected(client).toJson());
      expect(updated, isNot(first));
      expect(identical(storageReferenceForClient(client), updated), isTrue);
      expect(identical(storageReferenceForClient(equivalent), other), isTrue);
    });
  }

  test(
    'fallback namespaces and exact Unicode JSON inputs retain legacy identity',
    () {
      final client = _Client()
        ..account = 'reader "資料"\n📁'
        ..bucket = null
        ..root = '/資料/📁';
      final first = storageReferenceForClient(client);
      expect(first.toJson(), _expected(client).toJson());
      client.root = '/資料/📁/';
      final changed = storageReferenceForClient(client);
      expect(changed.toJson(), _expected(client).toJson());
      expect(changed, isNot(first));
      client.bucket = '';
      final emptyBucket = storageReferenceForClient(client);
      expect(emptyBucket.toJson(), _expected(client).toJson());
      expect(emptyBucket, isNot(changed));
    },
  );

  test(
    'anonymous identified anonymous transitions retain the original session',
    () {
      final client = _NamespacedClient()..account = null;
      final anonymous = storageReferenceForClient(client);
      expect(anonymous.persistent, isFalse);
      client.account = '';
      expect(identical(storageReferenceForClient(client), anonymous), isTrue);
      client.account = 'reader@example.test';
      final identified = storageReferenceForClient(client);
      expect(identified.persistent, isTrue);
      expect(identified.toJson(), _expected(client).toJson());
      expect(identified, isNot(anonymous));
      client.account = null;
      final restored = storageReferenceForClient(client);
      expect(restored.toJson(), anonymous.toJson());
      expect(restored.persistent, isFalse);
      expect(
        storageReferenceForClient(_NamespacedClient()..account = null),
        isNot(restored),
      );
      client.account = ' ';
      final whitespaceAccount = storageReferenceForClient(client);
      expect(whitespaceAccount.persistent, isTrue);
      expect(whitespaceAccount.toJson(), _expected(client).toJson());
    },
  );

  test(
    'weak cache keys use instance identity even for equal client objects',
    () {
      final first = _EqualClient()..account = null;
      final second = _EqualClient()..account = null;
      expect(first == second, isTrue);
      final a = storageReferenceForClient(first);
      final b = storageReferenceForClient(second);
      expect(a, isNot(b));
      expect(identical(storageReferenceForClient(first), a), isTrue);
      expect(identical(storageReferenceForClient(second), b), isTrue);
    },
  );

  test(
    'identity getter errors still propagate after a successful cache fill',
    () {
      final client = _NamespacedClient();
      final original = storageReferenceForClient(client);
      for (final field in [
        'provider',
        'account',
        'bucket',
        'namespace',
        'root',
      ]) {
        client.throwingField = field;
        expect(
          () => storageReferenceForClient(client),
          throwsStateError,
          reason: field,
        );
        client.throwingField = null;
        expect(identical(storageReferenceForClient(client), original), isTrue);
      }
    },
  );

  test('live authentication and source-generation checks remain independent of cache hits', () {
    final client = _NamespacedClient();
    var current = true;
    final backend = CloudOperationBackend(client, isCurrent: () => current);
    final original = storageReferenceForClient(client);
    expect(backend.isCurrent, isTrue);
    client.authenticated = false;
    expect(identical(storageReferenceForClient(client), original), isTrue);
    expect(backend.isCurrent, isFalse);
    client.authenticated = true;
    current = false;
    expect(identical(storageReferenceForClient(client), original), isTrue);
    expect(backend.isCurrent, isFalse);
    current = true;
    expect(backend.isCurrent, isTrue);
    client.namespace = 'https://different.example.test:8443';
    expect(backend.identity, isNot(original.id));
  });

  test('encrypted wrappers reread inner identity and retain independent cache entries', () {
    final inner = _NamespacedClient();
    final wrapper = EncryptedStorageWrapper(
      inner: inner,
      encryptionKey: Uint8List.fromList(List.generate(32, (index) => index)),
    );
    final equivalent = EncryptedStorageWrapper(
      inner: inner,
      encryptionKey: Uint8List.fromList(
        List.generate(32, (index) => 31 - index),
      ),
    );
    final first = storageReferenceForClient(wrapper);
    final other = storageReferenceForClient(equivalent);
    expect(first.toJson(), _expectedEncrypted(inner).toJson());
    expect(other.toJson(), first.toJson());
    expect(identical(first, other), isFalse);
    expect(identical(storageReferenceForClient(wrapper), first), isTrue);
    inner.namespace = 'https://files.example.test:9443';
    final updated = storageReferenceForClient(wrapper);
    expect(updated.toJson(), _expectedEncrypted(inner).toJson());
    expect(updated, isNot(first));
    expect(storageReferenceForClient(equivalent).toJson(), updated.toJson());
    inner.account = 'replacement@example.test';
    expect(
      storageReferenceForClient(wrapper).toJson(),
      _expectedEncrypted(inner).toJson(),
    );
  });

  test('panel and archive wrappers reuse the client reference without caching panel paths', () {
    final client = _NamespacedClient();
    final panel = RemotePanelSource(
      providerName: 'Panel label',
      client: client,
      path: '/shown',
    );
    final archive = ArchivePanelSource(
      archivePath: '/shown/a.zip',
      innerPath: 'nested',
      parent: panel,
    );
    final original = storageReferenceForClient(client);
    expect(identical(storageReferenceForSource(panel), original), isTrue);
    expect(identical(storageReferenceForSource(archive), original), isTrue);
    expect(
      identical(
        storageReferenceForSource(panel.withPath('/elsewhere')),
        original,
      ),
      isTrue,
    );
    client.root = '/new-root';
    expect(
      storageReferenceForSource(archive).toJson(),
      _expected(client).toJson(),
    );
    expect(storageReferenceForSource(panel), isNot(original));
  });
}
