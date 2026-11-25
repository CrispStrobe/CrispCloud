import 'dart:typed_data';

import '../services/internal_viewer_service.dart';
import 'file_editability.dart';

/// Bytes read from the start of an unknown file before choosing an editor.
const int editorHeaderProbeBytes = 16 * 1024;

/// Decides whether F4 should open [name] as text instead of the hex editor.
///
/// Known text extensions and extension-less names keep their existing text
/// behavior. For any other name the header is the authority, matching what F3
/// already does when it renders the same file as text/code with highlighting.
/// A null [header] means the probe failed, so the safe default stays Hex.
bool shouldEditAsText(String name, Uint8List? header) {
  if (isTextEditableName(name)) return true;
  if (header == null) return false;
  // An empty unknown file holds no binary evidence; a text editor can save it.
  if (header.isEmpty) return true;
  final mode = const InternalViewerService().detectMode(name, header: header);
  return const <ViewerMode>{
    ViewerMode.text,
    ViewerMode.markdown,
    ViewerMode.html,
    ViewerMode.xml,
    ViewerMode.lyrics,
  }.contains(mode);
}
