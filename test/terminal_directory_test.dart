import 'package:crisp_cloud/services/cloud_storage_interface.dart';
import 'package:crisp_cloud/services/panel_source_service.dart';
import 'package:crisp_cloud/services/terminal_directory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _Client extends Fake implements CloudStorageClient {}

void main() {
  final root = p.current;
  final documents = p.join(root, 'Documents');

  test('uses the first verified local source', () async {
    expect(
      await resolveTerminalDirectory([
        RemotePanelSource(providerName: 'remote', client: _Client(), path: '/'),
        LocalPanelSource(p.join(documents, 'folder', '..')),
        LocalPanelSource(root),
      ], fallback: () async => throw StateError('must not fall back')),
      documents,
    );
  });

  test(
    'a remote-only selection falls back to the app documents directory',
    () async {
      var calls = 0;
      expect(
        await resolveTerminalDirectory(
          [
            RemotePanelSource(
              providerName: 'remote',
              client: _Client(),
              path: '/work',
            ),
          ],
          fallback: () async {
            calls++;
            return documents;
          },
        ),
        documents,
      );
      expect(calls, 1);
    },
  );

  test(
    'invalid local paths are ignored and fallback errors remain visible',
    () async {
      expect(
        await resolveTerminalDirectory([
          const LocalPanelSource('relative'),
          LocalPanelSource('$documents\u0000'),
        ], fallback: () async => documents),
        documents,
      );
      await expectLater(
        resolveTerminalDirectory([], fallback: () async => 'relative'),
        throwsStateError,
      );
      final error = StateError('documents unavailable');
      await expectLater(
        resolveTerminalDirectory([], fallback: () async => throw error),
        throwsA(same(error)),
      );
    },
  );
}
