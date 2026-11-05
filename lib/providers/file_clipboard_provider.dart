import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/native_file_operations.dart';
import 'native_file_operations_provider.dart';
import 'panel_provider.dart';

class FileClipboardSelection {
  const FileClipboardSelection({
    required this.origin,
    required this.files,
    required this.side,
    required this.cut,
    required this.marker,
    required this.native,
  });
  final PanelFileOrigin origin;
  final List<FileItem> files;
  final PanelSide side;
  final bool cut;
  final String marker;
  final bool native;
}

class FileClipboardNotifier extends ChangeNotifier {
  FileClipboardSelection? _selection;
  FileClipboardSelection? get selection => _selection;

  Future<void> capture(
    PanelNotifier panel,
    List<FileItem> files,
    NativeFileOperations native, {
    required bool cut,
  }) async {
    final origin = panel.captureOperationOrigin(files);
    final marker = 'crispcloud://file-selection/${const Uuid().v4()}';
    final useNative = origin.source.isLocal && NativeFileOperations.supported;
    if (useNative) {
      await native.writeClipboard(
        files.map((file) => file.path!).toList(),
        cut: cut,
      );
    } else {
      // A token invalidates the app selection if another application changes
      // the clipboard. It contains no account credentials or source paths.
      await Clipboard.setData(ClipboardData(text: marker));
    }
    _selection = FileClipboardSelection(
      origin: origin,
      files: List.unmodifiable(files),
      side: panel.side,
      cut: cut,
      marker: marker,
      native: useNative,
    );
    notifyListeners();
  }

  Future<bool> stillOwnsClipboard(NativeFileOperations native) async {
    final selected = _selection;
    if (selected == null) return false;
    if (selected.native) {
      final current = await native.readClipboard();
      return current != null &&
          current.cut == selected.cut &&
          listEquals(
            current.paths,
            selected.files.map((file) => file.path!).toList(),
          );
    }
    return (await Clipboard.getData('text/plain'))?.text == selected.marker;
  }

  void clear() {
    _selection = null;
    notifyListeners();
  }
}

final fileClipboardProvider = ChangeNotifierProvider<FileClipboardNotifier>((
  ref,
) {
  ref.watch(nativeFileOperationsProvider);
  return FileClipboardNotifier();
});
