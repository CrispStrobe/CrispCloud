import 'package:crisp_cloud/services/legacy_word_copy.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/widgets/legacy_word_conversion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart'
    show CfbfFile, CfbfWriter, DocxPlainReader, OpcPackage;

import '../../packages/quds_office_engine/test/support/legacy_word_fixture.dart';
import '../support/legacy_word_recovery_fixture.dart';

Finder _key(String name) => find.byKey(ValueKey('word-conversion-$name'));

class _Outcome {
  LegacyWordCopy? copy;
  bool completed = false;
}

Future<void> _until(WidgetTester tester, bool Function() complete) async {
  final watch = Stopwatch()..start();
  while (!complete()) {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (watch.elapsed > const Duration(seconds: 15)) {
      throw TimeoutException('Built-in conversion did not complete.');
    }
  }
}

Future<_Outcome> _open(
  WidgetTester tester, {
  required Uint8List source,
  required Future<void> Function(LegacyWordCopy) onSave,
}) async {
  final outcome = _Outcome();
  await tester.binding.setSurfaceSize(const Size(1100, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              outcome.copy = await showLegacyWordConversionDialog(
                context,
                sourceName: 'legacy.doc',
                bytes: source,
                discover: () async => [],
                convert:
                    ({
                      required bytes,
                      required sourceName,
                      required installation,
                      output = InstalledOfficeOutput.docx,
                    }) async {
                      fail(
                        'A built-in choice must not launch an installed app.',
                      );
                    },
                onSave: onSave,
                describeSaveError: (_) => 'Choose another filename.',
              );
              outcome.completed = true;
            },
            child: const Text('Open conversion'),
          ),
        ),
      ),
    ),
  );
  await tester.runAsync(() async {
    await tester.tap(find.text('Open conversion'));
    await _until(tester, () => _key('method').evaluate().isNotEmpty);
  });
  await tester.pumpAndSettle();
  return outcome;
}

Future<void> _tap(WidgetTester tester, Finder control) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.tap(control);
  await tester.pumpAndSettle();
}

Future<void> _tapUntil(
  WidgetTester tester,
  Finder control,
  bool Function() complete,
) async {
  await tester.ensureVisible(control);
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    await tester.tap(control);
    await _until(tester, complete);
  });
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String label) async {
  await _tap(tester, _key('method'));
  await _tap(tester, find.text(label).last);
}

Future<void> _prepare(WidgetTester tester) async {
  await _choose(tester, 'Structured Writer (built in)');
  await _tapUntil(
    tester,
    _key('primary'),
    () => find.text('Review converted copy').evaluate().isNotEmpty,
  );
}

void main() {
  for (final entry in {
    'Word 6/95': (
      source: () => word6RecoveryFixture(),
      text: 'Legacy body text',
      inspected: false,
    ),
    'damaged compound': (
      source: damagedWordRecoveryFixture,
      text: 'Recovered body text',
      inspected: false,
    ),
    'unsupported structure': (
      source: unsupportedStructureRecoveryFixture,
      text: 'Bounded FIB',
      inspected: true,
    ),
  }.entries) {
    testWidgets(
      '${entry.key} recovery is reviewed as a separate text-only copy',
      (tester) async {
        final source = entry.value.source();
        final original = Uint8List.fromList(source);
        final attempts = <LegacyWordCopy>[];
        final outcome = await _open(
          tester,
          source: source,
          onSave: (copy) async {
            attempts.add(copy);
            if (entry.value.inspected && attempts.length == 1) {
              throw StateError('collision');
            }
          },
        );
        if (entry.value.inspected) {
          await _prepare(tester);
        } else {
          await _tap(tester, _key('method'));
          expect(find.text('Structured Writer (built in)'), findsNothing);
          await _tap(tester, find.text('Text only (built in)').last);
          expect(_key('output-text'), findsNothing);
          await _tapUntil(
            tester,
            _key('primary'),
            () => find.text('Review converted copy').evaluate().isNotEmpty,
          );
        }
        expect(find.text('Recovered text only'), findsOneWidget);
        expect(
          find.textContaining('only the recovered main body text'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Formatting, page layout, images'),
          findsOneWidget,
        );
        expect(find.text('Built-in structured conversion'), findsNothing);
        expect(find.textContaining('Support is partial'), findsNothing);
        expect(
          find.textContaining('original VBA project bytes may remain'),
          findsNothing,
        );
        expect(find.text('legacy (text).docx'), findsOneWidget);
        expect(attempts, isEmpty);
        expect(tester.widget<FilledButton>(_key('primary')).onPressed, isNull);
        await _tap(tester, _key('accept-loss'));
        if (entry.value.inspected) {
          await _tapUntil(
            tester,
            _key('primary'),
            () => find.text('Choose another filename.').evaluate().isNotEmpty,
          );
          expect(outcome.completed, isFalse);
          await tester.ensureVisible(_key('filename'));
          await tester.enterText(_key('filename'), 'reviewed-text.docx');
        }
        await _tapUntil(tester, _key('primary'), () => outcome.completed);
        final copy = attempts.last;
        expect(outcome.copy, same(copy));
        expect(copy.recoveredTextOnly, isTrue);
        expect(copy.isTextOnly, isTrue);
        expect(copy.converterName, 'Recovered text only');
        expect(copy.extension, 'docx');
        expect(
          copy.fileName,
          entry.value.inspected ? 'reviewed-text.docx' : 'legacy (text).docx',
        );
        expect(copy.inspection!.sourceInspected, entry.value.inspected);
        expect(
          DocxPlainReader.paragraphs(copy.bytes),
          contains(entry.value.text),
        );
        expect(
          DocxPlainReader.paragraphs(copy.bytes),
          isNot(contains('UNREFERENCED')),
        );
        expect(
          OpcPackage.openBytes(copy.bytes).getPart('/word/vbaProject.bin'),
          isNull,
        );
        expect(() => copy.bytes[0] = 0, throwsUnsupportedError);
        if (entry.value.inspected) {
          expect(attempts, hasLength(2));
          expect(attempts.last.bytes, same(attempts.first.bytes));
          expect(attempts.last.inspection, same(attempts.first.inspection));
          expect(attempts.first.recoveredTextOnly, isTrue);
        }
        expect(source, orderedEquals(original));
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final entry in {
    'encrypted Word 6': () => word6RecoveryFixture(encrypted: true),
    'non-Word input': () =>
        Uint8List.fromList(utf8.encode('%PDF-1.7\nnot a Word document')),
  }.entries) {
    testWidgets('${entry.key} never enables a recovery copy', (tester) async {
      final source = entry.value();
      final original = Uint8List.fromList(source);
      final saves = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: source,
        onSave: (copy) async => saves.add(copy),
      );
      expect(_key('error'), findsOneWidget);
      expect(tester.widget<FilledButton>(_key('primary')).onPressed, isNull);
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(_key('method'))
            .onChanged,
        isNull,
      );
      expect(saves, isEmpty);
      await _tapUntil(tester, find.text('Cancel'), () => outcome.completed);
      expect(outcome.copy, isNull);
      expect(source, orderedEquals(original));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'explicit structured DOCM retains a project and enforces the DOCM filename',
    (tester) async {
      final base = CfbfFile.fromBytes(legacyWordFixture('VBA container\r'));
      final writer = CfbfWriter()
        ..addStream('WordDocument', base.readPath('WordDocument')!)
        ..addStream('1Table', base.readPath('1Table')!)
        ..addStream('Macros/PROJECT', [65, 66])
        ..addStream('Macros/VBA/dir', [1, 2, 3])
        ..addStream('Macros/VBA/_VBA_PROJECT', [4, 5, 6])
        ..addStream('Macros/VBA/Module1', [7, 8, 9]);
      // Synthetic opaque streams exercise preservation, never VBA execution.
      final source = writer.build();
      final original = Uint8List.fromList(source);
      final saves = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: source,
        onSave: (copy) async => saves.add(copy),
      );
      await _choose(tester, 'Structured Writer (built in)');
      expect(find.text('legacy (converted).docx'), findsOneWidget);
      await _tap(tester, _key('output-structured'));
      await _tap(tester, find.text('DOCM (VBA macros)').last);
      expect(find.text('legacy (converted).docm'), findsOneWidget);
      await tester.enterText(_key('filename'), 'wrong.docx');
      await _tap(tester, _key('primary'));
      expect(
        find.text('Enter a single filename ending in .docm.'),
        findsOneWidget,
      );
      expect(saves, isEmpty);
      await tester.enterText(_key('filename'), 'reviewed.docm');
      await _tapUntil(
        tester,
        _key('primary'),
        () => find.text('Review converted copy').evaluate().isNotEmpty,
      );
      expect(tester.widget<FilledButton>(_key('primary')).onPressed, isNull);
      await _tap(tester, _key('accept-loss'));
      await _tapUntil(tester, _key('primary'), () => outcome.completed);
      final copy = saves.single;
      expect(copy.extension, 'docm');
      expect(copy.fileName, 'reviewed.docm');
      expect(copy.inspection!.counts['vba'], 1);
      final output = OpcPackage.openBytes(copy.bytes);
      final project = CfbfFile.fromBytes(
        output.getPart('/word/vbaProject.bin')!.readBytes(),
      );
      expect(project.readPath('VBA/Module1'), [7, 8, 9]);
      expect(source, orderedEquals(original));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'built-in structured conversion requires review and acknowledgement without an installed app',
    (tester) async {
      final source = legacyWordFixture('Hello 世界\rSecond paragraph\r');
      final original = Uint8List.fromList(source);
      final saves = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: source,
        onSave: (copy) async => saves.add(copy),
      );
      expect(tester.widget<FilledButton>(_key('primary')).onPressed, isNull);
      await _choose(tester, 'Structured Writer (built in)');
      expect(find.textContaining('Support is partial'), findsOneWidget);
      expect(find.text('legacy (converted).docx'), findsOneWidget);
      expect(find.text('DOCM (VBA macros)'), findsNothing);
      await tester.enterText(_key('filename'), '../unsafe.docx');
      await _tap(tester, _key('primary'));
      expect(
        find.text('Enter a single filename ending in .docx.'),
        findsOneWidget,
      );
      expect(saves, isEmpty);
      await tester.enterText(_key('filename'), 'reviewed.docx');
      await _tapUntil(
        tester,
        _key('primary'),
        () => find.text('Review converted copy').evaluate().isNotEmpty,
      );
      expect(saves, isEmpty);
      expect(outcome.completed, isFalse);
      expect(find.text('Built-in structured conversion'), findsOneWidget);
      expect(find.text('Conversion limitations'), findsOneWidget);
      expect(_key('preview-pages'), findsNothing);
      expect(tester.widget<FilledButton>(_key('primary')).onPressed, isNull);
      await _tap(tester, _key('accept-loss'));
      await _tapUntil(tester, _key('primary'), () => outcome.completed);
      final copy = saves.single;
      expect(outcome.copy, same(copy));
      expect(copy.fileName, 'reviewed.docx');
      expect(copy.isTextOnly, isFalse);
      expect(copy.extension, 'docx');
      expect(copy.inspection!.counts['paragraphs'], greaterThanOrEqualTo(2));
      expect(DocxPlainReader.paragraphs(copy.bytes), contains('Hello 世界'));
      expect(() => copy.bytes[0] = 0, throwsUnsupportedError);
      expect(source, orderedEquals(original));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inactive macro evidence is disclosed and a collision retry reuses the reviewed bytes',
    (tester) async {
      final attempts = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: legacyWordFixture('Macro source\r', withOpaqueMacro: true),
        onSave: (copy) async {
          attempts.add(copy);
          if (attempts.length == 1) throw StateError('collision');
        },
      );
      await _prepare(tester);
      expect(
        find.text('The converted copy has no active VBA project.'),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'original VBA project bytes may remain as inert evidence',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Macros are disabled during conversion.'),
        findsNothing,
      );
      expect(tester.widget<FilledButton>(_key('primary')).onPressed, isNull);
      await _tap(tester, _key('accept-loss'));
      await _tapUntil(
        tester,
        _key('primary'),
        () => find.text('Choose another filename.').evaluate().isNotEmpty,
      );
      expect(outcome.completed, isFalse);
      expect(find.text('Review converted copy'), findsOneWidget);
      final bytes = Uint8List.fromList(attempts.single.bytes);
      await tester.ensureVisible(_key('filename'));
      await tester.enterText(_key('filename'), 'another.docx');
      await _tapUntil(tester, _key('primary'), () => outcome.completed);
      expect(attempts.map((copy) => copy.fileName), [
        'legacy (converted).docx',
        'another.docx',
      ]);
      expect(attempts.last.bytes, same(attempts.first.bytes));
      expect(attempts.last.bytes, orderedEquals(bytes));
      expect(attempts.last.inspection, same(attempts.first.inspection));
      expect(attempts.last.inspection!.counts['vba'], 0);
      final output = OpcPackage.openBytes(attempts.last.bytes);
      expect(output.getPart('/word/vbaProject.bin'), isNull);
      final manifest = jsonDecode(
        output.getPart('/word/evidence/manifest.json')!.readText(),
      ) as Map<String, dynamic>;
      final evidence = (manifest['records'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .singleWhere((entry) => entry['kind'] == 'vbaProject');
      final retainedProject = CfbfFile.fromBytes(
        output.getPart('/${evidence['part']}')!.readBytes(),
      );
      expect(retainedProject.readPath('VBA/Module1'), [1, 2, 3, 4]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'failed structured conversion keeps its selected method without a text fallback',
    (tester) async {
      final saves = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: legacyWordFixture(
          'Before${String.fromCharCode(0xfffe)}after\r',
        ),
        onSave: (copy) async => saves.add(copy),
      );
      await _choose(tester, 'Structured Writer (built in)');
      await _tapUntil(
        tester,
        _key('primary'),
        () => _key('error').evaluate().isNotEmpty,
      );
      expect(saves, isEmpty);
      expect(outcome.completed, isFalse);
      expect(find.text('Structured Writer (built in)'), findsOneWidget);
      expect(find.text('Review converted copy'), findsNothing);
      expect(find.text('Create text-only DOCX'), findsNothing);
      expect(find.text('legacy (converted).docx'), findsOneWidget);
      await _tapUntil(tester, find.text('Cancel'), () => outcome.completed);
      expect(outcome.copy, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changing conversion discards the prepared choice and retains explicit text-only copying',
    (tester) async {
      final saves = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: legacyWordFixture('Plain copy\r'),
        onSave: (copy) async => saves.add(copy),
      );
      await _prepare(tester);
      await _tap(tester, _key('accept-loss'));
      await _tap(tester, find.text('Change conversion'));
      await _choose(tester, 'Text only (built in)');
      expect(_key('accept-loss'), findsNothing);
      expect(find.textContaining('extracted main body text'), findsOneWidget);
      expect(find.text('legacy (text).docx'), findsOneWidget);
      expect(saves, isEmpty);
      await _tapUntil(tester, _key('primary'), () => outcome.completed);
      expect(saves.single.isTextOnly, isTrue);
      expect(saves.single.fileName, 'legacy (text).docx');
      expect(DocxPlainReader.paragraphs(saves.single.bytes), 'Plain copy');
      expect(tester.takeException(), isNull);
    },
  );
}
