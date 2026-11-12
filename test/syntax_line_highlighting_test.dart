import 'dart:io';

import 'package:crisp_cloud/services/editor_highlighting.dart';
import 'package:crisp_cloud/services/syntax_line_highlighting.dart';
import 'package:crisp_cloud/widgets/code_highlighting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('NXC uses C-family lexing in both the viewer and editor', () async {
    expect(highlightLanguageFor('motor.NXC'), 'cpp');
    expect(editorLanguageForFile('motor.NXC'), 'cpp');
    final lines = await highlightSourceLines(
      'task main() { /* motor */\n  string label = "Drive"; OnFwd(OUT_A, 50);\n}',
      'cpp',
    );
    expect(
      lines
          .expand((line) => line)
          .where((run) => run.scopes.contains('string')),
      isNotEmpty,
    );
    expect(
      lines
          .expand((line) => line)
          .where((run) => run.scopes.contains('number')),
      isNotEmpty,
    );
  });

  test('large Dart keeps source text and scopes across virtualized lines', () async {
    final fixture = Platform.environment['CRISP_LARGE_DART_FIXTURE'];
    final text = fixture == null
        ? '// generated data\nconst puzzles = [\n${List.generate(26000, (i) => '  {"name": "Puzzle $i", "cells": "AABBCC....XX....", "difficulty": 12},\n').join()}];\n'
        : await File(fixture).readAsString();
    expect(text.length, greaterThan(400 * 1024));
    final lines = await highlightSourceLines(text, 'dart');
    expect(
      lines.map((line) => line.map((run) => run.text).join()).join('\n'),
      text,
    );
    final runs = lines.expand((line) => line);
    expect(runs.where((run) => run.scopes.contains('keyword')), isNotEmpty);
    expect(runs.where((run) => run.scopes.contains('string')), isNotEmpty);
    expect(
      lines
          .skip(lines.length ~/ 2)
          .expand((line) => line)
          .where((run) => run.scopes.isNotEmpty),
      isNotEmpty,
    );
    expect(
      buildEditorHighlightTheme(
        language: 'dart',
        dark: false,
      )!.languages['dart']!.maxSize,
      greaterThan(text.length),
    );
  }, timeout: const Timeout(Duration(minutes: 2)));

  test(
    'multiline scope survives line boundaries without altering characters',
    () async {
      const text = '/* first\ncontinued\nlast */\nconst answer = 42;';
      final lines = await highlightSourceLines(text, 'dart');
      expect(lines[1].single.text, 'continued');
      expect(lines[1].single.scopes, contains('comment'));
      expect(lines.last.any((run) => run.scopes.contains('number')), isTrue);
    },
  );
  test('chunk boundaries retain a long multiline comment and following code', () async {
    final text =
        '/* first\n${List.filled(6000, 'continued\n').join()}last */\nconst answer = 42;';
    final lines = await highlightSourceLines(text, 'dart');
    expect(lines[4000].single.scopes, contains('comment'));
    expect(lines.last.any((run) => run.scopes.contains('number')), isTrue);
    expect(
      lines.map((line) => line.map((run) => run.text).join()).join('\n'),
      text,
    );
  });
}
