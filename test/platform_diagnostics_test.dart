import 'dart:io';

import 'package:crisp_cloud/services/platform_diagnostics_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _PathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationSupportPath() async =>
      Directory.systemTemp.path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('collect returns non-sensitive platform health checks', () async {
    PathProviderPlatform.instance = _PathProvider();
    final diagnostics = await PlatformDiagnostics.collect();

    expect(diagnostics.platform, isNotEmpty);
    expect(diagnostics.cryptoBackend, isNotEmpty);
    expect(diagnostics.secureStorageBackend, isNotEmpty);
    expect(diagnostics.displayValues.keys, contains('Application Support'));
    expect(diagnostics.displayValues.values.join(), isNot(contains('/Users/')));
  });
}
