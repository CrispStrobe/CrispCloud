// Copyright (c) 2026 CrispCloud contributors
// SPDX-License-Identifier: MIT
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/archive_creation_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/providers.dart';
import '../services/file_operation_backend.dart';
import '../services/panel_source_service.dart';
import 'archive_jobs_dialog.dart';
import 'archive_zip_recovery_dialog.dart';

bool isArchiveZipRecoverySelection(List<FileItem> files) =>
    !kIsWeb &&
    files.length == 1 &&
    !files.single.isFolder &&
    files.single.isSymlink != true &&
    files.single.path != null &&
    const ['zip', 'cbz'].contains(files.single.extension);

List<FileItem> _selected(WidgetRef ref, PanelSide side) {
  final panel = ref.read(panelProvider(side));
  return panel.selection.isNotEmpty
      ? panel.selection.toList(growable: false)
      : [if (panel.cursorItem case final file? when file.name != '..') file];
}

bool canRecoverArchiveZipSelection(WidgetRef ref) {
  if (kIsWeb) return false;
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  final files = _selected(ref, side);
  if (panel.isInArchive || !isArchiveZipRecoverySelection(files)) return false;
  try {
    return panel.captureOperationOrigin(files).source is LocalPanelSource;
  } catch (_) {
    return false;
  }
}

Future<void> showArchiveZipRecoveryForSelection(
  BuildContext context,
  WidgetRef ref, {
  PanelSide? side,
  List<FileItem>? files,
  PanelFileOrigin? sourceOrigin,
}) async {
  if (kIsWeb) return;
  try {
    final PanelSide selectedSide = side ?? ref.read(activePanelProvider);
    final panel = ref.read(panelProvider(selectedSide));
    final selected = List<FileItem>.unmodifiable(
      files ?? _selected(ref, selectedSide),
    );
    final origin = sourceOrigin ?? panel.captureOperationOrigin(selected);
    if (!isArchiveZipRecoverySelection(selected) ||
        !origin.isCurrent ||
        origin.source is! LocalPanelSource) {
      throw StateError('Select one local ZIP or CBZ file for recovery.');
    }
    final backend = fileOperationBackend(
      source: origin.source,
      local: ref.read(localFileServiceProvider),
      isCurrent: () => origin.isCurrent,
    );
    final destinationDirectory = backend.paths.dirname(selected.single.path!);
    final transfers = ref.read(transferProvider);
    final rememberSelection = panel.captureSelectionMemoryForOperation(
      selected,
    );
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ArchiveZipRecoveryDialog(
        source: backend,
        file: selected.single,
        destination: backend,
        destinationDirectory: destinationDirectory,
        enqueue: (captured, name, offsets) =>
            transfers.enqueueArchiveZipRecovery(
              captured: captured,
              destination: backend,
              destinationDirectory: destinationDirectory,
              outputName: name,
              selectedOffsets: offsets,
              onPublished: rememberSelection,
            ),
        onViewJobs: () => showArchiveJobsDialog(context, ref),
      ),
    );
    if (context.mounted) await ref.read(panelProvider(selectedSide)).refresh();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(archiveCreationError(context, error))),
      );
    }
  }
}
