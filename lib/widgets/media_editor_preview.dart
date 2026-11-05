import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../l10n/media_editor_strings.dart';
import '../services/media_edit_session.dart';
import 'media_editor_controls.dart' show formatMediaTime;

/// Playback is independent of the renderer. A rendered-preview path is a real
/// output file, so auditioning gain/fades uses the same samples as export.
class MediaEditorPreview extends StatefulWidget {
  const MediaEditorPreview({
    super.key,
    required this.path,
    required this.info,
    required this.edit,
    required this.enabled,
    required this.playbackAvailable,
  });

  final String path;
  final MediaInfo info;
  final MediaEdit edit;
  final bool enabled;
  final bool playbackAvailable;

  @override
  State<MediaEditorPreview> createState() => _MediaEditorPreviewState();
}

class _MediaEditorPreviewState extends State<MediaEditorPreview> {
  VideoPlayerController? _controller;
  bool _failed = false;
  bool _stopping = false;

  @override
  void initState() {
    super.initState();
    if (widget.playbackAvailable) unawaited(_initialize());
  }

  Future<void> _initialize() async {
    final controller = VideoPlayerController.file(File(widget.path));
    _controller = controller;
    controller.addListener(_changed);
    try {
      await controller.initialize();
      if (!mounted) return;
      await controller.setVolume(widget.edit.muted ? 0 : 1);
      await controller.seekTo(widget.edit.start);
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant MediaEditorPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!widget.enabled && controller.value.isPlaying) unawaited(controller.pause());
    if (oldWidget.edit.muted != widget.edit.muted) unawaited(controller.setVolume(widget.edit.muted ? 0 : 1));
    if (controller.value.position < widget.edit.start || controller.value.position >= widget.edit.end) {
      unawaited(controller.seekTo(widget.edit.start));
    }
  }

  void _changed() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    if (controller.value.isPlaying && controller.value.position >= widget.edit.end && !_stopping) {
      _stopping = true;
      unawaited(controller.pause().then((_) { _stopping = false; }));
    }
    setState(() {});
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_changed);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    final controller = _controller!;
    try {
      if (controller.value.isPlaying) {
        await controller.pause();
      } else {
        if (controller.value.position >= widget.edit.end || controller.value.position < widget.edit.start) {
          await controller.seekTo(widget.edit.start);
        }
        await controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.playbackAvailable || _failed || (_controller?.value.hasError ?? false)) {
      return Padding(padding: const EdgeInsets.all(24), child: Text(context.mediaTr('Playback is unavailable. You can still edit and export.')));
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
    }
    final position = controller.value.position.inMicroseconds.clamp(widget.edit.start.inMicroseconds, widget.edit.end.inMicroseconds).toDouble();
    return Column(children: [
      if (widget.info.kind == MediaKind.video)
        Container(height: 260, color: Colors.black, child: Center(child: _video(controller)))
      else const Padding(padding: EdgeInsets.all(20), child: Icon(Icons.graphic_eq, size: 56)),
      Row(children: [
        IconButton(tooltip: context.mediaTr(controller.value.isPlaying ? 'Pause' : 'Play'),
          onPressed: widget.enabled ? _toggle : null,
          icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow)),
        Expanded(child: Slider(
          value: position,
          min: widget.edit.start.inMicroseconds.toDouble(),
          max: widget.edit.end.inMicroseconds.toDouble(),
          semanticFormatterCallback: (value) => formatMediaTime(Duration(microseconds: value.round())),
          onChanged: widget.enabled ? (value) => unawaited(controller.seekTo(Duration(microseconds: value.round()))) : null,
        )),
        Text(formatMediaTime(Duration(microseconds: position.round()))),
      ]),
    ]);
  }

  Widget _video(VideoPlayerController controller) {
    final width = widget.info.width!.toDouble();
    final height = widget.info.height!.toDouble();
    final crop = widget.edit.crop ?? const MediaCrop(x: 0, y: 0, width: 1, height: 1);
    return FittedBox(fit: BoxFit.contain, child: RotatedBox(
      quarterTurns: widget.edit.quarterTurns,
      child: ClipRect(child: SizedBox(width: width * crop.width, height: height * crop.height,
        child: OverflowBox(alignment: Alignment.topLeft, minWidth: width, maxWidth: width, minHeight: height, maxHeight: height,
          child: Transform.translate(offset: Offset(-width * crop.x, -height * crop.y),
            child: SizedBox(width: width, height: height, child: VideoPlayer(controller)),
          ),
        ),
      )),
    ));
  }
}
