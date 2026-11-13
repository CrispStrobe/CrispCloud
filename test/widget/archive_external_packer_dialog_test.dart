import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/archive_creation_service.dart';
import 'package:crisp_cloud/services/archive_external_packer.dart';
import 'package:crisp_cloud/services/archive_write_model.dart';
import 'package:crisp_cloud/services/file_operation_service.dart';
import 'package:crisp_cloud/widgets/archive_external_packer_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/archive_creation_backend.dart';

class _Preferences implements ArchiveExternalPackerPreferences {
  ArchiveExternalPackerConfiguration? saved;
  int saves = 0, resets = 0;
  @override
  Future<ArchiveExternalPackerConfiguration?> load() async => saved;
  @override
  Future<void> save(ArchiveExternalPackerConfiguration value) async {
    saves++;
    saved = value;
  }

  @override
  Future<void> reset() async {
    resets++;
    saved = null;
  }
}

class _Engine implements ArchiveExternalPackerEngine {
  @override
  String? platform = 'linux';
  int probes = 0, discoveries = 0;
  final profiles = <ArchiveExternalSevenZipProfile>[];
  Object? error;
  Completer<void>? probeGate;
  List<ArchiveExternalPackerConfiguration> candidates = [];
  Set<ArchiveExternalPackerFormat> formats = {
    ArchiveExternalPackerFormat.zip,
    ArchiveExternalPackerFormat.sevenZip,
  };
  @override
  Future<List<ArchiveExternalPackerConfiguration>> discover() async {
    discoveries++;
    return candidates;
  }

  @override
  Future<ArchiveExternalPackerInstallation> probe(
    ArchiveExternalPackerConfiguration configuration, {
    ArchiveExternalSevenZipProfile sevenZipProfile =
        const ArchiveExternalSevenZipProfile(),
    bool Function()? isCancelled,
  }) async {
    probes++;
    profiles.add(sevenZipProfile);
    await probeGate?.future;
    if (isCancelled?.call() ?? false) {
      throw const ArchiveExternalPackerException(
        ArchiveExternalPackerFailure.cancelled,
      );
    }
    if (error != null) throw error!;
    return ArchiveExternalPackerInstallation(
      configuration: configuration,
      identity: ArchiveExternalPackerIdentity(
        path: configuration.executable,
        length: 12,
        modified: DateTime.utc(2024),
        changed: DateTime.utc(2024),
        mode: 0x1c0,
        sha256: 'a' * 64,
      ),
      version: configuration.kind == ArchiveExternalPackerKind.rar
          ? '7.11'
          : '23.01',
      formats: configuration.kind == ArchiveExternalPackerKind.rar
          ? {ArchiveExternalPackerFormat.rar}
          : formats,
      sevenZipProfile: sevenZipProfile,
    );
  }

  @override
  Future<void> write({
    required ArchiveExternalPackerInstallation installation,
    required ArchiveExternalPackerOptions options,
    required List<ArchiveWriteEntry> entries,
    required Future<void> Function(List<int>) sink,
    required int maxOutputBytes,
    bool Function()? isCancelled,
  }) async => throw StateError('The recording creator owns this test.');
}

class _Service extends ArchiveExternalPackerService {
  _Service(_Engine engine) : super(engine: engine);
  final requests = <ArchiveExternalPackerOptions>[];
  String? destinationPath;
  Completer<void>? createGate;
  @override
  Future<ArchiveCreationResult> create({
    required FileOperationBackend source,
    required FileOperationBackend destination,
    required List<FileItem> files,
    required String destinationDirectory,
    required ArchiveExternalPackerInstallation installation,
    required ArchiveExternalPackerOptions options,
    bool Function()? isCancelled,
    void Function(ArchiveCreationProgress)? onProgress,
  }) async {
    requests.add(options);
    destinationPath = destinationDirectory;
    onProgress?.call(
      const ArchiveCreationProgress(
        ArchiveCreationPhase.packing,
        1,
        2,
        'report.txt',
      ),
    );
    await createGate?.future;
    if (isCancelled?.call() ?? false) {
      throw const ArchiveCreationException(ArchiveCreationError.cancelled);
    }
    return ArchiveCreationResult(
      '$destinationDirectory/${options.name}',
      files.length,
      123,
    );
  }
}

void main() {
  late _Preferences preferences;
  late _Engine engine;
  late _Service service;
  late ArchiveCreationBackend backend;
  int created = 0;
  setUp(() {
    preferences = _Preferences();
    engine = _Engine();
    service = _Service(engine);
    backend = ArchiveCreationBackend()..put('/input/report.txt', [1, 2, 3]);
    created = 0;
  });
  Future<void> show(
    WidgetTester tester, {
    String language = 'en',
    double width = 800,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final selected = (await backend.stat('/input/report.txt'))!;
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
          body: ArchiveExternalPackerDialog(
            source: backend,
            destination: backend,
            files: [selected],
            destinationDirectory: '/captured/output',
            service: service,
            preferences: preferences,
            onCreated: () => created++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byKey(ValueKey('archive-external-$name'));
  Future<void> tap(WidgetTester tester, String name) async {
    await tester.ensureVisible(key(name));
    await tester.pumpAndSettle();
    await tester.tap(key(name));
    await tester.pumpAndSettle();
  }

  Future<void> path(
    WidgetTester tester, [
    String value = '/opt/7-Zip/7zz',
  ]) async {
    await tester.ensureVisible(key('path'));
    await tester.enterText(key('path'), value);
    await tester.pumpAndSettle();
  }

  Future<void> probe(WidgetTester tester) async {
    await path(tester);
    await tap(tester, 'probe');
  }

  bool createEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(key('create')).onPressed != null;

  Future<void> chooseFormat(
    WidgetTester tester,
    ArchiveExternalPackerFormat value,
  ) async {
    final field = find.byType(
      DropdownButtonFormField<ArchiveExternalPackerFormat>,
    );
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text(value.label).last);
    await tester.pumpAndSettle();
  }

  Future<void> chooseNumber(
    WidgetTester tester,
    String name,
    String value,
  ) async {
    await tap(tester, name);
    await tester.tap(find.text(value).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'creation requires a capability probe and captures output directory',
    (tester) async {
      await show(tester);
      expect(createEnabled(tester), isFalse);
      await probe(tester);
      expect(createEnabled(tester), isTrue);
      expect(engine.probes, 1);
      expect(preferences.saves, 0);
      await tap(tester, 'create');
      expect(service.requests.single.format, ArchiveExternalPackerFormat.zip);
      expect(service.requests.single.name, 'report.zip');
      expect(service.destinationPath, '/captured/output');
      expect(created, 1);
      expect(key('success'), findsOneWidget);
      expect(key('create'), findsNothing);
    },
  );
  testWidgets('saved paths never restore unverified execution capabilities', (
    tester,
  ) async {
    preferences.saved = ArchiveExternalPackerConfiguration(
      platform: 'linux',
      kind: ArchiveExternalPackerKind.sevenZip,
      executable: '/saved/7zz',
    );
    await show(tester);
    expect(
      tester.widget<TextField>(key('path')).controller!.text,
      '/saved/7zz',
    );
    expect(createEnabled(tester), isFalse);
    expect(engine.probes, 0);
    await tap(tester, 'probe');
    await tap(tester, 'remember');
    expect(preferences.saves, 1);
    expect(preferences.saved!.executable, '/saved/7zz');
    await tap(tester, 'forget');
    expect(preferences.resets, 1);
    expect(preferences.saved, isNull);
  });
  testWidgets(
    'editing the selected executable immediately invalidates capabilities',
    (tester) async {
      await show(tester);
      await probe(tester);
      expect(createEnabled(tester), isTrue);
      await path(tester, '/different/7zz');
      expect(createEnabled(tester), isFalse);
      await tap(tester, 'probe');
      expect(engine.probes, 2);
      expect(createEnabled(tester), isTrue);
    },
  );
  testWidgets('discovery only fills an explicit selection and never runs it', (
    tester,
  ) async {
    engine.candidates = [
      ArchiveExternalPackerConfiguration(
        platform: 'linux',
        kind: ArchiveExternalPackerKind.rar,
        executable: '/opt/RAR Tools/rar',
      ),
    ];
    await show(tester);
    await tap(tester, 'discover');
    expect(engine.discoveries, 1);
    expect(engine.probes, 0);
    await tap(tester, 'candidates');
    await tester.tap(find.text('/opt/RAR Tools/rar').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(key('path')).controller!.text,
      '/opt/RAR Tools/rar',
    );
    expect(createEnabled(tester), isFalse);
    await tap(tester, 'probe');
    final dropdown = tester
        .widget<DropdownButtonFormField<ArchiveExternalPackerFormat>>(
          find.byType(DropdownButtonFormField<ArchiveExternalPackerFormat>),
        );
    expect(dropdown.initialValue, ArchiveExternalPackerFormat.rar);
    expect(
      tester.widget<TextField>(key('name')).controller!.text,
      'report.rar',
    );
    await tap(tester, 'create');
    expect(service.requests.single.format, ArchiveExternalPackerFormat.rar);
  });
  testWidgets('only the proved output formats can be selected', (tester) async {
    engine.formats = {ArchiveExternalPackerFormat.sevenZip};
    await show(tester);
    await probe(tester);
    expect(tester.widget<TextField>(key('name')).controller!.text, 'report.7z');
    final field = find.byType(
      DropdownButtonFormField<ArchiveExternalPackerFormat>,
    );
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    expect(find.text('ZIP'), findsNothing);
    expect(find.text('RAR5'), findsNothing);
    await tester.tap(find.text('7z').last);
    await tester.pumpAndSettle();
    await tap(tester, 'compression');
    await tester.tap(find.text('Maximum').last);
    await tester.pumpAndSettle();
    await tap(tester, 'create');
    expect(
      service.requests.single.compression,
      ArchiveExternalPackerCompression.maximum,
    );
    expect(
      service.requests.single.format,
      ArchiveExternalPackerFormat.sevenZip,
    );
  });
  testWidgets('probe failures are typed and creation remains unavailable', (
    tester,
  ) async {
    engine.error = const ArchiveExternalPackerException(
      ArchiveExternalPackerFailure.capabilityCheckFailed,
    );
    await show(tester);
    await probe(tester);
    expect(key('error'), findsOneWidget);
    expect(createEnabled(tester), isFalse);
    expect(
      find.textContaining('did not pass content and metadata verification'),
      findsOneWidget,
    );
    expect(preferences.saves, 0);
  });
  testWidgets('7z profile changes require a new exact capability check', (
    tester,
  ) async {
    await show(tester);
    await probe(tester);
    expect(key('dictionary'), findsNothing);
    await chooseFormat(tester, ArchiveExternalPackerFormat.sevenZip);
    expect(createEnabled(tester), isTrue);
    await chooseNumber(tester, 'dictionary', '1 MiB');
    expect(createEnabled(tester), isFalse);
    await chooseNumber(tester, 'threads', '4');
    await chooseNumber(tester, 'solid', '32 MiB');
    expect(key('profile-unverified'), findsOneWidget);
    expect(engine.probes, 1);
    expect(preferences.saves, 0);
    await tap(tester, 'probe');
    expect(
      engine.profiles.last,
      const ArchiveExternalSevenZipProfile(
        dictionaryMiB: 1,
        threads: 4,
        solidBlockMiB: 32,
      ),
    );
    expect(createEnabled(tester), isTrue);
    expect(key('profile-unverified'), findsNothing);
    await tap(tester, 'create');
    final options = service.requests.single;
    expect(options.name, 'report.7z');
    expect(options.sevenZipProfile, engine.profiles.last);
  });
  testWidgets('7z-only options do not alter the checked ZIP profile', (
    tester,
  ) async {
    await show(tester);
    await probe(tester);
    await chooseFormat(tester, ArchiveExternalPackerFormat.sevenZip);
    await chooseNumber(tester, 'solid', '16 MiB');
    expect(createEnabled(tester), isFalse);
    await chooseFormat(tester, ArchiveExternalPackerFormat.zip);
    expect(createEnabled(tester), isTrue);
    expect(key('dictionary'), findsNothing);
    expect(key('threads'), findsNothing);
    expect(key('solid'), findsNothing);
    await tap(tester, 'probe');
    expect(engine.profiles.last, const ArchiveExternalSevenZipProfile());
    expect(createEnabled(tester), isTrue);
    await tap(tester, 'create');
    expect(
      service.requests.single.sevenZipProfile,
      const ArchiveExternalSevenZipProfile(),
    );
    expect(service.requests.single.format, ArchiveExternalPackerFormat.zip);
  });
  testWidgets('Store disables only the unused dictionary control', (
    tester,
  ) async {
    engine.formats = {ArchiveExternalPackerFormat.sevenZip};
    await show(tester);
    await probe(tester);
    await tap(tester, 'compression');
    await tester.tap(find.text('Store (no compression)').last);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DropdownButtonFormField<int>>(key('dictionary')).onChanged,
      isNull,
    );
    expect(
      tester.widget<DropdownButtonFormField<int>>(key('threads')).onChanged,
      isNotNull,
    );
    expect(
      tester.widget<DropdownButtonFormField<int>>(key('solid')).onChanged,
      isNotNull,
    );
    expect(createEnabled(tester), isTrue);
  });
  testWidgets('a failed advanced-profile check leaves creation disabled', (
    tester,
  ) async {
    engine.formats = {ArchiveExternalPackerFormat.sevenZip};
    await show(tester);
    await probe(tester);
    await chooseNumber(tester, 'solid', '32 MiB');
    engine.error = const ArchiveExternalPackerException(
      ArchiveExternalPackerFailure.capabilityCheckFailed,
    );
    await tap(tester, 'probe');
    expect(createEnabled(tester), isFalse);
    expect(key('error'), findsOneWidget);
    // Controls remain available to recover from a failed selected profile.
    await chooseNumber(tester, 'solid', '16 MiB');
    engine.error = null;
    await tap(tester, 'probe');
    expect(createEnabled(tester), isTrue);
    expect(engine.profiles.last.solidBlockMiB, 16);
  });
  testWidgets('unknown process errors do not expose logs or private paths', (
    tester,
  ) async {
    engine.error = StateError('/private/workspace secret output token=hidden');
    await show(tester);
    await probe(tester);
    expect(find.textContaining('secret output'), findsNothing);
    expect(
      find.text('The external tool failed. No archive was published.'),
      findsOneWidget,
    );
  });
  testWidgets('cancelling an in-flight probe leaves no usable capabilities', (
    tester,
  ) async {
    engine.probeGate = Completer<void>();
    await show(tester);
    await path(tester);
    await tester.ensureVisible(key('probe'));
    await tester.tap(key('probe'));
    await tester.pump();
    expect(createEnabled(tester), isFalse);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    await tester.tap(key('close'));
    await tester.pump();
    engine.probeGate!.complete();
    await tester.pumpAndSettle();
    expect(createEnabled(tester), isFalse);
    expect(key('error'), findsOneWidget);
    expect(service.requests, isEmpty);
  });
  testWidgets(
    'creation cancellation reaches the service without announcing success',
    (tester) async {
      service.createGate = Completer<void>();
      await show(tester);
      await probe(tester);
      await tester.ensureVisible(key('create'));
      await tester.tap(key('create'));
      await tester.pump();
      await tester.tap(key('close'));
      await tester.pump();
      service.createGate!.complete();
      await tester.pumpAndSettle();
      expect(created, 0);
      expect(key('success'), findsNothing);
      expect(key('error'), findsOneWidget);
    },
  );
  testWidgets('unavailable platform leaves all executable actions disabled', (
    tester,
  ) async {
    engine.platform = null;
    await show(tester);
    expect(createEnabled(tester), isFalse);
    expect(tester.widget<OutlinedButton>(key('discover')).onPressed, isNull);
    expect(tester.widget<TextField>(key('path')).enabled, isFalse);
    expect(
      find.textContaining('desktop builds that permit local processes'),
      findsOneWidget,
    );
  });
  for (final language in ['de', 'fr', 'es', 'pt', 'zh', 'ja', 'ko', 'ar']) {
    testWidgets(
      '$language narrow dialog supports advanced profiles without overflow',
      (tester) async {
        engine.formats = {ArchiveExternalPackerFormat.sevenZip};
        await show(tester, language: language, width: 360, scale: 1.25);
        await probe(tester);
        expect(tester.takeException(), isNull);
        expect(find.text('External archive tool'), findsNothing);
        expect(find.text('Dictionary size'), findsNothing);
        expect(createEnabled(tester), isTrue);
        await chooseNumber(tester, 'dictionary', '4 MiB');
        await chooseNumber(tester, 'threads', '4');
        await chooseNumber(tester, 'solid', '16 MiB');
        expect(createEnabled(tester), isFalse);
        await tap(tester, 'probe');
        expect(createEnabled(tester), isTrue);
        await tap(tester, 'create');
        expect(service.requests.length, 1);
        expect(
          service.requests.single.sevenZipProfile,
          const ArchiveExternalSevenZipProfile(
            dictionaryMiB: 4,
            threads: 4,
            solidBlockMiB: 16,
          ),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
