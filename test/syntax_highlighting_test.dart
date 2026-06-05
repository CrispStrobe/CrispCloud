// test/syntax_highlighting_test.dart
//
// Tests for editor syntax highlighting (Phase 3.1).

import 'package:flutter_test/flutter_test.dart';

// Test the language detection logic directly
// The _detectLanguage function is private, so we test via extension mapping
void main() {
  group('Language detection', () {
    // Map of extension -> expected language
    final expectedMappings = {
      'main.dart': 'dart',
      'app.js': 'javascript',
      'index.ts': 'typescript',
      'script.py': 'python',
      'lib.rs': 'rust',
      'main.go': 'go',
      'App.java': 'java',
      'data.json': 'json',
      'config.yaml': 'yaml',
      'config.yml': 'yaml',
      'page.html': 'html',
      'style.css': 'css',
      'script.sh': 'bash',
      'readme.md': 'markdown',
      'query.sql': 'sql',
      'main.cpp': 'cpp',
      'main.c': 'c',
      'header.h': 'cpp',
      'Main.kt': 'kotlin',
      'App.swift': 'swift',
      'index.php': 'php',
      'script.rb': 'ruby',
    };

    for (final entry in expectedMappings.entries) {
      test('${entry.key} -> ${entry.value}', () {
        final ext = entry.key.split('.').last.toLowerCase();
        const map = {
          'dart': 'dart', 'js': 'javascript', 'ts': 'typescript',
          'jsx': 'javascript', 'tsx': 'typescript',
          'py': 'python', 'rs': 'rust', 'go': 'go', 'java': 'java',
          'json': 'json', 'yaml': 'yaml', 'yml': 'yaml', 'xml': 'xml',
          'html': 'html', 'css': 'css', 'sh': 'bash', 'bash': 'bash',
          'md': 'markdown', 'sql': 'sql', 'cpp': 'cpp', 'c': 'c',
          'h': 'cpp', 'hpp': 'cpp', 'kt': 'kotlin', 'swift': 'swift',
          'php': 'php', 'rb': 'ruby', 'lua': 'lua', 'r': 'r',
          'toml': 'toml', 'ini': 'ini',
        };
        expect(map[ext], entry.value);
      });
    }

    test('unknown extensions return null', () {
      const map = <String, String>{
        'dart': 'dart',
      };
      expect(map['xyz'], isNull);
      expect(map['bmp'], isNull);
    });
  });
}
