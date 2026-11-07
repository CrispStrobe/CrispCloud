import 'package:path/path.dart' as p;

import 'panel_source_service.dart';

/// Resolve a local shell directory from captured, verified panel origins.
/// Panel labels are not storage identities: either pane can display a cloud
/// source, whose slash-prefixed paths must never become local shell paths.
Future<String> resolveTerminalDirectory(
  Iterable<PanelSource> sources, {
  required Future<String> Function() fallback,
}) async {
  for (final source in sources) {
    if (source is LocalPanelSource && _valid(source.currentPath)) {
      return p.normalize(source.currentPath);
    }
  }
  final directory = await fallback();
  if (!_valid(directory)) {
    throw StateError('The local shell directory is unavailable.');
  }
  return p.normalize(directory);
}

bool _valid(String path) =>
    path.isNotEmpty && !path.contains('\u0000') && p.isAbsolute(path);
