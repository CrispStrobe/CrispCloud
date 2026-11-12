import 'dart:io';
import 'dart:ui' as ui;

import 'package:crisp_cloud/services/editor_highlighting.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

void main() {
  testWidgets('the editor paints syntax colors for large generated Dart', (
    tester,
  ) async {
    final fixture = Platform.environment['CRISP_LARGE_DART_FIXTURE'];
    final text = fixture == null
        ? '// generated source\nconst puzzles = [\n${List.generate(26000, (i) => '  {"name": "Puzzle $i", "cells": "AABB....XX....", "difficulty": 12},\n').join()}];\n'
        : (await tester.runAsync(() => File(fixture).readAsString()))!;
    final controller = CodeLineEditingController.fromText(text);
    final key = GlobalKey();
    final base = buildEditorHighlightTheme(language: 'dart', dark: false)!;
    const comment = Color(0xffa020f0);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RepaintBoundary(
            key: key,
            child: CodeEditor(
              controller: controller,
              autofocus: false,
              style: CodeEditorStyle(
                textColor: Colors.black,
                backgroundColor: Colors.white,
                codeTheme: CodeHighlightTheme(
                  languages: base.languages,
                  theme: {
                    ...base.theme,
                    'comment': const TextStyle(color: comment),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));
    var painted = false;
    final deadline = Stopwatch()..start();
    while (!painted && deadline.elapsed < const Duration(seconds: 90)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump();
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = (await tester.runAsync(
        () => boundary.toImage(pixelRatio: 1),
      ))!;
      final data = (await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      ))!;
      final bytes = data.buffer.asUint8List();
      for (var offset = 0; offset < bytes.length; offset += 4) {
        if (bytes[offset] == 160 &&
            bytes[offset + 1] == 32 &&
            bytes[offset + 2] == 240 &&
            bytes[offset + 3] == 255) {
          painted = true;
          break;
        }
      }
      image.dispose();
    }
    expect(
      painted,
      isTrue,
      reason: 'The background editor lexer must reach the painted document, not silently show plain text.',
    );
    expect(controller.text, text);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
