import 'dart:io';

import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/services/macos_application_launcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes application directories only on supported platforms', () {
    final launcher = MacApplicationLauncher(supported: true);
    expect(
      launcher.isApplicationBundle(
        FileItem(name: 'Viewer.APP', isFolder: true),
      ),
      isTrue,
    );
    expect(
      launcher.isApplicationBundle(
        FileItem(name: 'Viewer.app.zip', isFolder: false),
      ),
      isFalse,
    );
    expect(
      launcher.isApplicationBundle(FileItem(name: 'fake.app', isFolder: false)),
      isFalse,
    );
    expect(
      MacApplicationLauncher(supported: false)
          .isApplicationBundle(FileItem(name: 'Viewer.app', isFolder: true)),
      isFalse,
    );
  });
  test(
    'launches the exact absolute bundle as a separate argument without a shell',
    () async {
      final commands = <(String, List<String>)>[];
      final launcher = MacApplicationLauncher(
        supported: true,
        run: (executable, arguments) async {
          commands.add((executable, arguments));
          return ProcessResult(1, 0, '', '');
        },
      );
      const path = '/Applications/Unusual \$(name) & spaces.app';
      await launcher.launch(path);
      expect(commands.single.$1, '/usr/bin/open');
      expect(commands.single.$2, ['-a', path]);
      for (final invalid in [
        'relative.app',
        '/Applications/Folder',
        '/Applications/fake.app\u0000',
      ]) {
        await expectLater(launcher.launch(invalid), throwsArgumentError);
      }
      expect(commands, hasLength(1));
    },
  );
  test(
    'launch failures are surfaced instead of changing to the bundle directory',
    () async {
      final launcher = MacApplicationLauncher(
        supported: true,
        run: (_, _) async => ProcessResult(1, 1, '', 'Not launchable'),
      );
      await expectLater(
        launcher.launch('/Applications/Broken.app'),
        throwsA(isA<ProcessException>()),
      );
    },
  );
}
