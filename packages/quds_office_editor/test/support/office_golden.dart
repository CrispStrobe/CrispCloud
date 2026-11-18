import 'dart:io';

/// Raster references belong to their actual host, independently of the
/// platform simulated by a widget test. Preserve existing Linux references.
String officeGolden(String name) {
  if (Platform.isMacOS) return 'goldens/macos/$name';
  const linuxReferences = {
    'office_fidelity_word.png',
    'structure_create_1.png',
    'structure_edit_1.png',
    'structure_edit_2.png',
    'structure_remove_1.png',
    'word_selection_macOS.png',
    'word_selection_windows.png',
  };
  if (Platform.isLinux && linuxReferences.contains(name)) {
    return 'goldens/linux/$name';
  }
  return 'goldens/$name';
}
