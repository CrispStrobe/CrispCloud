import 'package:crisp_storage/crisp_storage.dart' show TransferResourceClaim;

import 'file_operation_service.dart';
import 'storage_transfer_contract.dart';

final _sessionProviderKeys = <Object, String>{};
int _nextSessionProviderKey = 0;

/// Both ends consume provider capacity, even when the destination is local.
/// Authentication objects and display labels are never used as account keys.
Set<String> transferProviderNames(FileOperationPlan plan) => {
  _providerKey(plan.source),
  _providerKey(plan.destination),
};

String _providerKey(FileOperationBackend backend) {
  final persistent = backend.persistentStorageId;
  if (persistent != null) return persistent;
  final identity = backend.identity;
  if (identity is String) return identity;
  return _sessionProviderKeys.putIfAbsent(
    identity,
    () => 'transfer-session-${_nextSessionProviderKey++}',
  );
}

/// Reserve the read/write footprint of a reviewed plan for its entire run.
///
/// A destination directory is exclusive because keep-both, staging and backup
/// names can be selected after review. Source directories reserve descendants;
/// moves also reserve their source paths for deletion and metadata cleanup.
/// The scheduler keeps these claims until asynchronous finalization settles.
List<TransferResourceClaim> transferResourceClaims(FileOperationPlan plan) {
  final namespaces = <Object, _ClaimNode>{};

  void add(FileOperationBackend backend, String path, {required bool write}) {
    var key = backend.destinationPathKey(path);
    // Read-only wrappers may delegate pathKey rather than destinationPathKey.
    // Unknown case semantics are reserved conservatively, like cloud writes.
    if (backend.capabilities.caseSensitivity !=
        StorageCaseSensitivity.sensitive) {
      key = key.toLowerCase();
    }
    final segments = backend.paths.split(key);
    var node = namespaces.putIfAbsent(
      backend.persistentStorageId ?? backend.identity,
      _ClaimNode.new,
    );
    for (final segment in segments) {
      if (node.write || (!write && node.read)) return;
      node = node.children.putIfAbsent(segment, _ClaimNode.new);
    }
    if (write) {
      node.write = true;
      node.read = false;
      node.children.clear();
    } else if (!node.write) {
      node.read = true;
    }
  }

  final moving = plan.options.kind == FileOperationKind.move;
  add(plan.destination, plan.targetDirectory, write: true);
  for (final entry in plan.entries) {
    // Completed directories can still require metadata and empty-directory
    // cleanup, and recovered entries can finish publication without copying.
    // Retaining all reviewed roots is deliberately conservative.
    final sourcePath = entry.source.path;
    if (sourcePath != null) add(plan.source, sourcePath, write: moving);
    add(plan.destination, entry.destination, write: true);
    final existingPath = entry.existing?.path;
    if (existingPath != null) add(plan.destination, existingPath, write: true);
    for (final field in const [
      'stagedPath',
      'stagingPath',
      'stagingDirectory',
      'backupPath',
      'renamedExistingPath',
      'resumeStagePath',
      'resumeUploadPath',
    ]) {
      final path = entry.recovery?[field];
      if (path is String && path.isNotEmpty) {
        add(plan.destination, path, write: true);
      }
    }
  }
  for (final path in plan.protectedDestinationPaths) {
    add(plan.destination, path, write: moving);
  }

  final claims = <TransferResourceClaim>[];
  void collect(
    Object namespace,
    _ClaimNode node,
    List<String> segments, {
    bool ancestorRead = false,
  }) {
    if (node.write || node.read && !ancestorRead) {
      claims.add(
        TransferResourceClaim(
          namespace: namespace,
          pathSegments: segments,
          write: node.write,
        ),
      );
    }
    if (node.write) return;
    for (final child in node.children.entries) {
      collect(namespace, child.value, [
        ...segments,
        child.key,
      ], ancestorRead: ancestorRead || node.read);
    }
  }

  for (final root in namespaces.entries) {
    collect(root.key, root.value, const []);
  }
  return List.unmodifiable(claims);
}

class _ClaimNode {
  bool read = false;
  bool write = false;
  final children = <String, _ClaimNode>{};
}
