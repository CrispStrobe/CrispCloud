import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'installation_identity.dart';
import 'panel_source_service.dart';

final _anonymousSessions = Expando<String>('unidentified storage session');
final _clientReferences = Expando<_ClientStorageReference>(
  'derived storage reference',
);
int _nextAnonymousSession = 0;

StorageReference storageReferenceForSource(PanelSource source) {
  if (source is LocalPanelSource) {
    final installation = InstallationIdentityService.instance.current;
    return StorageReference(
      kind: 'local',
      provider: kIsWeb ? 'browser' : defaultTargetPlatform.name,
      accountKey: installation.key,
      persistent: installation.persistent,
    );
  }
  if (source is RemotePanelSource) {
    return storageReferenceForClient(source.client);
  }
  if (source is ArchivePanelSource) {
    return storageReferenceForSource(source.parent);
  }
  throw UnsupportedError('This storage has no persistent file identity.');
}

StorageReference storageReferenceForClient(CloudStorageClient client) {
  // Always read the live identity inputs, including wrapper namespaces. Only
  // their derived digest/reference is cached; authentication and source/grant
  // validation remain live in the callers which own that authority.
  final user = client.userId;
  final provider = client.providerName;
  final bucket = client.bucketId;
  final root = client.rootPath;
  final namespace = client is StorageNamespaceIdentity
      ? (client as StorageNamespaceIdentity).storageNamespace
      : root;
  final persistent = user != null && user.isNotEmpty;
  final account = persistent
      ? user
      : (_anonymousSessions[client] ??=
            '${DateTime.now().microsecondsSinceEpoch}-${_nextAnonymousSession++}');
  final previous = _clientReferences[client];
  if (previous != null &&
      previous.provider == provider &&
      previous.account == account &&
      previous.bucket == bucket &&
      previous.namespace == namespace &&
      previous.root == root &&
      previous.persistent == persistent) {
    return previous.reference;
  }
  final digest = sha256
      .convert(
        utf8.encode(jsonEncode([provider, account, bucket, namespace, root])),
      )
      .toString();
  final reference = StorageReference(
    kind: 'remote',
    provider: provider,
    accountKey: digest,
    root: root,
    persistent: persistent,
  );
  // Expando keys are weak and identity-based. The value contains only existing
  // non-secret identity fields and the derived reference, never the client,
  // credentials, or a grant. Equivalent clients retain independent cache slots.
  _clientReferences[client] = _ClientStorageReference(
    provider: provider,
    account: account,
    bucket: bucket,
    namespace: namespace,
    root: root,
    persistent: persistent,
    reference: reference,
  );
  return reference;
}

class _ClientStorageReference {
  const _ClientStorageReference({
    required this.provider,
    required this.account,
    required this.bucket,
    required this.namespace,
    required this.root,
    required this.persistent,
    required this.reference,
  });

  final String provider;
  final String? account;
  final String? bucket;
  final String namespace;
  final String root;
  final bool persistent;
  final StorageReference reference;
}
