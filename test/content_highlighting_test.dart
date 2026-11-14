import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:crisp_cloud/widgets/code_highlighting.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/editor_highlighting.dart';

void main() {
  const strings =
      '/* Authored localization fixture */\n"Open" = "Open file";\n"Close" = "Close file";';
  test('unknown and strings extensions use OpenStep content', () {
    for (final name in ['Localizable.strings', 'unknown', 'x.weird']) {
      expect(highlightLanguageForDocument(name, strings), 'objectivec');
    }
    expect(editorLanguageForContent(strings), 'objectivec');
  });
  test('escaped strings and comment-like values', () {
    expect(
      highlightLanguageForContent(
        r'"a" = "quote: \" // /*";'
        '\n'
        r'"b" = "two";',
      ),
      'objectivec',
    );
  });
  test('JSON structural detection', () {
    expect(
      highlightLanguageForDocument('x.unknown', '{"answer":[42]}'),
      'json',
    );
    expect(highlightLanguageForContent('{not json}'), isNull);
  });
  test('XML structure and UTF16 BOM', () {
    const text = '<?xml version="1.0"?><plist><dict/></plist>';
    final b = Uint8List.fromList([
      255,
      254,
      ...text.codeUnits.expand((v) => [v & 255, v >> 8]),
    ]);
    expect(
      const InternalViewerService().detectMode('unknown', header: b),
      ViewerMode.xml,
    );
  });
  test('plain prose, binary plists and NULs stay unclassified', () {
    for (final text in [
      'This is a note about Dart and JSON.',
      'bplist00random',
      'abc\u0000xyz',
      '"one" = "not enough evidence";',
    ]) {
      expect(highlightLanguageForContent(text), isNull);
    }
  });
  test('bounded prefix does not inspect the entire document', () {
    expect(highlightLanguageForContent('${' ' * 32768}$strings'), isNull);
  });
  test('known grammar fallback and shebang', () {
    expect(highlightLanguageForDocument('a.dart', 'void main() {}'), 'dart');
    expect(
      highlightLanguageForContent('#!/usr/bin/env python3\nprint(1)'),
      'python',
    );
  });
  final real = File(
    '/Applications/Android File Transfer.app/Contents/Resources/bg.lproj/Localizable.strings',
  );
  test('live Mac UTF16 Localizable.strings', () {
    final decoded = InternalViewerService.decodeTextForView(
      real.readAsBytesSync(),
    );
    expect(decoded.encoding, 'utf16le');
    expect(highlightLanguageForDocument(real.path, decoded.text), 'objectivec');
  }, skip: !real.existsSync());
}
