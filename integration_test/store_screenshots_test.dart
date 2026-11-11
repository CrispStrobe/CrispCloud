// Captures Mac App Store screenshots from the real application.
//
// Runs only in the "Store screenshots" workflow on a fresh macOS runner:
//   flutter test integration_test/store_screenshots_test.dart -d macos
// It seeds demo files in the app's (sandbox) home, selects session-only
// credential storage so no keychain or account is involved, boots the
// production `main()`, and renders each screen at 1440x900 points @2x
// (2880x1800, an accepted Mac App Store size) straight from the layer tree.
// PNGs land in the app's temporary directory as crispcloud-store-NN-*.png;
// the workflow collects them from there.
//
// Steps are best-effort: a missing control is logged and the capture still
// happens, so one UI change cannot hide every other screenshot.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crisp_cloud/main.dart' as app;
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/providers/core_providers.dart';
import 'package:crisp_cloud/providers/panel_provider.dart';
import 'package:crisp_cloud/screens/file_browser_screen.dart';
import 'package:crisp_cloud/services/credential_storage_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _logicalSize = Size(1440, 900);
const _pixelRatio = 2.0;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Mac App Store screenshots', (tester) async {
    WidgetsApp.debugAllowBannerOverride = false;
    // Debug-only framework assertions (e.g. ink hidden by a decorated
    // ancestor) are logged, not fatal: they do not change release rendering
    // and must not discard the captures. Restored before the test ends.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => _log(
      'framework error: ${details.exceptionAsString().split('\n').first}',
    );
    tester.view.physicalSize = _logicalSize * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;

    final home = Platform.environment['HOME']!;
    final out = Directory('${Directory.systemTemp.path}/crispcloud-store')
      ..createSync(recursive: true);
    _log('home=$home out=${out.path}');
    await _seedDemoHome(home);
    await CredentialStorageConfig.writeSelection(
      mode: CredentialStorageMode.sessionOnly,
    );

    app.main();
    await _settle(tester, const Duration(seconds: 8));
    _dumpTexts('after boot');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(FileBrowserScreen)),
    );
    Future<void> go(PanelSide side, String path) async {
      await container.read(panelProvider(side)).navigateToPath(path);
      await _settle(tester, const Duration(seconds: 2));
    }

    await _step('home and documents', () async {
      await go(PanelSide.local, home);
      await go(PanelSide.remote, '$home/Documents');
    });
    _dumpTexts('home');
    await _shot(tester, out, '01-dual-panel');

    await _step('photos as gallery', () async {
      await go(PanelSide.local, '$home/Photos');
      container.read(localViewModeProvider.notifier).state = ViewMode.gallery;
      await _settle(tester, const Duration(seconds: 2));
    });
    await _settle(tester, const Duration(seconds: 5));
    _dumpTexts('photos');
    await _shot(tester, out, '02-photos-grid');

    await _step('project file with preview', () async {
      await go(PanelSide.remote, '$home/Projects/CrispCloud');
      await _tapTooltip(tester, 'Show Preview');
      await tester.tap(find.text('README.md').last);
      await _settle(tester, const Duration(seconds: 2));
    });
    await _settle(tester, const Duration(seconds: 3));
    _dumpTexts('projects');
    await _shot(tester, out, '03-preview');

    await _step('open settings', () async {
      await _tapTooltip(tester, 'Settings');
    });
    await _settle(tester, const Duration(seconds: 2));
    _dumpTexts('settings');
    await _shot(tester, out, '04-settings');
    FlutterError.onError = originalOnError;
  }, timeout: const Timeout(Duration(minutes: 10)));
}

void _log(String message) => debugPrint('STORE_SHOTS $message');

Future<void> _step(String name, Future<void> Function() body) async {
  try {
    await body();
    _log('step ok: $name');
  } catch (error) {
    _log('step failed: $name: $error');
  }
}

Future<void> _settle(WidgetTester tester, Duration total) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip).first);
  await _settle(tester, const Duration(milliseconds: 800));
}

void _dumpTexts(String label) {
  final texts = find
      .byType(Text)
      .evaluate()
      .map((e) => (e.widget as Text).data)
      .whereType<String>()
      .where((t) => t.trim().isNotEmpty)
      .take(80)
      .join(' | ');
  _log('texts[$label]: $texts');
}

Future<void> _shot(WidgetTester tester, Directory out, String name) async {
  await tester.pump();
  final view = tester.binding.renderViews.first;
  final layer = view.debugLayer! as OffsetLayer;
  // The root layer already carries the device-pixel-ratio transform, so
  // capture the physical rectangle 1:1 instead of scaling a second time.
  final image = await layer.toImage(Offset.zero & (view.size * _pixelRatio));
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${out.path}/crispcloud-store-$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  _log('saved ${file.path} ${image.width}x${image.height}');
}

Future<void> _seedDemoHome(String home) async {
  Future<void> text(String path, String content) async {
    final file = File('$home/$path');
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  await text(
    'Documents/Meeting notes.md',
    '# Weekly sync\n\n- Ship 1.1 to TestFlight\n- Review sync settings\n',
  );
  await text('Documents/Budget 2026.csv', 'Month,Cloud,Backup\nJan,12,4\n');
  await text(
    'Documents/Quarterly report.txt',
    'Q3 summary\n\nStorage across five providers grew 18%.\n',
  );
  await text(
    'Projects/CrispCloud/README.md',
    '# CrispCloud\n\nOne file manager for every cloud.\n\n'
        '## Features\n\n- Dual-panel browsing\n- Cloud-to-cloud transfers\n'
        '- Client-side encryption\n- Previews and an editor\n',
  );
  await text(
    'Projects/CrispCloud/main.dart',
    "void main() {\n  print('Hello from CrispCloud');\n}\n",
  );
  await text('Projects/Website/index.html', '<h1>Hello</h1>\n');
  await text('Backups/2026-11-01.log', 'Backup completed: 1,284 files\n');
  const palettes = [
    [Color(0xFF1E88E5), Color(0xFF26C6DA)],
    [Color(0xFFFF7043), Color(0xFFFFCA28)],
    [Color(0xFF43A047), Color(0xFF9CCC65)],
    [Color(0xFF8E24AA), Color(0xFFEC407A)],
    [Color(0xFF3949AB), Color(0xFF7E57C2)],
    [Color(0xFF00897B), Color(0xFF4DD0E1)],
  ];
  const names = [
    'Lake.png',
    'Sunset.png',
    'Forest.png',
    'Bloom.png',
    'Night.png',
    'Coast.png',
  ];
  for (var i = 0; i < names.length; i++) {
    final file = File('$home/Photos/${names[i]}');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await _gradientPng(palettes[i], i));
  }
}

Future<List<int>> _gradientPng(List<Color> colors, int seed) async {
  const size = Size(640, 420);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Offset.zero & size,
    Paint()
      ..shader = ui.Gradient.linear(
        Offset.zero,
        size.bottomRight(Offset.zero),
        colors,
      ),
  );
  final random = math.Random(seed);
  for (var i = 0; i < 5; i++) {
    canvas.drawCircle(
      Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * size.height,
      ),
      40 + random.nextDouble() * 90,
      Paint()..color = Colors.white.withValues(alpha: 0.12),
    );
  }
  final image = await recorder.endRecording().toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
