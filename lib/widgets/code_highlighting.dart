// lib/widgets/code_highlighting.dart
//
// Shared extension/shebang → highlight.js language mapping for the file
// editor (F4) and the internal viewer (F3). `package:highlight` is a pure-Dart
// port of highlight.js (MIT); the language identifier names below match the
// registerLanguages set bundled with highlight 0.7.0 exactly.

/// Lower-case basename without any leading path, mapped to highlight.js
/// language names (e.g. Dockerfile, Makefile, CMakeLists.txt).
const Map<String, String> kBasenameToHljsLanguage = <String, String>{
  'makefile': 'makefile',
  'dockerfile': 'dockerfile',
  'cmakelists.txt': 'cmake',
  'jenkinsfile': 'groovy',
  'gemfile': 'ruby',
  'rakefile': 'ruby',
  'guardfile': 'ruby',
  'vagrantfile': 'ruby',
  'pipfile': 'ini',
  'meson.build': 'ini',
  '.bashrc': 'bash',
  '.bash_profile': 'bash',
  '.profile': 'bash',
  '.zshrc': 'bash',
  '.env': 'ini',
  '.gitconfig': 'ini',
  '.gitignore': 'plaintext',
  '.gitattributes': 'plaintext',
  '.gitmodules': 'ini',
  '.editorconfig': 'ini',
};

/// Map from lower-case file extension (no leading dot) to a highlight.js
/// language name. Only names present in highlight 0.7.0 are used.
const Map<String, String> kExtensionToHljsLanguage = <String, String>{
  // ---- Shell / batch ---------------------------------------
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'ksh': 'bash',
  'fish': 'bash',
  'bat': 'dos',
  'cmd': 'dos',
  'ps1': 'powershell',
  'psm1': 'powershell',
  'psd1': 'powershell',
  // ---- Systems / compiled ----------------------------------
  // highlight 0.7.0 registers C under 'cpp' (no standalone 'c' language).
  'c': 'cpp',
  'h': 'cpp',
  'cpp': 'cpp',
  'cc': 'cpp',
  'cxx': 'cpp',
  'hpp': 'cpp',
  'hh': 'cpp',
  'hxx': 'cpp',
  'ino': 'arduino',
  'cs': 'cs',
  'csx': 'cs',
  'dart': 'dart',
  'go': 'go',
  'java': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'swift': 'swift',
  'm': 'objectivec',
  'mm': 'objectivec',
  'rs': 'rust',
  'd': 'd',
  'pas': 'delphi',
  'pp': 'delphi',
  'asm': 'x86asm',
  'nasm': 'x86asm',
  'masm': 'x86asm',
  's': 'x86asm',
  'sol': 'solidity',
  // ---- Scripting / dynamic ---------------------------------
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'jsx': 'javascript',
  'ts': 'typescript',
  'mts': 'typescript',
  'cts': 'typescript',
  'tsx': 'typescript',
  'py': 'python',
  'pyw': 'python',
  'pyi': 'python',
  'rb': 'ruby',
  'erb': 'erb',
  'php': 'php',
  'pl': 'perl',
  'pm': 'perl',
  'lua': 'lua',
  'coffee': 'coffeescript',
  'groovy': 'groovy',
  'gradle': 'groovy',
  'scala': 'scala',
  'erl': 'erlang',
  'hrl': 'erlang',
  'ex': 'elixir',
  'exs': 'elixir',
  'hs': 'haskell',
  'elm': 'elm',
  'clj': 'clojure',
  'cljs': 'clojure',
  'edn': 'clojure',
  'lisp': 'lisp',
  'el': 'lisp',
  'scm': 'scheme',
  'rkt': 'scheme',
  'ml': 'ocaml',
  'fs': 'fsharp',
  'fsi': 'fsharp',
  'fsx': 'fsharp',
  'vbs': 'vbscript',
  'vb': 'vbnet',
  'nsi': 'nsis',
  'vim': 'vim',
  // ---- Web markup / styles ---------------------------------
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
  'vue': 'vue',
  'svelte': 'xml',
  'astro': 'xml',
  'xml': 'xml',
  'xsl': 'xml',
  'xaml': 'xml',
  'svg': 'xml',
  'ui': 'xml',
  'plist': 'xml',
  'resx': 'xml',
  'twig': 'twig',
  'pug': 'haml',
  'jade': 'haml',
  'haml': 'haml',
  'hjs': 'handlebars',
  'handlebars': 'handlebars',
  'css': 'css',
  'scss': 'scss',
  'sass': 'scss',
  'less': 'less',
  // ---- Data / config ---------------------------------------
  'json': 'json',
  'json5': 'json',
  'jsonl': 'json',
  'ndjson': 'json',
  'avsc': 'json',
  'ipynb': 'json',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'ini': 'ini',
  'cfg': 'ini',
  'conf': 'ini',
  'env': 'ini',
  'properties': 'properties',
  'gitconfig': 'ini',
  'gitignore': 'plaintext',
  'sql': 'sql',
  'graphql': 'graphql',
  'gql': 'graphql',
  'proto': 'protobuf',
  'proto3': 'protobuf',
  'thrift': 'thrift',
  'diff': 'diff',
  'patch': 'diff',
  'feature': 'gherkin',
  'nix': 'nix',
  // ---- Scientific / misc -----------------------------------
  'r': 'r',
  'jl': 'julia',
  'tex': 'tex',
  'latex': 'tex',
  'sty': 'tex',
  'cls': 'tex',
  'md': 'markdown',
  'mdx': 'markdown',
  'gd': 'plaintext',
  'vhd': 'vhdl',
  'vhdl': 'vhdl',
  'v': 'verilog',
  'sv': 'verilog',
  // No HCL grammar in highlight 0.7.0; INI is the closest built-in.
  'tf': 'ini',
  'tfvars': 'ini',
  'tfstate': 'json',
  'rego': 'yaml',
  'nim': 'nimrod',
  'purs': 'plaintext',
  'smali': 'smali',
  'srt': 'plaintext',
  'vtt': 'plaintext',
  'sub': 'plaintext',
  'log': 'plaintext',
  'text': 'plaintext',
  'txt': 'plaintext',
  'au3': 'autoit',
  'ahk': 'autohotkey',
  'bf': 'brainfuck',
  'f': 'fortran',
  'for': 'fortran',
  'f90': 'fortran',
  'f95': 'fortran',
  'adb': 'ada',
  'ads': 'ada',
  'ada': 'ada',
  'qml': 'qml',
  'pde': 'processing',
  'moon': 'moonscript',
  'gms': 'gams',
  'sc': 'scala',
};

/// Interpreter strings (from `#!/usr/bin/env …` shebangs) → highlight.js
/// language names.
const Map<String, String> _shebangLanguagePatterns = <String, String>{
  'python': 'python',
  'ruby': 'ruby',
  'perl': 'perl',
  'node': 'javascript',
  'deno': 'javascript',
  'bun': 'javascript',
  'php': 'php',
  'bash': 'bash',
  'sh': 'bash',
  'zsh': 'bash',
  'fish': 'bash',
  'lua': 'lua',
  'pwsh': 'powershell',
  'tcl': 'tcl',
  'awk': 'awk',
  'expect': 'tcl',
};

const _defaultHljsLanguage = 'plaintext';

/// Resolve the highlight.js language for a filename.
///
/// Returns a language name for known files (Dockerfile, .gitignore get
/// dedicated mappings) and falls back to 'plaintext' when
/// [fallbackToPlaintext] is set, otherwise null for unknown files.
String? highlightLanguageFor(
  String filename, {
  bool fallbackToPlaintext = false,
}) {
  final lower = filename.toLowerCase();

  final slash = lower.lastIndexOf('/');
  final backslash = lower.lastIndexOf('\\');
  final start = (slash > backslash ? slash : backslash) + 1;
  final basename = lower.substring(start);
  final hasExt = basename.contains('.');
  final ext = hasExt ? basename.substring(basename.lastIndexOf('.') + 1) : '';

  final byBasename = kBasenameToHljsLanguage[basename];
  if (byBasename != null) return byBasename;

  if (hasExt) {
    final byExt = kExtensionToHljsLanguage[ext];
    if (byExt != null) return byExt;
    // Names like 'Makefile.dev' still resolve via the first dot segment
    // when the country/multi-suffix isn't registered on its own.
    if (ext.length >= 2) {
      final base = basename.split('.').first;
      final byBase =
          kBasenameToHljsLanguage[base] ?? kExtensionToHljsLanguage[base];
      if (byBase != null) return byBase;
    }
  } else {
    // Extension-less: try the whole basename as a language key (e.g. 'Dockerfile').
    final byWhole =
        kExtensionToHljsLanguage[basename] ?? kBasenameToHljsLanguage[basename];
    if (byWhole != null) return byWhole;
  }

  return fallbackToPlaintext ? _defaultHljsLanguage : null;
}

/// Sniff a shebang line from decoded text and return a highlight.js language,
/// or null when the file has no shebang / an unknown interpreter.
String? highlightLanguageForShebang(String decodedText) {
  for (final line in decodedText.split('\n')) {
    final l = line.trim();
    if (l.isEmpty || !l.startsWith('#!')) return null;
    // '#!/usr/bin/env python3' → 'python3' → mapped by interpreter prefix.
    final tail = l.startsWith('#!/usr/bin/env ')
        ? l.substring('#!/usr/bin/env '.length)
        : l.substring(2);
    final interp = tail.split('/').last.trim().split(' ').first.toLowerCase();
    for (final entry in _shebangLanguagePatterns.entries) {
      if (interp == entry.key || interp.startsWith(entry.key)) {
        return entry.value;
      }
    }
    return null;
  }
  return null;
}
