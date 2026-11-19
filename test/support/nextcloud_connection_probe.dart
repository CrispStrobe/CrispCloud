import 'dart:convert';

import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/nextcloud_client_adapter.dart';
import 'package:crisp_cloud/services/nextcloud_config_service.dart';
import 'package:crisp_cloud/services/secure_storage_service.dart';
import 'package:crisp_cloud/services/webdav_client_adapter.dart';
import 'package:crisp_cloud/services/webdav_config_service.dart';
import 'package:http/http.dart' as http;

/// Real adapters and real DAV I/O, shared by the VM acceptance test and the
/// browser probe. Use only dedicated test accounts; each case removes its file.
Future<List<Map<String, Object?>>> probeNextcloudConnections(
  Map<String, dynamic> settings,
) async {
  final url = settings['url'] as String;
  final user = settings['username'] as String;
  final password = settings['password'] as String;
  final email = settings['email'] as String;
  final emailUser = settings['second_username'] as String;
  final emailPassword = settings['second_password'] as String;
  final results = <Map<String, Object?>>[];
  final cases = [
    ('Nextcloud installation URL', user, password, url, user, false),
    (
      'Nextcloud pasted DAV URL',
      user,
      password,
      '$url/remote.php/dav/files/${Uri.encodeComponent(user)}/',
      user,
      false,
    ),
    (
      'Nextcloud legacy DAV URL',
      user,
      password,
      '$url/remote.php/webdav/',
      user,
      false,
    ),
    ('Nextcloud email alias', email, password, url, user, false),
    (
      'Nextcloud email alias with canonical DAV URL',
      email,
      password,
      '$url/remote.php/dav/files/${Uri.encodeComponent(user)}/',
      user,
      false,
    ),
    (
      'Nextcloud email-shaped account ID',
      emailUser,
      emailPassword,
      url,
      emailUser,
      false,
    ),
    (
      'WebDAV Nextcloud endpoint',
      user,
      password,
      '$url/remote.php/dav/files/${Uri.encodeComponent(user)}/',
      user,
      true,
    ),
    (
      'WebDAV email alias',
      email,
      password,
      '$url/remote.php/dav/files/${Uri.encodeComponent(user)}/',
      user,
      true,
    ),
    (
      'WebDAV email-shaped account ID',
      emailUser,
      emailPassword,
      '$url/remote.php/dav/files/${Uri.encodeComponent(emailUser)}/',
      emailUser,
      true,
    ),
  ];
  final mounted = settings['mounted_url'] as String?;
  if (mounted != null && mounted.isNotEmpty) {
    final dav = '$mounted/remote.php/dav/files/${Uri.encodeComponent(user)}/';
    cases.addAll([
      (
        'Nextcloud subdirectory installation',
        user,
        password,
        mounted,
        user,
        false,
      ),
      (
        'Nextcloud pasted subdirectory DAV URL',
        user,
        password,
        dav,
        user,
        false,
      ),
      ('WebDAV subdirectory endpoint', user, password, dav, user, true),
    ]);
  }
  var index = 0;
  for (final (name, login, secret, endpoint, uid, generic) in cases) {
    final marker =
        'crisp96-${DateTime.now().microsecondsSinceEpoch}-${index++} café #1%20.txt';
    final contents = 'Nextcloud issue 96: $marker — café';
    final uri = Uri.parse(
      '$url/remote.php/dav/files/${Uri.encodeComponent(uid)}/${Uri.encodeComponent(marker)}',
    );
    final headers = {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$login:$secret'))}',
    };
    final store = InMemorySecureStorage();
    final nextcloudConfig = NextcloudConfigService(
      configPath: '',
      secureStorage: store,
    );
    final webdavConfig = WebDavConfigService(
      configPath: '',
      secureStorage: store,
    );
    final CloudStorageClient client = generic
        ? WebDavClientAdapter(config: webdavConfig)
        : NextcloudClientAdapter(config: nextcloudConfig);
    var seeded = false;
    try {
      final put = await http.put(
        uri,
        headers: headers,
        body: utf8.encode('seed:$marker'),
      );
      if (put.statusCode != 201) {
        throw StateError('Fixture PUT: ${put.statusCode}');
      }
      seeded = true;
      await client.login('$login@$endpoint', secret);
      await client.uploadFile(utf8.encode(contents), marker, '/');
      for (var attempt = 0; attempt < 2; attempt++) {
        final files = (await client.listPath('/'))['files'] as List;
        if (!files.any((file) => file['name'] == marker)) {
          throw StateError('Verified marker absent from listing $attempt');
        }
      }
      if (utf8.decode(await client.downloadFileBytes('/$marker')) != contents) {
        throw StateError('Downloaded content differs');
      }
      final CloudStorageClient restored;
      if (generic) {
        final adapter = WebDavClientAdapter(config: webdavConfig);
        await adapter.restoreSession();
        restored = adapter;
      } else {
        final adapter = NextcloudClientAdapter(config: nextcloudConfig);
        if (!await adapter.restoreCredentials()) {
          throw StateError('Restore failed');
        }
        restored = adapter;
      }
      try {
        if (utf8.decode(await restored.downloadFileBytes('/$marker')) !=
            contents) {
          throw StateError('Restored session changed the DAV home');
        }
      } finally {
        await restored.logout();
      }
      results.add({
        'case': name,
        'passed': true,
        'listings': 2,
        'upload': true,
        'restore': true,
        'contentVerified': true,
      });
    } catch (error) {
      results.add({
        'case': name,
        'passed': false,
        'error': error.toString().replaceAll(secret, '[redacted]'),
      });
    } finally {
      await client.logout();
      if (seeded) {
        final deleted = await http.delete(uri, headers: headers);
        if (deleted.statusCode != 204) {
          throw StateError('Fixture cleanup failed: ${deleted.statusCode}');
        }
      }
    }
  }
  return results;
}
