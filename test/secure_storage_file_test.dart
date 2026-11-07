import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:crisp_cloud/services/secure_storage_file_io.dart';
import 'package:crisp_cloud/services/secure_storage_web.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('credential storage mode is persisted outside the vault', () async {
    SharedPreferences.setMockInitialValues({});
    expect(
      await CredentialStorageConfig.readMode(),
      CredentialStorageMode.systemKeychain,
    );
    await CredentialStorageConfig.writeMode(
      CredentialStorageMode.encryptedFile,
    );
    expect(
      await CredentialStorageConfig.readMode(),
      CredentialStorageMode.encryptedFile,
    );
    await CredentialStorageConfig.writeCustomKeychainPath(
      '/tmp/brickwright.keychain-db',
    );
    expect(
      await CredentialStorageConfig.readCustomKeychainPath(),
      '/tmp/brickwright.keychain-db',
    );
  });

  test('encrypted file vault persists values across instances', () async {
    final directory = Directory.systemTemp.createTempSync('crisp-vault-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final file = File('${directory.path}/credential-vault.json');

    final first = WebEncryptedStorage(
      FileStorageBackend(file),
      newVaultIterations: 1000,
    );
    await first.initialize('correct horse battery staple');
    await first.write('internxt', 'secret-value');

    final second = WebEncryptedStorage(
      FileStorageBackend(file),
      newVaultIterations: 1000,
    );
    await second.initialize('correct horse battery staple');
    expect(await second.read('internxt'), 'secret-value');
    expect(await file.exists(), isTrue);
    if (!Platform.isWindows) {
      expect(FileStat.statSync(file.path).mode & 0x1ff, 0x180);
    }
  });

  group('transactional encrypted file vault', () {
    late Directory directory;
    late File file;

    WebEncryptedStorage vault({FileStorageBackend? backend}) =>
        WebEncryptedStorage(backend ?? FileStorageBackend(file),
            newVaultIterations: 1000);

    setUp(() {
      directory = Directory.systemTemp.createTempSync('crisp-vault-');
      file = File('${directory.path}/credential-vault.json');
      addTearDown(() => directory.deleteSync(recursive: true));
    });

    test('first-run password factory refuses an already existing vault', () async {
      final original = vault();
      await original.initialize('same-password');
      await original.write('internxt', 'preserve-this-secret');
      final before = await file.readAsBytes();
      final previous = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _VaultPaths(directory.path);
      addTearDown(() => PathProviderPlatform.instance = previous);

      // Even the correct password must not turn first-run creation into an
      // existing-vault unlock, which could incorrectly reset app-lock policy.
      await expectLater(
        createEncryptedFileStorage(masterPassword: 'same-password'),
        throwsStateError,
      );
      expect(await file.readAsBytes(), before);
      final returned = await createEncryptedFileStorage();
      expect(returned, isA<EncryptedFileStorage>());
      final locked = returned as EncryptedFileStorage;
      expect(locked.isInitialized, isFalse);
      expect(await locked.hasVault(), isTrue);
      expect(await file.readAsBytes(), before);
    });

    test('first-run factory preserves a vault created during path lookup', () async {
      final previous = PathProviderPlatform.instance;
      late List<int> committed;
      PathProviderPlatform.instance = _VaultPaths(directory.path,
        beforeLookupCompletes: () async {
          final competitor = vault();
          await competitor.initialize('same-password');
          await competitor.write('filen', 'concurrently-created-secret');
          committed = await file.readAsBytes();
        },
      );
      addTearDown(() => PathProviderPlatform.instance = previous);
      await expectLater(
        createEncryptedFileStorage(masterPassword: 'same-password'),
        throwsStateError,
      );
      expect(await file.readAsBytes(), committed);
      final restarted = vault();
      await restarted.initialize('same-password', expectedExisting: true);
      expect(await restarted.read('filen'), 'concurrently-created-secret');
    });

    test('two unlocked instances preserve sequential and overlapping writes', () async {
      final first = vault();
      final second = vault();
      await first.initialize('pw');
      await second.initialize('pw');
      await first.write('filen', 'first-secret');
      await second.write('internxt', 'second-secret');
      // Reads must also observe another instance's commit, not a stale cache.
      expect(await first.read('internxt'), 'second-secret');
      expect(await second.read('filen'), 'first-secret');
      await Future.wait([
        for (var i = 0; i < 12; i++)
          (i.isEven ? first : second).write('token-$i', 'value-$i'),
      ]);
      final restarted = vault();
      await restarted.initialize('pw');
      expect(await restarted.read('filen'), 'first-secret');
      expect(await restarted.read('internxt'), 'second-secret');
      for (var i = 0; i < 12; i++) {
        expect(await restarted.read('token-$i'), 'value-$i');
      }
    });

    test('parallel initialization commits one compatible generation', () async {
      final first = vault();
      final second = vault();
      await Future.wait([first.initialize('pw'), second.initialize('pw')]);
      await Future.wait([
        first.write('filen', 'one'),
        second.write('internxt', 'two'),
      ]);
      final restarted = vault();
      await restarted.initialize('pw');
      expect(await restarted.read('filen'), 'one');
      expect(await restarted.read('internxt'), 'two');
    });

    test('parallel different passwords cannot initialize a mixed vault', () async {
      final first = vault();
      final second = vault();
      Future<bool> unlock(WebEncryptedStorage candidate, String password) async {
        try {
          await candidate.initialize(password);
          return true;
        } on StateError {
          return false;
        }
      }
      final results = await Future.wait([
        unlock(first, 'first-password'),
        unlock(second, 'second-password'),
      ]);
      expect(results.where((value) => value).length, 1);
      final winner = results[0] ? first : second;
      final password = results[0] ? 'first-password' : 'second-password';
      await winner.write('token', 'preserved');
      final restarted = vault();
      await restarted.initialize(password);
      expect(await restarted.read('token'), 'preserved');
    });

    test('rename failure keeps the previous committed bytes and releases locks', () async {
      final first = vault();
      await first.initialize('pw');
      await first.write('token', 'preserve');
      final before = await file.readAsBytes();
      var replacements = 0;
      final failing = vault(backend: FileStorageBackend(file,
        replaceForTesting: (temporary, destination) async {
          replacements++;
          expect(await destination.readAsBytes(), before);
          expect(await temporary.exists(), isTrue);
          throw const FileSystemException('Injected replacement failure');
        },
      ));
      await failing.initialize('pw');
      await expectLater(failing.write('token', 'destroy'),
          throwsA(isA<FileSystemException>()));
      expect(replacements, 1);
      expect(await file.readAsBytes(), before);
      expect(await directory.list().where((entry) =>
          entry is Directory).toList(), isEmpty);
      final restarted = vault();
      await restarted.initialize('pw');
      expect(await restarted.read('token'), 'preserve');
      await restarted.write('other', 'works-after-failure');
      expect(await restarted.read('other'), 'works-after-failure');
    });

    test('failed initial publication leaves no partial salt or verification', () async {
      final failing = vault(backend: FileStorageBackend(file,
        replaceForTesting: (_, _) async {
          throw const FileSystemException('Injected first commit failure');
        },
      ));
      await expectLater(failing.initialize('pw'),
          throwsA(isA<FileSystemException>()));
      expect(failing.isInitialized, isFalse);
      expect(await file.exists(), isFalse);
      expect(await failing.hasVault(), isFalse);
      final restarted = vault();
      await restarted.initialize('different-password');
      await restarted.write('token', 'fresh');
      expect(await restarted.read('token'), 'fresh');
    });

    test('transaction failure rolls back all staged changes', () async {
      final backend = FileStorageBackend(file);
      await backend.setItem('existing', 'preserve');
      final before = await file.readAsBytes();
      await expectLater(backend.transaction<void>((staged) async {
        await staged.setItem('existing', 'changed');
        await staged.setItem('added', 'no');
        throw StateError('Injected transaction failure');
      }), throwsStateError);
      expect(await file.readAsBytes(), before);
      expect(await backend.getItem('added'), isNull);
      expect(await backend.getItem('existing'), 'preserve');
    });

    test('transaction handles cannot mutate state after completion', () async {
      final backend = FileStorageBackend(file);
      late WebStorageBackend expired;
      await backend.transaction<void>((staged) async { expired = staged; });
      await expectLater(expired.setItem('key', 'value'), throwsStateError);
      expect(await file.exists(), isFalse);
    });

    test('an active transaction excludes a separate isolate', () async {
      final backend = FileStorageBackend(file);
      await backend.setItem('token', 'preserve');
      final before = await file.readAsBytes();
      final ready = ReceivePort();
      final complete = ReceivePort();
      final child = await Isolate.spawn(_holdVaultTransaction,
          (file.path, ready.sendPort, complete.sendPort));
      addTearDown(() {
        ready.close();
        complete.close();
        child.kill(priority: Isolate.immediate);
      });
      final signal = await ready.first.timeout(const Duration(seconds: 10));
      expect(signal, isA<SendPort>(), reason: '$signal');
      try {
        await expectLater(backend.setItem('token', 'overwrite'), throwsStateError);
        expect(await file.readAsBytes(), before);
      } finally {
        (signal as SendPort).send('release');
      }
      expect(await complete.first.timeout(const Duration(seconds: 10)), 'released');
      await backend.setItem('after-release', 'allowed');
      expect(await backend.getItem('token'), 'preserve');
    });

    test('replacing a vault invalidates an old unlocked handle before writing', () async {
      final old = vault();
      await old.initialize('old-password');
      await old.write('old-token', 'old-value');
      final replacementFile = File('${directory.path}/replacement.json');
      final replacement = WebEncryptedStorage(FileStorageBackend(replacementFile),
          newVaultIterations: 1000);
      await replacement.initialize('new-password');
      await replacement.write('new-token', 'new-value');
      // Simulates an externally restored vault / changed master key.
      final changed = await replacementFile.readAsBytes();
      await file.writeAsBytes(changed, flush: true);
      await expectLater(old.write('old-token', 'corrupt-new-vault'), throwsStateError);
      expect(old.isInitialized, isFalse);
      expect(await file.readAsBytes(), changed);
      final restarted = vault();
      await restarted.initialize('new-password');
      expect(await restarted.read('new-token'), 'new-value');
      expect(await restarted.read('old-token'), isNull);
    });

    for (final damaged in ['', '  ', '[]', '{"token": 7}', '{"token": null}', '{']) {
      test('corrupt existing file is preserved: ${jsonEncode(damaged)}', () async {
        await file.writeAsString(damaged);
        final candidate = vault();
        await expectLater(candidate.hasVault(), throwsStateError);
        await expectLater(candidate.initialize('new-password'), throwsStateError);
        expect(candidate.isInitialized, isFalse);
        expect(await file.readAsString(), damaged);
      });
    }

    test('missing metadata preserves existing ciphertext on restart', () async {
      final first = vault();
      await first.initialize('pw');
      await first.write('token', 'preserve');
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      data.remove('crisp_enc_verify');
      await file.writeAsString(jsonEncode(data));
      final before = await file.readAsBytes();
      final restarted = vault();
      await expectLater(restarted.initialize('new-password'), throwsStateError);
      expect(await file.readAsBytes(), before);
    });

    test('staging permissions are restricted before publication', () async {
      var checked = false;
      final candidate = vault(backend: FileStorageBackend(file,
        replaceForTesting: (temporary, destination) async {
          if (!Platform.isWindows) {
            expect((await temporary.stat()).mode & 0x1ff, 0x180);
            expect((await temporary.parent.stat()).mode & 0x1ff, 0x1c0);
          }
          checked = true;
          await temporary.rename(destination.path);
        },
      ));
      await candidate.initialize('pw');
      expect(checked, isTrue);
      if (!Platform.isWindows) {
        expect((await file.stat()).mode & 0x1ff, 0x180);
        expect((await File('${file.path}.lock').stat()).mode & 0x1ff, 0x180);
      }
    });

    test('a pre-existing legacy temp symlink is never followed', () async {
      final sentinel = File('${directory.path}/sentinel.txt');
      await sentinel.writeAsString('do not truncate');
      await Link('${file.path}.tmp').create(sentinel.path);
      final candidate = vault();
      await candidate.initialize('pw');
      await candidate.write('token', 'secret');
      expect(await sentinel.readAsString(), 'do not truncate');
      expect(await candidate.read('token'), 'secret');
    }, skip: Platform.isWindows ? 'Creating links needs Windows privileges' : false);

    test('vault symlinks are rejected without touching their target', () async {
      final sentinel = File('${directory.path}/sentinel.json');
      await sentinel.writeAsString('{"keep":"unchanged"}');
      await Link(file.path).create(sentinel.path);
      final candidate = vault();
      await expectLater(candidate.hasVault(), throwsA(isA<FileSystemException>()));
      await expectLater(candidate.initialize('pw'), throwsA(isA<FileSystemException>()));
      expect(await sentinel.readAsString(), '{"keep":"unchanged"}');
    }, skip: Platform.isWindows ? 'Creating links needs Windows privileges' : false);

    test('lock symlinks are rejected without touching their target', () async {
      final sentinel = File('${directory.path}/sentinel.txt');
      await sentinel.writeAsString('keep unchanged');
      await Link('${file.path}.lock').create(sentinel.path);
      final candidate = vault();
      await expectLater(candidate.initialize('pw'), throwsA(isA<FileSystemException>()));
      expect(await sentinel.readAsString(), 'keep unchanged');
      expect(await file.exists(), isFalse);
    }, skip: Platform.isWindows ? 'Creating links needs Windows privileges' : false);
  });

}

// flock must exclude separate isolates as well as processes. Dart's POSIX
// RandomAccessFile.lock alone would allow both isolates to hold an "exclusive"
// process-wide fcntl lock and would fail this deterministic contention test.
void _holdVaultTransaction((String, SendPort, SendPort) args) async {
  final (path, ready, complete) = args;
  final release = ReceivePort();
  var announced = false;
  try {
    await FileStorageBackend(File(path)).transaction<void>((_) async {
      ready.send(release.sendPort);
      announced = true;
      await release.first;
    });
    complete.send('released');
  } catch (error) {
    if (!announced) ready.send(error.toString());
    complete.send(error.toString());
  } finally {
    release.close();
  }
}

class _VaultPaths extends PathProviderPlatform {
  _VaultPaths(this.path, {this.beforeLookupCompletes});
  final String path;
  final Future<void> Function()? beforeLookupCompletes;

  @override
  Future<String?> getApplicationSupportPath() async {
    await beforeLookupCompletes?.call();
    return path;
  }
}
