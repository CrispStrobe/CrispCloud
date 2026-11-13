import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/installed_office_preview_strings.dart';
import 'package:crisp_cloud/providers/office_conversion_provider.dart';
import 'package:crisp_cloud/services/installed_office_converter.dart';
import 'package:crisp_cloud/widgets/installed_office_preview_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _office = InstalledOfficeInstallation(
  kind: InstalledOfficeKind.libreOffice,
  displayName: 'LibreOffice fixture',
  executablePath: '/not-executed/libreoffice',
);
const _word = InstalledOfficeInstallation(
  kind: InstalledOfficeKind.microsoftWord,
  displayName: 'Word fixture',
  executablePath: '/not-executed/word',
);
const _noPdf = InstalledOfficeInstallation(
  kind: InstalledOfficeKind.libreOffice,
  displayName: 'Text export only',
  executablePath: '/not-executed/text-only',
  supportedOutputs: {InstalledOfficeOutput.docx},
);

const _primary = ValueKey('installed-preview-primary');
const _close = ValueKey('installed-preview-close');
const _selector = ValueKey('installed-preview-application');
const _error = ValueKey('installed-preview-error');

// The dialog checks a generated PDF's bounded envelope; the real PDF viewer
// validates its structure. This independent payload never launches an app.
Uint8List _pdf() =>
    Uint8List.fromList(utf8.encode('%PDF-1.7\n1 0 obj <<>> endobj\n%%EOF\n'));

InstalledOfficeConversionResult _result({
  InstalledOfficeInstallation installation = _office,
  InstalledOfficeOutput output = InstalledOfficeOutput.pdf,
  Uint8List? bytes,
}) => InstalledOfficeConversionResult(
  bytes: bytes ?? _pdf(),
  installation: installation,
  output: output,
  elapsed: const Duration(milliseconds: 1),
);

Future<void> _open(
  WidgetTester tester, {
  String sourceName = 'letter.doc',
  Uint8List? bytes,
  InstalledOfficeDiscovery? discover,
  InstalledOfficeConversion? convert,
  Future<void> Function(Uint8List, String)? preview,
  Locale locale = const Locale('en'),
  double scale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showInstalledOfficePreviewDialog(
              context,
              sourceName: sourceName,
              bytes: bytes ?? Uint8List.fromList([1, 2, 3, 4]),
              discover: discover ?? () async => [_office],
              convert:
                  convert ??
                  ({
                    required bytes,
                    required sourceName,
                    required installation,
                    output = InstalledOfficeOutput.docx,
                  }) async => _result(installation: installation),
              onPreviewPdf: preview ?? (_, _) async {},
            ),
            child: const Text('Open preview action'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open preview action'));
  await tester.pumpAndSettle();
}

void _platformTest(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.linux,
}) => testWidgets(
  description,
  callback,
  variant: TargetPlatformVariant.only(platform),
);

void main() {
  _platformTest(
    'requires an explicit selected app and preserves source bytes',
    (tester) async {
      final source = Uint8List.fromList([10, 20, 30, 40]);
      final calls = <InstalledOfficeInstallation>[];
      Uint8List? received;
      Uint8List? previewed;
      String? previewName;
      await _open(
        tester,
        bytes: source,
        sourceName: 'Letter.DOCX',
        discover: () async => [_office, _word, _noPdf],
        convert:
            ({
              required bytes,
              required sourceName,
              required installation,
              output = InstalledOfficeOutput.docx,
            }) async {
              calls.add(installation);
              received = bytes;
              expect(sourceName, 'Letter.DOCX');
              expect(output, InstalledOfficeOutput.pdf);
              expect(() => bytes[0] = 0, throwsUnsupportedError);
              return _result(installation: installation);
            },
        preview: (pdf, name) async {
          previewed = pdf;
          previewName = name;
          expect(() => pdf[0] = 0, throwsUnsupportedError);
        },
      );
      expect(calls, isEmpty);
      final menu = tester.widget<DropdownButton<int>>(
        find.descendant(
          of: find.byKey(_selector),
          matching: find.byType(DropdownButton<int>),
        ),
      );
      expect(menu.items, hasLength(2));
      source[0] = 99;
      await tester.tap(find.byKey(_selector));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Word fixture (installed)').last);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tap(find.byKey(_primary));
      await tester.pumpAndSettle();
      expect(calls, [_word]);
      expect(received, orderedEquals([10, 20, 30, 40]));
      expect(source, orderedEquals([99, 20, 30, 40]));
      expect(previewName, 'Letter.pdf');
      expect(previewed, orderedEquals(_pdf()));
      expect(find.text('Preview created with Word fixture.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  _platformTest('no installed app keeps the built-in view available', (
    tester,
  ) async {
    var discoveries = 0;
    await _open(
      tester,
      discover: () async {
        discoveries++;
        return discoveries == 1 ? [_noPdf] : [_office];
      },
    );
    expect(
      find.byKey(const ValueKey('installed-preview-unavailable')),
      findsOneWidget,
    );
    expect(tester.widget<FilledButton>(find.byKey(_primary)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byKey(_close)).onPressed, isNotNull);
    await tester.tap(
      find.byKey(const ValueKey('installed-preview-check-again')),
    );
    await tester.pumpAndSettle();
    expect(discoveries, 2);
    expect(
      tester.widget<FilledButton>(find.byKey(_primary)).onPressed,
      isNotNull,
    );
  });

  for (final invalid in [
    ('unsupported suffix', 'document.pptx', Uint8List.fromList([1])),
    ('empty document', 'empty.doc', Uint8List(0)),
    (
      'over-limit input',
      'large.doc',
      Uint8List(kInstalledOfficeInputLimit + 1),
    ),
  ]) {
    _platformTest('rejects ${invalid.$1} before discovering applications', (
      tester,
    ) async {
      var discovered = false;
      await _open(
        tester,
        sourceName: invalid.$2,
        bytes: invalid.$3,
        discover: () async {
          discovered = true;
          return [_office];
        },
      );
      expect(discovered, isFalse);
      expect(find.byKey(_error), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byKey(_primary)).onPressed,
        isNull,
      );
      expect(
        find.byKey(const ValueKey('installed-preview-check-again')),
        findsNothing,
      );
    });
  }

  _platformTest('does not probe installed applications on mobile', (
    tester,
  ) async {
    var discovered = false;
    await _open(
      tester,
      discover: () async {
        discovered = true;
        return [_office];
      },
    );
    expect(discovered, isFalse);
    expect(find.byKey(_error), findsOneWidget);
    expect(supportsInstalledOfficePreview, isFalse);
  }, platform: TargetPlatform.android);

  _platformTest('conversion cannot be duplicated or dismissed while running', (
    tester,
  ) async {
    final result = Completer<InstalledOfficeConversionResult>();
    var calls = 0;
    await _open(
      tester,
      convert:
          ({
            required bytes,
            required sourceName,
            required installation,
            output = InstalledOfficeOutput.docx,
          }) {
            calls++;
            return result.future;
          },
    );
    await tester.tap(find.byKey(_primary));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Preparing page preview…'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(_primary)).onPressed, isNull);
    expect(tester.widget<TextButton>(find.byKey(_close)).onPressed, isNull);
    expect(
      tester
          .widget<DropdownButtonFormField<int>>(find.byKey(_selector))
          .onChanged,
      isNull,
    );
    final context = tester.element(find.byType(InstalledOfficePreviewDialog));
    expect(await Navigator.of(context).maybePop(), isTrue);
    await tester.pump();
    expect(find.byType(InstalledOfficePreviewDialog), findsOneWidget);
    result.complete(_result());
    await tester.pumpAndSettle();
    expect(tester.widget<TextButton>(find.byKey(_close)).onPressed, isNotNull);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    expect(find.byType(InstalledOfficePreviewDialog), findsNothing);
  });

  for (final invalid in [
    ('wrong output format', () => _result(output: InstalledOfficeOutput.docx)),
    ('wrong engine', () => _result(installation: _word)),
    ('invalid PDF', () => _result(bytes: Uint8List.fromList([1, 2, 3]))),
  ]) {
    _platformTest('rejects ${invalid.$1} before showing preview', (
      tester,
    ) async {
      var displayed = false;
      await _open(
        tester,
        convert: ({
          required bytes,
          required sourceName,
          required installation,
          output = InstalledOfficeOutput.docx,
        }) async => invalid.$2(),
        preview: (_, _) async => displayed = true,
      );
      await tester.tap(find.byKey(_primary));
      await tester.pumpAndSettle();
      expect(displayed, isFalse);
      expect(
        find.text('The application did not return a valid PDF preview.'),
        findsOneWidget,
      );
      expect(
        tester.widget<FilledButton>(find.byKey(_primary)).onPressed,
        isNotNull,
      );
    });
  }

  _platformTest('reports timeout and allows an explicit retry', (tester) async {
    var attempts = 0;
    var displayed = 0;
    await _open(
      tester,
      convert:
          ({
            required bytes,
            required sourceName,
            required installation,
            output = InstalledOfficeOutput.docx,
          }) async {
            attempts++;
            if (attempts == 1) {
              throw const InstalledOfficeConversionException(
                InstalledOfficeConversionErrorCode.timeout,
              );
            }
            return _result();
          },
      preview: (_, _) async => displayed++,
    );
    await tester.tap(find.byKey(_primary));
    await tester.pumpAndSettle();
    expect(find.textContaining('did not finish in time'), findsOneWidget);
    expect(displayed, 0);
    await tester.tap(find.byKey(_primary));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(displayed, 1);
    expect(find.byKey(_error), findsNothing);
  });

  _platformTest('drops results after parent disposal', (tester) async {
    final result = Completer<InstalledOfficeConversionResult>();
    var displayed = false;
    await _open(
      tester,
      convert: ({
        required bytes,
        required sourceName,
        required installation,
        output = InstalledOfficeOutput.docx,
      }) => result.future,
      preview: (_, _) async => displayed = true,
    );
    await tester.tap(find.byKey(_primary));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    result.complete(_result());
    await tester.pumpAndSettle();
    expect(displayed, isFalse);
    expect(tester.takeException(), isNull);
  });

  _platformTest('discovery and viewer errors do not leak exception details', (
    tester,
  ) async {
    await _open(
      tester,
      discover: () async => throw StateError('/private/document/path'),
    );
    expect(find.textContaining('/private/'), findsNothing);
    expect(find.byKey(_error), findsOneWidget);
    await tester.tap(find.byKey(_close));
    await tester.pumpAndSettle();
    await _open(
      tester,
      preview: (_, _) async => throw StateError('/private/preview/path'),
    );
    await tester.tap(find.byKey(_primary));
    await tester.pumpAndSettle();
    expect(find.textContaining('/private/'), findsNothing);
    expect(
      find.textContaining('could not be created or opened'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  _platformTest('localized controls fit a narrow enlarged-text dialog', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(480, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final locale in AppLocalizations.supportedLocales) {
      await _open(tester, locale: locale, scale: 1.4);
      final strings = InstalledOfficePreviewStrings(locale);
      expect(find.text(strings.text('title')), findsOneWidget);
      expect(
        tester.takeException(),
        isNull,
        reason: 'No overflow for ${locale.languageCode}',
      );
      await tester.tap(find.byKey(_close));
      await tester.pumpAndSettle();
    }
  });
}
