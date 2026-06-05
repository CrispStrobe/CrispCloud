// lib/services/fkey_action_service.dart
//
// F-key action service for the dual-panel orthodox file manager.
// Handles F3 View, F4 Edit, F5 Copy, F6 Move, F7 MkDir, F8 Delete.

import '../models/file_item.dart';
import 'panel_source_service.dart';

// ---------------------------------------------------------------------------
// FKeyAction enum
// ---------------------------------------------------------------------------

enum FKeyAction {
  /// F3 — open the selected file in the internal viewer.
  view,

  /// F4 — open the selected file in the internal/external editor.
  edit,

  /// F5 — copy selected files from active panel to opposite panel.
  copy,

  /// F6 — move selected files from active panel to opposite panel.
  move,

  /// F7 — create a new directory in the active panel.
  mkdir,

  /// F8 — delete selected files from the active panel.
  delete,
}

// ---------------------------------------------------------------------------
// FKeyContext — lightweight descriptor of the current UI state
// ---------------------------------------------------------------------------

/// All information the service needs to decide availability and dispatch.
class FKeyContext {
  /// The panel that has keyboard focus.
  final PanelSource activePanel;

  /// The other panel (destination for copy/move).
  final PanelSource oppositePanel;

  /// Files currently selected in the active panel.
  final List<FileItem> selectedFiles;

  const FKeyContext({
    required this.activePanel,
    required this.oppositePanel,
    required this.selectedFiles,
  });

  bool get hasSelection => selectedFiles.isNotEmpty;

  /// True when exactly one non-folder file is selected.
  bool get hasSingleFile =>
      selectedFiles.length == 1 && !selectedFiles.first.isFolder;
}

// ---------------------------------------------------------------------------
// FKeyActionResult — outcome of executeAction
// ---------------------------------------------------------------------------

/// Describes what should happen next after the service resolves an action.
sealed class FKeyActionResult {
  const FKeyActionResult();
}

/// The action completed successfully without needing further UI interaction.
class FKeySuccess extends FKeyActionResult {
  final String message;
  const FKeySuccess(this.message);
}

/// The action requires a text prompt (e.g. directory name for F7).
class FKeyNeedsPrompt extends FKeyActionResult {
  final String title;
  final String hint;

  /// Call this with the user's input to complete the action.
  final Future<FKeyActionResult> Function(String input) onConfirm;

  const FKeyNeedsPrompt({
    required this.title,
    required this.hint,
    required this.onConfirm,
  });
}

/// The action requires a yes/no confirmation (e.g. F8 delete).
class FKeyNeedsConfirm extends FKeyActionResult {
  final String message;
  final Future<FKeyActionResult> Function() onConfirm;
  final FKeyActionResult Function() onCancel;

  const FKeyNeedsConfirm({
    required this.message,
    required this.onConfirm,
    required this.onCancel,
  });
}

/// The action opens the internal file viewer.
class FKeyOpenViewer extends FKeyActionResult {
  final FileItem file;
  final PanelSource source;
  const FKeyOpenViewer(this.file, this.source);
}

/// The action opens the internal/external editor.
class FKeyOpenEditor extends FKeyActionResult {
  final FileItem file;
  final PanelSource source;
  const FKeyOpenEditor(this.file, this.source);
}

/// The action failed.
class FKeyError extends FKeyActionResult {
  final String message;
  const FKeyError(this.message);
}

/// The action was cancelled (e.g. user dismissed a confirm dialog).
class FKeyCancelled extends FKeyActionResult {
  const FKeyCancelled();
}

// ---------------------------------------------------------------------------
// FKeyActionService
// ---------------------------------------------------------------------------

class FKeyActionService {
  const FKeyActionService();

  // ---- Labels and shortcuts -------------------------------------------------

  /// Human-readable action label shown in the F-key bar.
  String getActionLabel(FKeyAction action) {
    return switch (action) {
      FKeyAction.view => 'View',
      FKeyAction.edit => 'Edit',
      FKeyAction.copy => 'Copy',
      FKeyAction.move => 'Move',
      FKeyAction.mkdir => 'MkDir',
      FKeyAction.delete => 'Delete',
    };
  }

  /// Display string for the keyboard shortcut (F3–F8).
  String getActionShortcut(FKeyAction action) {
    return switch (action) {
      FKeyAction.view => 'F3',
      FKeyAction.edit => 'F4',
      FKeyAction.copy => 'F5',
      FKeyAction.move => 'F6',
      FKeyAction.mkdir => 'F7',
      FKeyAction.delete => 'F8',
    };
  }

  /// F-key number (3–8).
  int getFKeyNumber(FKeyAction action) {
    return switch (action) {
      FKeyAction.view => 3,
      FKeyAction.edit => 4,
      FKeyAction.copy => 5,
      FKeyAction.move => 6,
      FKeyAction.mkdir => 7,
      FKeyAction.delete => 8,
    };
  }

  // ---- Context-aware availability -------------------------------------------

  /// Returns true when [action] is available in the current [context].
  bool isActionAvailable(FKeyAction action, FKeyContext context) {
    return switch (action) {
      // View / Edit require exactly one non-folder file.
      FKeyAction.view => context.hasSingleFile,
      FKeyAction.edit => context.hasSingleFile,

      // Copy / Move / Delete require at least one selected file.
      FKeyAction.copy => context.hasSelection,
      FKeyAction.move => context.hasSelection,
      FKeyAction.delete => context.hasSelection,

      // MkDir is always available (creates in active panel).
      FKeyAction.mkdir => true,
    };
  }

  // ---- Dispatch -------------------------------------------------------------

  /// Resolve [action] in [context].
  ///
  /// Returns a [FKeyActionResult] that the UI layer should handle:
  /// - [FKeySuccess] — display a snackbar / no further action needed.
  /// - [FKeyNeedsPrompt] — show a text-input dialog, then call [onConfirm].
  /// - [FKeyNeedsConfirm] — show a yes/no dialog, then call [onConfirm].
  /// - [FKeyOpenViewer] — push the viewer route.
  /// - [FKeyOpenEditor] — push the editor route.
  /// - [FKeyError] — show an error message.
  FKeyActionResult executeAction(
    FKeyAction action,
    FKeyContext context,
  ) {
    if (!isActionAvailable(action, context)) {
      return FKeyError(
        '${getActionLabel(action)} is not available: no files selected.',
      );
    }

    return switch (action) {
      FKeyAction.view => _handleView(context),
      FKeyAction.edit => _handleEdit(context),
      FKeyAction.copy => _handleCopy(context),
      FKeyAction.move => _handleMove(context),
      FKeyAction.mkdir => _handleMkDir(context),
      FKeyAction.delete => _handleDelete(context),
    };
  }

  // ---- F3 View --------------------------------------------------------------

  FKeyActionResult _handleView(FKeyContext context) {
    final file = context.selectedFiles.first;
    return FKeyOpenViewer(file, context.activePanel);
  }

  // ---- F4 Edit --------------------------------------------------------------

  FKeyActionResult _handleEdit(FKeyContext context) {
    final file = context.selectedFiles.first;
    return FKeyOpenEditor(file, context.activePanel);
  }

  // ---- F5 Copy --------------------------------------------------------------

  FKeyActionResult _handleCopy(FKeyContext context) {
    final files = List<FileItem>.unmodifiable(context.selectedFiles);
    final destination = context.oppositePanel;
    final destDesc = destination.displayName;
    final count = files.length;
    final noun = count == 1 ? 'file' : 'files';

    return FKeyNeedsConfirm(
      message: 'Copy $count $noun to "$destDesc"?',
      onConfirm: () async {
        // In a full implementation: delegate to TransferService.
        // Here we return success so that the UI layer can trigger the real
        // copy logic via panel_provider / transfer_provider.
        return FKeySuccess('Copying $count $noun to $destDesc');
      },
      onCancel: () => const FKeyCancelled(),
    );
  }

  // ---- F6 Move --------------------------------------------------------------

  FKeyActionResult _handleMove(FKeyContext context) {
    final files = List<FileItem>.unmodifiable(context.selectedFiles);
    final destination = context.oppositePanel;
    final destDesc = destination.displayName;
    final count = files.length;
    final noun = count == 1 ? 'file' : 'files';

    return FKeyNeedsConfirm(
      message: 'Move $count $noun to "$destDesc"?',
      onConfirm: () async {
        // Move = copy + delete source.  Delegate to transfer_provider.
        return FKeySuccess('Moving $count $noun to $destDesc');
      },
      onCancel: () => const FKeyCancelled(),
    );
  }

  // ---- F7 MkDir -------------------------------------------------------------

  FKeyActionResult _handleMkDir(FKeyContext context) {
    return FKeyNeedsPrompt(
      title: 'Create directory',
      hint: 'New folder name',
      onConfirm: (name) async {
        if (name.trim().isEmpty) {
          return const FKeyError('Directory name cannot be empty.');
        }
        // Delegate to panel_provider.createFolder in the UI layer.
        return FKeySuccess('Directory "$name" created');
      },
    );
  }

  // ---- F8 Delete ------------------------------------------------------------

  FKeyActionResult _handleDelete(FKeyContext context) {
    final files = List<FileItem>.unmodifiable(context.selectedFiles);
    final count = files.length;
    final noun = count == 1 ? 'file' : 'files';
    final names = count <= 3
        ? files.map((f) => f.name).join(', ')
        : '${files.take(3).map((f) => f.name).join(', ')} … (+${count - 3} more)';

    return FKeyNeedsConfirm(
      message: 'Delete $count $noun?\n$names',
      onConfirm: () async {
        // Delegate to panel_provider.deleteFiles in the UI layer.
        return FKeySuccess('Deleted $count $noun');
      },
      onCancel: () => const FKeyCancelled(),
    );
  }

  // ---- Copy direction helper ------------------------------------------------

  /// Returns a human-readable description of the copy direction.
  String copyDirectionLabel(FKeyContext context) {
    return '${context.activePanel.displayName} → ${context.oppositePanel.displayName}';
  }
}
