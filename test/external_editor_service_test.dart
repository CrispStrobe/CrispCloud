import 'dart:async';

import 'package:crisp_cloud/services/external_editor_service.dart';
import 'package:crisp_cloud/services/external_remote_editing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/external_edit_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeEditStagingStore store;
  late FakeEditClient client;
  late ExternalRemoteEditingService service;
  late FakeEditorHost host;
  late ExternalEditorLauncher launcher;
  ExternalEditorConfiguration config([List<String> args = const ['{file}']]) =>
      ExternalEditorConfiguration(
        platform: 'linux',
        executable: '/tools/editor',
        arguments: args,
      );
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = FakeEditStagingStore();
    client = FakeEditClient();
    service = ExternalRemoteEditingService(staging: store);
    host = FakeEditorHost();
    launcher = ExternalEditorLauncher(host: host);
  });
  tearDown(() => service.close());

  test('preferences are platform-scoped literal argv and never launch on load or save', () async {
    final preferences = ExternalEditorStore('linux');
    final value = config([
      '--project={"name":"café"}',
      '{file}',
      r'$(touch no); "quotes"',
    ]);
    await preferences.save(value);
    expect((await preferences.load())!.arguments, value.arguments);
    expect(await ExternalEditorStore('windows').load(), isNull);
    expect(host.launches, isEmpty);
    expect(() => value.arguments.add('changed'), throwsUnsupportedError);
    await preferences.reset();
    expect(await preferences.load(), isNull);
  });

  test('known shells and interpreters, missing placeholder and nonabsolute programs are refused', () {
    for (final executable in [
      '/bin/bash',
      '/bin/sh.exe',
      '/bin/python3',
      '/bin/node',
      'editor',
    ]) {
      expect(
        () => ExternalEditorConfiguration(
          platform: 'linux',
          executable: executable,
          arguments: const ['{file}'],
        ),
        throwsA(isA<ExternalEditException>()),
      );
    }
    for (final args in [
      <String>[],
      ['--file={file}'],
      ['{file}', '{file}'],
    ]) {
      expect(() => config(args), throwsA(isA<ExternalEditException>()));
    }
    expect(
      () => ExternalEditorConfiguration(
        platform: 'windows',
        executable: r'C:\tools\bash.exe',
        arguments: const ['{file}'],
      ),
      throwsA(isA<ExternalEditException>()),
    );
  });

  test('launch requires review, retains literal arguments and records intent before detached start', () async {
    final session = await service.prepare(client.source());
    final review = await launcher.prepare(
      session,
      config(['--wait', '{file}', r'a;$(b) "quote"']),
      isCurrent: () => true,
    );
    expect(host.launches, isEmpty);
    host.onLaunch = () async {
      expect(store.bundles[session.id]!.manifest!['launched'], isTrue);
    };
    await launcher.launch(review, autoUpload: false);
    expect(host.launches.single.executable, '/tools/editor');
    expect(host.launches.single.arguments, [
      '--wait',
      review.file.path,
      r'a;$(b) "quote"',
    ]);
    expect(host.launches.single.directory, session.directoryPath);
    expect(session.watching, isTrue);
    expect(session.autoUpload, isFalse);
    expect(client.writes, 0);
    await expectLater(
      launcher.launch(review, autoUpload: false),
      throwsA(isA<ExternalEditException>()),
    );
  });

  for (final mutation in ['draft', 'source', 'executable', 'file', 'grant']) {
    test('changed $mutation after review launches no process', () async {
      final session = await service.prepare(client.source());
      var current = true;
      final review = await launcher.prepare(
        session,
        config(),
        isCurrent: () => current,
      );
      if (mutation == 'draft') current = false;
      if (mutation == 'source') client.reviewCurrent = false;
      if (mutation == 'executable') host.executableVersion++;
      if (mutation == 'file') store.edit(session, [7]);
      if (mutation == 'grant') host.access = false;
      await expectLater(
        launcher.launch(review, autoUpload: false),
        throwsA(isA<ExternalEditException>()),
      );
      expect(host.launches, isEmpty);
      expect(client.writes, 0);
      expect(store.bundles.containsKey(session.id), isTrue);
    });
  }

  test(
    'cleanup refuses a pending detached start and disposal waits then retains',
    () async {
      final session = await service.prepare(client.source());
      final review = await launcher.prepare(
        session,
        config(),
        isCurrent: () => true,
      );
      final starting = Completer<void>();
      final started = Completer<void>();
      host.onLaunch = () async {
        starting.complete();
        await started.future;
      };
      final launch = launcher.launch(review, autoUpload: false);
      await starting.future;
      await expectLater(
        Future<void>.sync(() => session.discard(editorClosed: true)),
        throwsA(isA<ExternalEditException>()),
      );
      var closed = false;
      final closing = service.close().then((_) {
        closed = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      expect(store.bundles[session.id]!.leased, isTrue);
      started.complete();
      await Future.wait([launch, closing]);
      expect(store.bundles.containsKey(session.id), isTrue);
      expect(store.bundles[session.id]!.leased, isFalse);
      expect(session.watching, isFalse);
    },
  );

  test(
    'failed OS launch retains stage and launch intent without automatic upload',
    () async {
      final session = await service.prepare(client.source());
      final review = await launcher.prepare(
        session,
        config(),
        isCurrent: () => true,
      );
      host.onLaunch = () async {
        throw StateError('OS refused');
      };
      await expectLater(
        launcher.launch(review, autoUpload: true),
        throwsA(isA<ExternalEditException>()),
      );
      expect(session.record!.launched, isTrue);
      expect(session.watching, isFalse);
      expect(client.writes, 0);
      expect(store.bundles.containsKey(session.id), isTrue);
    },
  );
}
