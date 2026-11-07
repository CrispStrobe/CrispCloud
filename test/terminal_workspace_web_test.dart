@TestOn('browser')
library;

import 'package:crisp_cloud/services/terminal_workspace_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'public workspace boundary selects the web-safe unsupported service',
    () async {
      final service = TerminalWorkspaceService();
      expect(service.isSupported, isFalse);
      expect(service.warnings, isEmpty);
      expect(await service.list(), isEmpty);
      await expectLater(service.load('workspace'), throwsUnsupportedError);
      await expectLater(service.inspect('workspace'), throwsUnsupportedError);
    },
  );
}
