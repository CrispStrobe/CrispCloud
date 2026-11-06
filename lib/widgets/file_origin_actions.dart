import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/cloud_storage_interface.dart';
import '../services/panel_source_service.dart';
import '../services/local_file_service.dart';

/// Capture a listed row once. A missing row never falls back to whichever cloud
/// account happens to be selected when a delayed menu callback runs.
PanelFileOrigin captureFileActionOrigin(
  WidgetRef ref,
  FileItem file, {
  PanelFileOrigin? sourceOrigin,
}) {
  if (sourceOrigin != null) {
    if (!sourceOrigin.isCurrent ||
        (file.storageId != null && file.storageId != sourceOrigin.storageId)) {
      throw StateError('The original file account is unavailable.');
    }
    return sourceOrigin;
  }
  for (final side in PanelSide.values) {
    final origin = ref.read(panelProvider(side)).originForOperation(file);
    if (origin != null && origin.isCurrent) return origin;
  }
  throw StateError('Refresh or reopen this file from its original account.');
}

/// Every request checks the captured session, including follow-up writes after
/// an awaited permission, version or metadata read.
CloudStorageClient capturedRemoteClient(PanelFileOrigin origin) {
  if (!origin.isCurrent) {
    throw StateError('The original file account is no longer connected.');
  }
  final source = origin.source;
  if (source is! RemotePanelSource) {
    throw UnsupportedError('This operation requires a cloud file.');
  }
  return source.client;
}

String requireFilePath(FileItem file) {
  final path = file.path;
  if (path == null || path.isEmpty) {
    throw StateError(
      'The original file path is unavailable. Refresh the folder.',
    );
  }
  return path;
}

String requireFileId(FileItem file) {
  final id = file.uuid;
  if (id == null || id.isEmpty) {
    throw StateError(
      'The original file identity is unavailable. Refresh the folder.',
    );
  }
  return id;
}

void requireCurrentOrigin(PanelFileOrigin origin) {
  if (!origin.isCurrent) {
    throw StateError('The original file account is no longer connected.');
  }
}

/// Desktop path-only APIs are valid only for captured local rows. Access
/// scopes remain open until the complete operation (including its awaits) ends.
Future<T> withNativeFileAction<T>(
  WidgetRef ref,
  PanelFileOrigin origin,
  Iterable<String> paths,
  Future<T> Function() action,
) async {
  requireCurrentOrigin(origin);
  if (origin.source is! LocalPanelSource) {
    throw UnsupportedError('This operation requires a local file.');
  }
  final local = ref.read(localFileServiceProvider);
  final scopes = paths.toSet().toList();
  Future<T> run(int index) async {
    requireCurrentOrigin(origin);
    if (index == scopes.length) return action();
    return local.withFileOperationAccess(scopes[index], () => run(index + 1));
  }

  return run(0);
}
