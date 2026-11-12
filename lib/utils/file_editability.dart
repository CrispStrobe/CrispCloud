// lib/utils/file_editability.dart
//
// Shared rules for deciding whether the built-in F4 editor can open a file.

import '../services/image_edit_session.dart' show isImageEditorFileName;
import '../services/media_capabilities.dart';

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
  'xhtml',
  'opf',
  'ncx',
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
  // PEM certificates, requests and ASCII-armored keys are text. (DER-encoded
  // .crt/.cer files are binary; the text editor reports them instead of
  // decoding with replacements, and Hex stays one click away.)
  'pem',
  'crt',
  'cer',
  'csr',
  'asc',
  // Apple project and configuration formats are text/XML, not opaque binaries.
  'plist',
  'strings',
  'stringsdict',
  'entitlements',
  'xcconfig',
  'pbxproj',
  'xcscheme',
  'xcworkspacedata',
  'storyboard',
  'xib',
  // Other structured text that benefits from the code editor.
  'xaml',
  'resx',
  'csproj',
  'vcxproj',
  'props',
  'targets',
  'nuspec',
  'ipynb',
  'jsonc',
  'json5',
  'ndjson',
  'cmake',
  'mk',
  'mak',
  'ninja',
  'podspec',
  'proto',
  'graphql',
  'gql',
  'tf',
  'tfvars',
  'hcl',
  'rego',
  'tex',
  'bib',
  'rst',
  'adoc',
  'asciidoc',
  'org',
  'srt',
  'vtt',
  'sub',
  'ass',
  'ssa',
  'lock',
  'gitattributes',
  'gitmodules',
  'editorconfig',
  'dockerignore',
  'npmignore',
  'npmrc',
  'nvmrc',
  'prettierrc',
  'eslintrc',
  'babelrc',
  'local',
  'desktop',
  'service',
  'socket',
  'timer',
  'rules',
  'spec',
  'manifest',
  'config',
  // RTF is a text format even though it is markup-heavy.
  'rtf',
  // Saved MIME messages can be edited as source while preserving byte encoding
  // and line endings. Outlook MSG remains binary and opens in the hex editor.
  'eml',
  // Autodesk keyboard shortcuts are XML; this is distinct from KeePass KDBX.
  'kbdx',
};

/// Office formats the built-in editor can actually save in place.
const Set<String> editableOfficeExtensions = <String>{
  'docx',
  'docm',
  'dotx',
  'dotm',
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
  // A trailing dot is not evidence of text: photo.jpg. must not be decoded as
  // text merely because its final extension is empty.
  return !name.contains('.') || textEditableExtensions.contains(ext);
}

bool isKeePassFileName(String name) => _extensionOf(name) == 'kdbx';

bool isLegacyWordFileName(String name) =>
    const {'doc', 'dot'}.contains(_extensionOf(name));

/// True when F4 can open [name] in an editor with save support.
bool isEditableInBuiltInEditor(String name) {
  final lower = name.toLowerCase();
  if (lower.endsWith('.pdf')) return true;
  if (lower.endsWith('.epub')) return true;
  if (isKeePassFileName(lower)) return true;
  if (isImageEditorFileName(lower)) return true;
  final mediaKind = mediaKindForFileName(lower);
  if (mediaKind != null) return MediaCapabilities.canEdit(mediaKind);
  final ext = _extensionOf(lower);
  return editableOfficeExtensions.contains(ext) || isTextEditableName(lower);
}
