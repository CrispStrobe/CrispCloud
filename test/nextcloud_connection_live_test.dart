@Tags(['live'])
@TestOn('vm')
@Timeout(Duration(minutes: 4))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/nextcloud_connection_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final path = Platform.environment['CRISPCLOUD_NEXTCLOUD_TEST_CONFIG'];
  test(
    'prepared Nextcloud endpoint, email, WebDAV and restored-session matrix',
    () async {
      final previous = HttpOverrides.current;
      HttpOverrides.global = null;
      try {
        final settings = jsonDecode(
          await File(path!).readAsString(),
        ) as Map<String, dynamic>;
        final results = await probeNextcloudConnections(settings);
        // ignore: avoid_print
        print(jsonEncode(results));
        expect(results, hasLength(settings['mounted_url'] == null ? 9 : 12));
        expect(results.where((result) => result['passed'] != true), isEmpty);
      } finally {
        HttpOverrides.global = previous;
      }
    },
    skip: path == null
        ? 'Requires private prepared-instance test config.'
        : false,
  );
}
