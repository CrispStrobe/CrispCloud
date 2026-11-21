// Shows files handed to CrispCloud by other apps (see ExternalOpenService).
//
// "Open with": the active pane moves to the file's folder with the file under
// the cursor and it opens in the normal viewer (F3), so editing, printing and
// copying work as usual. Where the folder itself is not readable (sandboxed
// macOS/iOS grant only the file), the viewer opens the file directly.
//
// Shared files are kept in the app's Received folder, which the active pane
// shows with the files selected, ready to copy to any storage (F5).

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/commander_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/core_providers.dart';
import '../providers/panel_provider.dart';
import '../screens/screen_dialogs.dart';
import '../services/external_open_service.dart';
import '../services/log_service.dart';
import '../services/panel_source_service.dart';
import '../services/storage_identity.dart';
import 'internal_viewer_dialog.dart';

const _log = Log('ExternalOpenHandler');

/// At most this many files open one after another from a single hand-off.
const maxExternalViewerFiles = 8;

class ExternalOpenListener {
  ExternalOpenListener(this._context, this._ref);

  final BuildContext Function() _context;
  final WidgetRef _ref;
  StreamSubscription<ExternalOpenRequest>? _subscription;
  Future<void> _queue = Future.value();

  void start() {
    final service = ExternalOpenService.instance;
    _subscription = service.requests.listen(_enqueue);
    service.takePending().forEach(_enqueue);
    unawaited(service.startPlatformSources());
  }

  void _enqueue(ExternalOpenRequest request) {
    // One hand-off at a time: viewers are modal.
    _queue = _queue.then((_) async {
      final context = _context();
      if (!context.mounted) return;
      try {
        await handleExternalOpen(context, _ref, request);
      } catch (e, st) {
        _log.error('Could not open $request', e, st);
      }
    });
  }

  void dispose() => unawaited(_subscription?.cancel());
}

Future<FileItem?> _localItem(String path) async {
  final stat = await FileStat.stat(path);
  if (stat.type == FileSystemEntityType.notFound) return null;
  return FileItem(
    name: p.basename(path),
    path: path,
    isFolder: stat.type == FileSystemEntityType.directory,
    size: stat.type == FileSystemEntityType.file ? stat.size : null,
    updatedAt: stat.modified,
  );
}

/// Moves [side]'s pane to [folder] (a local path) without ever opening a
/// folder-access prompt. Returns false where the folder cannot be listed.
Future<bool> _showLocalFolder(
  WidgetRef ref,
  PanelSide side,
  String folder, {
  FileItem? select,
}) async {
  final panel = ref.read(panelProvider(side));
  if (!await ref.read(localFileServiceProvider).hasAccessToPath(folder)) {
    return false;
  }
  final origin = panel.resolveStorageReference(
    storageReferenceForSource(LocalPanelSource(folder)),
    folder,
  );
  if (origin == null || !origin.isCurrent) return false;
  try {
    await panel.navigateToPath(
      folder,
      origin: origin,
      selectItem: select,
      allowAccessRequests: false,
    );
  } catch (_) {
    return false;
  }
  return p.equals(panel.currentPath, folder) &&
      (panel.directorySource?.isLocal ?? false);
}

Future<void> handleExternalOpen(
  BuildContext context,
  WidgetRef ref,
  ExternalOpenRequest request,
) async {
  final side = ref.read(activePanelProvider);
  if (request.reveal) {
    final first = request.paths.first;
    final folder = p.dirname(first);
    final wanted = request.paths.map(p.basename).toSet();
    if (await _showLocalFolder(ref, side, folder)) {
      final panel = ref.read(panelProvider(side));
      for (final item in panel.files ?? const <FileItem>[]) {
        if (wanted.contains(item.name)) {
          panel.toggleSelection(item, ctrlKey: true);
        }
      }
    }
    return;
  }
  if (request.shared) {
    final service = ExternalOpenService.instance;
    final folder = await service.keepReceived(request.paths);
    await service.removeHandOff(request.cleanup);
    if (request.deleteSources) {
      for (final path in request.paths) {
        await service.removeHandOff(path);
      }
    }
    if (!context.mounted) return;
    final names = Directory(folder)
        .listSync()
        .map((e) => p.basename(e.path))
        .toSet();
    final shown = await _showLocalFolder(ref, side, folder);
    if (shown) {
      final panel = ref.read(panelProvider(side));
      for (final item in panel.files ?? const <FileItem>[]) {
        if (names.contains(item.name)) {
          panel.toggleSelection(item, ctrlKey: true);
        }
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.commanderTr(
              '{0} received file(s) are in the Received folder. Copy them to any storage with F5.',
              [names.length],
            ),
          ),
        ),
      );
    }
    return;
  }

  var opened = 0;
  for (final path in request.paths) {
    if (!context.mounted || opened >= maxExternalViewerFiles) return;
    final item = await _localItem(path);
    if (item == null || !context.mounted) continue;
    if (item.isFolder) {
      await _showLocalFolder(ref, side, path);
      continue;
    }
    opened++;
    final parent = p.dirname(path);
    if (await _showLocalFolder(ref, side, parent, select: item)) {
      final panel = ref.read(panelProvider(side));
      if (panel.cursorItem?.name == item.name && context.mounted) {
        await viewSelectedFileAndWait(context, ref);
        continue;
      }
    }
    if (!context.mounted) return;
    // Only the file itself is accessible: open it without its folder.
    await showInternalViewer(
      context,
      file: item,
      side: side,
      origin: ref.read(panelProvider(side)).captureLocalClipboardOrigin(parent),
      displayName: item.name,
    );
  }
}
