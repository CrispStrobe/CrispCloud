import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' show Locale;

import 'package:crisp_cloud/l10n/office_preview_strings.dart';
import 'package:crisp_cloud/services/internal_viewer_service.dart';
import 'package:crisp_cloud/services/office_document_service.dart';
import 'package:crisp_cloud/services/rtf_document.dart';
import 'package:flutter_test/flutter_test.dart';

RtfDocument _read(String rtf) =>
    parseRtfDocument(Uint8List.fromList(latin1.encode(rtf)));
Matcher _error(RtfDocumentErrorCode code) => throwsA(
  isA<RtfDocumentException>().having((error) => error.code, 'code', code),
);

void main() {
  test('keeps surrogate pairs intact across formatting run boundaries', () {
    final document = _read(r'{\rtf1\uc0\b\u-10179\b0\u-8704  text}');
    expect(document.plainText, '😀 text');
    expect(document.html, contains('<strong>😀</strong> text'));
    expect(document.markdown, '**😀** text');
  });
  test('preserves scoped emphasis, alignment and paragraph boundaries', () {
    final document = _read(
      r'{\rtf1\ansi\qc Title\par\pard Normal {\b bold {\i both}} {\ul under}\line last\par}',
    );
    expect(document.plainText, 'Title\nNormal bold both under\nlast');
    expect(document.html, contains('text-align:center'));
    expect(document.html, contains('<strong>bold </strong>'));
    expect(document.html, contains('<em><strong>both</strong></em>'));
    expect(document.html, contains('<u>under</u>'));
    expect(document.markdown, contains('**bold **'));
  });

  test('decodes Unicode, scoped fallback counts and surrogate pairs', () {
    final document = _read(
      r'{\rtf1\ansi A\u945? {\uc2\u946??} \uc0\u-10179\u-8704\par}',
    );
    expect(document.plainText, 'Aα β 😀');
  });

  test(
    'skips fallback control tokens, escaped bytes and complete binary blobs',
    () {
      expect(
        _read(r"{\rtf1\uc1\u945\'3f\u946\~\u947\bin3 {}\Z}").plainText,
        'αβγZ',
      );
      expect(_read(r'{\rtf1\uc2\u945?{B}C}').plainText, 'αBC');
    },
  );

  test(
    'Unicode alternate representation does not duplicate the ANSI branch',
    () {
      expect(
        _read(r'{\rtf1{\upr{old ANSI}{\*\ud New \u945?}}}').plainText,
        'New α',
      );
      expect(
        () => _read(r'{\rtf1{\upr{only one}}}'),
        _error(RtfDocumentErrorCode.malformed),
      );
    },
  );

  test(
    'decodes document and per-font code pages without leaking font table',
    () {
      final document = _read(
        r"{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fcharset0 Arial;}{\f1\fcharset204 Cyrillic;}}caf\'e9 \f1\'cf\'f0\'e8\'e2\'e5\'f2\f0!}",
      );
      expect(document.plainText, 'café Привет!');
      expect(document.html, isNot(contains('Arial')));
      expect(
        _read(r"{\rtf1\ansicpg65001\'e4\'b8\'96\'e7\'95\'8c}").plainText,
        '世界',
      );
    },
  );

  test(
    'uses Unicode for Asian RTF and rejects unsupported actual legacy bytes',
    () {
      expect(_read(r'{\rtf1\ansicpg932\u19990?\u30028?}').plainText, '世界');
      expect(
        () => _read(r"{\rtf1\ansicpg932\'82\'a0}"),
        _error(RtfDocumentErrorCode.unsupportedCodePage),
      );
      expect(
        () => _read(r"{\rtf1\ansicpg65001\'ff}"),
        _error(RtfDocumentErrorCode.malformed),
      );
    },
  );

  test('shows explicit list labels and safe flat tables', () {
    final document = _read(
      r'{\rtf1{\listtext 3.\tab}\ls1 Third\par\pard{\pntext\bullet\tab}Bullet\par\pard\trowd\intbl A\cell {\b B}\cell\row\trowd\intbl C\cell D\cell\row\pard After}',
    );
    expect(document.plainText, '3. Third\n• Bullet\nA\tB\nC\tD\nAfter');
    expect(document.html, contains('<ol start="3">'));
    expect(document.html, contains('<ul>'));
    expect(document.html, contains('<table><tbody><tr>'));
    expect(document.html, contains('<strong>B</strong>'));
  });

  test(
    'skips destination text, objects and binary data without interpreting them',
    () {
      final document = _read(
        r'{\rtf1{\fonttbl{\f0 SecretFont;}}{\info{\title SecretTitle}}{\*\unknown SecretUnknown}{\header SecretHeader}{\footnote SecretNote}{\pict 1234}{\object{\objdata\bin5 {}\{} }}Visible {\field{\*\fldinst INCLUDETEXT "https://example.invalid/secret"}{\fldrslt Saved result}}{\v Hidden}}',
      );
      expect(document.plainText, 'Visible Saved result');
      for (final secret in [
        'Secret',
        'example.invalid',
        'Hidden',
        'INCLUDETEXT',
      ]) {
        expect(document.html, isNot(contains(secret)));
      }
    },
  );

  test('HTML and Markdown-looking document text remain literal content', () {
    final document = _read(
      r'{\rtf1 <script>alert(1)</script> [link](https://example.invalid) ![image](x) & text}',
    );
    expect(document.html, contains('&lt;script&gt;'));
    expect(document.html, isNot(contains('<script>')));
    expect(document.html, isNot(contains('<a ')));
    expect(document.html, isNot(contains('<img')));
    expect(document.markdown, contains(r'\[link\]'));
  });

  test('rejects nested tables explicitly', () {
    expect(
      () => _read(r'{\rtf1\intbl\itap2 nested}'),
      _error(RtfDocumentErrorCode.unsupportedFeature),
    );
  });

  test('rejects malformed syntax, binary extents and surrogate sequences', () {
    for (final invalid in [
      r'{\rtf1 missing',
      r'{\rtf1 ok}trailing',
      '{\\rtf1\\',
      r"{\rtf1\'gg}",
      r'{\rtf1\bin999 x}',
      r'{\rtf1\uc-1 x}',
      r'{\rtf1\u-10179?x}',
      r'{\rtf1\u-8704?}',
    ]) {
      expect(
        () => _read(invalid),
        _error(RtfDocumentErrorCode.malformed),
        reason: invalid,
      );
    }
  });

  test('bounds input, nesting and decoded output', () {
    expect(
      () => parseRtfDocument(Uint8List(kRtfInputLimit + 1)),
      _error(RtfDocumentErrorCode.resourceLimit),
    );
    expect(
      () => _read('{\\rtf1${'{' * 128}x${'}' * 129}'),
      _error(RtfDocumentErrorCode.resourceLimit),
    );
    expect(
      () => _read('{\\rtf1${'x' * (kRtfTextLimit + 1)}}'),
      _error(RtfDocumentErrorCode.resourceLimit),
    );
  });

  test(
    'office integration exposes safe formatted content and localized notices',
    () async {
      final document = await parseOfficeDocument(
        Uint8List.fromList(ascii.encode(r'{\rtf1{\b Hello}}')),
        'memo.RTF',
      );
      expect(document.safeHtml, contains('<strong>Hello</strong>'));
      expect(document.plainText, 'Hello');
      expect(document.notice, OfficePreviewNotice.rtfFormatting);
      expect(
        OfficePreviewStrings(const Locale('de')).note(document),
        contains('RTF'),
      );
      expect(
        const InternalViewerService().detectMode('memo.rtf'),
        ViewerMode.office,
      );
      final malformed = await parseOfficeDocument(Uint8List(0), 'bad.rtf');
      expect(malformed.notice, OfficePreviewNotice.rtfMalformed);
      expect(malformed.fallback, OfficePreviewFallback.extractionFailed);
      expect(malformed.safeHtml, isNull);
    },
  );
}
