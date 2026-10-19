@Tags(['live'])
@Timeout(Duration(minutes: 5))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:internxt_client/internxt_client.dart' as sdk;
import 'package:uuid/uuid.dart';
import 'package:crisp_cloud/services/internxt_client_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;
  final enabled = Platform.environment['CRISP_INTERNXT_DOWNLOAD_LIVE'] == '1' &&
      !Platform.environment.containsKey('CI') &&
      !Platform.environment.containsKey('GITHUB_ACTIONS');
  test('live Internxt adapter publishes the requested filename', () async {
    if (!enabled) {
      throw StateError(
          'This live account test requires the local credential launcher.');
    }
    await runZoned(() async {
      final root =
          await Directory.systemTemp.createTemp('crisp-internxt-live-');
      final config = sdk.ConfigService(
          configPath: root.path, storage: sdk.InMemoryConfigStorage());
      final adapter = InternxtClientAdapter(config: config);
      final fixture = sdk.InternxtClient(config: config);
      final folder = '/__crispcloud_download_${const Uuid().v4()}';
      final name = 'Original document ${const Uuid().v4()}.txt';
      final bytes = utf8.encode('CrispCloud owned download fixture.');
      var created = false;
      var stage = 'login';
      try {
        await adapter.login(Platform.environment['CRISP_INTERNXT_TEST_EMAIL']!,
            Platform.environment['CRISP_INTERNXT_TEST_PASSWORD']!);
        fixture.setAuth(adapter.lastLoginResponse!);
        stage = 'create fixture';
        await fixture.createFolderPath(folder);
        created = true;
        await fixture.uploadFileBytes(bytes, name, folder);
        stage = 'download under a different local name';
        final output = File('${root.path}/preview-renamed.bin');
        await output.writeAsBytes([9]);
        await adapter.downloadFileByPath('$folder/$name', output.path);
        expect(await output.readAsBytes(), bytes);
        stage = 'download through the SDK stem alias';
        await adapter.downloadFileByPath(
            '$folder/${name.substring(0, name.length - 4)}',
            '${root.path}/stem-alias.bin');
        expect(await File('${root.path}/stem-alias.bin').readAsBytes(), bytes);
        Zone.root
            .print('CrispCloud Internxt live renamed/stem downloads passed');
      } catch (error) {
        throw TestFailure('Internxt $stage failed (${error.runtimeType})');
      } finally {
        if (created) {
          try {
            await fixture.deletePath(folder);
            Zone.root.print('Owned CrispCloud test folder moved to trash');
          } catch (error) {
            Zone.root.print(
                'Owned fixture cleanup failed (${error.runtimeType}): $folder');
          }
        }
        await root.delete(recursive: true);
      }
    },
        zoneSpecification:
            ZoneSpecification(print: (self, parent, zone, line) {}));
  }, skip: enabled ? false : 'Local opt-in test credentials required');
}
