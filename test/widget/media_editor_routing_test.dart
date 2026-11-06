import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/models/file_item.dart';
import 'package:crisp_cloud/models/panel_side.dart';
import 'package:crisp_cloud/widgets/file_editor_dialog.dart';
import 'package:crisp_cloud/widgets/hex_editor_dialog.dart';
import 'package:crisp_cloud/widgets/media_editor_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openFile(WidgetTester tester, FileItem file) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showFileEditorDialog(context, ref, file, PanelSide.local),
              child: const Text('Open file with F4 dispatcher'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open file with F4 dispatcher'));
  await tester.pumpAndSettle();
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'F4 routes native audio formats before attempting to load their bytes',
    (tester) async {
      for (final name in ['recording.WAV', 'song.mp3', 'lossless.FLAC']) {
        await _openFile(tester, FileItem(name: name, isFolder: false));
        expect(find.byType(MediaEditorDialog), findsOneWidget);
        expect(find.byType(CodeEditor), findsNothing);
        expect(find.byType(TextField), findsNothing);
        // Routing does not require a configured cloud login. This harness omits
        // app startup providers, so opening fails safely before media decoding.
        expect(find.text('Could not open media'), findsOneWidget);
        expect(find.textContaining('UnimplementedError'), findsNothing);
        await _unmount(tester);
      }
    },
    skip: kIsWeb,
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'F4 routes Apple and Android video formats to the media host',
    (tester) async {
      for (final name in ['movie.MP4', 'camera.mov', 'clip.m4v']) {
        await _openFile(tester, FileItem(name: name, isFolder: false));
        expect(find.byType(MediaEditorDialog), findsOneWidget);
        expect(find.byType(CodeEditor), findsNothing);
        expect(find.byType(TextField), findsNothing);
        await _unmount(tester);
      }
    },
    skip: kIsWeb,
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  testWidgets(
    'F4 rejects media editing on web before opening a native engine',
    (tester) async {
      for (final name in [
        'recording.wav',
        'song.mp3',
        'lossless.flac',
        'movie.mp4',
        'camera.mov',
      ]) {
        await _openFile(tester, FileItem(name: name, isFolder: false));
        expect(find.byType(MediaEditorDialog), findsNothing);
        expect(find.byType(CodeEditor), findsNothing);
        expect(
          find.text('This media format cannot be edited on this platform.'),
          findsOneWidget,
        );
        await _unmount(tester);
      }
    },
    skip: !kIsWeb,
  );

  testWidgets(
    'F4 rejects video on unsupported desktops without opening a binary text editor',
    (tester) async {
      await _openFile(tester, FileItem(name: 'movie.mp4', isFolder: false));
      expect(find.byType(MediaEditorDialog), findsNothing);
      expect(find.byType(CodeEditor), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.text('This media format cannot be edited on this platform.'),
        findsOneWidget,
      );
      await _unmount(tester);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.linux,
      TargetPlatform.windows,
    }),
  );

  testWidgets('unsupported media formats never fall through to editable text', (
    tester,
  ) async {
    for (final name in [
      'recording.aac',
      'sound.m4a',
      'movie.mkv',
      'capture.webm',
    ]) {
      await _openFile(tester, FileItem(name: name, isFolder: false));
      expect(find.byType(MediaEditorDialog), findsNothing);
      expect(find.byType(CodeEditor), findsNothing);
      expect(find.textContaining('Cannot open hex editor'), findsOneWidget);
      await _unmount(tester);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('a media-like folder is ignored by the edit dispatcher', (
    tester,
  ) async {
    await _openFile(tester, FileItem(name: 'recordings.wav', isFolder: true));
    expect(find.byType(MediaEditorDialog), findsNothing);
    expect(find.byType(CodeEditor), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await _unmount(tester);
  });
}
