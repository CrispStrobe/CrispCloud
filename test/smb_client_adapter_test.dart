import 'dart:convert';
import 'dart:io';
import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/smb_config_service.dart';
import 'package:crisp_cloud/services/smb_client_adapter.dart';
import 'package:crisp_storage/crisp_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final python = Platform.environment['CRISPER_SMB_PYTHON'];
  test('SMB provider uses secure credentials and supports complete file-manager operations', () async {
    final root = await Directory.systemTemp.createTemp('crispcloud_smb_');
    final output = await Directory.systemTemp.createTemp('crispcloud_smb_download_');
    final process = await Process.start(python!, ['packages/crisp_storage/tool/smb_fixture.py', root.path]);
    final errors = <String>[];
    final stderr = process.stderr.transform(utf8.decoder).listen(errors.add);
    final config = SmbConfigService(InMemorySecureStorage());
    final client = CloudStorageFactory.create(CloudProvider.smb, config: config) as SmbClientAdapter;
    SmbClientAdapter? restored;
    try {
      final info = jsonDecode(await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(seconds: 15))) as Map;
      final identity = 'reader@smb://127.0.0.1:${info['port']}/books/';
      expect(await client.restoreCredentials(), isFalse);
      expect(client.supportsTrash, isFalse);
      expect(client.supportsStreaming, isTrue);
      await expectLater(client.login(identity, 'fixture-password'), throwsA(isA<RemoteException>()));
      expect(await config.readCredentials(), isNull);
      client.requireEncryption = false;
      await client.login(identity, 'fixture-password');
      expect(client.isAuthenticated, isTrue);
      await client.createFolderPath('/Audio Books/Disc 1');
      await client.uploadStream(Stream.fromIterable([[1, 2], [3, 4]]), 4, 'Chapter #1.mp3', '/Audio Books/Disc 1');
      final listing = await client.listPath('/Audio Books/Disc 1');
      expect((listing['files'] as List).single['path'], '/Audio Books/Disc 1/Chapter #1.mp3');
      expect((await client.resolvePath('/Audio Books/Disc 1/Chapter #1.mp3'))!['size'], 4);
      await client.downloadFileByPath('/Audio Books/Disc 1/Chapter #1.mp3', '${output.path}/chapter.mp3');
      expect(await File('${output.path}/chapter.mp3').readAsBytes(), [1, 2, 3, 4]);
      expect(await File('${output.path}/chapter.mp3.resume').exists(), isFalse);
      restored = SmbClientAdapter(config: config);
      expect(await restored.restoreCredentials(), isTrue);
      expect(restored.requireEncryption, isFalse);
      await restored.renamePath('/Audio Books/Disc 1/Chapter #1.mp3', 'Chapter 2.mp3');
      expect(await restored.downloadFileBytes('/Audio Books/Disc 1/Chapter 2.mp3'), [1, 2, 3, 4]);
      await restored.movePath('/Audio Books/Disc 1', '/Audio Books/Disc 2');
      await restored.deletePath('/Audio Books');
      expect((await restored.listPath('/'))['folders'], isEmpty);
      await expectLater(client.deletePath('/'), throwsFormatException);
      await expectLater(client.createFolderPath('../outside'), throwsFormatException);
      await expectLater(client.renamePath('/a', '../outside'), throwsFormatException);
      await client.logout();
      expect(await config.readCredentials(), isNull);
      expect(client.isAuthenticated, isFalse);
    } catch (e) {
      if (e is RemoteException) throw Exception('SMB diagnostic: ${e.cause}');
      rethrow;
    } finally {
      await client.logout(); await restored?.logout();
      process.kill(); await process.exitCode.timeout(const Duration(seconds: 10));
      await stderr.cancel();
      await root.delete(recursive: true); await output.delete(recursive: true);
    }
  }, skip: python == null ? 'Set CRISPER_SMB_PYTHON to a Python with impacket.' : false, timeout: const Timeout(Duration(minutes: 3)));
}
