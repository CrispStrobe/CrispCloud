import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crisp_cloud/l10n/external_terminal_strings.dart';
import 'package:crisp_cloud/services/external_terminal_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/external_terminal_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  ExternalTerminalConfiguration config({String platform = 'linux'}) =>
      ExternalTerminalConfiguration(
        platform: platform,
        executable: platform == 'windows'
            ? r'C:\Tools\Terminal.exe'
            : '/tools/terminal',
        arguments: ['--directory', '{directory}', 'literal "quote"'],
      );
  Matcher failure(ExternalTerminalFailure expected) =>
      isA<ExternalTerminalException>().having(
        (error) => error.failure,
        'failure',
        expected,
      );

  test(
    'argv preserves quotes, Unicode and shell syntax as directory data',
    () async {
      final host = TerminalHostFixture();
      const directory = '/files/a "quoted" café \$HOME \$(echo test) ; &';
      await ExternalTerminalService(host: host).launch(
        config(),
        ExternalTerminalDirectory(
          path: directory,
          isCurrent: () => true,
          hasExistingAccess: () async => true,
        ),
      );
      expect(host.launches.single.executable, '/tools/terminal');
      expect(host.launches.single.arguments, [
        '--directory',
        directory,
        'literal "quote"',
      ]);
      expect(host.launches.single.directory, directory);
    },
  );

  test(
    'Windows paths remain complete arguments and settings use their path style',
    () async {
      final host = TerminalHostFixture(platform: 'windows');
      const directory = r'C:\Users\A & B\作品';
      await ExternalTerminalService(host: host).launch(
        config(platform: 'windows'),
        ExternalTerminalDirectory(
          path: directory,
          isCurrent: () => true,
          hasExistingAccess: () async => true,
        ),
      );
      expect(host.launches.single.arguments[1], directory);
      expect(host.launches.single.directory, directory);
    },
  );

  for (final executable in [
    'relative-terminal',
    '/bin/sh',
    '/bin/bash',
    '/bin/zsh',
  ]) {
    test('rejects an implicit path or shell executable: $executable', () {
      expect(
        () => ExternalTerminalConfiguration(
          platform: 'linux',
          executable: executable,
          arguments: [],
        ),
        throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
      );
    });
  }
  for (final executable in [
    r'C:\Tools\run.cmd',
    r'C:\Tools\run.BAT',
    r'C:\Windows\cmd.exe',
    r'C:\Tools\powershell.exe',
  ]) {
    test('rejects Windows command execution fallback: $executable', () {
      expect(
        () => ExternalTerminalConfiguration(
          platform: 'windows',
          executable: executable,
          arguments: [],
        ),
        throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
      );
    });
  }
  test('rejects unsupported placeholders and excessive configuration before saving', () {
    for (final arguments in [
      ['--cwd={directory}'],
      ['{selection}'],
      ['bad\u0000argument'],
      List.filled(65, 'x'),
      ['x' * 4097],
    ]) {
      expect(
        () => ExternalTerminalConfiguration(
          platform: 'linux',
          executable: '/tools/terminal',
          arguments: arguments,
        ),
        throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
      );
    }
  });

  for (final point in ['access', 'directory', 'executable']) {
    test('view changes during $point check prevent a process launch', () async {
      final host = TerminalHostFixture();
      final gate = Completer<void>();
      if (point == 'directory') host.directoryGate = gate;
      if (point == 'executable') host.executableGate = gate;
      var current = true;
      final pending = ExternalTerminalService(host: host).launch(
        config(),
        ExternalTerminalDirectory(
          path: '/files',
          isCurrent: () => current,
          hasExistingAccess: () async {
            if (point == 'access') await gate.future;
            return true;
          },
        ),
      );
      final rejected = expectLater(
        pending,
        throwsA(failure(ExternalTerminalFailure.changed)),
      );
      while (point != 'access' &&
          (point == 'directory'
                  ? host.checkedDirectories
                  : host.checkedExecutables)
              .isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      current = false;
      gate.complete();
      await rejected;
      expect(host.launches, isEmpty);
    });
  }
  test(
    'unavailable access is never replaced by a fallback directory',
    () async {
      final host = TerminalHostFixture();
      await expectLater(
        ExternalTerminalService(host: host).launch(
          config(),
          ExternalTerminalDirectory(
            path: '/files',
            isCurrent: () => true,
            hasExistingAccess: () async => false,
          ),
        ),
        throwsA(failure(ExternalTerminalFailure.accessUnavailable)),
      );
      expect(host.checkedDirectories, isEmpty);
      expect(host.launches, isEmpty);
    },
  );
  test(
    'missing executable and missing directory are actionable without fallback',
    () async {
      final host = TerminalHostFixture()..executableExists = false;
      final directory = ExternalTerminalDirectory(
        path: '/files',
        isCurrent: () => true,
        hasExistingAccess: () async => true,
      );
      await expectLater(
        ExternalTerminalService(host: host).launch(config(), directory),
        throwsA(failure(ExternalTerminalFailure.executableUnavailable)),
      );
      host.directoryExists = false;
      await expectLater(
        ExternalTerminalService(host: host).launch(config(), directory),
        throwsA(failure(ExternalTerminalFailure.accessUnavailable)),
      );
      expect(host.launches, isEmpty);
    },
  );
  test(
    'unsupported runtime and another platform configuration cannot launch',
    () async {
      final directory = ExternalTerminalDirectory(
        path: '/files',
        isCurrent: () => true,
        hasExistingAccess: () async => true,
      );
      await expectLater(
        ExternalTerminalService(host: TerminalHostFixture(platform: null))
            .launch(config(), directory),
        throwsA(failure(ExternalTerminalFailure.unsupported)),
      );
      await expectLater(
        ExternalTerminalService(host: TerminalHostFixture(platform: 'windows'))
            .launch(config(), directory),
        throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
      );
    },
  );
  test('runtime errors do not expose arbitrary exception contents', () async {
    final host = TerminalHostFixture()
      ..launchError = StateError('https://user:secret@private.example');
    await expectLater(
      ExternalTerminalService(host: host).launch(
        config(),
        ExternalTerminalDirectory(
          path: '/files',
          isCurrent: () => true,
          hasExistingAccess: () async => true,
        ),
      ),
      throwsA(failure(ExternalTerminalFailure.launchFailed)),
    );
  });
  test('preferences roundtrip per OS, reject mismatched saves and reset independently', () async {
    final linux = ExternalTerminalStore('linux');
    final windows = ExternalTerminalStore('windows');
    await linux.save(config());
    await windows.save(config(platform: 'windows'));
    await expectLater(
      linux.save(config(platform: 'windows')),
      throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
    );
    expect(
      (await ExternalTerminalStore('linux').load())!.toJson(),
      config().toJson(),
    );
    await linux.reset();
    expect(await linux.load(), isNull);
    expect((await windows.load())!.platform, 'windows');
  });
  test(
    'malformed or unsupported saved data is reported without erasing it',
    () async {
      final store = ExternalTerminalStore('linux');
      final prefs = await SharedPreferences.getInstance();
      for (final raw in [
        'bad json',
        jsonEncode({...config().toJson(), 'version': 2}),
        jsonEncode(config(platform: 'windows').toJson()),
        'x' * 65537,
      ]) {
        await prefs.setString(store.key, raw);
        await expectLater(
          store.load(),
          throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
        );
        expect(prefs.getString(store.key), raw);
      }
    },
  );
  test(
    'native host distinguishes real directories and absent executables',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'external-terminal-',
      );
      addTearDown(() => directory.delete(recursive: true));
      const host = NativeExternalTerminalHost();
      expect(await host.directoryAvailable(directory.path), isTrue);
      expect(
        await host.executableAvailable('${directory.path}/missing'),
        isFalse,
      );
    },
  );
  test(
    'expanded arguments and the working directory retain the launch bounds',
    () async {
      final host = TerminalHostFixture();
      final expanded = ExternalTerminalConfiguration(
        platform: 'linux',
        executable: '/tools/terminal',
        arguments: List.filled(64, '{directory}'),
      );
      for (final path in ['/${'x' * 1000}', '/${'x' * 4096}']) {
        await expectLater(
          ExternalTerminalService(host: host).launch(
            expanded,
            ExternalTerminalDirectory(
              path: path,
              isCurrent: () => true,
              hasExistingAccess: () async => true,
            ),
          ),
          throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
        );
      }
      expect(host.checkedDirectories, isEmpty);
      expect(host.launches, isEmpty);
    },
  );
  test(
    'escaped settings cannot save a value that exceeds the load limit',
    () async {
      final store = ExternalTerminalStore('linux');
      await store.save(config());
      final escaped = ExternalTerminalConfiguration(
        platform: 'linux',
        executable: '/tools/terminal',
        arguments: List.filled(8, '\u0001' * 3000),
      );
      expect(jsonEncode(escaped.toJson()).length, greaterThan(65536));
      await expectLater(
        store.save(escaped),
        throwsA(failure(ExternalTerminalFailure.invalidConfiguration)),
      );
      expect((await store.load())!.toJson(), config().toJson());
    },
  );
  test('all supported languages have complete terminal labels and errors', () {
    final translations = ExternalTerminalStrings.translations;
    expect(translations.keys.toSet(), {
      'en',
      'de',
      'fr',
      'es',
      'pt',
      'ja',
      'ko',
      'zh',
      'ar',
    });
    for (final language in translations.entries) {
      expect(
        language.value.keys.toSet(),
        translations['en']!.keys.toSet(),
        reason: language.key,
      );
      expect(language.value.values.every((value) => value.isNotEmpty), isTrue);
      for (final reason in ExternalTerminalFailure.values) {
        expect(
          ExternalTerminalStrings.forLanguage(language.key)
              .failure(ExternalTerminalException(reason)),
          isNotEmpty,
        );
      }
    }
  });
}
