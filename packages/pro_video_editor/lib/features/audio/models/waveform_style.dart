import 'package:flutter/widgets.dart';

/// Visual styling options for [AudioWaveform].
class WaveformStyle {
  /// Creates a [WaveformStyle].
  const WaveformStyle({
    this.height = 80.0,
    this.waveColor = const Color(0xFF4CAF50),
    this.waveColorPlayed,
    this.backgroundColor = const Color(0xFF212121),
    this.positionIndicatorColor,
    this.centerLineColor,
    this.playedOverlayColor,
    this.unplayedOverlayColor,
    this.barWidth = 3.0,
    this.barSpacing = 1.0,
    this.minBarHeight = 2.0,
    this.borderRadius,
    this.showCenterLine = true,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  /// Height of the waveform widget in pixels.
  final double height;

  /// Animation duration for bar height transitions (streaming mode).
  final Duration animationDuration;

  /// Color for the waveform bars (left channel in stereo).
  final Color waveColor;

  /// Color for the played portion of the waveform.
  /// If null, uses [waveColor].
  final Color? waveColorPlayed;

  /// Background color of the waveform container.
  final Color backgroundColor;

  /// Color of the playback position indicator line.
  /// If null, uses [waveColor].
  final Color? positionIndicatorColor;

  /// Color of the center line (for stereo display).
  /// If null, uses [waveColor] with reduced opacity.
  final Color? centerLineColor;

  /// Overlay color for the played portion (before position indicator).
  /// If null, no overlay is shown.
  final Color? playedOverlayColor;

  /// Overlay color for the unplayed portion (after position indicator).
  /// If null, no overlay is shown.
  final Color? unplayedOverlayColor;

  /// Width of each waveform bar in pixels.
  final double barWidth;

  /// Spacing between bars in pixels.
  final double barSpacing;

  /// Minimum height for bars (ensures quiet sections are visible).
  final double minBarHeight;

  /// Border radius for the waveform container.
  final BorderRadius? borderRadius;

  /// Whether to show the center line for stereo waveforms.
  final bool showCenterLine;

  /// Creates a copy of this style with the given fields replaced.
  WaveformStyle copyWith({
    double? height,
    Duration? animationDuration,
    Color? waveColor,
    Color? waveColorPlayed,
    Color? backgroundColor,
    Color? positionIndicatorColor,
    Color? centerLineColor,
    Color? playedOverlayColor,
    Color? unplayedOverlayColor,
    double? barWidth,
    double? barSpacing,
    double? minBarHeight,
    BorderRadius? borderRadius,
    bool? showCenterLine,
  }) {
    return WaveformStyle(
      height: height ?? this.height,
      animationDuration: animationDuration ?? this.animationDuration,
      waveColor: waveColor ?? this.waveColor,
      waveColorPlayed: waveColorPlayed ?? this.waveColorPlayed,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      positionIndicatorColor:
          positionIndicatorColor ?? this.positionIndicatorColor,
      centerLineColor: centerLineColor ?? this.centerLineColor,
      playedOverlayColor: playedOverlayColor ?? this.playedOverlayColor,
      unplayedOverlayColor: unplayedOverlayColor ?? this.unplayedOverlayColor,
      barWidth: barWidth ?? this.barWidth,
      barSpacing: barSpacing ?? this.barSpacing,
      minBarHeight: minBarHeight ?? this.minBarHeight,
      borderRadius: borderRadius ?? this.borderRadius,
      showCenterLine: showCenterLine ?? this.showCenterLine,
    );
  }
}
