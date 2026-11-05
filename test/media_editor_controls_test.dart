import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/widgets/media_editor_controls.dart';
import 'package:crisp_cloud/widgets/media_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter_test/flutter_test.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  test(
    'default export names preserve Unicode and leave a portable byte budget',
    () {
      for (final character in ['界', '🎥']) {
        final source = '${List.filled(100, character).join()}.mp4';
        final name = defaultMediaExportFileName(source, 'mp4');
        final suffix = RegExp(r'-edited-[0-9a-f]{8}\.mp4$').firstMatch(name)!;
        final stem = name.substring(0, suffix.start);
        expect(stem, isNotEmpty);
        expect(utf8.encode(stem).length, lessThanOrEqualTo(160));
        expect(utf8.encode(name).length, lessThanOrEqualTo(240));
        expect(
          stem.runes.every((rune) => rune == character.runes.single),
          isTrue,
        );
        expect(utf8.decode(utf8.encode(name)), name);
      }
    },
  );

  test(
    'default export names replace reserved characters and avoid empty stems',
    () {
      final name = defaultMediaExportFileName('clip:part*?<>|"\\.mp4', 'mp4');
      expect(name, matches(r'^clip_part_+-edited-[0-9a-f]{8}\.mp4$'));
      expect(RegExp(r'[<>:"/\\|?*\x00-\x1f]').hasMatch(name), isFalse);
      expect(
        defaultMediaExportFileName(' .mp4', 'mp4'),
        matches(r'^media-edited-'),
      );
    },
  );

  for (final quarterTurns in [1, 3]) {
    testWidgets(
      'crop presets describe final output after $quarterTurns quarter turns',
      (tester) async {
        const info = MediaInfo(
          kind: MediaKind.video,
          duration: Duration(seconds: 10),
          width: 1920,
          height: 1080,
        );
        var edit = MediaEdit(
          start: Duration.zero,
          end: info.duration,
          quarterTurns: quarterTurns,
        );
        await tester.pumpWidget(
          _app(
            StatefulBuilder(
              builder: (context, setState) => MediaEditorControls(
                info: info,
                edit: edit,
                peaks: const [],
                onChanged: (value) => setState(() => edit = value),
              ),
            ),
          ),
        );

        for (final preset in [(2, 16 / 9), (3, 9 / 16)]) {
          final finder = find.byWidgetPredicate(
            (widget) =>
                widget is DropdownButtonFormField<int> &&
                widget.decoration.labelText == 'Crop',
          );
          tester.widget<DropdownButtonFormField<int>>(finder).onChanged!(
            preset.$1,
          );
          await tester.pump();
          final crop = edit.crop!;
          final outputWidth = info.height! * crop.height;
          final outputHeight = info.width! * crop.width;
          expect(outputWidth / outputHeight, closeTo(preset.$2, 1e-9));
          expect(
            find.byKey(ValueKey('media-crop-${preset.$1}')),
            findsOneWidget,
          );
          expect(crop.x, closeTo((1 - crop.width) / 2, 1e-9));
          expect(crop.y, closeTo((1 - crop.height) / 2, 1e-9));
        }

        // Rotating an existing portrait crop changes the displayed preset label
        // to landscape while preserving its source-space crop rectangle.
        final before = edit.crop;
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Rotate clockwise'),
        );
        await tester.pump();
        expect(edit.crop, before);
        expect(find.byKey(const ValueKey('media-crop-2')), findsOneWidget);
      },
    );
  }

  testWidgets(
    'RTL trim keeps waveform time direction and readable adjustable semantics',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        const info = MediaInfo(
          kind: MediaKind.audio,
          duration: Duration(seconds: 10),
          sampleRate: 48000,
          channels: 2,
        );
        const edit = MediaEdit(
          start: Duration(milliseconds: 1250),
          end: Duration(milliseconds: 8500),
        );
        await tester.pumpWidget(
          _app(
            Directionality(
              textDirection: TextDirection.rtl,
              child: MediaEditorControls(
                info: info,
                edit: edit,
                peaks: const [0.2, 0.8],
                onChanged: (_) {},
              ),
            ),
          ),
        );
        expect(
          Directionality.of(tester.element(find.byType(RangeSlider))),
          TextDirection.ltr,
        );
        final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
        expect(slider.semanticFormatterCallback!(1250000), '0:01.250');
        expect(slider.semanticFormatterCallback!(8500000), '0:08.500');
        final node = tester.getSemantics(find.byType(RangeSlider));
        final thumbs = <String, SemanticsNode>{};
        void collectThumbs(SemanticsNode current) {
          final data = current.getSemanticsData();
          if (['0:01.250', '0:08.500'].contains(data.value) &&
              data.hasAction(SemanticsAction.increase)) {
            thumbs[data.value] = current;
            expect(data.hasAction(SemanticsAction.decrease), isTrue);
          }
          current.visitChildren((child) {
            collectThumbs(child);
            return true;
          });
        }

        collectThumbs(node);
        expect(thumbs.keys, unorderedEquals(['0:01.250', '0:08.500']));
        expect(
          thumbs['0:01.250']!.rect.center.dx,
          lessThan(thumbs['0:08.500']!.rect.center.dx),
        );
      } finally {
        semantics.dispose();
      }
    },
  );
}
