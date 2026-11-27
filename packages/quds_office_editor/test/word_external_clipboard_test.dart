import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';
import 'package:super_clipboard/super_clipboard.dart';

class _ClipboardReader extends Fake implements ClipboardDataReader {
  _ClipboardReader({this.html, this.rtf, this.plain});

  final String? html;
  final String? rtf;
  final String? plain;

  String? _data(DataFormat format) {
    if (format == Formats.htmlText) return html;
    if (format == Formats.plainText) return plain;
    if (format is ValueFormat<String> &&
        format.codec.decodingFormats.any(
          (type) =>
              type.toLowerCase().contains('rtf') || type == 'Rich Text Format',
        )) {
      return rtf;
    }
    return null;
  }

  @override
  bool canProvide(DataFormat format) => _data(format) != null;

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async =>
      _data(format) as T?;
}

WmlRun _run(WmlParagraph paragraph, String text) => paragraph.inlines
    .whereType<WmlRun>()
    .firstWhere((run) => run.text.contains(text));

void main() {
  test('browser HTML becomes styled and editable Word content', () async {
    final payload = await OfficeClipboard.readWordRepresentations(
      _ClipboardReader(
        plain: 'A title\nHello world!\nnext',
        html: '''
          <html><head><style>
            p.MsoNormal { font-family: 'Calibri'; text-align: center; }
            .Accent { color: #1a73e8; font-size: 16px; }
          </style></head><body>
          <h2>A title</h2>
          <p class="MsoNormal" dir="rtl">
            Hello <strong class="Accent" style="background-color:rgb(255, 255, 0)">
            <em>world</em></strong><u>!</u><br>
            <a href="https://example.com/a">next</a><script>bad()</script>
            <span style="display:none">Hidden</span>
          </p></body></html>
        ''',
      ),
    );
    expect(payload!.plain, 'A title\nHello world!\nnext');
    final paragraphs = payload.wordBlocks.whereType<WmlParagraph>().toList();
    expect(paragraphs, hasLength(2));
    expect(_run(paragraphs.first, 'title').properties.bold, isTrue);
    final content = paragraphs.last;
    expect(content.text, 'Hello world!next');
    expect(content.properties.justification, WmlJustification.center);
    expect(content.properties.rightToLeft, isTrue);
    final styled = _run(content, 'world').properties;
    expect(
      styled,
      isA<WmlRunProps>()
          .having((p) => p.bold, 'bold', true)
          .having((p) => p.italic, 'italic', true)
          .having((p) => p.asciiFont, 'font', 'Calibri')
          .having((p) => p.fontSizeHalfPoints, 'size', 24)
          .having((p) => p.highlight, 'highlight', 'FFFF00')
          .having((p) => p.color, 'color', '1A73E8'),
    );
    expect(_run(content, '!').properties.underline, WmlUnderline.single);
    expect(
      content.inlines.whereType<WmlBreak>().single.type,
      WmlBreakType.textWrapping,
    );
    expect(_run(content, 'next').hyperlink?.url, 'https://example.com/a');
  });

  test(
    'HTML selection retains its enclosing Word class but excludes surrounding text',
    () {
      final payload = OfficeClipboardPayload.fromWordClipboard(
        html: """
      <html><head><style>span.Emphasis { font-style: italic; color: red; }</style></head>
      <body><p><span class="Emphasis">Unselected <!--StartFragment-->ausgewählt<!--EndFragment--> text</span></p></body></html>
    """,
      );
      final paragraph = payload.wordBlocks.single as WmlParagraph;
      expect(payload.plain, 'ausgewählt');
      expect(_run(paragraph, 'ausgewählt').properties.italic, isTrue);
      expect(_run(paragraph, 'ausgewählt').properties.color, 'FF0000');
    },
  );

  test(
    'unsafe links and external resources are never imported as active content',
    () {
      final payload = OfficeClipboardPayload.fromWordClipboard(
        html: '''
      <p><a href="javascript:alert(1)">text</a>
      <img src="https://example.com/track" alt="picture">
      <object data="file:///secret"><p>hidden</p></object></p>
    ''',
      );
      final para = payload.wordBlocks.single as WmlParagraph;
      expect(payload.plain, 'text picture');
      expect(
        para.inlines.whereType<WmlRun>().every((r) => r.hyperlink == null),
        isTrue,
      );
    },
  );

  test(
    'RTF-only clipboard preserves font, colors, styles and Unicode',
    () async {
      final payload = await OfficeClipboard.readWordRepresentations(
        _ClipboardReader(
          html: '<img src="https://example.com/tracker">',
          rtf: r'''
{\rtf1\ansi\deff0{\fonttbl{\f0\fswiss Calibri;}{\f1\froman Georgia;}}
{\colortbl;\red32\green80\blue160;\red255\green255\blue0;}
\qc {\b\i\f1\fs30\cf1\highlight2 Word} \u233?\line next\par
\pard {\ul second} {\*\unknown invisible}}
''',
        ),
      );
      expect(payload!.plain, 'Word é\nnext\nsecond ');
      final paras = payload.wordBlocks.whereType<WmlParagraph>().toList();
      final first = _run(paras.first, 'Word').properties;
      expect(first.bold, isTrue);
      expect(first.italic, isTrue);
      expect(first.asciiFont, 'Georgia');
      expect(first.fontSizeHalfPoints, 30);
      expect(first.color, '2050A0');
      expect(first.highlight, 'FFFF00');
      expect(paras.first.properties.justification, WmlJustification.center);
      expect(
        _run(paras.last, 'second').properties.underline,
        WmlUnderline.single,
      );
      expect(_run(paras.last, 'second').properties.bold, isFalse);
    },
  );

  test('deep HTML is rejected with plain-text fallback', () {
    final nested = ['<span>' * 100, 'hidden', '</span>' * 100].join();
    final payload = OfficeClipboardPayload.fromWordClipboard(
      plain: 'Plain fallback',
      html: nested,
    );
    expect(payload.hasWordBlocks, isFalse);
    expect(payload.plain, 'Plain fallback');
  });

  testWidgets(
    'normal paste retains source styles and Shift+Paste strips them',
    (tester) async {
      final clipboard = OfficeClipboard.instance;
      final usedSystem = clipboard.useSystem;
      clipboard.useSystem = false;
      addTearDown(() {
        clipboard.clear();
        clipboard.useSystem = usedSystem;
      });
      clipboard.writeLocal(
        OfficeClipboardPayload.fromWordClipboard(
          plain: 'A bold link',
          html: '<p><b>A bold <a href="https://example.com">link</a></b></p>',
        ),
      );
      final controller = WordEditorController(document: WmlDocument.empty());
      addTearDown(controller.dispose);
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: QudsWordEditor(
            controller: controller,
            focusNode: focus,
            enableLiveProofing: false,
          ),
        ),
      );
      focus.requestFocus();
      await tester.pump();
      Future<void> paste({bool plain = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (plain) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
        if (plain) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await paste();
      var paragraph = controller.document.paragraphs.single;
      expect(paragraph.text, 'A bold link');
      expect(_run(paragraph, 'bold').properties.bold, isTrue);
      expect(_run(paragraph, 'link').hyperlink?.url, 'https://example.com');
      controller.undo();
      expect(controller.document.paragraphs.single.text, '');
      await paste(plain: true);
      paragraph = controller.document.paragraphs.single;
      expect(paragraph.text, 'A bold link');
      expect(_run(paragraph, 'bold').properties.bold, isFalse);
      expect(_run(paragraph, 'link').hyperlink, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
