import 'package:flutter/widgets.dart';
import '/shared/extensions/duration_extension.dart';

import '../video_editor_configurable.dart';

/// Displays the trim duration information in the video editor.
///
/// This widget shows the start and end time of the selected trim span.
class VideoEditorTrimInfoWidget extends StatelessWidget {
  /// Creates a [VideoEditorTrimInfoWidget] widget.
  const VideoEditorTrimInfoWidget({super.key});

  @override
  Widget build(BuildContext context) {
    var player = VideoEditorConfigurable.of(context);
    return ValueListenableBuilder(
      valueListenable: player.showTrimTimeSpanNotifier,
      builder: (_, showTrimTimeSpan, _) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, animation) {
            final scaleAnimation = Tween<double>(
              begin: 0.7,
              end: 1.0,
            ).animate(animation);
            return ScaleTransition(
              scale: scaleAnimation,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          child: showTrimTimeSpan
              ? _buildTimeSpanText(player)
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildTimeSpanText(VideoEditorConfigurable player) {
    return ValueListenableBuilder(
      valueListenable: player.controller.trimDurationSpanNotifier,
      builder: (_, value, _) {
        if (player.configs.widgets.trimDurationInfo != null) {
          return player.configs.widgets.trimDurationInfo!(value);
        }

        return IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: player.style.trimDurationBackground,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${value.start.toTimeString()} - '
                '${(value.end.toTimeString())}',
                style:
                    player.style.trimDurationTextStyle ??
                    TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: player.style.trimDurationTextColor,
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}
