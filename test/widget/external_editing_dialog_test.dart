import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/l10n/external_editing_strings.dart';
import 'package:crisp_cloud/services/command_entry_service.dart';
import 'package:crisp_cloud/services/external_editor_service.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:crisp_cloud/widgets/external_editing_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/external_edit_fakes.dart';

void main() {
  late FakeEditStagingStore store;
  late FakeEditClient client;
  late FakeEditorHost host;
  late ExternalRemoteEditingService service;
  late ExternalEditorStore preferences;
  late ExternalEditSource source;
  final services = <ExternalRemoteEditingService>[];
  var exports = 0;

  ExternalRemoteEditingService createService() {
    final result = ExternalRemoteEditingService(
      staging: store,
      debounce: const Duration(milliseconds: 20),
      pollInterval: const Duration(hours: 1),
    );
    services.add(result);
    return result;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = FakeEditStagingStore();
    client = FakeEditClient();
    host = FakeEditorHost();
    source = client.source();
    service = createService();
    preferences = ExternalEditorStore('linux');
    await preferences.save(
      ExternalEditorConfiguration(
        platform: 'linux',
        executable: '/apps/editor tool',
        arguments: const ['--', '{file}'],
      ),
    );
    exports = 0;
  });
  tearDown(() {
    for (final current in services) {
      current.dispose();
    }
    services.clear();
  });

  void editingTest(
    String description,
    Future<void> Function(WidgetTester) body,
  ) {
    testWidgets(description, (tester) async {
      try {
        await body(tester);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        // Services outlive their dialogs; explicitly stop their watchers before
        // the widget binding verifies that no fake-zone timers remain.
        await tester.runAsync(() async {
          for (final current in services) {
            await current.close();
          }
        });
        await tester.pump();
      }
    });
  }

  Finder field(String name) => find.byKey(ValueKey('external-editing-$name'));
  Finder action(String name, ExternalEditSession session) =>
      field('$name-${session.id}');
  String text(String key, [String language = 'en']) =>
      ExternalEditingStrings.messages[key]![ExternalEditingStrings.languages
          .indexOf(language)];
  Future<void> drain(WidgetTester tester, {int ticks = 12}) async {
    for (var tick = 0; tick < ticks; tick++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Future<void> mount(
    WidgetTester tester, {
    bool withSource = true,
    String language = 'en',
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExternalEditingDialog(
                context,
                service: service,
                source: withSource ? source : null,
                preferences: preferences,
                launcher: ExternalEditorLauncher(host: host),
                exportCopy: (session, _) async {
                  exports++;
                  return true;
                },
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await drain(tester);
    await tester.pumpAndSettle();
  }

  Future<ExternalEditSession> prepare(WidgetTester tester) async {
    await tap(tester, field('prepare'));
    expect(find.byType(ExternalEditorLaunchReview), findsOneWidget);
    expect(host.launches, isEmpty);
    return service.sessions.last;
  }

  Future<void> closeReview(WidgetTester tester) =>
      tap(tester, field('review-close'));
  Future<ExternalEditSession> staged(
    WidgetTester tester, {
    bool edited = false,
  }) async {
    final result = await tester.runAsync(() => service.prepare(source));
    if (edited) {
      store.edit(result!, [7, 8, 9], notify: false);
      await tester.runAsync(result.scan);
    }
    return result!;
  }

  editingTest(
    'settings without a source save preferences without staging or launch',
    (tester) async {
      await mount(tester, withSource: false);
      expect(tester.widget<FilledButton>(field('prepare')).onPressed, isNull);
      await tester.enterText(
        field('arguments'),
        '--label "café with spaces" {file}',
      );
      await tap(tester, field('save'));
      final saved = await tester.runAsync(preferences.load);
      expect(saved!.arguments, ['--label', 'café with spaces', '{file}']);
      expect(find.text(text('preferenceSaved')), findsOneWidget);
      expect(host.launches, isEmpty);
      expect(store.bundles, isEmpty);
    },
  );

  editingTest(
    'review pins actual source and private argv with upload consent initially off',
    (tester) async {
      await mount(tester);
      final session = await prepare(tester);
      final review = tester.widget<ExternalEditorLaunchReview>(
        find.byType(ExternalEditorLaunchReview),
      );
      expect(review.prepared.arguments, [
        '--',
        '${session.directoryPath}/${session.record!.workingName}',
      ]);
      expect(review.prepared.arguments, isNot(contains(source.reference.path)));
      expect(
        find.descendant(
          of: find.byType(ExternalEditorLaunchReview),
          matching: find.textContaining(source.reference.storage.accountKey),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<CheckboxListTile>(field('auto-consent')).value,
        isFalse,
      );
      await tap(tester, field('confirm-launch'));
      expect(host.launches.single.arguments, review.prepared.arguments);
      expect(session.watching, isTrue);
      expect(session.autoUpload, isFalse);
      expect(client.writes, 0);
      await closeReview(tester);
      store.edit(session, [5, 6], notify: false);
      await tester.runAsync(session.scan);
      await tester.pump();
      expect(session.record!.hasLocalChanges, isTrue);
      expect(find.text(text('unsent')), findsOneWidget);
      expect(find.textContaining('Last confirmed save'), findsNothing);
      expect(client.writes, 0);
    },
  );

  editingTest(
    'explicit launch consent enables uploads and closing UI retains the live session',
    (tester) async {
      await mount(tester);
      final session = await prepare(tester);
      await tap(tester, field('auto-consent'));
      await tap(tester, field('confirm-launch'));
      expect(session.autoUpload, isTrue);
      await closeReview(tester);
      store.edit(session, [9, 8, 7]);
      await drain(tester);
      expect(client.writes, 1);
      expect(session.record!.savedGeneration, 1);
      expect(session.record!.hasLocalChanges, isFalse);
      expect(
        find.text('Last confirmed save to the original: generation 1.'),
        findsOneWidget,
      );
      await tap(tester, field('close'));
      expect(session.watching, isTrue);
      expect(session.autoUpload, isTrue);
      expect(store.bundles.containsKey(session.id), isTrue);
    },
  );

  editingTest(
    'cancelled launch review retains copy and preserves the argument draft',
    (tester) async {
      await mount(tester);
      final before = parseCommandEntryArguments(
        tester.widget<TextField>(field('arguments')).controller!.text,
      );
      final session = await prepare(tester);
      await closeReview(tester);
      expect(host.launches, isEmpty);
      expect(session.record!.launched, isFalse);
      expect(store.bundles.containsKey(session.id), isTrue);
      expect(
        parseCommandEntryArguments(
          tester.widget<TextField>(field('arguments')).controller!.text,
        ),
        before,
      );
      await tap(tester, field('close'));
      await tester.tap(find.text('Open'));
      await drain(tester);
      await tester.pumpAndSettle();
      await tap(tester, action('rebind', session));
      expect(session.autoUpload, isFalse);
      await tap(tester, action('launch', session));
      expect(find.byType(ExternalEditorLaunchReview), findsOneWidget);
      expect(service.sessions.single.id, session.id);
      expect(host.launches, isEmpty);
      await closeReview(tester);
    },
  );

  editingTest(
    'manual upload reports only confirmed original saves and export remains a separate copy',
    (tester) async {
      final session = await staged(tester, edited: true);
      await mount(tester);
      await tap(tester, action('export', session));
      expect(exports, 1);
      expect(find.text(text('exported')), findsOneWidget);
      expect(session.record!.savedGeneration, 0);
      expect(session.record!.hasLocalChanges, isTrue);
      expect(client.writes, 0);
      await tap(tester, action('upload', session));
      expect(client.bytes, [7, 8, 9]);
      expect(client.writes, 1);
      expect(session.record!.savedGeneration, 1);
      expect(
        find.text('Last confirmed save to the original: generation 1.'),
        findsOneWidget,
      );
    },
  );

  editingTest(
    'source lost during launch review cannot redirect to a newer source',
    (tester) async {
      await mount(tester);
      final session = await prepare(tester);
      client.reviewCurrent = false;
      await tap(tester, field('confirm-launch'));
      expect(host.launches, isEmpty);
      expect(client.writes, 0);
      expect(find.text(text('failure_sourceChanged')), findsOneWidget);
      await closeReview(tester);
      expect(store.bundles.containsKey(session.id), isTrue);
    },
  );

  editingTest(
    'failed launch retains edits and discard requires editor-closed confirmation',
    (tester) async {
      host.onLaunch = () async {
        throw StateError('OS failure');
      };
      await mount(tester);
      final session = await prepare(tester);
      await tap(tester, field('confirm-launch'));
      expect(find.text(text('failure_launchFailed')), findsOneWidget);
      expect(session.record!.launched, isTrue);
      await closeReview(tester);
      expect(store.bundles.containsKey(session.id), isTrue);
      await tap(tester, action('discard', session));
      expect(
        tester.widget<FilledButton>(field('confirm-discard')).onPressed,
        isNull,
      );
      await tap(tester, field('editor-closed'));
      await tap(tester, field('confirm-discard'));
      expect(store.bundles.containsKey(session.id), isFalse);
      expect(service.sessions, isEmpty);
      expect(client.writes, 0);
    },
  );

  editingTest(
    'recovered edits stay paused without upload authority until explicit exact-source reconnect',
    (tester) async {
      final original = await staged(tester, edited: true);
      await tester.runAsync(service.close);
      service = createService();
      await mount(tester);
      final recovered = service.sessions.single;
      expect(recovered.id, original.id);
      expect(recovered.isBound, isFalse);
      expect(recovered.watching, isFalse);
      expect(
        tester.widget<TextButton>(action('upload', recovered)).onPressed,
        isNull,
      );
      expect(host.launches, isEmpty);
      await tap(tester, action('rebind', recovered));
      expect(recovered.isBound, isTrue);
      expect(recovered.autoUpload, isFalse);
      expect(recovered.watching, isFalse);
      expect(client.writes, 0);
      await tap(tester, action('upload', recovered));
      expect(client.writes, 1);
    },
  );

  editingTest(
    'preferences without a matching source offer retained export but no recovery upload',
    (tester) async {
      await staged(tester, edited: true);
      await tester.runAsync(service.close);
      service = createService();
      await mount(tester, withSource: false);
      final recovered = service.sessions.single;
      expect(
        tester.widget<TextButton>(action('rebind', recovered)).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(action('upload', recovered)).onPressed,
        isNull,
      );
      await tap(tester, action('export', recovered));
      expect(exports, 1);
      expect(recovered.record!.savedGeneration, 0);
      expect(client.writes, 0);
    },
  );

  editingTest(
    'changed originals require reviewed replacement and reject a newer remote revision',
    (tester) async {
      final session = await staged(tester, edited: true);
      client.remoteEdit([3, 4]);
      await mount(tester);
      await tap(tester, action('upload', session));
      expect(session.record!.phase, ExternalEditPhase.conflict);
      expect(session.autoUpload, isFalse);
      await tap(tester, action('reviewConflict', session));
      expect(find.byType(ExternalEditConflictDialog), findsOneWidget);
      expect(
        tester.widget<FilledButton>(field('confirm-replace')).onPressed,
        isNull,
      );
      client.remoteEdit([11, 12]);
      await tap(tester, field('replace-consent'));
      await tap(tester, field('confirm-replace'));
      expect(client.bytes, [11, 12]);
      expect(client.writes, 0);
      expect(session.record!.hasLocalChanges, isTrue);
      expect(
        find.descendant(
          of: find.byType(ExternalEditConflictDialog),
          matching: find.text(text('failure_conflict')),
        ),
        findsOneWidget,
      );
    },
  );

  editingTest(
    'copy-only sources never offer automatic or manual original upload',
    (tester) async {
      source = FakeReadOnlyEditClient().source();
      await mount(tester);
      final session = await prepare(tester);
      expect(session.canPublish, isFalse);
      expect(
        tester.widget<CheckboxListTile>(field('auto-consent')).onChanged,
        isNull,
      );
      expect(
        find.descendant(
          of: find.byType(ExternalEditorLaunchReview),
          matching: find.text(text('localOnly')),
        ),
        findsOneWidget,
      );
      await closeReview(tester);
      expect(
        tester.widget<TextButton>(action('upload', session)).onPressed,
        isNull,
      );
      await tap(tester, action('export', session));
      expect(exports, 1);
      expect(session.record!.savedGeneration, 0);
    },
  );

  editingTest('closing during preparation cannot open a late editor review', (
    tester,
  ) async {
    final entered = Completer<void>(), release = Completer<void>();
    var held = false;
    store.beforeManifest = (_) async {
      if (held) return;
      held = true;
      entered.complete();
      await release.future;
    };
    try {
      await mount(tester);
      await tester.tap(field('prepare'));
      await drain(tester);
      expect(entered.isCompleted, isTrue);
      await tester.tap(field('close'));
      await drain(tester);
      release.complete();
      await drain(tester);
      await tester.pumpAndSettle();
      expect(find.byType(ExternalEditorLaunchReview), findsNothing);
      expect(find.byType(ExternalEditingDialog), findsNothing);
      expect(host.launches, isEmpty);
      expect(client.writes, 0);
      expect(
        service.sessions.single.record!.failure,
        ExternalEditFailure.sourceChanged,
      );
    } finally {
      if (!release.isCompleted) release.complete();
      await drain(tester);
    }
  });

  editingTest(
    'corrupt tool preferences never hide retained recovery and export',
    (tester) async {
      await staged(tester, edited: true);
      await tester.runAsync(service.close);
      service = createService();
      await tester.runAsync(() async {
        await (await SharedPreferences.getInstance()).setString(
          'external_editor_v1_linux',
          'invalid json',
        );
      });
      await mount(tester, withSource: false);
      expect(service.sessions, hasLength(1));
      final recovered = service.sessions.single;
      expect(find.text(text('failure_invalid')), findsOneWidget);
      await tap(tester, action('export', recovered));
      expect(exports, 1);
      expect(client.writes, 0);
    },
  );

  for (final language in ['de', 'ar']) {
    editingTest(
      'narrow enlarged $language launch review keeps consent and actions reachable',
      (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await mount(tester, language: language, scale: 1.8);
        expect(tester.takeException(), isNull);
        await prepare(tester);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(field('auto-consent'));
        await tester.pump();
        expect(
          tester.widget<CheckboxListTile>(field('auto-consent')).value,
          isFalse,
        );
        await tester.ensureVisible(field('confirm-launch'));
        await tester.pump();
        expect(
          tester.getRect(field('confirm-launch')).bottom,
          lessThanOrEqualTo(760),
        );
        await closeReview(tester);
        expect(host.launches, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test('every message, phase and failure is present in all nine catalogs', () {
    expect(ExternalEditingStrings.languages.toSet(), {
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
    for (final item in ExternalEditingStrings.messages.entries) {
      expect(item.value, hasLength(9), reason: item.key);
      expect(
        item.value.every((value) => value.trim().isNotEmpty),
        isTrue,
        reason: item.key,
      );
    }
    for (final failure in ExternalEditFailure.values) {
      expect(
        ExternalEditingStrings.messages.containsKey('failure_${failure.name}'),
        isTrue,
      );
    }
    for (final phase in ExternalEditPhase.values) {
      expect(
        ExternalEditingStrings.messages.containsKey('phase_${phase.name}'),
        isTrue,
      );
    }
  });
}
