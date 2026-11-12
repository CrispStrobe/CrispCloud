import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/providers/office_conversion_provider.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/services/legacy_word_conversion.dart';
import 'package:crisp_cloud/services/word_conversion_inspection.dart';
import 'package:crisp_cloud/widgets/legacy_word_conversion_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quds_office_engine/quds_office_engine.dart' show CfbfWriter;

import '../support/legacy_word_fixture.dart';

const _engine = InstalledOfficeInstallation(
  kind: InstalledOfficeKind.libreOffice,
  displayName: 'Fixture Office',
  executablePath: '/not-executed/fixture-office',
);
const _primary = ValueKey('word-conversion-primary');
const _filename = ValueKey('word-conversion-filename');
const _acceptLoss = ValueKey('word-conversion-accept-loss');
const _error = ValueKey('word-conversion-error');

/// Small independent OPC result. The opaque part makes byte-for-byte retention
/// observable without involving any native application or external fixture.
Uint8List _package({bool macroEnabled = false, bool includeVba = false}) {
  const word = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
  const office =
      'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
  const relationships =
      'http://schemas.openxmlformats.org/package/2006/relationships';
  final mainType = macroEnabled
      ? 'application/vnd.ms-word.document.macroEnabled.main+xml'
      : 'application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml';
  final parts = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Default Extension="bin" ContentType="application/octet-stream"/>'
      '<Override PartName="/word/document.xml" ContentType="$mainType"/>'
      '${includeVba ? '<Override PartName="/word/vbaProject.bin" ContentType="application/vnd.ms-office.vbaProject"/>' : ''}'
      '</Types>',
    ),
    '_rels/.rels': utf8.encode(
      '<Relationships xmlns="$relationships">'
      '<Relationship Id="main" Type="$office/officeDocument" Target="word/document.xml"/>'
      '</Relationships>',
    ),
    'word/document.xml': utf8.encode(
      '<w:document xmlns:w="$word"><w:body>'
      '<w:p><w:r><w:t>Converted body</w:t></w:r></w:p><w:sectPr/>'
      '</w:body></w:document>',
    ),
    'custom/opaque.bin': [17, 0, 255, 83],
  };
  if (includeVba) {
    final project = CfbfWriter()
      ..addStream('VBA/Module1', Uint8List.fromList([1, 2, 3, 4]));
    parts['word/vbaProject.bin'] = project.build();
    parts['word/_rels/document.xml.rels'] = utf8.encode(
      '<Relationships xmlns="$relationships">'
      '<Relationship Id="vba" Type="http://schemas.microsoft.com/office/2006/relationships/vbaProject" Target="vbaProject.bin"/>'
      '</Relationships>',
    );
  }
  final archive = Archive();
  for (final part in parts.entries) {
    archive.addFile(ArchiveFile.bytes(part.key, part.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

class _FakeConverter {
  _FakeConverter(this.package, {this.failure});

  final Uint8List package;
  final InstalledOfficeConversionException? failure;
  final outputs = <InstalledOfficeOutput>[];
  Uint8List? source;
  String? sourceName;

  Future<InstalledOfficeConversionResult> call({
    required Uint8List bytes,
    required String sourceName,
    required InstalledOfficeInstallation installation,
    InstalledOfficeOutput output = InstalledOfficeOutput.docx,
  }) async {
    source = bytes;
    this.sourceName = sourceName;
    outputs.add(output);
    if (failure case final error?) throw error;
    return InstalledOfficeConversionResult(
      bytes: package,
      installation: installation,
      output: output,
      elapsed: const Duration(milliseconds: 1),
    );
  }
}

class _DialogOutcome {
  LegacyWordCopy? copy;
  bool completed = false;
}

Future<void> _until(WidgetTester tester, bool Function() complete) async {
  final elapsed = Stopwatch()..start();
  while (!complete()) {
    await tester.pump(const Duration(milliseconds: 20));
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (elapsed.elapsed > const Duration(seconds: 10)) {
      throw TimeoutException(
        'The conversion dialog did not finish its action.',
      );
    }
  }
}

Future<_DialogOutcome> _open(
  WidgetTester tester, {
  required Uint8List source,
  required InstalledOfficeConversion convert,
  required Future<void> Function(LegacyWordCopy) onSave,
  Future<void> Function(Uint8List, String)? onPreviewPdf,
}) async {
  final outcome = _DialogOutcome();
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
                discover: () async => [_engine],
                convert: convert,
                onSave: onSave,
                onPreviewPdf: onPreviewPdf,
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
  // Source inspection uses compute. Build the route and wait in the real zone
  // so isolate completion is not blocked by the widget test's fake clock.
  await tester.runAsync(() async {
    await tester.tap(find.text('Open conversion'));
    await _until(tester, () {
      final button = find.byKey(_primary);
      return button.evaluate().isNotEmpty &&
          tester.widget<FilledButton>(button).onPressed != null;
    });
  });
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return outcome;
}

Future<void> _convertUntil(WidgetTester tester, Finder terminal) async {
  await _tapUntil(
    tester,
    find.byKey(_primary),
    () => terminal.evaluate().isNotEmpty,
  );
}

Future<void> _tapUntil(
  WidgetTester tester,
  Finder control,
  bool Function() complete,
) async {
  await tester.runAsync(() async {
    await tester.tap(control);
    await _until(tester, complete);
  });
  await tester.pumpAndSettle();
}

void main() {
  for (final invalidPreview in [false, true]) {
    testWidgets(
      'page review ${invalidPreview ? 'failure preserves' : 'renders'} the exact prepared copy without saving',
      (tester) async {
        final package = _package();
        final pdf = Uint8List.fromList(
          ascii.encode('%PDF-1.7\npreview fixture\n%%EOF\n'),
        );
        final calls = <InstalledOfficeOutput>[];
        final saved = <LegacyWordCopy>[];
        var previews = 0;
        final outcome = await _open(
          tester,
          source: legacyWordFixture('Original body\r'),
          onSave: (copy) async => saved.add(copy),
          onPreviewPdf: (bytes, name) async {
            previews++;
            expect(bytes, orderedEquals(pdf));
            expect(name, 'legacy (converted).pdf');
            expect(() => bytes[0] = 0, throwsUnsupportedError);
          },
          convert:
              ({
                required bytes,
                required sourceName,
                required installation,
                output = InstalledOfficeOutput.docx,
              }) async {
                calls.add(output);
                if (output == InstalledOfficeOutput.pdf) {
                  expect(bytes, orderedEquals(package));
                  expect(sourceName, 'legacy (converted).docx');
                  expect(installation, same(_engine));
                }
                return InstalledOfficeConversionResult(
                  bytes: output == InstalledOfficeOutput.pdf && !invalidPreview
                      ? pdf
                      : package,
                  installation: installation,
                  output: output,
                  elapsed: Duration.zero,
                );
              },
        );
        await _convertUntil(tester, find.text('Review converted copy'));
        await _tapUntil(
          tester,
          find.byKey(const ValueKey('word-conversion-preview-pages')),
          () => invalidPreview
              ? find.byKey(_error).evaluate().isNotEmpty
              : previews == 1,
        );
        expect(saved, isEmpty);
        expect(outcome.completed, isFalse);
        expect(calls, [InstalledOfficeOutput.docx, InstalledOfficeOutput.pdf]);
        if (invalidPreview) {
          expect(previews, 0);
          expect(
            find.text('The converter did not return a valid PDF preview.'),
            findsOneWidget,
          );
        }
        await _tapUntil(tester, find.byKey(_primary), () => outcome.completed);
        expect(saved.single.bytes, orderedEquals(package));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'reviews installed output before saving its exact package bytes',
    (tester) async {
      final source = legacyWordFixture('Original body\r');
      final converter = _FakeConverter(_package());
      final saved = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: source,
        convert: converter.call,
        onSave: (copy) async => saved.add(copy),
      );
      expect(converter.outputs, isEmpty);
      expect(saved, isEmpty);

      await _convertUntil(tester, find.text('Review converted copy'));
      expect(
        saved,
        isEmpty,
        reason: 'Conversion must not write before review.',
      );
      expect(outcome.completed, isFalse);
      expect(converter.source, same(source));
      expect(converter.sourceName, 'legacy.doc');
      expect(converter.outputs, [InstalledOfficeOutput.docx]);
      expect(find.text('Paragraphs: 1'), findsOneWidget);
      expect(
        find.textContaining('They do not certify visual fidelity'),
        findsOneWidget,
      );
      expect(find.byKey(_acceptLoss), findsNothing);

      await _tapUntil(tester, find.byKey(_primary), () => outcome.completed);
      expect(outcome.completed, isTrue);
      expect(saved, hasLength(1));
      expect(saved.single.fileName, 'legacy (converted).docx');
      expect(saved.single.bytes, orderedEquals(converter.package));
      expect(saved.single.isTextOnly, isFalse);
      expect(saved.single.inspection!.losses, isEmpty);
      expect(outcome.copy!.bytes, orderedEquals(converter.package));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'macro sources default to DOCM and retain the returned VBA package',
    (tester) async {
      final converter = _FakeConverter(
        _package(macroEnabled: true, includeVba: true),
      );
      final saved = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: legacyWordFixture('Macro source\r', withOpaqueMacro: true),
        convert: converter.call,
        onSave: (copy) async => saved.add(copy),
      );
      expect(
        tester.widget<TextField>(find.byKey(_filename)).controller!.text,
        'legacy (converted).docm',
      );
      await _convertUntil(tester, find.text('Review converted copy'));
      expect(converter.outputs, [InstalledOfficeOutput.docm]);
      expect(saved, isEmpty);
      expect(find.text('VBA projects: 1'), findsOneWidget);
      expect(find.byKey(_acceptLoss), findsNothing);
      await _tapUntil(tester, find.byKey(_primary), () => outcome.completed);
      expect(outcome.copy!.extension, 'docm');
      expect(outcome.copy!.bytes, orderedEquals(converter.package));
      expect(saved.single.inspection!.losses, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('invalid output never reaches the review or save callback', (
    tester,
  ) async {
    final converter = _FakeConverter(Uint8List.fromList([0x50, 0x4b, 3, 4]));
    final saved = <LegacyWordCopy>[];
    final outcome = await _open(
      tester,
      source: legacyWordFixture('Original body\r'),
      convert: converter.call,
      onSave: (copy) async => saved.add(copy),
    );
    await _convertUntil(tester, find.byKey(_error));
    expect(
      find.text('The converter did not return a valid Word package.'),
      findsOneWidget,
    );
    expect(find.text('Review converted copy'), findsNothing);
    expect(saved, isEmpty);
    expect(outcome.completed, isFalse);
    expect(converter.outputs, hasLength(1));
    await _tapUntil(tester, find.text('Cancel'), () => outcome.completed);
    expect(outcome.completed, isTrue);
    expect(outcome.copy, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('engine failure stays visible without a silent text conversion', (
    tester,
  ) async {
    final converter = _FakeConverter(
      _package(),
      failure: const InstalledOfficeConversionException(
        InstalledOfficeConversionErrorCode.conversionFailed,
      ),
    );
    final saved = <LegacyWordCopy>[];
    final outcome = await _open(
      tester,
      source: legacyWordFixture('This text could be extracted\r'),
      convert: converter.call,
      onSave: (copy) async => saved.add(copy),
    );
    await _convertUntil(tester, find.byKey(_error));
    expect(
      find.textContaining('The installed application could not convert'),
      findsOneWidget,
    );
    expect(find.text('Convert and review'), findsOneWidget);
    expect(find.text('Create text-only DOCX'), findsNothing);
    expect(
      tester.widget<TextField>(find.byKey(_filename)).controller!.text,
      'legacy (converted).docx',
    );
    expect(saved, isEmpty);
    expect(outcome.completed, isFalse);
    expect(converter.outputs, [InstalledOfficeOutput.docx]);
    await _tapUntil(tester, find.text('Cancel'), () => outcome.completed);
    expect(outcome.copy, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'requires loss acceptance and retries a collision without reconverting',
    (tester) async {
      final converter = _FakeConverter(_package(macroEnabled: true));
      final attempts = <LegacyWordCopy>[];
      final outcome = await _open(
        tester,
        source: legacyWordFixture('Macro source\r', withOpaqueMacro: true),
        convert: converter.call,
        onSave: (copy) async {
          attempts.add(copy);
          if (attempts.length == 1) throw StateError('collision');
        },
      );
      await _convertUntil(tester, find.text('Review converted copy'));
      expect(
        find.text('The converted copy has no active VBA project.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(_primary)).onPressed,
        isNull,
      );
      await tester.tap(find.byKey(_primary));
      await tester.pump();
      expect(attempts, isEmpty);

      await tester.ensureVisible(find.byKey(_acceptLoss));
      await tester.tap(find.byKey(_acceptLoss));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.byKey(_primary)).onPressed,
        isNotNull,
      );
      await _tapUntil(
        tester,
        find.byKey(_primary),
        () => find.text('Choose another filename.').evaluate().isNotEmpty,
      );
      expect(find.text('Choose another filename.'), findsOneWidget);
      expect(outcome.completed, isFalse);
      expect(attempts, hasLength(1));
      expect(attempts.single.inspection!.losses, [
        WordConversionLoss.vbaMissing,
      ]);

      await tester.ensureVisible(find.byKey(_filename));
      await tester.enterText(find.byKey(_filename), 'another.docm');
      await tester.pump();
      await _tapUntil(tester, find.byKey(_primary), () => outcome.completed);
      expect(outcome.completed, isTrue);
      expect(outcome.copy!.fileName, 'another.docm');
      expect(attempts.map((copy) => copy.fileName), [
        'legacy (converted).docm',
        'another.docm',
      ]);
      expect(converter.outputs, [InstalledOfficeOutput.docm]);
      expect(attempts[0].bytes, same(attempts[1].bytes));
      expect(outcome.copy!.bytes, orderedEquals(converter.package));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
