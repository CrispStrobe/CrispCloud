// lib/widgets/fkey_bar.dart
//
// FKeyBar — horizontal row of F3–F8 buttons at the bottom of the screen.
// Follows the orthodox file manager convention (Midnight Commander, Total Commander).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/panel_source_provider.dart';
import '../services/fkey_action_service.dart';

// ---------------------------------------------------------------------------
// FKeyBar widget
// ---------------------------------------------------------------------------

class FKeyBar extends ConsumerWidget {
  /// Called when the user taps an F-key button.
  final void Function(FKeyAction action)? onAction;

  /// Override the active panel context for testing / preview purposes.
  final FKeyContext? overrideContext;

  const FKeyBar({super.key, this.onAction, this.overrideContext});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(fkeyBarVisibleProvider);
    if (!visible) return const SizedBox.shrink();

    final fkeyCtx = overrideContext ?? ref.watch(activeFKeyContextProvider);
    final service = const FKeyActionService();

    return _FKeyBarContent(
      fkeyContext: fkeyCtx,
      service: service,
      onAction: onAction,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal stateless bar content
// ---------------------------------------------------------------------------

class _FKeyBarContent extends StatelessWidget {
  final FKeyContext? fkeyContext;
  final FKeyActionService service;
  final void Function(FKeyAction action)? onAction;

  const _FKeyBarContent({
    required this.fkeyContext,
    required this.service,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 480;

    return Material(
      color: colorScheme.surfaceContainerHighest,
      elevation: 4,
      child: SizedBox(
        height: 36,
        child: Row(
          children: FKeyAction.values.map((action) {
            final available = fkeyContext != null &&
                service.isActionAvailable(action, fkeyContext!);
            return _FKeyButton(
              action: action,
              label: service.getActionLabel(action),
              shortcut: service.getActionShortcut(action),
              available: available,
              isNarrow: isNarrow,
              onTap: available && onAction != null
                  ? () => onAction!(action)
                  : null,
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual F-key button
// ---------------------------------------------------------------------------

class _FKeyButton extends StatelessWidget {
  final FKeyAction action;
  final String label;
  final String shortcut;
  final bool available;
  final bool isNarrow;
  final VoidCallback? onTap;

  const _FKeyButton({
    required this.action,
    required this.label,
    required this.shortcut,
    required this.available,
    required this.isNarrow,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeColor = colorScheme.onSurface;
    final disabledColor = colorScheme.onSurface.withAlpha(77); // ~30%

    Widget child;
    if (isNarrow) {
      // Narrow: show icon only
      child = Icon(
        _iconForAction(action),
        size: 18,
        color: available ? activeColor : disabledColor,
      );
    } else {
      // Wide: show "F5 Copy"
      child = RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$shortcut ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: available
                    ? colorScheme.primary
                    : disabledColor,
              ),
            ),
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 12,
                color: available ? activeColor : disabledColor,
              ),
            ),
          ],
        ),
      );
    }

    return Expanded(
      child: Tooltip(
        message: '$shortcut — $label',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(2),
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: colorScheme.outline.withAlpha(51), // ~20%
                  width: 1,
                ),
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  static IconData _iconForAction(FKeyAction action) {
    return switch (action) {
      FKeyAction.view => Icons.visibility_outlined,
      FKeyAction.edit => Icons.edit_outlined,
      FKeyAction.copy => Icons.copy_outlined,
      FKeyAction.move => Icons.drive_file_move_outlined,
      FKeyAction.mkdir => Icons.create_new_folder_outlined,
      FKeyAction.delete => Icons.delete_outline,
    };
  }
}
