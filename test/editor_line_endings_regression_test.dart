import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:crisp_cloud/services/editor_document.dart';
import 'package:crisp_cloud/services/editor_document_history.dart';

void main() {
  test('preserve, explicit dominant conversion, and new-line preference are independent', () {
    final doc = EditorDocument.decode(utf8.encode('a\r\nb\nc\r'));
    expect(utf8.decode(doc.encode()), 'a\r\nb\nc\r');
    expect(
      utf8.decode(doc.copyWith(lineEnding: EditorLineEnding.crlf).encode()),
      'a\r\nb\r\nc\r\n',
    );
    final preference = doc.withNewLineEnding(EditorLineEnding.lf);
    expect(utf8.decode(preference.encode()), 'a\r\nb\nc\r');
    expect(
      utf8.decode(preference.replace(2, 2, 'new\n').encode()),
      'a\r\nnew\nb\nc\r',
    );
  });
  test('sequential edits preserve distinct interior terminators and final newline state', () {
    var doc = EditorDocument.decode(utf8.encode('one\r\ntwo\nthree\rfour'));
    doc = doc.copyWith(text: 'ONE\ntwo\nthree\nfour');
    doc = doc.copyWith(text: 'ONE\ntwo\nTHREE\nfour');
    expect(utf8.decode(doc.encode()), 'ONE\r\ntwo\nTHREE\rfour');
    expect(doc.hasFinalNewline, isFalse);
    final reloaded = EditorDocument.decode(doc.encode());
    expect(reloaded.encode(), doc.encode());
  });
  test('all encodings preserve mixed breaks and honor BOM controls', () {
    for (final encoding in EditorEncoding.values) {
      final original = EditorDocument.decode(utf8.encode('a\r\nb\nc\r'));
      final encoded = original
          .copyWith(
            encoding: encoding,
            hadBom: encoding != EditorEncoding.latin1,
          )
          .encode();
      final decoded = EditorDocument.decode(encoded, encoding: encoding);
      expect(decoded.encode(), encoded, reason: encoding.name);
    }
    for (final encoding in [
      EditorEncoding.utf16le,
      EditorEncoding.utf16be,
      EditorEncoding.utf32le,
      EditorEncoding.utf32be,
    ]) {
      final doc = EditorDocument.decode(utf8.encode('a\r\nb'))
          .copyWith(encoding: encoding, hadBom: false);
      final decoded = EditorDocument.decode(doc.encode(), encoding: encoding);
      expect(decoded.writesBom, isFalse);
      expect(decoded.encode(), doc.encode());
    }
  });
  test('malformed BOM-marked data never silently re-encodes', () {
    for (final bytes in <List<int>>[
      [0xef, 0xbb, 0xbf, 0xff],
      [0xff, 0xfe, 1],
      [0xff, 0xfe, 0x00, 0xd8],
      [0, 0, 0xfe, 0xff, 0xff, 0xff, 0xff, 0xff],
      [0xff, 0xfe, 0, 0, 0, 0xd8, 0, 0],
      [0, 0, 0xfe, 0xff, 1],
    ]) {
      expect(
        () => EditorDocument.decode(bytes),
        throwsA(isA<EditorEncodingException>()),
      );
    }
  });
  test('UTF32 unsigned values are rejected consistently in browser and VM', () {
    final bytes = Uint8List.fromList([0, 0, 0xfe, 0xff, 0x80, 0, 0, 0]);
    expect(
      () => EditorDocument.decode(bytes),
      throwsA(isA<EditorEncodingException>()),
    );
  });
  test('exact edit delta preserves metadata even when repeated line text is ambiguous', () {
    final doc = EditorDocument.decode(utf8.encode('a\r\na\na\r'));
    expect(utf8.decode(doc.replace(2, 4, '').encode()), 'a\r\na\r');
    expect(
      utf8.decode(
        doc.replace(2, 2, 'x\r\n', preserveInsertedEndings: true).encode(),
      ),
      'a\r\nx\r\na\na\r',
    );
  });
  test('Re-Editor undo and redo restore per-boundary metadata', () {
    final history = EditorDocumentHistory();
    var document = EditorDocument.decode(utf8.encode('a\r\nb\nc\r'));
    final controller = CodeLineEditingController.fromText(document.text);
    addTearDown(controller.dispose);
    history.remember(controller.codeLines, document);
    controller.addListener(() {
      document = history.apply(controller.codeLines, controller.text, document);
    });
    controller.selection = const CodeLineSelection.collapsed(
      index: 1,
      offset: 0,
    );
    controller.replaceSelection('new\n');
    final changed = document.encode();
    controller.undo();
    expect(utf8.decode(document.encode()), 'a\r\nb\nc\r');
    controller.redo();
    expect(document.encode(), changed);
  });
}
