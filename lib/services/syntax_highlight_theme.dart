import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

final Map<String, TextStyle> _darkTheme = Map.unmodifiable({
  ...monokaiSublimeTheme,
  'root': monokaiSublimeTheme['root']!.copyWith(backgroundColor: Colors.black),
});

/// Shared token colours and canvas for F3, F4 and the preview pane.
Map<String, TextStyle> syntaxHighlightTheme({required bool dark}) =>
    dark ? _darkTheme : githubTheme;

Color syntaxCanvasColor({required bool dark}) =>
    syntaxHighlightTheme(dark: dark)['root']!.backgroundColor ??
    (dark ? Colors.black : Colors.white);

Color syntaxTextColor({required bool dark}) =>
    syntaxHighlightTheme(dark: dark)['root']!.color ??
    (dark ? Colors.white : Colors.black);
