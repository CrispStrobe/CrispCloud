// lib/services/editor_highlighting.dart
//
// Language selection and theme construction for the code editor.
//
// Highlighting is provided by re_highlight (the Re-Editor engine), which is a
// Dart port of highlight.js. Reusing the existing extension/shebang mapping in
// code_highlighting.dart keeps the editor and the read-only viewer in sync.

import 'package:flutter/material.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/all.dart';

import 'syntax_highlight_theme.dart';

import '../widgets/code_highlighting.dart';

/// Maximum source size (in characters) that is syntax-highlighted.
const int kEditorHighlightMaxChars = 8 * 1024 * 1024;

/// Return the highlight.js language for [filename], or null when the file
/// should be shown as plain text.
String? editorLanguageForFile(String filename) {
  return normalizeEditorLanguage(highlightLanguageFor(filename));
}

/// Return the highlight.js language for a shebang in [content], or null.
String? editorLanguageForContent(String content) {
  return normalizeEditorLanguage(highlightLanguageForShebang(content));
}

/// Map a highlight.js language name to one re_highlight knows, or null.
String? normalizeEditorLanguage(String? language) {
  if (language == null || language == 'plaintext') return null;
  return builtinAllLanguages.containsKey(language) ? language : null;
}

/// Build the syntax-highlighting theme for one language.
///
/// Only the active language is registered so re_highlight does not compile
/// every bundled grammar on the first paint.
CodeHighlightTheme? buildEditorHighlightTheme({
  required String? language,
  required bool dark,
  bool enabled = true,
  int maxChars = kEditorHighlightMaxChars,
}) {
  if (!enabled || language == null) return null;
  final mode = builtinAllLanguages[language];
  if (mode == null) return null;
  return CodeHighlightTheme(
    languages: <String, CodeHighlightThemeMode>{
      language: CodeHighlightThemeMode(
        mode: mode,
        maxSize: maxChars,
        maxLineLength: 512 * 1024,
      ),
    },
    theme: syntaxHighlightTheme(dark: dark),
  );
}

/// Theme used by editor chrome (line numbers, indicators) in tests and hosts.
TextStyle editorChromeTextStyle({
  required Color color,
  double fontSize = 12,
  double height = 1.45,
}) {
  return TextStyle(
    fontFamily: 'AppMono',
    fontSize: fontSize,
    height: height,
    color: color,
  );
}
