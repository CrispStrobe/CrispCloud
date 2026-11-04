/// Transactional undo/redo with invert-able deltas.
abstract class OfficeCommand {
  /// execute API.
  void execute();

  /// undo API.
  void undo();

  /// invert API.
  OfficeCommand invert();
}

/// Class CommandPipeline.
class CommandPipeline {
  /// CommandPipeline API.
  CommandPipeline({this.capacity = 200});

  /// capacity API.
  final int capacity;
  final List<OfficeCommand> _undo = <OfficeCommand>[];
  final List<OfficeCommand> _redo = <OfficeCommand>[];
  final List<OfficeCommand> _batch = <OfficeCommand>[];

  /// Function API.
  final List<void Function()> _listeners = <void Function()>[];
  var _batching = false;

  /// canUndo API.
  bool get canUndo => _undo.isNotEmpty;

  /// canRedo API.
  bool get canRedo => _redo.isNotEmpty;

  /// addListener API.
  void addListener(void Function() listener) => _listeners.add(listener);

  /// removeListener API.
  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final void Function() listener in List<void Function()>.of(
      _listeners,
    )) {
      listener();
    }
  }

  /// beginBatch API.
  void beginBatch() {
    _batching = true;
    _batch.clear();
  }

  /// endBatch API.
  void endBatch() {
    _batching = false;
    if (_batch.isEmpty) {
      return;
    }
    final CompositeCommand composite = CompositeCommand(
      List<OfficeCommand>.from(_batch),
    );
    _batch.clear();
    _undo.add(composite);
    if (_undo.length > capacity) {
      _undo.removeAt(0);
    }
    _redo.clear();
    _notify();
  }

  /// commit API.
  void commit(OfficeCommand command) {
    if (_batching) {
      _batch.add(command);
      command.execute();
      return;
    }
    command.execute();
    _undo.add(command);
    if (_undo.length > capacity) {
      _undo.removeAt(0);
    }
    _redo.clear();
    _notify();
  }

  /// undo API.
  void undo() {
    if (_undo.isEmpty) {
      return;
    }
    final OfficeCommand cmd = _undo.removeLast();
    cmd.undo();
    _redo.add(cmd);
    _notify();
  }

  /// redo API.
  void redo() {
    if (_redo.isEmpty) {
      return;
    }
    final OfficeCommand cmd = _redo.removeLast();
    cmd.execute();
    _undo.add(cmd);
    _notify();
  }
}

/// Class CompositeCommand.
class CompositeCommand implements OfficeCommand {
  /// CompositeCommand API.
  CompositeCommand(this.commands);

  /// commands API.
  final List<OfficeCommand> commands;

  @override
  /// execute API.
  void execute() {
    for (final OfficeCommand c in commands) {
      c.execute();
    }
  }

  @override
  /// undo API.
  void undo() {
    for (final OfficeCommand c in commands.reversed) {
      c.undo();
    }
  }

  @override
  /// invert API.
  OfficeCommand invert() =>
      CompositeCommand(commands.reversed.map((c) => c.invert()).toList());
}

/// Class InsertTextDelta.
class InsertTextDelta implements OfficeCommand {
  /// InsertTextDelta API.
  InsertTextDelta({
    required this.getText,
    required this.setText,
    required this.index,
    required this.text,
  });

  /// Function API.
  final String Function() getText;

  /// Function API.
  final void Function(String value) setText;

  /// index API.
  final int index;

  /// text API.
  final String text;

  @override
  /// execute API.
  void execute() {
    final String cur = getText();
    final int i = index.clamp(0, cur.length);
    setText(cur.replaceRange(i, i, text));
  }

  @override
  /// undo API.
  void undo() {
    final String cur = getText();
    final int i = index.clamp(0, cur.length);
    final int end = (i + text.length).clamp(0, cur.length);
    setText(cur.replaceRange(i, end, ''));
  }

  @override
  /// invert API.
  OfficeCommand invert() => DeleteTextDelta(
    getText: getText,
    setText: setText,
    index: index,
    length: text.length,
  );
}

/// Class DeleteTextDelta.
class DeleteTextDelta implements OfficeCommand {
  /// DeleteTextDelta API.
  DeleteTextDelta({
    required this.getText,
    required this.setText,
    required this.index,
    required this.length,
  });

  /// Function API.
  final String Function() getText;

  /// Function API.
  final void Function(String value) setText;

  /// index API.
  final int index;

  /// length API.
  final int length;
  String _deleted = '';

  @override
  /// execute API.
  void execute() {
    final String cur = getText();
    final int i = index.clamp(0, cur.length);
    final int end = (i + length).clamp(0, cur.length);
    _deleted = cur.substring(i, end);
    setText(cur.replaceRange(i, end, ''));
  }

  @override
  /// undo API.
  void undo() {
    final String cur = getText();
    final int i = index.clamp(0, cur.length);
    setText(cur.replaceRange(i, i, _deleted));
  }

  @override
  /// invert API.
  OfficeCommand invert() => InsertTextDelta(
    getText: getText,
    setText: setText,
    index: index,
    text: _deleted,
  );
}

/// Class UpdateCellDelta.
class UpdateCellDelta implements OfficeCommand {
  /// UpdateCellDelta API.
  UpdateCellDelta({
    required this.read,
    required this.write,
    required this.next,
  });

  /// Function API.
  final Object? Function() read;

  /// Function API.
  final void Function(Object? value) write;

  /// next API.
  final Object? next;
  Object? _prev;

  @override
  /// execute API.
  void execute() {
    _prev = read();
    write(next);
  }

  @override
  /// undo API.
  void undo() => write(_prev);

  @override
  /// invert API.
  OfficeCommand invert() =>
      UpdateCellDelta(read: read, write: write, next: _prev);
}

/// Class FormatRangeDelta.
class FormatRangeDelta implements OfficeCommand {
  /// FormatRangeDelta API.
  FormatRangeDelta({required this.apply, required this.revert});

  /// Function API.
  final void Function() apply;

  /// Function API.
  final void Function() revert;

  @override
  /// execute API.
  void execute() => apply();

  @override
  /// undo API.
  void undo() => revert();

  @override
  /// invert API.
  OfficeCommand invert() => FormatRangeDelta(apply: revert, revert: apply);
}

/// Class TransformShapeDelta.
class TransformShapeDelta implements OfficeCommand {
  /// TransformShapeDelta API.
  TransformShapeDelta({
    required this.read,
    required this.write,
    required this.next,
  });

  /// Function API.
  final List<int> Function() read;

  /// Function API.
  final void Function(List<int> v) write;

  /// next API.
  final List<int> next;
  List<int> _prev = const <int>[];

  @override
  /// execute API.
  void execute() {
    _prev = read();
    write(next);
  }

  @override
  /// undo API.
  void undo() => write(_prev);

  @override
  /// invert API.
  OfficeCommand invert() =>
      TransformShapeDelta(read: read, write: write, next: _prev);
}
