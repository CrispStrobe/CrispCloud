import 'package:crisp_cloud/l10n/image_editor_strings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' as material;
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/core/mixins/converted_configs.dart';
import 'package:pro_image_editor/core/mixins/converted_callbacks.dart';
import 'package:pro_image_editor/core/mixins/editor_configs_mixin.dart';
import 'package:pro_image_editor/core/mixins/standalone_editor.dart';

class _TextTool extends StatefulWidget with SimpleConfigsAccess {
  const _TextTool({super.key});
  @override
  ProImageEditorConfigs get configs => const ProImageEditorConfigs(
    textEditor: TextEditorConfigs(enableAutoOverflow: false),
  );
  @override
  ProImageEditorCallbacks get callbacks => ProImageEditorCallbacks();
  @override
  State<_TextTool> createState() => _TextToolState();
}

class _TextToolState extends State<_TextTool>
    with ImageEditorConvertedConfigs, SimpleConfigsAccessState {
  String draft = 'unsaved text';
  @override
  void initState() {
    super.initState();
    // Production tools read their configuration during initialization.
    expect(configs.textEditor.enableAutoOverflow, isFalse);
  }

  @override
  Widget build(BuildContext context) => Text('$draft: ${i18n.textEditor.done}');
}

class _CropTool extends StatefulWidget
    with StandaloneEditor<CropRotateEditorInitConfigs> {
  const _CropTool({super.key});
  @override
  CropRotateEditorInitConfigs get initConfigs =>
      CropRotateEditorInitConfigs(theme: material.ThemeData());
  @override
  EditorImage? get editorImage => null;
  @override
  ProVideoController? get videoController => null;
  @override
  State<_CropTool> createState() => _CropToolState();
}

class _CropToolState extends State<_CropTool>
    with
        ImageEditorConvertedConfigs,
        ImageEditorConvertedCallbacks,
        StandaloneEditorState<_CropTool, CropRotateEditorInitConfigs> {
  int rotation = 90;
  @override
  Widget build(BuildContext context) => Text(
    '$rotation: ${i18n.cropRotateEditor.ratio}: ${cropRotateEditorConfigs.aspectRatios.first.text}',
  );
}

void main() {
  testWidgets(
    'open tools follow every locale without losing unsaved tool state',
    (tester) async {
      final textKey = GlobalKey<_TextToolState>();
      final cropKey = GlobalKey<_CropToolState>();
      final textTool = _TextTool(key: textKey);
      final cropTool = _CropTool(key: cropKey);
      _TextToolState? originalText;
      _CropToolState? originalCrop;
      for (final language in ImageEditorStrings.supportedLanguageCodes) {
        final strings = ImageEditorStrings.editorI18nForLocale(
          Locale(language),
        );
        final free = ImageEditorStrings.forLanguage(language, 'Free');
        await tester.pumpWidget(
          Directionality(
            textDirection: language == 'ar'
                ? TextDirection.rtl
                : TextDirection.ltr,
            child: EditorLocalizationScope(
              i18n: strings,
              aspectRatios: [AspectRatioItem(text: free, value: -1)],
              child: Column(children: [textTool, cropTool]),
            ),
          ),
        );
        originalText ??= textKey.currentState;
        originalCrop ??= cropKey.currentState;
        expect(textKey.currentState, same(originalText));
        expect(cropKey.currentState, same(originalCrop));
        expect(
          find.text('unsaved text: ${strings.textEditor.done}'),
          findsOneWidget,
        );
        expect(
          find.text('90: ${strings.cropRotateEditor.ratio}: $free'),
          findsOneWidget,
        );
        expect(
          textKey.currentState!.configs.textEditor.enableAutoOverflow,
          isFalse,
        );
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('standalone tools retain original configs without a host scope', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: _TextTool(),
      ),
    );
    expect(find.text('unsaved text: Done'), findsOneWidget);
  });
}
