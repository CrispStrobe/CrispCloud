// flutter build web --target tool/probes/nextcloud_connection_web.dart
//   --dart-define-from-file=/private/path/to/dedicated-test-accounts.json
// Serve ONLY on loopback at an origin explicitly allowed by the test server.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:dio/dio.dart';

import '../../test/support/nextcloud_connection_probe.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = <String, dynamic>{
    'url': const String.fromEnvironment('url'),
    'username': const String.fromEnvironment('username'),
    'password': const String.fromEnvironment('password'),
    'email': const String.fromEnvironment('email'),
    'second_username': const String.fromEnvironment('second_username'),
    'second_password': const String.fromEnvironment('second_password'),
    'mounted_url': const String.fromEnvironment('mounted_url'),
  };
  web.document.title = 'CRISP_NEXTCLOUD_RUNNING';
  try {
    if (settings.entries.any(
      (entry) => entry.key != 'mounted_url' && entry.value == '',
    )) {
      throw StateError('Missing private test configuration');
    }
    // Reproduce the prior browser challenge path against the real server.
    // Its approved-origin policy intentionally does not expose WWW-Authenticate.
    final baseline = <String, Object?>{};
    final unconfigured = webdav.newClient(
      '${settings['url']}/remote.php/dav/files/${Uri.encodeComponent(settings['username'] as String)}/',
      user: settings['username'] as String,
      password: settings['password'] as String,
      debug: false,
    );
    try {
      await unconfigured.readDir('/');
      baseline['challengeSucceeded'] = true;
    } on DioException catch (error) {
      baseline['status'] = error.response?.statusCode;
      baseline['challengeExposed'] =
          error.response?.headers.value('www-authenticate') != null;
    } finally {
      unconfigured.c.close(force: true);
    }
    final results = await probeNextcloudConnections(settings);
    final output = web.document.createElement('pre')
      ..textContent = jsonEncode({'baseline': baseline, 'results': results});
    web.document.body!.append(output);
    web.document.title = results.every((result) => result['passed'] == true)
        ? 'CRISP_NEXTCLOUD_PASS'
        : 'CRISP_NEXTCLOUD_FAIL';
  } catch (error) {
    web.document.body!.append(
      web.document.createElement('pre')
        ..textContent = 'Probe failed: ${error.runtimeType}',
    );
    web.document.title = 'CRISP_NEXTCLOUD_FAIL';
  }
}
