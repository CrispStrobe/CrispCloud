import 'dart:async';
import 'dart:convert';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/transfer_bandwidth_strings.dart';
import 'package:crisp_cloud/providers/transfer_bandwidth_provider.dart';
import 'package:crisp_cloud/widgets/transfer_bandwidth_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

String _policy(int upload, int download) => jsonEncode({
  'version': 1,
  'uploadBytesPerSecond': upload,
  'downloadBytesPerSecond': download,
});

void main() {
  late TransferBandwidthController controller;
  String? stored;
  Completer<String?>? pendingRead;
  Completer<bool>? pendingWrite;
  late List<String> writes;
  var created = false;

  setUp(() {
    stored = null;
    pendingRead = null;
    pendingWrite = null;
    writes = [];
    created = false;
  });

  void createController() {
    created = true;
    controller = TransferBandwidthController(
      readSettings: () async {
        return pendingRead == null ? stored : await pendingRead!.future;
      },
      writeSettings: (value) async {
        writes.add(value);
        final success = pendingWrite == null
            ? true
            : await pendingWrite!.future;
        if (success) stored = value;
        return success;
      },
    );
  }

  tearDown(() {
    if (created) {
      controller.dispose();
    }
  });

  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    bool narrow = false,
    bool browser = false,
    bool settle = true,
  }) async {
    createController();
    if (narrow) {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [transferBandwidthProvider.overrideWith((_) => controller)],
        child: MaterialApp(
          locale: Locale(language),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(narrow ? 2 : 1)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TransferBandwidthSettingsTile(),
                  const TransferBandwidthActionButton(),
                  const TransferBandwidthTrafficSummary(),
                  if (browser)
                    Builder(
                      builder: (context) => TextButton(
                        key: const ValueKey('open-browser-bandwidth'),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (_) => const TransferBandwidthDialog(
                            browserUploadUnsupported: true,
                          ),
                        ),
                        child: const Text('Browser settings'),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester, {
    String key = 'settings-transfer-bandwidth',
    bool settle = true,
  }) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  Future<void> save(WidgetTester tester, {bool settle = true}) async {
    final button = find.byKey(const ValueKey('bandwidth-save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  test('rate input handles unlimited, fractions and localized digits without widening limits', () {
    expect(parseTransferBandwidthKibibytes('0'), 0);
    expect(parseTransferBandwidthKibibytes('  '), 0);
    expect(parseTransferBandwidthKibibytes('0.5'), 512);
    expect(parseTransferBandwidthKibibytes('1,25'), 1280);
    expect(parseTransferBandwidthKibibytes('١٫٥'), 1536);
    expect(parseTransferBandwidthKibibytes('۱۰'), 10240);
    expect(parseTransferBandwidthKibibytes('0.0009765625'), 1);
    expect(
      parseTransferBandwidthKibibytes('1073741824'),
      TransferBandwidthLimits.maximumBytesPerSecond,
    );
    for (final value in [
      '-1',
      'NaN',
      'Infinity',
      '1e9',
      '1.2.3',
      '0.0001',
      '1073741825',
    ]) {
      expect(
        () => parseTransferBandwidthKibibytes(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('all nine languages retain messages and named placeholders', () {
    final translations = TransferBandwidthStrings.translations;
    expect(translations.keys.toSet(), {
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'zh',
      'ja',
      'ko',
      'ar',
    });
    final english = translations['en']!;
    final placeholder = RegExp(r'\{[^}]+\}');
    for (final language in translations.entries) {
      expect(
        language.value.keys.toSet(),
        english.keys.toSet(),
        reason: language.key,
      );
      for (final entry in language.value.entries) {
        expect(entry.value, isNotEmpty);
        expect(
          placeholder.allMatches(entry.value).map((m) => m.group(0)).toSet(),
          placeholder
              .allMatches(english[entry.key]!)
              .map((m) => m.group(0))
              .toSet(),
          reason: '${language.key}: ${entry.key}',
        );
      }
    }
  });

  testWidgets('Settings and Activity share one saved policy and dialog', (
    tester,
  ) async {
    stored = _policy(512, 2048);
    await show(tester);
    await open(tester);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bandwidth-upload')))
          .controller!
          .text,
      '0.5',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bandwidth-upload')),
      '1,25',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bandwidth-download')),
      '0',
    );
    await save(tester);
    expect(find.byType(TransferBandwidthDialog), findsNothing);
    expect(controller.limits.uploadBytesPerSecond, 1280);
    expect(controller.limits.downloadBytesPerSecond, 0);
    expect(jsonDecode(stored!), jsonDecode(_policy(1280, 0)));
    await open(tester, key: 'queue-bandwidth');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bandwidth-upload')))
          .controller!
          .text,
      '1.25',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bandwidth-download')))
          .controller!
          .text,
      '0',
    );
    expect(find.textContaining('Other request paths'), findsOneWidget);
    expect(find.textContaining('Protocol overhead'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid input stays open and does not change either direction', (
    tester,
  ) async {
    stored = _policy(1024, 2048);
    await show(tester);
    await open(tester);
    await tester.enterText(
      find.byKey(const ValueKey('bandwidth-upload')),
      '100',
    );
    await tester.enterText(
      find.byKey(const ValueKey('bandwidth-download')),
      '-5',
    );
    await save(tester);
    expect(find.byType(TransferBandwidthDialog), findsOneWidget);
    expect(find.byKey(const ValueKey('bandwidth-error')), findsOneWidget);
    expect(writes, isEmpty);
    expect(controller.limits.uploadBytesPerSecond, 1024);
    expect(controller.limits.downloadBytesPerSecond, 2048);
  });

  testWidgets(
    'failed durable save retains the active policy and prevents duplicate submits',
    (tester) async {
      stored = _policy(1000, 2000);
      pendingWrite = Completer<bool>();
      await show(tester);
      await open(tester);
      await tester.enterText(
        find.byKey(const ValueKey('bandwidth-upload')),
        '10',
      );
      final oldSubmit = tester
          .widget<FilledButton>(find.byKey(const ValueKey('bandwidth-save')))
          .onPressed!;
      await save(tester, settle: false);
      oldSubmit();
      await tester.pump();
      expect(writes, hasLength(1));
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('bandwidth-save')))
            .onPressed,
        isNull,
      );
      expect(controller.limits.uploadBytesPerSecond, 1000);
      pendingWrite!.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('active policy has not changed'),
        findsOneWidget,
      );
      expect(controller.limits.downloadBytesPerSecond, 2000);
      pendingWrite = null;
      await save(tester);
      expect(find.byType(TransferBandwidthDialog), findsNothing);
      expect(controller.limits.uploadBytesPerSecond, 10240);
    },
  );

  testWidgets(
    'loading prevents premature save and then populates exact stored limits',
    (tester) async {
      pendingRead = Completer<String?>();
      await show(tester, settle: false);
      await open(tester, settle: false);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('bandwidth-save')))
            .onPressed,
        isNull,
      );
      expect(find.text('Loading limits…'), findsWidgets);
      pendingRead!.complete(_policy(512, 1280));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('bandwidth-upload')))
            .controller!
            .text,
        '0.5',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('bandwidth-download')))
            .controller!
            .text,
        '1.25',
      );
      expect(writes, isEmpty);
    },
  );

  testWidgets('unreadable stored policy can be explicitly replaced', (
    tester,
  ) async {
    stored = '{';
    await show(tester);
    await open(tester);
    expect(controller.isReady, isFalse);
    expect(
      find.textContaining('Saved limits could not be loaded'),
      findsWidgets,
    );
    await tester.enterText(find.byKey(const ValueKey('bandwidth-upload')), '5');
    await tester.enterText(
      find.byKey(const ValueKey('bandwidth-download')),
      '8',
    );
    await save(tester);
    await controller.ready;
    expect(controller.isReady, isTrue);
    expect(controller.loadError, isNull);
    expect(controller.limits.uploadBytesPerSecond, 5120);
    expect(controller.limits.downloadBytesPerSecond, 8192);
  });

  testWidgets('browser upload is explicitly unsupported and cannot be edited', (
    tester,
  ) async {
    stored = _policy(3000, 4000);
    await show(tester, browser: true);
    await open(tester, key: 'open-browser-bandwidth');
    expect(
      find.byKey(const ValueKey('bandwidth-browser-upload-unsupported')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('bandwidth-upload')))
          .enabled,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('bandwidth-download')),
      '10',
    );
    await save(tester);
    expect(controller.limits.uploadBytesPerSecond, 3000);
    expect(controller.limits.downloadBytesPerSecond, 10240);
    expect(tester.takeException(), isNull);
  });

  for (final language in ['de', 'ar']) {
    testWidgets(
      'narrow enlarged $language settings remain usable without overflow',
      (tester) async {
        await show(tester, language: language, narrow: true);
        await open(tester);
        final strings = TransferBandwidthStrings.forLanguage(language);
        expect(find.text(strings.text('title')), findsWidgets);
        if (language == 'ar') {
          expect(
            Directionality.of(
              tester.element(find.byType(TransferBandwidthDialog)),
            ),
            TextDirection.rtl,
          );
        }
        final upload = find.byKey(const ValueKey('bandwidth-upload'));
        final download = find.byKey(const ValueKey('bandwidth-download'));
        await tester.ensureVisible(upload);
        await tester.enterText(upload, language == 'ar' ? '١٫٥' : '1,5');
        await tester.ensureVisible(download);
        await tester.enterText(download, '0');
        await save(tester);
        expect(controller.limits.uploadBytesPerSecond, 1536);
        expect(controller.limits.downloadBytesPerSecond, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
