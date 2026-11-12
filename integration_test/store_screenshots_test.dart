// Captures App Store screenshots from the real application.
//
// Runs only in the "Store screenshots" workflow on fresh runners:
//   flutter test integration_test/store_screenshots_test.dart -d macos \
//     --dart-define=STORE_TARGET=mac --dart-define=STORE_HOME=/Users/alex
//   flutter test ... -d <iPhone simulator> --dart-define=STORE_TARGET=iphone
//   flutter test ... -d <iPad simulator>   --dart-define=STORE_TARGET=ipad
// It seeds demo files in STORE_HOME (default: the app's home), selects
// session-only credential storage so no keychain or account is involved,
// boots the production `main()`, and renders each screen straight from the
// layer tree at an accepted store size: Mac 2880x1800, iPhone 6.5" 1284x2778,
// iPad 12.9" 2048x2732. PNGs land in the app's temporary directory as
// crispcloud-store-NN-*.png; the workflow collects them from there.
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
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:quds_office_engine/quds_office_engine.dart';

const _target = String.fromEnvironment('STORE_TARGET', defaultValue: 'mac');
const _storeHome = String.fromEnvironment('STORE_HOME');
const _storeOut = String.fromEnvironment('STORE_OUT');

/// Logical size and pixel ratio per store slot.
final (Size, double) _slot = switch (_target) {
  'iphone' => (const Size(428, 926), 3.0), // 1284x2778, iPhone 6.5"
  'ipad' => (const Size(1024, 1366), 2.0), // 2048x2732, iPad 12.9"
  _ => (const Size(1440, 900), 2.0), // 2880x1800, Mac
};
final Size _logicalSize = _slot.$1;
final double _pixelRatio = _slot.$2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture Mac App Store screenshots', (tester) async {
    WidgetsApp.debugAllowBannerOverride = false;
    // Debug-only framework assertions (e.g. ink hidden by a decorated
    // ancestor) are logged, not fatal: they do not change release rendering
    // and must not discard the captures. Restored before the test ends.
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => _log(
      'framework error: ${details.exceptionAsString().split('\n').first}\n'
      '${details.stack.toString().split('\n').take(8).join('\n')}',
    );
    tester.view.physicalSize = _logicalSize * _pixelRatio;
    tester.view.devicePixelRatio = _pixelRatio;

    // iOS exposes no HOME to the test process; the app's Documents folder is
    // the root its local panel shows, so the demo folders go there.
    final home = _storeHome.isNotEmpty
        ? _storeHome
        : Platform.isIOS
        ? (await getApplicationDocumentsDirectory()).path
        : Platform.environment['HOME']!;
    // STORE_OUT writes straight to a host folder: `flutter test` uninstalls
    // the iOS app afterwards, deleting anything left in its container.
    final out = Directory(
      _storeOut.isNotEmpty
          ? _storeOut
          : '${Directory.systemTemp.path}/crispcloud-store',
    )..createSync(recursive: true);
    _log('target=$_target home=$home out=${out.path}');
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

    final nav = Navigator.of(
      tester.element(find.byType(FileBrowserScreen)),
      rootNavigator: true,
    );
    Future<void> closeDialogs() async {
      nav.popUntil((route) => route.isFirst);
      await _settle(tester, const Duration(milliseconds: 800));
    }

    Future<void> select(PanelSide side, String name) async {
      final panel = container.read(panelProvider(side));
      final item = panel.files!.firstWhere((f) => f.name == name);
      panel.toggleSelection(item);
      await _settle(tester, const Duration(seconds: 2));
    }

    await _step('documents and projects', () async {
      await go(PanelSide.local, '$home/Documents');
      await go(PanelSide.remote, '$home/Projects');
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

    await _step('markdown preview', () async {
      container.read(localViewModeProvider.notifier).state = ViewMode.list;
      await go(PanelSide.local, '$home/Documents');
      await go(PanelSide.remote, '$home/Projects/CrispCloud');
      container.read(showPreviewProvider.notifier).state = true;
      await select(PanelSide.remote, 'README.md');
    });
    await _settle(tester, const Duration(seconds: 3));
    _dumpTexts('preview');
    await _shot(tester, out, '03-preview');

    await _step('word document in the office editor', () async {
      container.read(showPreviewProvider.notifier).state = false;
      await go(PanelSide.remote, '$home/Documents');
      await select(PanelSide.remote, 'Project plan.docx');
      await tester.sendKeyEvent(LogicalKeyboardKey.f4);
      await _settle(tester, const Duration(seconds: 6));
    });
    _dumpTexts('office');
    await _shot(tester, out, '04-office-editor');
    await closeDialogs();

    await _step('connect to a server', () async {
      await go(PanelSide.local, '$home/Documents');
      await tester.tap(find.text('Connect').first);
      await _settle(tester, const Duration(seconds: 2));
    });
    _dumpTexts('connect');
    await _shot(tester, out, '05-connect');
    await closeDialogs();

    await _step('open settings', () async {
      await _tapTooltip(tester, 'Settings');
    });
    await _settle(tester, const Duration(seconds: 2));
    _dumpTexts('settings');
    await _shot(tester, out, '06-settings');
    await closeDialogs();
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
  final plan = File('$home/Documents/Project plan.docx');
  await plan.writeAsBytes(WordSerializer().write(_projectPlan()).save());
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

/// A short, formatted Word document for the office editor screenshot.
WmlDocument _projectPlan() {
  WmlParagraph para(
    String text, {
    bool bold = false,
    int size = 22,
    String color = '1F2933',
  }) => WmlParagraph(
    inlines: <WmlInline>[
      WmlRun(
        text: text,
        properties: WmlRunProps(
          bold: bold,
          fontSizeHalfPoints: size,
          color: color,
        ),
      ),
    ],
  );
  WmlTableCell cell(String text, {bool header = false}) =>
      WmlTableCell(blocks: <WmlBlock>[para(text, bold: header)]);
  final doc = WmlDocument.empty();
  doc.sections.first.blocks
    ..clear()
    ..addAll(<WmlBlock>[
      para('Website relaunch', bold: true, size: 40, color: '1F4E79'),
      para(
        'Goals, milestones and owners for the relaunch in spring. '
        'Drafts live in the shared Projects folder; final assets are '
        'synced to every cloud the team uses.',
      ),
      para('Milestones', bold: true, size: 28, color: '1F4E79'),
      WmlTable(
        grid: <double>[2600, 3600, 2400],
        rows: <WmlTableRow>[
          WmlTableRow(
            cells: <WmlTableCell>[
              cell('Date', header: true),
              cell('Milestone', header: true),
              cell('Owner', header: true),
            ],
          ),
          WmlTableRow(
            cells: <WmlTableCell>[
              cell('March 3'),
              cell('Content inventory'),
              cell('Maya'),
            ],
          ),
          WmlTableRow(
            cells: <WmlTableCell>[
              cell('March 24'),
              cell('Design review'),
              cell('Jonas'),
            ],
          ),
          WmlTableRow(
            cells: <WmlTableCell>[
              cell('April 14'),
              cell('Launch'),
              cell('Whole team'),
            ],
          ),
        ],
      ),
      para('Next steps', bold: true, size: 28, color: '1F4E79'),
      para('Collect feedback on the draft and share the final plan.'),
    ]);
  return doc;
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
