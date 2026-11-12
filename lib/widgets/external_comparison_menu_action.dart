import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/external_comparison_strings.dart';
import '../models/file_item.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../services/command_entry_service.dart';
import 'external_comparison_dialog.dart';

/// Owns a pair captured before a context menu opens. The menu and the dialog
/// have separate lifetimes: selecting the action hands off ownership before
/// the popup's completion callback can dispose an unused capture.
class ExternalComparisonMenuAction {
  ExternalComparisonMenuAction._(this.context, this.ref, this._pair);

  final BuildContext context;
  final WidgetRef ref;
  final ExternalComparisonPair _pair;
  bool _handedOff = false;

  static ExternalComparisonMenuAction? capture(
    BuildContext context,
    WidgetRef ref,
    PanelSide side,
    List<FileItem> files,
  ) {
    if (const NativeCommandEntryHost().platform == null) return null;
    try {
      final ExternalComparisonPair pair;
      if (files.length == 2) {
        pair = captureExternalComparisonPair(
          ref,
          leftSide: side,
          leftFile: files[0],
          rightSide: side,
          rightFile: files[1],
        );
      } else if (files.length == 1 && !files.single.isFolder) {
        final otherSide = side == PanelSide.local
            ? PanelSide.remote
            : PanelSide.local;
        final matches = (ref.read(panelProvider(otherSide)).files ?? [])
            .where((item) => !item.isFolder && item.name == files.single.name)
            .toList(growable: false);
        // Ambiguous collection rows must be selected explicitly instead of
        // silently choosing the first path with the same display name.
        if (matches.length != 1) return null;
        pair = captureExternalComparisonPair(
          ref,
          leftSide: side == PanelSide.local ? side : otherSide,
          leftFile: side == PanelSide.local ? files.single : matches.single,
          rightSide: side == PanelSide.local ? otherSide : side,
          rightFile: side == PanelSide.local ? matches.single : files.single,
        );
      } else {
        return null;
      }
      return ExternalComparisonMenuAction._(context, ref, pair);
    } catch (_) {
      return null;
    }
  }

  PopupMenuItem<void> buildItem() => PopupMenuItem<void>(
    child: Row(
      children: [
        const Icon(Icons.compare_arrows, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(ExternalComparisonStrings(context).text('compare')),
        ),
      ],
    ),
    onTap: () {
      _handedOff = true;
      unawaited(
        Future<void>.delayed(Duration.zero, () async {
          try {
            if (!context.mounted) return;
            await showExternalComparisonDialog(context, ref, pair: _pair);
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    ExternalComparisonStrings(context).failure(error),
                  ),
                ),
              );
            }
          } finally {
            _pair.dispose();
          }
        }),
      );
    },
  );

  void menuClosed() {
    if (!_handedOff) _pair.dispose();
  }
}
