import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as path;

import '../services/action_history_service.dart';
import 'command_strings.dart';

/// Presents action-history records and structured undo results in the UI locale.
class UndoPresentation {
  UndoPresentation(BuildContext context) : _strings = CommandStrings(context);
  final CommandStrings _strings;

  String description(ActionRecord action) {
    final name = path.basename(action.originalPath);
    return switch (action.type) {
      ActionType.delete => _strings.text('deleted', {'name': name}),
      ActionType.rename => _strings.text('renamed', {
          'old': name,
          'new': action.newPath == null ? '?' : path.basename(action.newPath!),
        }),
      ActionType.move => _strings.text('moved', {'name': name}),
      ActionType.copy => _strings.text('copied', {'name': name}),
      ActionType.createFolder => _strings.text('createdFolder', {'name': name}),
    };
  }

  String result(UndoResult result) => result.code == null
      ? result.message
      : _strings.text(result.code!.name, result.arguments);
}
