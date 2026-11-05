import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crisp_cloud/services/sftp_client_adapter.dart';
import 'package:crisp_cloud/services/sftp_config_service.dart';
import 'package:crisp_cloud/services/connection_failure.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  test(
      'WebDAV native streaming works below a URL prefix without buffering to EOF',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final gate = Completer<void>();
    final paths = <String>[];
    final audio = List<int>.generate(256 * 1024, (i) => i % 251);
    server.listen((request) async {
      try {
        paths.add(Uri.decodeComponent(request.uri.path));
        if (request.method == 'PROPFIND') {
          request.response.statusCode = 207;
          request.response.write('<multistatus xmlns="DAV:"/>');
        } else {
          expect(request.headers.value('authorization'),
              'Basic ${base64Encode(utf8.encode('reader:pass'))}');
          request.response.bufferOutput = false;
          request.response.contentLength = audio.length;
          request.response.add(audio.sublist(0, 65536));
          await request.response.flush();
          await gate.future;
          request.response.add(audio.sublist(65536));
        }
        await request.response.close();
      } on IOException {/* Consumer cancellation closes its HTTP socket. */}
    });
    final adapter = WebDavClientAdapter(
        config: WebDavConfigService(
            configPath: '', secureStorage: InMemorySecureStorage()));
    final received = <int>[];
    try {
      await adapter.login(
          'reader@http://127.0.0.1:${server.port}/dav/user', 'pass');
      expect(adapter.supportsStreaming, isTrue);
      final first = Completer<void>();
      final done =
          adapter.downloadStream('/Audio Books/chapter 1.mp3').listen((bytes) {
        received.addAll(bytes);
        if (!first.isCompleted) first.complete();
      }).asFuture<void>();
      await first.future.timeout(const Duration(seconds: 5));
      expect(received.length, greaterThan(0));
      expect(received.length, lessThan(audio.length));
      gate.complete();
      await done;
      expect(received, audio);
      expect(paths.last, '/dav/user/Audio Books/chapter 1.mp3');
    } finally {
      if (!gate.isCompleted) gate.complete();
      await adapter.logout();
      await server.close(force: true);
    }
  });
  final python = Platform.environment['CRISPER_SFTP_PYTHON'];
  test('SFTP key login verifies host, persists securely and reconnects', () async {
    final root = await Directory.systemTemp.createTemp('crispcloud_ssh_key_');
    await File('${root.path}/book.txt').writeAsString('fixture');
    final process = await Process.start(
        python!, ['test/support/sftp_fixture.py', root.path, 'publickey']);
    final stderr = process.stderr.drain<void>();
    final info = jsonDecode(await process.stdout.transform(utf8.decoder)
        .transform(const LineSplitter()).first.timeout(const Duration(seconds: 15))) as Map;
    final store = InMemorySecureStorage();
    final client = SFTPClientAdapter(config: SFTPConfigService(configPath: '', secureStorage: store));
    final identity = 'reader@127.0.0.1:${info['port']}';
    final pem = await File('${root.path}/fixture-key').readAsString();
    try {
      await expectLater(client.loginWithPrivateKey(identity, pem, 'wrong'), throwsFormatException);
      expect(await File('${root.path}/auth-count').exists(), isFalse);
      await expectLater(client.loginWithPrivateKey(identity, pem, 'fixture-passphrase'),
          throwsA(isA<SftpHostKeyException>()));
      expect(await File('${root.path}/auth-count').exists(), isFalse);
      client.confirmHostKey = (_, __) async => true;
      final untrusted = await File('${root.path}/fixture-key-untrusted').readAsString();
      await expectLater(client.loginWithPrivateKey(identity, untrusted, null),
          throwsA(isA<SftpConnectionFailure>()));
      expect(await store.readMap('sftp_credentials'), isNull);
      await client.loginWithPrivateKey(identity, pem, 'fixture-passphrase');
      expect(await client.downloadFileBytes('/book.txt'), utf8.encode('fixture'));
      final saved = await store.readMap('sftp_credentials');
      expect(saved?['privateKey'], pem);
      expect(saved?['keyPassphrase'], 'fixture-passphrase');
      expect(saved?.containsKey('password'), isFalse);
      await client.logout();
      await store.writeMap('sftp_credentials', saved!);
      final restored = SFTPClientAdapter(config: SFTPConfigService(configPath: '', secureStorage: store));
      try {
        expect(await restored.downloadFileBytes('/book.txt'), utf8.encode('fixture'));
      } finally {
        await restored.logout();
      }
      final plain = SFTPClientAdapter(config: SFTPConfigService(configPath: '', secureStorage: store));
      try {
        final plainPem = await File('${root.path}/fixture-key-plain').readAsString();
        await plain.loginWithPrivateKey(identity, plainPem, null);
        expect(await plain.downloadFileBytes('/book.txt'), utf8.encode('fixture'));
      } finally {
        await plain.logout();
      }
    } finally {
      await client.logout();
      process.kill();
      await process.exitCode;
      await stderr;
      await root.delete(recursive: true);
    }
  }, skip: python == null ? 'Set CRISPER_SFTP_PYTHON to a Python with paramiko' : false);
  test('SFTP accepts password authentication over keyboard-interactive',
      () async {
    final root = await Directory.systemTemp.createTemp('crispcloud_ssh_pam_');
    final process = await Process.start(
        python!, ['test/support/sftp_fixture.py', root.path, 'interactive']);
    final stderr = process.stderr.drain<void>();
    final info = jsonDecode(await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 15))) as Map;
    final client = SFTPClientAdapter(
        config: SFTPConfigService(
            configPath: '', secureStorage: InMemorySecureStorage()));
    client.confirmHostKey = (_, __) async => true;
    try {
      await client.login(
          'reader@127.0.0.1:${info['port']}', 'fixture-password');
      expect(client.isAuthenticated, isTrue);
      expect(await File('${root.path}/auth-count').readAsString(), '1');
    } finally {
      await client.logout();
      process.kill();
      await process.exitCode;
      await stderr;
      await root.delete(recursive: true);
    }
  },
      skip: python == null
          ? 'Set CRISPER_SFTP_PYTHON to a Python with paramiko'
          : false);
  test('CrispCloud verifies and persists SSH trust before sending a password',
      () async {
    final root = await Directory.systemTemp.createTemp('crispcloud_ssh_');
    await File('${root.path}/book.mp3').writeAsBytes([1, 2, 3]);
    final process = await Process.start(
        python!, ['test/support/sftp_fixture.py', root.path]);
    final stderr = process.stderr.drain<void>();
    final first = await process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 15));
    final info = jsonDecode(first) as Map;
    final store = InMemorySecureStorage();
    SFTPClientAdapter client() => SFTPClientAdapter(
        config: SFTPConfigService(configPath: '', secureStorage: store));
    final unknown = client();
    final identity = 'reader@127.0.0.1:${info['port']}';
    try {
      await expectLater(unknown.login(identity, 'fixture-password'),
          throwsA(isA<SftpHostKeyException>()));
      expect(await File('${root.path}/auth-count').exists(), isFalse);
      final accepted = client();
      accepted.confirmHostKey = (endpoint, fingerprint) async {
        expect(fingerprint, info['hostKey']);
        return true;
      };
      await accepted.login(identity, 'fixture-password');
      expect((await accepted.listPath('/'))['files'], isNotEmpty);
      expect(await accepted.downloadFileBytes('/book.mp3'), [1, 2, 3]);
      await accepted.logout();
      final remembered = client();
      await remembered.login(identity, 'fixture-password');
      final previousCredentials = await store.read('sftp_credentials');
      expect(previousCredentials, isNotNull);
      await remembered.logout();
      await store.write('sftp_credentials', previousCredentials!);
      final auths = await File('${root.path}/auth-count').readAsString();
      await store.write(
          'ssh_known_hosts_v1',
          jsonEncode({
            '127.0.0.1:${info['port']}': 'SHA256:${List.filled(43, 'A').join()}'
          }));
      final changed = client();
      changed.confirmHostKey =
          (_, __) async => throw StateError('Changed key must never prompt');
      await expectLater(changed.login(identity, 'fixture-password'),
          throwsA(isA<SftpHostKeyException>()));
      expect(await File('${root.path}/auth-count').readAsString(), auths);
      expect(await store.read('sftp_credentials'), previousCredentials);
    } finally {
      await unknown.logout();
      process.kill();
      await process.exitCode;
      await stderr;
      await root.delete(recursive: true);
    }
  },
      skip: python == null
          ? 'Set CRISPER_SFTP_PYTHON to a Python with paramiko'
          : false);
}
