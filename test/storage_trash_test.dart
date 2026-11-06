import 'dart:convert';

import 'package:crisp_cloud/services/gdrive_client_adapter.dart';
import 'package:crisp_cloud/services/gdrive_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/native_file_operations.dart';
import 'package:crisp_cloud/services/storage_trash.dart';
import 'package:crisp_cloud/services/action_history_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Google Drive delete defaults to trash; restore uses the returned object ID', () async {
    final requests = <http.Request>[];
    var trashed = false;
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.host == 'oauth2.googleapis.com') {
        return http.Response(
          jsonEncode({'access_token': 'test-only', 'expires_in': 3600}),
          200,
        );
      }
      if (request.method == 'GET' && request.url.path.endsWith('/files')) {
        return http.Response(
          jsonEncode({
            'files': trashed
                ? []
                : [
                    {'id': 'file-42', 'name': 'report.txt'},
                  ],
          }),
          200,
        );
      }
      if (request.method == 'PATCH') {
        expect(request.url.path, '/drive/v3/files/file-42');
        trashed = (jsonDecode(request.body) as Map)['trashed'] as bool;
        return http.Response('{}', 200);
      }
      throw StateError('Unexpected ${request.method} ${request.url}');
    });
    await http.runWithClient(() async {
      final config = GDriveConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      );
      await config.saveCredentials({
        'client_id': 'test-client',
        'refresh_token': 'test-refresh',
        'email': 'test@example.invalid',
      });
      final adapter = GDriveClientAdapter(config: config);
      expect(await adapter.restoreCredentials(), isTrue);
      final receipt = await adapter.trashPath('/report.txt');
      expect(trashed, isTrue);
      expect(receipt.trashId, 'file-42');
      await adapter.restoreTrash(receipt);
      expect(trashed, isFalse);
      await adapter.deletePath('/report.txt');
      expect(trashed, isTrue);
      expect(requests.where((request) => request.method == 'DELETE'), isEmpty);
    }, () => client);
  });

  test('permanent Google Drive deletion is a distinct explicit call', () async {
    var deletes = 0;
    final client = MockClient((request) async {
      if (request.url.host == 'oauth2.googleapis.com')
        return http.Response('{"access_token":"test-only"}', 200);
      if (request.method == 'GET')
        return http.Response(
          '{"files":[{"id":"42","name":"report.txt"}]}',
          200,
        );
      if (request.method == 'DELETE') {
        deletes++;
        return http.Response('', 204);
      }
      throw StateError('Unexpected mutation');
    });
    await http.runWithClient(() async {
      final config = GDriveConfigService(
        configPath: '',
        secureStorage: InMemorySecureStorage(),
      );
      await config.saveCredentials({
        'client_id': 'test-client',
        'refresh_token': 'test-refresh',
      });
      final adapter = GDriveClientAdapter(config: config);
      await adapter.restoreCredentials();
      await adapter.deletePermanently('/report.txt');
      expect(deletes, 1);
    }, () => client);
  });

  test('native trash failure never falls back to deletion and receipt survives serialization', () async {
    const channel = MethodChannel('test/crispcloud/files');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          if (call.method == 'trash')
            throw PlatformException(code: 'unsupported');
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final native = NativeFileOperations(channel: channel);
    await expectLater(
      native.trash('/original'),
      throwsA(isA<PlatformException>()),
    );
    expect(calls, ['trash']);
    const receipt = TrashReceipt(
      originalPath: '/original',
      trashId: 'trash:///unique',
    );
    await native.restore(
      TrashReceipt.fromJson(jsonDecode(jsonEncode(receipt.toJson()))),
    );
    expect(calls, ['trash', 'restoreTrash']);
  });

  test(
    'receipt-bound local deletion is reversible; a permanent deletion is not',
    () async {
      final history = ActionHistoryService();
      var restored = false;
      final id = history.recordNew(
        type: ActionType.delete,
        originalPath: '/file',
        provider: 'local',
        isCurrent: () => true,
        undoAction: () async {
          restored = true;
          return const UndoResult.success('Restored');
        },
      );
      expect(history.canUndo(history.history.single), isTrue);
      expect((await history.undo(id, const UndoContext())).success, isTrue);
      expect(restored, isTrue);
      history.recordNew(
        type: ActionType.delete,
        originalPath: '/file',
        provider: 'Google Drive',
      );
      expect(history.canUndo(history.history.single), isFalse);
    },
  );

  test('native file clipboard round trips paths and cut semantics', () async {
    const channel = MethodChannel('test/crispcloud/clipboard');
    Map<Object?, Object?>? stored;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'writeClipboard') stored = call.arguments as Map;
          return call.method == 'readClipboard' ? stored : null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final native = NativeFileOperations(channel: channel);
    await native.writeClipboard(['/a file', '/β.txt'], cut: true);
    final value = await native.readClipboard();
    expect(value!.paths, ['/a file', '/β.txt']);
    expect(value.cut, isTrue);
  });
}
