import 'dart:async';

import 'package:crisp_cloud/l10n/app_localizations.dart';
import 'package:crisp_cloud/services/media_edit_session.dart';
import 'package:crisp_cloud/widgets/media_editor_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

class _PlayerPlatform extends VideoPlayerPlatform {
  final streams = <int, StreamController<VideoEvent>>{};
  final positions = <int, Duration>{};
  int nextId = 0;
  int plays = 0;
  int pauses = 0;
  int seeks = 0;
  Completer<void>? seekGate;
  bool failSeek = false;
  bool failVolume = false;
  bool failPause = false;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = nextId++;
    streams[id] = StreamController<VideoEvent>()
      ..add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          duration: const Duration(seconds: 10),
          size: const Size(320, 180),
        ),
      );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async {
    await streams.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {
    plays++;
  }

  @override
  Future<void> pause(int playerId) async {
    pauses++;
    if (failPause) throw PlatformException(code: 'pause_failed');
  }

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seeks++;
    await seekGate?.future;
    if (failSeek) throw PlatformException(code: 'seek_failed');
    positions[playerId] = position;
  }

  @override
  Future<Duration> getPosition(int playerId) async =>
      positions[playerId] ?? Duration.zero;

  @override
  Future<void> setVolume(int playerId, double volume) async {
    if (failVolume) throw PlatformException(code: 'volume_failed');
  }

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Widget buildView(int playerId) => const SizedBox.expand();
}

const _info = MediaInfo(
  kind: MediaKind.video,
  duration: Duration(seconds: 10),
  width: 320,
  height: 180,
);
const _edit = MediaEdit(start: Duration(seconds: 2), end: Duration(seconds: 8));
const _unavailable = 'Playback is unavailable. You can still edit and export.';

Widget _app({
  bool enabled = true,
  MediaEdit edit = _edit,
  TextDirection direction = TextDirection.ltr,
}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Directionality(
      textDirection: direction,
      child: MediaEditorPreview(
        path: '/__crisp_media_preview_test__/source.mp4',
        info: _info,
        edit: edit,
        enabled: enabled,
        playbackAvailable: true,
      ),
    ),
  ),
);

Future<void> _ready(WidgetTester tester) async {
  for (var frame = 0; frame < 20; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
    if (find.byType(VideoPlayer).evaluate().isNotEmpty) return;
  }
  fail('The test player did not initialize.');
}

void main() {
  late VideoPlayerPlatform previous;
  late _PlayerPlatform platform;

  setUp(() {
    previous = VideoPlayerPlatform.instance;
    platform = _PlayerPlatform();
    VideoPlayerPlatform.instance = platform;
  });
  tearDown(() => VideoPlayerPlatform.instance = previous);

  testWidgets(
    'a seek finishing after preview is disabled cannot start playback',
    (tester) async {
      await tester.pumpWidget(_app(direction: TextDirection.rtl));
      await _ready(tester);
      expect(
        Directionality.of(tester.element(find.byType(Slider))),
        TextDirection.ltr,
      );
      final controller = tester
          .widget<VideoPlayer>(find.byType(VideoPlayer))
          .controller;
      controller.value = controller.value.copyWith(position: _edit.end);
      await tester.pump();
      platform.seekGate = Completer<void>();
      final before = platform.seeks;
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(platform.seeks, greaterThan(before));
      expect(platform.plays, 0);

      await tester.pumpWidget(_app(enabled: false));
      platform.seekGate!.complete();
      await tester.pump();
      await tester.pump();
      expect(platform.plays, 0);
      expect(controller.value.isPlaying, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  for (final operation in ['seek', 'mute', 'pause']) {
    testWidgets(
      'failed preview $operation stays contained and leaves editing available',
      (tester) async {
        await tester.pumpWidget(_app());
        await _ready(tester);
        switch (operation) {
          case 'seek':
            platform.failSeek = true;
            tester.widget<Slider>(find.byType(Slider)).onChanged!(3000000);
          case 'mute':
            platform.failVolume = true;
            await tester.pumpWidget(_app(edit: _edit.copyWith(muted: true)));
          case 'pause':
            await tester.tap(find.byTooltip('Play'));
            await tester.pump();
            expect(platform.plays, 1);
            platform.failPause = true;
            await tester.pumpWidget(_app(enabled: false));
        }
        await tester.pump();
        await tester.pump();
        expect(find.text(_unavailable), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  }
}
