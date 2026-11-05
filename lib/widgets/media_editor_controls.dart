import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/media_editor_strings.dart';
import '../services/media_edit_session.dart';

String formatMediaTime(Duration value) {
  final milliseconds = value.inMilliseconds;
  final minutes = milliseconds ~/ 60000;
  final seconds = (milliseconds ~/ 1000) % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.'
      '${(milliseconds % 1000).toString().padLeft(3, '0')}';
}

Duration? parseMediaTime(String text) {
  final parts = text.trim().split(':');
  if (parts.length > 3 || parts.isEmpty) return null;
  var seconds = 0.0;
  for (var i = 0; i < parts.length; i++) {
    final value = double.tryParse(parts[i]);
    if (value == null || !value.isFinite || value < 0) return null;
    if (i < parts.length - 1 && value != value.floorToDouble()) return null;
    if (i > 0 && value >= 60) return null;
    seconds = seconds * 60 + value;
  }
  // Avoid overflowing a Duration from malformed manual input.
  if (seconds > 7 * 24 * 60 * 60) return null;
  return Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}

class MediaEditorControls extends StatefulWidget {
  const MediaEditorControls({
    super.key,
    required this.info,
    required this.edit,
    required this.onChanged,
    required this.peaks,
    this.enabled = true,
  });

  final MediaInfo info;
  final MediaEdit edit;
  final ValueChanged<MediaEdit> onChanged;
  final List<double> peaks;
  final bool enabled;

  @override
  State<MediaEditorControls> createState() => MediaEditorControlsState();
}

class MediaEditorControlsState extends State<MediaEditorControls> {
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  bool _invalidTime = false;
  MediaInfo get info => widget.info;
  MediaEdit get edit => widget.edit;
  List<double> get peaks => widget.peaks;
  bool get enabled => widget.enabled;
  ValueChanged<MediaEdit> get onChanged => widget.onChanged;

  @override
  void initState() {
    super.initState();
    _startController = TextEditingController(text: formatMediaTime(edit.start));
    _endController = TextEditingController(text: formatMediaTime(edit.end));
  }

  @override
  void didUpdateWidget(covariant MediaEditorControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edit.start != edit.start || oldWidget.edit.end != edit.end) {
      _startController.text = formatMediaTime(edit.start);
      _endController.text = formatMediaTime(edit.end);
      _invalidTime = false;
    }
  }

  /// Commit both precision fields together before preview/export/close. Clicking
  /// Export must not silently ignore a value that has not received Enter yet.
  bool commit() {
    // Display milliseconds while preserving the decoder's exact microsecond
    // boundary when the user has not changed a field (especially audio EOF).
    final start = _startController.text == formatMediaTime(edit.start)
        ? edit.start
        : parseMediaTime(_startController.text);
    final end = _endController.text == formatMediaTime(edit.end)
        ? edit.end
        : parseMediaTime(_endController.text);
    if (start == null ||
        end == null ||
        start < Duration.zero ||
        end <= start ||
        end > info.duration) {
      setState(() => _invalidTime = true);
      return false;
    }
    setState(() => _invalidTime = false);
    if (start != edit.start || end != edit.end) _trim(start, end);
    return true;
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _trim(Duration start, Duration end) {
    final duration = end - start;
    onChanged(
      edit.copyWith(
        start: start,
        end: end,
        fadeIn: edit.fadeIn > duration ? duration : edit.fadeIn,
        fadeOut: edit.fadeOut > duration ? duration : edit.fadeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.mediaTr('Trim'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (peaks.isNotEmpty)
          SizedBox(
            height: 84,
            child: CustomPaint(
              painter: MediaWaveformPainter(
                peaks: peaks,
                start: edit.start.inMicroseconds / info.duration.inMicroseconds,
                end: edit.end.inMicroseconds / info.duration.inMicroseconds,
                color: Theme.of(context).colorScheme.primary,
                inactiveColor: Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
          ),
        _TrimSlider(info: info, edit: edit, enabled: enabled, onChanged: _trim),
        Row(
          children: [
            Expanded(child: _timeField(context, 'Start')),
            const SizedBox(width: 16),
            Expanded(child: _timeField(context, 'End')),
          ],
        ),
        const SizedBox(height: 16),
        if (info.kind == MediaKind.audio)
          ..._audioControls(context)
        else
          ..._videoControls(context),
      ],
    );
  }

  Widget _timeField(BuildContext context, String label) => TextFormField(
    key: ValueKey('media-time-$label'),
    controller: label == 'Start' ? _startController : _endController,
    enabled: enabled,
    keyboardType: TextInputType.datetime,
    decoration: InputDecoration(
      labelText: context.mediaTr(label),
      errorText: _invalidTime
          ? context.mediaTr('Could not apply changes')
          : null,
      border: const OutlineInputBorder(),
    ),
    onFieldSubmitted: (_) => commit(),
  );

  List<Widget> _audioControls(BuildContext context) => [
    _ValueSlider(
      label: context.mediaTr('Gain'),
      value: edit.gainDb,
      min: -60,
      max: 12,
      suffix: 'dB',
      enabled: enabled,
      onChanged: (value) => onChanged(edit.copyWith(gainDb: value)),
    ),
    _ValueSlider(
      label: context.mediaTr('Fade in'),
      value: edit.fadeIn.inMicroseconds / 1000000,
      max: math.min(10, edit.duration.inMicroseconds / 1000000),
      suffix: 's',
      enabled: enabled,
      onChanged: (value) => onChanged(
        edit.copyWith(
          fadeIn: Duration(microseconds: (value * 1000000).round()),
        ),
      ),
    ),
    _ValueSlider(
      label: context.mediaTr('Fade out'),
      value: edit.fadeOut.inMicroseconds / 1000000,
      max: math.min(10, edit.duration.inMicroseconds / 1000000),
      suffix: 's',
      enabled: enabled,
      onChanged: (value) => onChanged(
        edit.copyWith(
          fadeOut: Duration(microseconds: (value * 1000000).round()),
        ),
      ),
    ),
  ];

  List<Widget> _videoControls(BuildContext context) {
    final crop = edit.crop;
    final sourceCropAspect = crop == null
        ? null
        : info.width! * crop.width / (info.height! * crop.height);
    final cropAspect = sourceCropAspect == null
        ? null
        : edit.quarterTurns.isOdd
        ? 1 / sourceCropAspect
        : sourceCropAspect;
    final ratio = cropAspect == null
        ? 0
        : (cropAspect - 1).abs() < 0.001
        ? 1
        : (cropAspect - 16 / 9).abs() < 0.001
        ? 2
        : 3;
    return [
      Wrap(
        spacing: 16,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            onPressed: enabled
                ? () => onChanged(
                    edit.copyWith(quarterTurns: (edit.quarterTurns + 1) % 4),
                  )
                : null,
            icon: const Icon(Icons.rotate_right),
            label: Text(context.mediaTr('Rotate clockwise')),
          ),
          FilterChip(
            label: Text(context.mediaTr('Mute')),
            selected: edit.muted,
            onSelected: enabled
                ? (muted) => onChanged(edit.copyWith(muted: muted))
                : null,
          ),
        ],
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        key: ValueKey('media-crop-$ratio'),
        initialValue: ratio,
        decoration: InputDecoration(
          labelText: context.mediaTr('Crop'),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in {
            0: 'Original',
            1: 'Square',
            2: 'Landscape',
            3: 'Portrait',
          }.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(context.mediaTr(entry.value)),
            ),
        ],
        onChanged: enabled
            ? (value) {
                if (value == null) return;
                if (value == 0) {
                  onChanged(edit.copyWith(clearCrop: true));
                  return;
                }
                final outputAspect = value == 1
                    ? 1.0
                    : value == 2
                    ? 16 / 9
                    : 9 / 16;
                // Presets describe the output the user sees. The render recipe's
                // crop is in source coordinates, before its clockwise rotation.
                final target = edit.quarterTurns.isOdd
                    ? 1 / outputAspect
                    : outputAspect;
                final source = info.width! / info.height!;
                final width = math.min(1.0, target / source);
                final height = math.min(1.0, source / target);
                onChanged(
                  edit.copyWith(
                    crop: MediaCrop(
                      x: (1 - width) / 2,
                      y: (1 - height) / 2,
                      width: width,
                      height: height,
                    ),
                  ),
                );
              }
            : null,
      ),
      if (crop != null && crop.width < 0.999)
        _ValueSlider(
          label: context.mediaTr('Horizontal position'),
          value: crop.x / (1 - crop.width) * 100,
          max: 100,
          suffix: '%',
          enabled: enabled,
          onChanged: (value) => onChanged(
            edit.copyWith(
              crop: MediaCrop(
                x: value / 100 * (1 - crop.width),
                y: crop.y,
                width: crop.width,
                height: crop.height,
              ),
            ),
          ),
        ),
      if (crop != null && crop.height < 0.999)
        _ValueSlider(
          label: context.mediaTr('Vertical position'),
          value: crop.y / (1 - crop.height) * 100,
          max: 100,
          suffix: '%',
          enabled: enabled,
          onChanged: (value) => onChanged(
            edit.copyWith(
              crop: MediaCrop(
                x: crop.x,
                y: value / 100 * (1 - crop.height),
                width: crop.width,
                height: crop.height,
              ),
            ),
          ),
        ),
      const SizedBox(height: 16),
      DropdownButtonFormField<int>(
        key: ValueKey('media-height-${edit.maxOutputHeight}'),
        initialValue: edit.maxOutputHeight ?? 0,
        decoration: InputDecoration(
          labelText: context.mediaTr('Output height'),
          border: const OutlineInputBorder(),
        ),
        items: [
          DropdownMenuItem(
            value: 0,
            child: Text(context.mediaTr('Full resolution')),
          ),
          for (final height in [480, 720, 1080, 2160])
            DropdownMenuItem(value: height, child: Text('${height}p')),
        ],
        onChanged: enabled
            ? (value) {
                if (value != null)
                  onChanged(
                    edit.copyWith(
                      maxOutputHeight: value,
                      clearMaxOutputHeight: value == 0,
                    ),
                  );
              }
            : null,
      ),
    ];
  }
}

class _TrimSlider extends StatefulWidget {
  const _TrimSlider({
    required this.info,
    required this.edit,
    required this.enabled,
    required this.onChanged,
  });
  final MediaInfo info;
  final MediaEdit edit;
  final bool enabled;
  final void Function(Duration, Duration) onChanged;
  @override
  State<_TrimSlider> createState() => _TrimSliderState();
}

class _TrimSliderState extends State<_TrimSlider> {
  RangeValues? _drag;
  @override
  void didUpdateWidget(covariant _TrimSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.edit != widget.edit || !widget.enabled) _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final values =
        _drag ??
        RangeValues(
          widget.edit.start.inMicroseconds.toDouble(),
          widget.edit.end.inMicroseconds.toDouble(),
        );
    return Semantics(
      // Each thumb is an independent adjustable accessibility node. Keep the
      // label on a stable parent rather than merging it into changing siblings.
      container: true,
      explicitChildNodes: true,
      label: context.mediaTr('Trim'),
      // Media time follows the waveform's physical left-to-right axis in
      // every locale; surrounding controls and labels retain their direction.
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: RangeSlider(
          values: values,
          max: widget.info.duration.inMicroseconds.toDouble(),
          labels: RangeLabels(
            formatMediaTime(Duration(microseconds: values.start.round())),
            formatMediaTime(Duration(microseconds: values.end.round())),
          ),
          semanticFormatterCallback: (value) =>
              formatMediaTime(Duration(microseconds: value.round())),
          onChanged: widget.enabled
              ? (value) => setState(() => _drag = value)
              : null,
          onChangeEnd: widget.enabled
              ? (value) {
                  if (value.end - value.start >= 1)
                    widget.onChanged(
                      Duration(microseconds: value.start.round()),
                      Duration(microseconds: value.end.round()),
                    );
                  setState(() => _drag = null);
                }
              : null,
        ),
      ),
    );
  }
}

class _ValueSlider extends StatefulWidget {
  const _ValueSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.suffix,
    required this.enabled,
    required this.onChanged,
    this.min = 0,
  });
  final String label, suffix;
  final double value, min, max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  @override
  State<_ValueSlider> createState() => _ValueSliderState();
}

class _ValueSliderState extends State<_ValueSlider> {
  double? _drag;
  @override
  void didUpdateWidget(covariant _ValueSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value || !widget.enabled) _drag = null;
  }

  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value)
        .clamp(widget.min, widget.max)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('${widget.label}: ${value.toStringAsFixed(1)} ${widget.suffix}'),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          semanticFormatterCallback: (value) =>
              '${widget.label}: ${value.toStringAsFixed(1)} ${widget.suffix}',
          onChanged: widget.enabled
              ? (value) => setState(() => _drag = value)
              : null,
          onChangeEnd: widget.enabled
              ? (value) {
                  widget.onChanged(value);
                  setState(() => _drag = null);
                }
              : null,
        ),
      ],
    );
  }
}

class MediaWaveformPainter extends CustomPainter {
  const MediaWaveformPainter({
    required this.peaks,
    required this.start,
    required this.end,
    required this.color,
    required this.inactiveColor,
  });
  final List<double> peaks;
  final double start, end;
  final Color color, inactiveColor;
  @override
  void paint(Canvas canvas, Size size) {
    if (peaks.isEmpty) return;
    final paint = Paint()
      ..strokeWidth = math.max(1, size.width / peaks.length * 0.7);
    for (var i = 0; i < peaks.length; i++) {
      final fraction = (i + 0.5) / peaks.length;
      paint.color = fraction >= start && fraction <= end
          ? color
          : inactiveColor;
      final peak = peaks[i].isFinite ? peaks[i].abs().clamp(0, 1) : 0;
      final half = math.max(0.5, peak * size.height / 2);
      final x = fraction * size.width;
      canvas.drawLine(
        Offset(x, size.height / 2 - half),
        Offset(x, size.height / 2 + half),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MediaWaveformPainter oldDelegate) =>
      !identical(peaks, oldDelegate.peaks) ||
      start != oldDelegate.start ||
      end != oldDelegate.end ||
      color != oldDelegate.color ||
      inactiveColor != oldDelegate.inactiveColor;
}
