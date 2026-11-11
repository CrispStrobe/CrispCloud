// lib/widgets/fkey_bar.dart
//
// Common file actions with their current keyboard bindings.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/panel_source_provider.dart';
import '../providers/keyboard_shortcut_provider.dart';
import '../l10n/access_and_fkey_strings.dart';
import '../services/fkey_action_service.dart';
import '../services/keyboard_shortcut_service.dart';

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
    ref.watch(shortcutBindingsProvider);
    final shortcuts = ref.read(keyboardShortcutServiceProvider);
    const service = FKeyActionService();

    return _FKeyBarContent(
      fkeyContext: fkeyCtx,
      service: service,
      shortcuts: {
        for (final action in FKeyAction.values)
          action: shortcuts.browserDisplay(_bindingFor(action)),
      },
      onAction: onAction,
    );
  }

  static ShortcutAction _bindingFor(FKeyAction action) => switch (action) {
    FKeyAction.view => ShortcutAction.preview,
    FKeyAction.edit => ShortcutAction.edit,
    FKeyAction.copy => ShortcutAction.copyWithOptions,
    FKeyAction.move => ShortcutAction.moveWithOptions,
    FKeyAction.mkdir => ShortcutAction.newFolder,
    FKeyAction.delete => ShortcutAction.delete,
  };
}

// ---------------------------------------------------------------------------
// Internal stateless bar content
// ---------------------------------------------------------------------------

class _FKeyBarContent extends StatelessWidget {
  final FKeyContext? fkeyContext;
  final FKeyActionService service;
  final Map<FKeyAction, String> shortcuts;
  final void Function(FKeyAction action)? onAction;

  const _FKeyBarContent({
    required this.fkeyContext,
    required this.service,
    required this.shortcuts,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final scaledFontSize = MediaQuery.textScalerOf(context).scale(12);
    final isNarrow = screenWidth < 480 || scaledFontSize > 20;

    final platform = Theme.of(context).platform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final barHeight = (scaledFontSize + 16)
        .clamp(isMobile ? 48.0 : 36.0, 80.0)
        .toDouble();

    return Material(
      color: colorScheme.surfaceContainerHighest,
      elevation: 4,
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: FKeyAction.values.map((action) {
            final available =
                fkeyContext != null &&
                service.isActionAvailable(action, fkeyContext!);
            return _FKeyButton(
              action: action,
              label: AccessAndFKeyStrings(Localizations.localeOf(context))
                  .action(action.index),
              shortcut: shortcuts[action]!,
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
      // The full binding is retained in the tooltip and accessibility label
      // when a custom combination is too long for one compact button.
      child = RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textScaler: MediaQuery.textScalerOf(context),
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$shortcut ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: available ? colorScheme.primary : disabledColor,
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
      child: Semantics(
        key: ValueKey('file-action-${action.name}'),
        button: true,
        enabled: onTap != null,
        label: '$label ($shortcut)',
        onTap: onTap,
        excludeSemantics: true,
        child: Tooltip(
          message: '$shortcut — $label',
          excludeFromSemantics: true,
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
