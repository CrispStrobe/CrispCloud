import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_editor/quds_office_editor.dart';

WordEditorController _controller({
  WmlParagraphProps? properties,
  WmlDocument? document,
  TextDirection direction = TextDirection.ltr,
}) {
  final controller = WordEditorController(
    document:
        document ??
        WmlDocument(
          sections: [
            WmlSection(
              blocks: [
                WmlParagraph(
                  properties: properties,
                  inlines: [WmlRun(text: '')],
                ),
              ],
            ),
          ],
        ),
    config: OfficeSurfaceConfig(textDirection: direction),
  );
  controller.proofing.enabled = false;
  addTearDown(controller.dispose);
  return controller;
}

void _direction(WordEditorController controller, TextDirection direction) {
  controller.syncConfig(controller.config.copyWith(textDirection: direction));
  controller.relayout();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(OfficeHostFonts.ensureRegistered);

  test('fresh blank paragraphs follow host language and incoming script', () {
    final controller = _controller();
    final paragraph = controller.document.paragraphs.single;
    expect(paragraph.properties.rightToLeft, isNull);
    expect(paragraph.properties.justification, WmlJustification.left);
    for (var cycle = 0; cycle < 2; cycle++) {
      _direction(controller, TextDirection.rtl);
      expect(paragraph.properties.rightToLeft, isTrue);
      expect(paragraph.properties.justification, WmlJustification.right);
      _direction(controller, TextDirection.ltr);
      expect(paragraph.properties.rightToLeft, isNull);
      expect(paragraph.properties.justification, WmlJustification.left);
    }
    controller.insertText('مرحبا');
    expect(paragraph.text, 'مرحبا');
    expect(paragraph.properties.rightToLeft, isTrue);
    expect(paragraph.properties.justification, WmlJustification.right);
    _direction(controller, TextDirection.ltr);
    expect(paragraph.properties.rightToLeft, isTrue);
    expect(controller.canUndo, isTrue);
    controller.undo();
    expect(paragraph.text, isEmpty);
    expect(paragraph.properties.rightToLeft, isNull);
  });

  for (final rtl in [false, true]) {
    test(
      'explicit blank direction $rtl survives reopen, layout and typing',
      () {
        final original = _controller(
          properties: WmlParagraphProps(
            rightToLeft: rtl,
            justification: WmlJustification.center,
            explicitJustification: true,
          ),
          direction: rtl ? TextDirection.ltr : TextDirection.rtl,
        );
        final reopened = WordDeserializer().readBytes(
          WordSerializer().writeBytes(original.document),
        );
        for (final controller in [
          original,
          _controller(
            document: reopened,
            direction: rtl ? TextDirection.ltr : TextDirection.rtl,
          ),
        ]) {
          final paragraph = controller.document.paragraphs.single;
          for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
            _direction(controller, direction);
            expect(paragraph.properties.rightToLeft, rtl);
            expect(paragraph.properties.justification, WmlJustification.center);
          }
          controller.insertText(rtl ? 'Latin text' : 'نص عربي');
          expect(paragraph.properties.rightToLeft, rtl);
          expect(paragraph.properties.justification, WmlJustification.center);
          controller.undo();
          expect(paragraph.text, isEmpty);
          expect(paragraph.properties.rightToLeft, rtl);
          expect(paragraph.properties.justification, WmlJustification.center);
          controller.redo();
          expect(paragraph.text, rtl ? 'Latin text' : 'نص عربي');
          expect(paragraph.properties.rightToLeft, rtl);
        }
      },
    );
  }

  test('explicit alignment remains independent of automatic direction', () {
    for (final alignment in [
      WmlJustification.left,
      WmlJustification.center,
      WmlJustification.right,
      WmlJustification.justify,
    ]) {
      final controller = _controller(
        properties: WmlParagraphProps(
          justification: alignment,
          explicitJustification: true,
        ),
      );
      final paragraph = controller.document.paragraphs.single;
      _direction(controller, TextDirection.rtl);
      expect(paragraph.properties.rightToLeft, isTrue);
      expect(paragraph.properties.justification, alignment);
      _direction(controller, TextDirection.ltr);
      expect(paragraph.properties.rightToLeft, isNull);
      expect(paragraph.properties.justification, alignment);
      controller.insertText('مرحبا');
      expect(paragraph.properties.rightToLeft, isTrue);
      expect(paragraph.properties.justification, alignment);
    }
  });

  test('authored direction replaces an automatic blank-paragraph choice', () {
    final controller = _controller(direction: TextDirection.rtl);
    final paragraph = controller.document.paragraphs.single;
    expect(paragraph.properties.rightToLeft, isTrue);
    controller.setParagraphDirection(rtl: false);
    expect(paragraph.properties.rightToLeft, isFalse);
    for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
      _direction(controller, direction);
      expect(paragraph.properties.rightToLeft, isFalse);
      expect(paragraph.properties.justification, WmlJustification.left);
    }
    controller.insertText('مرحبا');
    expect(paragraph.properties.rightToLeft, isFalse);
    controller.undo();
    expect(paragraph.text, isEmpty);
    expect(paragraph.properties.rightToLeft, isFalse);
    controller.undo();
    expect(paragraph.properties.rightToLeft, isTrue);
    controller.redo();
    expect(paragraph.properties.rightToLeft, isFalse);
  });

  test('replacement properties cannot inherit an earlier automatic latch', () {
    final controller = _controller(direction: TextDirection.rtl);
    final paragraph = controller.document.paragraphs.single;
    expect(paragraph.properties.rightToLeft, isTrue);
    paragraph.properties = paragraph.properties.copy();
    _direction(controller, TextDirection.ltr);
    expect(paragraph.properties.rightToLeft, isTrue);
    expect(paragraph.properties.justification, WmlJustification.right);
    controller.insertText('Latin text');
    expect(paragraph.properties.rightToLeft, isTrue);
  });
}
