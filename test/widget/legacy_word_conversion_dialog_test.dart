import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/legacy_word_conversion.dart';
import 'package:crisp_cloud/widgets/legacy_word_conversion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

import '../support/legacy_word_fixture.dart';

void main() {
  testWidgets('discloses text-only losses before preparing a new DOCX', (
    tester,
  ) async {
    final source = legacyWordFixture('Hello 世界\r');
    LegacyWordDocxCopy? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showLegacyWordConversionDialog(
                context,
                sourceName: 'legacy.doc',
                bytes: source,
              );
            },
            child: const Text('Open conversion'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open conversion'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Formatting, page layout'), findsOneWidget);
    expect(find.textContaining('The original file is kept'), findsOneWidget);
    expect(find.text('legacy (text).docx'), findsOneWidget);
    expect(result, isNull);

    await tester.enterText(find.byType(TextField), '../unsafe.docx');
    await tester.tap(find.text('Create text-only DOCX'));
    await tester.pump();
    expect(
      find.text('Enter a single filename ending in .docx.'),
      findsOneWidget,
    );
    expect(result, isNull);

    await tester.enterText(find.byType(TextField), 'converted.docx');
    await tester.runAsync(() async {
      await tester.tap(find.text('Create text-only DOCX'));
      final watch = Stopwatch()..start();
      while (result == null) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (watch.elapsed > const Duration(seconds: 15)) {
          throw TimeoutException('The DOCX conversion did not finish.');
        }
      }
    });
    expect(result!.fileName, 'converted.docx');
    expect(DocxPlainReader.paragraphs(result!.bytes), 'Hello 世界');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('German conversion disclosure can be cancelled', (tester) async {
    var completed = false;
    LegacyWordDocxCopy? result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('de'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showLegacyWordConversionDialog(
                context,
                sourceName: 'vorlage.dot',
                bytes: legacyWordFixture('Vorlage\r'),
              );
              completed = true;
            },
            child: const Text('Open conversion'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open conversion'));
    await tester.pumpAndSettle();
    expect(find.text('In DOCX konvertieren'), findsOneWidget);
    expect(find.textContaining('Das Original bleibt erhalten'), findsOneWidget);
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('save failure keeps the prepared workflow open for a new name', (
    tester,
  ) async {
    final attempts = <String>[];
    LegacyWordDocxCopy? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showLegacyWordConversionDialog(
                context,
                sourceName: 'legacy.doc',
                bytes: legacyWordFixture('Copy body\r'),
                onSave: (copy) async {
                  attempts.add(copy.fileName);
                  if (attempts.length == 1) throw StateError('collision');
                },
                describeSaveError: (_) => 'Choose another filename.',
              );
            },
            child: const Text('Open conversion'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open conversion'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('Create text-only DOCX'));
      final watch = Stopwatch()..start();
      while (find.text('Choose another filename.').evaluate().isEmpty) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (watch.elapsed > const Duration(seconds: 15)) {
          throw TimeoutException('The save failure was not reported.');
        }
      }
    });
    expect(result, isNull);
    expect(find.byType(LegacyWordConversionDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'another.docx');
    await tester.runAsync(() async {
      await tester.tap(find.text('Create text-only DOCX'));
      final watch = Stopwatch()..start();
      while (result == null) {
        await tester.pump(const Duration(milliseconds: 20));
        await Future<void>.delayed(const Duration(milliseconds: 1));
        if (watch.elapsed > const Duration(seconds: 15)) {
          throw TimeoutException('The copy retry did not finish.');
        }
      }
    });
    expect(attempts, ['legacy (text).docx', 'another.docx']);
    expect(result!.fileName, 'another.docx');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
