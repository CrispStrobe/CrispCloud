import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/file_view_configuration.dart';
import '../models/panel_side.dart';
import '../providers/panel_provider.dart';
import '../providers/toolbar_provider.dart';

class FileColumnHeader extends ConsumerWidget {
  const FileColumnHeader({
    super.key,
    required this.side,
    required this.panel,
    this.onConfigure,
  });
  final PanelSide side;
  final PanelNotifier panel;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final widths = ref.watch(columnWidthsProvider(side));
    final view = FileViewConfiguration(
      columns: ref.watch(fileColumnsProvider(side)),
      widths: widths,
    );
    final style = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );

    Widget label(FileColumnDefinition column) {
      final primary =
          panel.sortColumnId == column.id ||
          (panel.sortColumnId == null &&
              column.builtInSort != null &&
              panel.sortBy == column.builtInSort);
      final secondary =
          panel.secondarySortColumnId == column.id ||
          (panel.secondarySortColumnId == null &&
              column.builtInSort != null &&
              panel.secondarySortBy == column.builtInSort);
      final arrow = primary
          ? (panel.sortOrder == SortOrder.ascending ? ' ↑' : ' ↓')
          : secondary
          ? (panel.secondarySortOrder == SortOrder.ascending ? ' ²↑' : ' ²↓')
          : '';
      void secondarySort() {
        if (column.builtInSort != null) {
          panel.setSecondarySortBy(secondary ? null : column.builtInSort);
        } else {
          panel.setColumnSort(column.id, secondary: true);
        }
      }

      return GestureDetector(
        onTap: () {
          if (column.builtInSort == null) {
            panel.setColumnSort(column.id);
          } else if (primary) {
            panel.toggleSortOrder();
          } else {
            panel.setSortBy(column.builtInSort!);
          }
        },
        onSecondaryTap: secondarySort,
        onLongPress: secondarySort,
        child: Tooltip(
          message:
              '${column.label}\nClick to sort; secondary click or long press for secondary sort.',
          child: SizedBox(
            width: view.widthFor(column),
            child: Text(
              '${column.label}$arrow',
              style: style.copyWith(
                color: primary ? theme.colorScheme.primary : null,
              ),
              textAlign: column.kind == FileColumnKind.size
                  ? TextAlign.right
                  : TextAlign.left,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }

    Widget resize(FileColumnDefinition column) => GestureDetector(
      onHorizontalDragUpdate: (details) => ref
          .read(columnWidthsProvider(side).notifier)
          .setWidth(column.id, view.widthFor(column) + details.delta.dx),
      onDoubleTap: () => ref
          .read(columnWidthsProvider(side).notifier)
          .setWidth(column.id, column.defaultWidth),
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        child: Tooltip(
          message: 'Resize ${column.label}',
          child: Container(
            width: 6,
            color: Colors.transparent,
            child: Center(
              child: Container(width: 1, height: 12, color: theme.dividerColor),
            ),
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = view.columnsFitting(constraints.maxWidth);
        final omitted = view.columns
            .where(
              (column) =>
                  view.widthFor(column) > 0 && !visible.contains(column),
            )
            .toList();
        final namePrimary =
            panel.sortColumnId == null && panel.sortBy == SortBy.name;
        return Container(
          height: 22,
          color: theme.colorScheme.surfaceContainerLow,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              const SizedBox(width: 18),
              Expanded(
                child: GestureDetector(
                  onTap: () => namePrimary
                      ? panel.toggleSortOrder()
                      : panel.setSortBy(SortBy.name),
                  onSecondaryTap: () => _menu(context, ref, view),
                  onLongPress: () => _menu(context, ref, view),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${panel.showingSearchResults ? 'Original path' : 'Name'}${namePrimary
                              ? panel.sortOrder == SortOrder.ascending
                                    ? ' ↑'
                                    : ' ↓'
                              : ''}',
                          style: style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (omitted.isNotEmpty)
                        Tooltip(
                          message:
                              'Widen this panel to show: ${omitted.map((column) => column.label).join(', ')}',
                          child: const Icon(Icons.more_horiz, size: 14),
                        ),
                    ],
                  ),
                ),
              ),
              for (final column in visible) ...[resize(column), label(column)],
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }

  Future<void> _menu(
    BuildContext context,
    WidgetRef ref,
    FileViewConfiguration view,
  ) async {
    final selection = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width / 2,
        80,
        MediaQuery.sizeOf(context).width / 2 + 1,
        81,
      ),
      items: [
        for (final column in view.columns)
          CheckedPopupMenuItem(
            value: column.id,
            checked: view.widthFor(column) > 0,
            child: Text(column.label),
          ),
        if (onConfigure != null) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: ':configure',
            child: Text('Configure columns and views…'),
          ),
        ],
      ],
    );
    if (!context.mounted || selection == null) return;
    if (selection == ':configure') {
      onConfigure?.call();
    } else {
      ref
          .read(columnWidthsProvider(side).notifier)
          .toggleVisibility(
            selection,
            defaultWidth: view.columns
                .firstWhere((column) => column.id == selection)
                .defaultWidth,
          );
    }
  }
}
