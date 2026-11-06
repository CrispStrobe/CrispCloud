import 'plugin_workspace_stub.dart'
    if (dart.library.io) 'plugin_workspace_io.dart'
    as platform;

void validatePluginId(String id) {
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$').hasMatch(id) ||
      id.contains('..') ||
      id.endsWith('.')) {
    throw const FormatException(
      'Extension IDs must use letters, numbers, dots, hyphens or underscores without path segments.',
    );
  }
}

/// A scoped temporary resource, not an operating-system sandbox. Native
/// resources are real directories; web resources identify a virtual namespace.
class PluginWorkspace {
  PluginWorkspace(this.path, this._release);
  final String path;
  final Future<void> Function() _release;
  bool _closed = false;
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _release();
  }
}

Future<PluginWorkspace> createPluginWorkspace(
  String id, {
  String? baseDirectory,
}) async {
  validatePluginId(id);
  final value = await platform.createWorkspace(
    id,
    baseDirectory: baseDirectory,
  );
  return PluginWorkspace(value.$1, value.$2);
}
