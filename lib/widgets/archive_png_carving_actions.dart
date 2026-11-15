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
import 'archive_png_carving_dialog.dart';

bool isArchivePngCarvingSelection(List<FileItem> files) =>
    !kIsWeb &&
    files.length == 1 &&
    !files.single.isFolder &&
    files.single.isSymlink != true &&
    files.single.path != null &&
    files.single.size != null &&
    files.single.size! >= 0 &&
    files.single.size! <= 64 * 1024 * 1024;

List<FileItem> _selected(WidgetRef ref, PanelSide side) {
  final panel = ref.read(panelProvider(side));
  return panel.selection.isNotEmpty
      ? panel.selection.toList(growable: false)
      : [if (panel.cursorItem case final file? when file.name != '..') file];
}

bool canCarveArchivePngSelection(WidgetRef ref) {
  if (kIsWeb) return false;
  final side = ref.read(activePanelProvider);
  final panel = ref.read(panelProvider(side));
  final files = _selected(ref, side);
  if (panel.isInArchive || !isArchivePngCarvingSelection(files)) return false;
  try {
    return panel.captureOperationOrigin(files).source is LocalPanelSource;
  } catch (_) {
    return false;
  }
}

Future<void> showArchivePngCarvingForSelection(
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
    if (!isArchivePngCarvingSelection(selected) ||
        !origin.isCurrent ||
        origin.source is! LocalPanelSource) {
      throw StateError(
        'Select one local regular file of at most 64 MiB for PNG carving.',
      );
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
      builder: (_) => ArchivePngCarvingDialog(
        source: backend,
        file: selected.single,
        destination: backend,
        destinationDirectory: destinationDirectory,
        enqueue: (captured, name, offsets) =>
            transfers.enqueueArchivePngCarving(
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
