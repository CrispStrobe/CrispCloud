import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/storage_reference.dart';
import 'cloud_storage_interface.dart';
import 'panel_source_service.dart';

final _anonymousSessions = Expando<String>('unidentified storage session');
int _nextAnonymousSession = 0;

StorageReference storageReferenceForSource(PanelSource source) {
  if (source is LocalPanelSource) {
    return StorageReference(
      kind: 'local',
      provider: kIsWeb ? 'browser' : defaultTargetPlatform.name,
      accountKey: 'device',
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
  final user = client.userId;
  final namespace = client is StorageNamespaceIdentity
      ? (client as StorageNamespaceIdentity).storageNamespace
      : client.rootPath;
  final persistent = user != null && user.isNotEmpty;
  final account = persistent
      ? user
      : (_anonymousSessions[client] ??=
            '${DateTime.now().microsecondsSinceEpoch}-${_nextAnonymousSession++}');
  final digest = sha256
      .convert(
        utf8.encode(
          jsonEncode([
            client.providerName,
            account,
            client.bucketId,
            namespace,
            client.rootPath,
          ]),
        ),
      )
      .toString();
  return StorageReference(
    kind: 'remote',
    provider: client.providerName,
    accountKey: digest,
    root: client.rootPath,
    persistent: persistent,
  );
}
