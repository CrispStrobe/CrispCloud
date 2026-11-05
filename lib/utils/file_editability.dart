// lib/utils/file_editability.dart
//
// Shared rules for deciding whether the built-in F4 editor can open a file.

/// Text/code extensions handled by the built-in text editor.
const Set<String> textEditableExtensions = <String>{
  'txt',
  'json',
  'yaml',
  'yml',
  'xml',
  'csv',
  'log',
  'ini',
  'cfg',
  'conf',
  'toml',
  'env',
  'gitignore',
  'dockerfile',
  'md',
  'markdown',
  'dart',
  'js',
  'ts',
  'jsx',
  'tsx',
  'py',
  'rb',
  'go',
  'rs',
  'java',
  'kt',
  'swift',
  'c',
  'cpp',
  'h',
  'hpp',
  'cs',
  'php',
  'html',
  'css',
  'scss',
  'less',
  'sql',
  'sh',
  'bash',
  'zsh',
  'ps1',
  'bat',
  'r',
  'lua',
  'vim',
  'makefile',
  'properties',
  'gradle',
};

/// Office formats the built-in editor can actually save in place.
const Set<String> editableOfficeExtensions = <String>{
  'docx',
  'xlsx',
  'pptx',
};

String _extensionOf(String name) {
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isTextEditableName(String name) {
  final ext = _extensionOf(name);
  // Extension-less text files (README, Makefile, ...) are editable too.
  return ext.isEmpty || textEditableExtensions.contains(ext);
}

/// True when F4 can open [name] in an editor with save support.
bool isEditableInBuiltInEditor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return true;
  final ext = _extensionOf(lower);
  return editableOfficeExtensions.contains(ext) || isTextEditableName(lower);
}
