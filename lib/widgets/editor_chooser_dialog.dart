import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../services/editor_kind.dart';
import '../utils/file_editability.dart';
import 'file_context_menu.dart' show openListedFileWithSystemEditor;
import 'file_editor_dialog.dart' show showFileEditorDialog;
import 'hex_editor_dialog.dart' show showHexEditorDialog;

/// F4 opens the default editor. Shift+F4 (or the context menu) opens this
/// chooser so the same file can be inspected in text/code or raw hex.
Future<void> showEditorChooser(
  BuildContext context,
  WidgetRef ref,
  FileItem file,
  PanelSide side,
) async {
  if (file.isFolder) return;
  final canUseText = isTextEditableName(file.name);
  final canUseSystem = !kIsWeb && file.path != null;
  final choice = await showDialog<EditorKind>(
    context: context,
    builder: (dialogContext) => SimpleDialog(
      title: const Text('Open with…'),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(dialogContext).textTheme.bodySmall,
          ),
        ),
        if (canUseText)
          _option(
            dialogContext,
            icon: Icons.code,
            title: 'Text / Code Editor',
            subtitle: 'Encoding, BOM and line-ending controls with syntax highlighting',
            value: EditorKind.text,
          ),
        _option(
          dialogContext,
          icon: Icons.hexagon_outlined,
          title: 'Hex Editor',
          subtitle: 'Inspect and edit raw bytes, including CR/LF characters',
          value: EditorKind.hex,
        ),
        if (canUseSystem)
          _option(
            dialogContext,
            icon: Icons.open_in_new,
            title: 'System Editor',
            subtitle: 'Open with the default application for this file type',
            value: EditorKind.system,
          ),
      ],
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case EditorKind.text:
      await showFileEditorDialog(context, ref, file, side, forceText: true);
    case EditorKind.hex:
      await showHexEditorDialog(context, ref, file, side);
    case EditorKind.system:
      await openListedFileWithSystemEditor(context, ref, file);
  }
}

Widget _option(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String subtitle,
  required EditorKind value,
}) {
  return SimpleDialogOption(
    onPressed: () => Navigator.of(context).pop(value),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}
