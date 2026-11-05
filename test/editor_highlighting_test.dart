// Regression tests for the editor highlighter.
//
// The previous TextField-highlighter could advance past the end of a line for
// an unfinished string ending in a backslash, and it skipped JSON entirely
// because its keyword map had no JSON entry. The editor now uses re_highlight;
// these tests keep both cases covered.

import 'package:crisp_cloud/services/editor_highlighting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_highlight/re_highlight.dart';

void main() {
  group('language selection', () {
    test('maps common extensions through the shared viewer mapping', () {
      expect(editorLanguageForFile('main.dart'), 'dart');
      expect(editorLanguageForFile('data.json'), 'json');
      expect(editorLanguageForFile('script.py'), 'python');
      expect(editorLanguageForFile('README.md'), 'markdown');
      expect(editorLanguageForFile('Dockerfile'), 'dockerfile');
      expect(editorLanguageForFile('unknown.xyz'), isNull);
      expect(editorLanguageForFile('notes.txt'), isNull);
    });

    test('detects a shebang when the extension is unknown', () {
      expect(
        editorLanguageForContent('#!/usr/bin/env python3\nprint(1)\n'),
        'python',
      );
      expect(editorLanguageForContent('plain text'), isNull);
    });
  });

  group('highlight theme', () {
    test('registers only the requested language', () {
      final theme = buildEditorHighlightTheme(language: 'json', dark: false);
      expect(theme, isNotNull);
      expect(theme!.languages.keys, <String>['json']);
      expect(theme.languages['json']!.mode.name, 'JSON');
      expect(theme.theme, isNotEmpty);
    });

    test('is disabled for plain text, unknown languages and the toggle', () {
      expect(buildEditorHighlightTheme(language: null, dark: false), isNull);
      expect(
        buildEditorHighlightTheme(language: 'not-a-language', dark: false),
        isNull,
      );
      expect(
        buildEditorHighlightTheme(
          language: 'json',
          dark: false,
          enabled: false,
        ),
        isNull,
      );
    });

    test('uses a dark theme for dark mode', () {
      final light = buildEditorHighlightTheme(language: 'dart', dark: false);
      final dark = buildEditorHighlightTheme(language: 'dart', dark: true);
      expect(light, isNotNull);
      expect(dark, isNotNull);
      expect(light!.theme, isNot(equals(dark!.theme)));
    });
  });

  group('tokenization regressions', () {
    test('JSON strings, attribute names and numbers are styled', () {
      final theme = buildEditorHighlightTheme(language: 'json', dark: false)!;
      final mode = theme.languages['json']!.mode;
      final highlighter = Highlight()..registerLanguage('json', mode);

      const source = '{"message": "hello", "count": 42, "ready": true}';
      final result = highlighter.highlight(code: source, language: 'json');
      final html = result.toHtml();

      expect(result.code, source);
      expect(html, contains('hljs-attr'));
      expect(html, contains('hljs-string'));
      expect(html, contains('hljs-number'));
      expect(html, contains('hljs-literal'));
    });

    test('an unfinished string ending in a backslash is safe', () {
      final theme = buildEditorHighlightTheme(language: 'dart', dark: false)!;
      final mode = theme.languages['dart']!.mode;
      final highlighter = Highlight()..registerLanguage('dart', mode);

      for (final source in <String>[
        'final value = "unfinished\\',
        "final value = 'unfinished\\",
      ]) {
        final result = highlighter.highlight(code: source, language: 'dart');
        expect(result.code, source);
      }
    });
  });
}
